import SwiftUI

/// btop's process list: pid, program, memory and CPU with an inline bar. Selection follows the panel.
@MainActor
struct QuickPanelProcessTable: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var monitor: QuickPanelMonitor
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        let processes = monitor.sortedProcesses
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                heading(.pid, width: 60, alignment: .trailing)
                heading(.name, width: nil, alignment: .leading)
                heading(.memory, width: 86, alignment: .trailing)
                heading(.cpu, width: 150, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Ink.header)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if processes.isEmpty {
                            Text(monitor.processError ?? "Reading processes…").foregroundStyle(Ink.meta)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        }
                        ForEach(Array(processes.enumerated()), id: \.element.pid) { index, process in
                            row(process, selected: index == controller.selectedIndex)
                                .id(index)
                                .onTapGesture { controller.selectResultFromPointer(index) }
                        }
                    }
                }
                .onChange(of: controller.selectedIndex) { _, index in proxy.scrollTo(index) }
            }
            HStack(spacing: 14) {
                QuickPanelKeyCaps(keys: "< >", label: "Sort column")
                QuickPanelKeyCaps(keys: "i", label: monitor.descending ? "Descending" : "Ascending")
                Spacer(minLength: 0)
                Text("\(processes.count) processes · read-only").foregroundStyle(Ink.meta)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
        }
        .panelFont(11.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Processes sorted by \(monitor.sort.title)")
    }

    @ViewBuilder private func heading(
        _ sort: QuickPanelMonitor.Sort, width: CGFloat?, alignment: Alignment
    ) -> some View {
        let active = monitor.sort == sort
        let label = Text(sort.title + (active ? (monitor.descending ? " ▼" : " ▲") : ""))
            .foregroundStyle(active ? Ink.title : Ink.cyan)
        if let width {
            label.frame(width: width, alignment: alignment)
        } else {
            label.frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private func row(_ process: QuickPanelProcess, selected: Bool) -> some View {
        let fraction = min(1, process.cpu / 100)
        return HStack(spacing: 14) {
            Text(verbatim: String(process.pid)).foregroundStyle(Ink.meta).frame(width: 60, alignment: .trailing)
            Text(process.name).foregroundStyle(Ink.primary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(QuickPanelMonitor.bytes(process.residentKB * 1024)).foregroundStyle(Ink.footer)
                .frame(width: 86, alignment: .trailing)
            HStack(spacing: 8) {
                QuickPanelMeter(fraction: fraction).frame(width: 90, height: 6)
                Text(String(format: "%5.1f", process.cpu)).foregroundStyle(QuickPanelMeter.color(fraction))
            }
            .frame(width: 150, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(selected ? Ink.selection : .clear)
        .contentShape(Rectangle())
    }
}

/// A thin titled box in the panel's palette, like btop's panes.
struct QuickPanelMonitorBox<Content: View>: View {
    let title: String
    var trailing = ""
    var fill = false
    @ViewBuilder let content: Content
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        content
            .frame(maxHeight: fill ? .infinity : nil, alignment: .topLeading)
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
    var tint: Color?
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
                    .fill(tint ?? (inverted ? Ink.cyan : Self.color(value)))
                    .frame(width: max(value > 0 ? 3 : 0, geometry.size.width * value))
            }
        }
    }
}

/// A filled history graph with a cool → hot vertical gradient, like btop's braille graphs.
struct QuickPanelAreaGraph: View {
    let values: [Double]
    let maximum: Double
    let length: Int
    var tint: Color?
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(max(1, length - 1))
            let start = CGFloat(length - values.count) * step
            func point(_ index: Int) -> CGPoint {
                let fraction = min(1, max(0, values[index] / max(maximum, .leastNonzeroMagnitude)))
                return CGPoint(x: start + CGFloat(index) * step, y: size.height * (1 - fraction))
            }
            var line = Path()
            line.move(to: point(0))
            for index in 1..<values.count { line.addLine(to: point(index)) }
            var area = line
            area.addLine(to: CGPoint(x: point(values.count - 1).x, y: size.height))
            area.addLine(to: CGPoint(x: start, y: size.height))
            area.closeSubpath()
            let gradient =
                tint.map { Gradient(colors: [$0.opacity(0.55), $0.opacity(0.08)]) }
                ?? Gradient(colors: [Ink.coral.opacity(0.7), Ink.gold.opacity(0.5), Ink.cyan.opacity(0.15)])
            context.fill(
                area,
                with: .linearGradient(
                    gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(tint ?? Ink.cyan), lineWidth: 1.2)
        }
        .background(Ink.header.opacity(0.5))
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
