import Foundation
import SwiftUI

/// Live system readings for the Monitor view. It samples only while the panel is visible on that view,
/// and only reads: it never starts, signals or kills a process.
@MainActor
final class QuickPanelMonitor: ObservableObject {
    static let historyLength = 90

    @Published private(set) var reading = QuickPanelMonitorReading()
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var inHistory: [Double] = []
    @Published private(set) var outHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var processes: [QuickPanelProcess] = []
    @Published private(set) var processError: String?
    @Published private(set) var sort: Sort = .cpu
    @Published private(set) var descending = true
    @Published private(set) var sessionIn: Double = 0
    @Published private(set) var sessionOut: Double = 0

    enum Sort: String, CaseIterable {
        case pid, name, memory, cpu

        var title: String {
            switch self {
            case .pid: "pid"
            case .name: "program"
            case .memory: "mem"
            case .cpu: "cpu%"
            }
        }
    }

    private var sampler = QuickPanelMonitorSampler()
    private var task: Task<Void, Never>?
    private var previousNetwork: (bytes: (UInt64, UInt64), at: Date)?
    private weak var owner: QuickPanelController?
    private let runner = QuickPanelCommandRunner(timeout: 3, outputLimit: 512 * 1024)

    var rateIn: Double { inHistory.last ?? 0 }
    var rateOut: Double { outHistory.last ?? 0 }

    var processRows: [QuickPanelDataRow] {
        if processes.isEmpty {
            return [.unavailable("Processes", processError ?? "Reading processes…")]
        }
        return sortedProcesses.map { process in
            var row = QuickPanelDataRow(
                id: "process:\(process.pid)", title: process.name,
                detail: "pid \(process.pid) · \(Self.bytes(process.residentKB * 1024))", group: "Processes")
            row.badge = String(format: "%.1f%% cpu", process.cpu)
            row.keywords = "\(process.pid)"
            return row
        }
    }

    var sortedProcesses: [QuickPanelProcess] {
        let ascending: [QuickPanelProcess]
        switch sort {
        case .pid: ascending = processes.sorted { $0.pid < $1.pid }
        case .name:
            ascending = processes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .memory: ascending = processes.sorted { $0.residentKB < $1.residentKB }
        case .cpu: ascending = processes.sorted { $0.cpu < $1.cpu }
        }
        return descending ? ascending.reversed() : ascending
    }

    /// `<` / `>` move the sort column like btop; `i` reverses it.
    func cycleSort(by offset: Int) {
        let all = Sort.allCases
        let index = all.firstIndex(of: sort) ?? 0
        sort = all[(index + offset + all.count) % all.count]
        descending = sort != .name && sort != .pid
        owner?.updateRows()
    }

    func reverseSort() {
        descending.toggle()
        owner?.updateRows()
    }

    func start(owner: QuickPanelController) {
        self.owner = owner
        guard task == nil else { return }
        task = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self, let owner = self.owner, owner.isVisible,
                    owner.currentRoute == .monitor
                else {
                    self?.task = nil
                    return
                }
                self.takeSample()
                if tick % 2 == 0 { await self.readProcesses() }
                tick += 1
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func apply(processes: [QuickPanelProcess]) {
        self.processes = processes
        processError = nil
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func takeSample(now: Date = Date()) {
        let next = sampler.sample()
        if let previous = previousNetwork {
            let (received, sent) = previous.bytes
            let seconds = max(0.25, now.timeIntervalSince(previous.at))
            // 32-bit interface counters wrap; the wrapping difference is still the bytes moved.
            let inBytes = Double(UInt32(truncatingIfNeeded: next.bytesIn &- received))
            let outBytes = Double(UInt32(truncatingIfNeeded: next.bytesOut &- sent))
            sessionIn += inBytes
            sessionOut += outBytes
            append(&inHistory, inBytes / seconds)
            append(&outHistory, outBytes / seconds)
        }
        previousNetwork = ((next.bytesIn, next.bytesOut), now)
        append(&cpuHistory, next.totalLoad)
        append(&memoryHistory, Double(next.memoryUsed) / Double(max(1, next.memoryTotal)))
        reading = next
    }

    private func readProcesses() async {
        do {
            let output = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/ps"), arguments: QuickPanelMonitorSampler.processArguments)
            guard output.exitStatus == 0 else { throw QuickPanelCommandError.exited(output.exitStatus) }
            apply(
                processes: QuickPanelMonitorSampler.parseProcesses(String(bytes: output.stdout, encoding: .utf8) ?? ""))
        } catch {
            processError = "Process list unavailable"
        }
        owner?.updateRows()
    }

    private func append(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    static func bytes<T: BinaryInteger>(_ value: T) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: Int64(clamping: value))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let days = minutes / 1440
        let hours = minutes / 60 % 24
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h \(minutes % 60)m"
    }
}

/// btop-style boxes above the process table: CPU graph and cores, memory, network and battery.
@MainActor
struct QuickPanelMonitorView: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var monitor: QuickPanelMonitor
    private typealias Ink = QuickPanelPascalSkin.Ink

    private var reading: QuickPanelMonitorReading { monitor.reading }

