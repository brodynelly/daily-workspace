import SwiftUI

@MainActor
struct QuickPanelHarnessView: View {
    @ObservedObject var harness: QuickPanelHarness
    @FocusState private var editorFocused: Bool
    @FocusState private var filterFocused: Bool
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 8) {
                    QuickPanelFrameBox(
                        title: "Agent config", trailing: harness.loading ? "scanning" : "\(harness.visibleFiles.count)",
                        active: !harness.editing
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            if harness.filtering || !harness.filter.isEmpty { filterField }
                            fileList
                        }
                    }
                    .frame(width: max(240, geometry.size.width * 0.36))
                    QuickPanelFrameBox(title: contentTitle, trailing: contentTrailing, active: harness.editing) {
                        contentView
                    }
                }
                .padding(.top, 7)
            }
            if let notice = harness.notice {
                Text(notice).foregroundStyle(harness.noticeIsError ? Ink.coral : Ink.cyan).lineLimit(1)
            }
        }
        .panelFont(11)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent harness")
    }

    private var contentTitle: String { harness.selectedFile.map { $0.name } ?? "File" }

    private var contentTrailing: String {
        guard let file = harness.selectedFile else { return "" }
        if harness.editing { return harness.isDirty ? "editing · modified" : "editing" }
        if !file.editable { return "read-only" }
        return file.size >= 1024 ? "\(file.size / 1024) KB" : "\(file.size) B"
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Text("/").foregroundStyle(Ink.title)
            TextField("filter", text: $harness.filter)
                .textFieldStyle(.plain)
                .focused($filterFocused)
                .disabled(!harness.filtering)
                .accessibilityLabel("Filter harness files")
        }
        .onAppear { DispatchQueue.main.async { filterFocused = harness.filtering } }
        .onChange(of: harness.filtering) { _, on in filterFocused = on }
    }

    private var fileList: some View {
        let files = harness.visibleFiles
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        if index == 0 || files[index - 1].group != file.group {
                            Text(file.group).foregroundStyle(Ink.gold).padding(.top, index == 0 ? 0 : 6)
                        }
                        Text("  " + file.name)
                            .foregroundStyle(file.editable ? Ink.primary : Ink.meta)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
                            .pascalSelection(index == harness.selected)
                            .contentShape(Rectangle())
                            .onTapGesture { harness.select(index) }
                            .id(file.id)
                    }
                }
            }
            .onChange(of: harness.selected) { _, index in
                guard files.indices.contains(index) else { return }
                proxy.scrollTo(files[index].id)
            }
            .overlay {
                if files.isEmpty {
                    Text(emptyText).foregroundStyle(Ink.meta)
                }
            }
        }
    }

    private var emptyText: String {
        harness.loading ? "Scanning…" : harness.filter.isEmpty ? "No agent configuration" : "No matches"
    }

    @ViewBuilder
    private var contentView: some View {
        if harness.editing {
            TextEditor(text: $harness.buffer)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Ink.titleBox.opacity(0.5))
                .foregroundStyle(Ink.primary)
                .focused($editorFocused)
                .onAppear { DispatchQueue.main.async { editorFocused = true } }
                .accessibilityLabel("Edit \(contentTitle)")
        } else if let content = harness.content {
            QuickPanelDiffLines(
                lines: content.split(separator: "\n", omittingEmptySubsequences: false).prefix(5_000).enumerated()
                    .map { .init(id: $0.offset, text: String($0.element)) },
                scroll: harness.previewScroll, plain: true)
        } else {
            Text(harness.contentNote ?? "").foregroundStyle(Ink.meta)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
