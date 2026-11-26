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
    @Published private(set) var processes: [QuickPanelProcess] = []
    @Published private(set) var processError: String?

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
        return processes.map { process in
            var row = QuickPanelDataRow(
                id: "process:\(process.pid)", title: process.name,
                detail: "pid \(process.pid) · \(Self.bytes(process.residentKB * 1024))", group: "Processes")
            row.badge = String(format: "%.1f%% cpu", process.cpu)
            row.keywords = "\(process.pid)"
            return row
        }
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
            append(&inHistory, Double(UInt32(truncatingIfNeeded: next.bytesIn &- received)) / seconds)
            append(&outHistory, Double(UInt32(truncatingIfNeeded: next.bytesOut &- sent)) / seconds)
        }
        previousNetwork = ((next.bytesIn, next.bytesOut), now)
        append(&cpuHistory, next.totalLoad)
        reading = next
    }

    private func readProcesses() async {
        do {
            let output = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/ps"), arguments: QuickPanelMonitorSampler.processArguments)
            guard output.exitStatus == 0 else { throw QuickPanelCommandError.exited(output.exitStatus) }
            processes = QuickPanelMonitorSampler.parseProcesses(String(bytes: output.stdout, encoding: .utf8) ?? "")
            processError = nil
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

/// btop-style boxes above the process table: CPU graph and cores, memory, network, disk and battery.
@MainActor
struct QuickPanelMonitorView: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var monitor: QuickPanelMonitor
    private typealias Ink = QuickPanelPascalSkin.Ink

    private var reading: QuickPanelMonitorReading { monitor.reading }

    var body: some View {
        GeometryReader { geometry in
            let left = (geometry.size.width - 10) * 0.58
            HStack(alignment: .top, spacing: 10) {
                cpuBox.frame(width: left)
                VStack(spacing: 10) {
                    memoryBox
                    networkBox
                }
                .frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .onAppear { monitor.start(owner: controller) }
        .onDisappear { monitor.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("System monitor")
    }

    private var cpuBox: some View {
        QuickPanelMonitorBox(title: "cpu", trailing: String(format: "%3.0f%%", reading.totalLoad * 100)) {
            VStack(alignment: .leading, spacing: 8) {
                QuickPanelSparkGraph(values: monitor.cpuHistory, maximum: 1, length: QuickPanelMonitor.historyLength)
                    .frame(height: 64)
                let cores = reading.coreLoads
                let half = (cores.count + 1) / 2
                HStack(alignment: .top, spacing: 14) {
                    coreColumn(Array(cores.prefix(half).enumerated()))
                    coreColumn(Array(cores.dropFirst(half).enumerated()).map { ($0.offset + half, $0.element) })
                }
                HStack(spacing: 14) {
                    label(
                        "load",
                        reading.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " "))
                    label("up", QuickPanelMonitor.duration(reading.uptime))
                    label("cores", "\(cores.count)")
                }
            }
        }
    }

    private func coreColumn(_ cores: [(offset: Int, element: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(cores, id: \.offset) { core in
                HStack(spacing: 6) {
                    Text(String(format: "C%-2d", core.offset)).foregroundStyle(Ink.meta)
                    QuickPanelMeter(fraction: core.element).frame(height: 7)
                    Text(String(format: "%3.0f%%", core.element * 100)).foregroundStyle(Ink.primary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    private var memoryBox: some View {
        let total = Double(max(1, reading.memoryTotal))
        let free = reading.memoryTotal &- reading.memoryUsed &- reading.memoryCached
        return QuickPanelMonitorBox(title: "mem", trailing: QuickPanelMonitor.bytes(reading.memoryTotal)) {
            VStack(spacing: 5) {
                meterRow("used", Double(reading.memoryUsed) / total, QuickPanelMonitor.bytes(reading.memoryUsed))
                meterRow(
                    "cached", Double(reading.memoryCached) / total, QuickPanelMonitor.bytes(reading.memoryCached))
                meterRow("free", Double(free) / total, QuickPanelMonitor.bytes(free), inverted: true)
                meterRow(
                    "swap", reading.swapTotal == 0 ? 0 : Double(reading.swapUsed) / Double(reading.swapTotal),
                    QuickPanelMonitor.bytes(reading.swapUsed))
                let diskUsed = max(0, reading.diskTotal - reading.diskFree)
                meterRow(
                    "disk /", reading.diskTotal == 0 ? 0 : Double(diskUsed) / Double(reading.diskTotal),
                    "\(QuickPanelMonitor.bytes(reading.diskFree)) free")
            }
        }
    }

    private var networkBox: some View {
        QuickPanelMonitorBox(title: "net", trailing: batteryText) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("▼").foregroundStyle(Ink.cyan)
                    Text(QuickPanelMonitor.rate(monitor.rateIn)).foregroundStyle(Ink.primary)
                        .frame(width: 92, alignment: .leading)
                    QuickPanelSparkGraph(
                        values: monitor.inHistory, maximum: max(1, monitor.inHistory.max() ?? 1),
                        length: QuickPanelMonitor.historyLength)
                }
                .frame(height: 22)
                HStack(spacing: 8) {
                    Text("▲").foregroundStyle(Ink.gold)
                    Text(QuickPanelMonitor.rate(monitor.rateOut)).foregroundStyle(Ink.primary)
                        .frame(width: 92, alignment: .leading)
                    QuickPanelSparkGraph(
                        values: monitor.outHistory, maximum: max(1, monitor.outHistory.max() ?? 1),
                        length: QuickPanelMonitor.historyLength)
                }
                .frame(height: 22)
            }
        }
    }

    private var batteryText: String {
        guard let battery = reading.battery else { return "" }
        return "bat \(battery.percent)%" + (battery.charging ? " ⚡" : battery.onAC ? " ac" : "")
    }

    private func meterRow(_ name: String, _ fraction: Double, _ value: String, inverted: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(name).foregroundStyle(Ink.meta).frame(width: 50, alignment: .leading)
            QuickPanelMeter(fraction: fraction, inverted: inverted).frame(height: 8)
            Text(value).foregroundStyle(Ink.primary).lineLimit(1).frame(width: 112, alignment: .trailing)
        }
    }

    private func label(_ name: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(name).foregroundStyle(Ink.meta)
            Text(value).foregroundStyle(Ink.primary)
        }
    }
}

/// A thin titled box in the panel's palette, like btop's panes.
struct QuickPanelMonitorBox<Content: View>: View {
    let title: String
    var trailing = ""
    @ViewBuilder let content: Content
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Ink.idleRule.opacity(0.8), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                Text(" \(title) ").foregroundStyle(Ink.title).background(Ink.titleBox).offset(x: 10, y: -7)
            }
            .overlay(alignment: .topTrailing) {
                if !trailing.isEmpty {
                    Text(" \(trailing) ").foregroundStyle(Ink.cyan).background(Ink.titleBox).offset(x: -10, y: -7)
                }
            }
    }
}

/// A horizontal meter coloured cool → warm → hot by how full it is.
struct QuickPanelMeter: View {
    let fraction: Double
    var inverted = false
    private typealias Ink = QuickPanelPascalSkin.Ink

    static func color(_ value: Double) -> Color {
        value < 0.5 ? Ink.cyan : value < 0.8 ? Ink.gold : Ink.coral
    }

    var body: some View {
        GeometryReader { geometry in
            let value = min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.header)
                Capsule()
                    .fill(inverted ? Ink.cyan : Self.color(value))
                    .frame(width: max(value > 0 ? 3 : 0, geometry.size.width * value))
            }
        }
    }
}

/// A bar graph of recent samples, newest on the right, like btop's history graphs.
struct QuickPanelSparkGraph: View {
    let values: [Double]
    let maximum: Double
    let length: Int

    var body: some View {
        Canvas { context, size in
            let step = size.width / CGFloat(max(1, length))
            let start = length - values.count
            for (index, value) in values.enumerated() {
                let fraction = min(1, max(0, value / max(maximum, .leastNonzeroMagnitude)))
                let height = max(1, size.height * fraction)
                let rect = CGRect(
                    x: CGFloat(start + index) * step, y: size.height - height, width: max(1, step - 1), height: height)
                context.fill(Path(rect), with: .color(QuickPanelMeter.color(fraction).opacity(0.85)))
            }
        }
        .background(QuickPanelPascalSkin.Ink.header.opacity(0.6))
    }
}