    var body: some View {
        GeometryReader { geometry in
            let left = (geometry.size.width - 12) * 0.56
            HStack(alignment: .top, spacing: 12) {
                cpuBox.frame(width: left, height: geometry.size.height)
                VStack(spacing: 12) {
                    memoryBox.frame(maxHeight: .infinity)
                    networkBox
                }
                .frame(maxWidth: .infinity, maxHeight: geometry.size.height)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .onAppear { monitor.start(owner: controller) }
        .onDisappear { monitor.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("System monitor")
    }

    private var cpuBox: some View {
        QuickPanelMonitorBox(
            title: "cpu",
            trailing: "load \(reading.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " "))"
                + "  up \(QuickPanelMonitor.duration(reading.uptime))", fill: true
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.0f%%", reading.totalLoad * 100))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(QuickPanelMeter.color(reading.totalLoad))
                    Text("total · \(reading.coreLoads.count) cores").foregroundStyle(Ink.meta)
                }
                QuickPanelAreaGraph(values: monitor.cpuHistory, maximum: 1, length: QuickPanelMonitor.historyLength)
                    .frame(minHeight: 40, maxHeight: .infinity)
                cores
            }
        }
    }

    private var cores: some View {
        let cores = reading.coreLoads
        let columns = cores.count > 8 ? 2 : 1
        let perColumn = max(1, (cores.count + columns - 1) / columns)
        return HStack(alignment: .top, spacing: 16) {
            ForEach(0..<columns, id: \.self) { column in
                VStack(alignment: .leading, spacing: 3) {
                    let slice = Array(cores.enumerated().dropFirst(column * perColumn).prefix(perColumn))
                    ForEach(slice, id: \.offset) { core in
                        HStack(spacing: 6) {
                            Text(String(format: "C%-2d", core.offset)).foregroundStyle(Ink.meta)
                            QuickPanelMeter(fraction: core.element).frame(height: 6)
                            Text(String(format: "%3.0f%%", core.element * 100))
                                .foregroundStyle(QuickPanelMeter.color(core.element))
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var memoryBox: some View {
        let total = Double(max(1, reading.memoryTotal))
        let free = reading.memoryTotal &- reading.memoryUsed &- reading.memoryCached
        let diskUsed = max(0, reading.diskTotal - reading.diskFree)
        return QuickPanelMonitorBox(title: "mem", trailing: QuickPanelMonitor.bytes(reading.memoryTotal), fill: true) {
            VStack(spacing: 7) {
                meterRow("used", Double(reading.memoryUsed) / total, QuickPanelMonitor.bytes(reading.memoryUsed))
                meterRow(
                    "cached", Double(reading.memoryCached) / total, QuickPanelMonitor.bytes(reading.memoryCached),
                    tint: Ink.cyan)
                meterRow("free", Double(free) / total, QuickPanelMonitor.bytes(free), tint: Ink.cyan)
                meterRow(
                    "swap", reading.swapTotal == 0 ? 0 : Double(reading.swapUsed) / Double(reading.swapTotal),
                    QuickPanelMonitor.bytes(reading.swapUsed))
                Rectangle().fill(Ink.idleRule.opacity(0.3)).frame(height: 1)
                meterRow(
                    "disk /", reading.diskTotal == 0 ? 0 : Double(diskUsed) / Double(reading.diskTotal),
                    "\(QuickPanelMonitor.bytes(reading.diskFree)) free")
                if let battery = reading.battery {
                    meterRow(
                        battery.charging ? "bat ⚡" : "bat", Double(battery.percent) / 100,
                        "\(battery.percent)%\(battery.onAC && !battery.charging ? " ac" : "")",
                        tint: battery.percent < 20 ? Ink.coral : Ink.cyan)
                }
                QuickPanelAreaGraph(
                    values: monitor.memoryHistory, maximum: 1, length: QuickPanelMonitor.historyLength, tint: Ink.gold
                )
                .frame(minHeight: 18, maxHeight: .infinity)
            }
        }
    }

    private var networkBox: some View {
        QuickPanelMonitorBox(
            title: "net",
            trailing: "session ▼\(QuickPanelMonitor.bytes(Int64(monitor.sessionIn))) "
                + "▲\(QuickPanelMonitor.bytes(Int64(monitor.sessionOut)))"
        ) {
            VStack(alignment: .leading, spacing: 6) {
                netRow("▼", Ink.cyan, monitor.rateIn, monitor.inHistory)
                netRow("▲", Ink.gold, monitor.rateOut, monitor.outHistory)
            }
        }
    }

    private func netRow(_ arrow: String, _ color: Color, _ rate: Double, _ history: [Double]) -> some View {
        HStack(spacing: 8) {
            Text(arrow).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(QuickPanelMonitor.rate(rate)).foregroundStyle(Ink.primary)
                Text("peak \(QuickPanelMonitor.rate(history.max() ?? 0))").foregroundStyle(Ink.meta)
                    .font(.system(size: 9.5, design: .monospaced))
            }
            .frame(width: 104, alignment: .leading)
            QuickPanelAreaGraph(
                values: history, maximum: max(1, history.max() ?? 1), length: QuickPanelMonitor.historyLength,
                tint: color)
        }
        .frame(height: 28)
    }

    private func meterRow(
        _ name: String, _ fraction: Double, _ value: String, tint: Color? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(name).foregroundStyle(Ink.meta).frame(width: 50, alignment: .leading)
            QuickPanelMeter(fraction: fraction, tint: tint).frame(height: 7)
            Text(value).foregroundStyle(Ink.primary).lineLimit(1).frame(width: 112, alignment: .trailing)
        }
    }
}
