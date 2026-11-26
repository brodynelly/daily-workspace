import Darwin
import Foundation
import IOKit.ps

/// One reading of the machine, taken with read-only Darwin calls. Nothing here starts or signals a process.
struct QuickPanelMonitorReading: Equatable, Sendable {
    var coreLoads: [Double] = []
    var totalLoad: Double = 0
    var memoryTotal: UInt64 = 0
    var memoryUsed: UInt64 = 0
    var memoryCached: UInt64 = 0
    var swapTotal: UInt64 = 0
    var swapUsed: UInt64 = 0
    var diskTotal: Int64 = 0
    var diskFree: Int64 = 0
    var loadAverage: [Double] = [0, 0, 0]
    var uptime: TimeInterval = 0
    var bytesIn: UInt64 = 0
    var bytesOut: UInt64 = 0
    var battery: QuickPanelBattery?
}

struct QuickPanelBattery: Equatable, Sendable {
    let percent: Int
    let charging: Bool
    let onAC: Bool
}

struct QuickPanelProcess: Equatable, Sendable {
    let pid: Int32
    let cpu: Double
    let memoryPercent: Double
    let residentKB: UInt64
    let name: String
}

/// Keeps the previous CPU tick counts so each sample reports the load since the last one.
struct QuickPanelMonitorSampler {
    private var previousTicks: [[UInt32]] = []

    mutating func sample() -> QuickPanelMonitorReading {
        var reading = QuickPanelMonitorReading()
        reading.coreLoads = sampleCores()
        reading.totalLoad =
            reading.coreLoads.isEmpty ? 0 : reading.coreLoads.reduce(0, +) / Double(reading.coreLoads.count)
        sampleMemory(into: &reading)
        sampleSwap(into: &reading)
        sampleDisk(into: &reading)
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { reading.loadAverage = loads }
        reading.uptime = ProcessInfo.processInfo.systemUptime
        (reading.bytesIn, reading.bytesOut) = Self.networkBytes()
        reading.battery = Self.battery()
        return reading
    }

    private mutating func sampleCores() -> [Double] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard
            host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
                == KERN_SUCCESS, let info
        else { return [] }
        defer {
            vm_deallocate(
                mach_task_self_, vm_address_t(bitPattern: info),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        var ticks: [[UInt32]] = []
        for core in 0..<Int(count) {
            ticks.append((0..<states).map { UInt32(bitPattern: info[core * states + $0]) })
        }
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else { return ticks.map { _ in 0 } }
        return zip(ticks, previousTicks).map { now, before in
            let delta = (0..<states).map { Double(now[$0] &- before[$0]) }
            let total = delta.reduce(0, +)
            guard total > 0 else { return 0 }
            return 1 - delta[Int(CPU_STATE_IDLE)] / total
        }
    }

    private func sampleMemory(into reading: inout QuickPanelMonitorReading) {
        reading.memoryTotal = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = UInt64(vm_kernel_page_size)
        // Activity Monitor's "Memory Used": app memory + wired + compressed.
        let app = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        reading.memoryUsed = min(
            reading.memoryTotal,
            (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page)
        reading.memoryCached = min(
            reading.memoryTotal - reading.memoryUsed,
            (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * page)
    }

    private func sampleSwap(into reading: inout QuickPanelMonitorReading) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return }
        reading.swapTotal = usage.xsu_total
        reading.swapUsed = usage.xsu_used
    }

    private func sampleDisk(into reading: inout QuickPanelMonitorReading) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        reading.diskTotal = Int64(values.volumeTotalCapacity ?? 0)
        reading.diskFree = values.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Cumulative bytes over every interface except loopback. Counters are 32-bit, so rates use wrapping deltas.
    static func networkBytes() -> (UInt64, UInt64) {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return (0, 0) }
        defer { freeifaddrs(first) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0, let data = entry.ifa_data
            else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(stats.ifi_ibytes)
            sent += UInt64(stats.ifi_obytes)
        }
        return (received, sent)
    }

    static func battery() -> QuickPanelBattery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            return QuickPanelBattery(
                percent: current * 100 / maximum,
                charging: description[kIOPSIsChargingKey] as? Bool ?? false,
                onAC: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }

    /// `ps` output (`pid pcpu pmem rss comm`, sorted by CPU) parsed into processes.
    static func parseProcesses(_ text: String, limit: Int = 60) -> [QuickPanelProcess] {
        text.split(whereSeparator: \.isNewline).prefix(limit).compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5, let pid = Int32(fields[0]), let cpu = Double(fields[1]),
                let memory = Double(fields[2]), let rss = UInt64(fields[3])
            else { return nil }
            let name = String(fields[4]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return QuickPanelProcess(pid: pid, cpu: cpu, memoryPercent: memory, residentKB: rss, name: name)
        }
    }

    static let processArguments = ["-Aceo", "pid=,pcpu=,pmem=,rss=,comm=", "-r"]
}
