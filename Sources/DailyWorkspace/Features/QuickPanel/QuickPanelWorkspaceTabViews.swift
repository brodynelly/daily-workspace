import SwiftUI

/// The workspace page: a tab strip over Overview (dashboard plus action rows), Git and Harness.
@MainActor
struct QuickPanelWorkspacePageView<Table: View>: View {
    @ObservedObject var controller: QuickPanelController
    @ViewBuilder let table: Table
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            tabStrip
            switch controller.workspaceTab {
            case .overview:
                VStack(spacing: 12) {
                    QuickPanelWorkspaceInsightsView(controller: controller, insights: controller.insights)
                    table
                }
            case .git:
                QuickPanelGitHubView(controller: controller, git: controller.gitHub)
            case .harness:
                QuickPanelHarnessView(harness: controller.harness)
            }
        }
        .padding(.top, 4)
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(Array(QuickPanelWorkspaceTab.allCases.enumerated()), id: \.element) { index, tab in
                let active = controller.workspaceTab == tab
                Button {
                    controller.selectWorkspaceTab(tab)
                } label: {
                    Text(" \(index + 1) \(tab.title) ")
                        .foregroundStyle(active ? Ink.title : Ink.inactiveTitle)
                        .padding(.vertical, 2)
                        .background(active ? Ink.selection : Ink.titleBox.opacity(0.6))
                        .overlay(Rectangle().strokeBorder(active ? Ink.activeRule : Ink.idleRule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tab.title) tab")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
            Text("[ ] switch").foregroundStyle(Ink.meta).padding(.leading, 6)
            Spacer(minLength: 0)
        }
        .panelFont(12)
    }
}

/// A framed list or preview box with an active border, like lazygit's panels.
struct QuickPanelFrameBox<Content: View>: View {
    let title: String
    var trailing = ""
    var active = false
    @ViewBuilder let content: Content
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(active ? Ink.activeRule : Ink.idleRule.opacity(0.8), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                Text(" \(title) ").foregroundStyle(active ? Ink.title : Ink.inactiveTitle).background(Ink.titleBox)
                    .offset(x: 8, y: -7)
            }
            .overlay(alignment: .topTrailing) {
                if !trailing.isEmpty {
                    Text(" \(trailing) ").foregroundStyle(Ink.cyan).background(Ink.titleBox).offset(x: -8, y: -7)
                }
            }
    }
}

/// Diff or log lines, coloured like a terminal diff, scrolled by `scroll` (a line index).
struct QuickPanelDiffLines: View {
    let lines: [QuickPanelGitPreviewLine]
    let scroll: Int
    /// Plain text (harness files) wraps and is not coloured as a diff.
    var plain = false
    private typealias Ink = QuickPanelPascalSkin.Ink

    static func color(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return Ink.title }
        if line.hasPrefix("+") { return Ink.cyan }
        if line.hasPrefix("-") { return Ink.coral }
        if line.hasPrefix("@@") { return Ink.gold }
        if line.hasPrefix("diff ") || line.hasPrefix("commit ") || line.hasPrefix("index ") { return Ink.title }
        if line.hasPrefix("──") { return Ink.gold }
        return Ink.primary
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .foregroundStyle(plain ? Ink.primary : Self.color(line.text))
                            .lineLimit(plain ? nil : 1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .textSelection(.enabled)
            }
            .onChange(of: scroll) { _, line in proxy.scrollTo(line, anchor: .top) }
        }
    }
}

@MainActor
struct QuickPanelGitHubView: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var git: QuickPanelGitHub
    @FocusState private var inputFocused: Bool
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = git.unavailable {
                Text(reason).foregroundStyle(Ink.meta).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                header
                GeometryReader { geometry in
                    HStack(alignment: .top, spacing: 8) {
                        sections(height: geometry.size.height)
                            .frame(width: max(240, geometry.size.width * 0.4))
                        QuickPanelFrameBox(title: previewTitle, trailing: git.loading ? "loading" : "", active: false) {
                            QuickPanelDiffLines(lines: git.preview, scroll: git.previewScroll)
                        }
                    }
                    .padding(.top, 7)
                }
                prompt
            }
        }
        .panelFont(11)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Git hub")
    }

    private var previewTitle: String {
        switch git.section {
        case .files: "Diff"
        case .branches: "Log"
        case .commits: "Commit"
        case .stash: "Stash"
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("⎇ \(git.head.branch.isEmpty ? "…" : git.head.branch)").foregroundStyle(Ink.title)
            Text(
                git.head.upstream.isEmpty
                    ? "no upstream (P pushes with -u)"
                    : "→ \(git.head.upstream)  ↑\(git.head.ahead) ↓\(git.head.behind)"
            )
            .foregroundStyle(git.head.ahead + git.head.behind > 0 ? Ink.gold : Ink.meta)
            Spacer(minLength: 8)
            if let busy = git.busy {
                ProgressView().controlSize(.mini)
                Text(busy).foregroundStyle(Ink.gold)
            } else if let notice = git.notice {
                Text(notice).foregroundStyle(git.noticeIsError ? Ink.coral : Ink.cyan)
            }
        }
        .lineLimit(1)
    }

    private func sections(height: CGFloat) -> some View {
        let compact = max(48, min(86, (height - 40) * 0.17))
        return VStack(spacing: 14) {
            ForEach(QuickPanelGitSection.allCases, id: \.self) { section in
                let active = git.section == section
                QuickPanelFrameBox(
                    title: "\(section.title)", trailing: "\(git.count(of: section))", active: active
                ) {
                    list(section)
                }
                .frame(height: active ? nil : compact)
                .frame(maxHeight: active ? .infinity : compact)
                .contentShape(Rectangle())
                .onTapGesture { git.section = section }
            }
        }
    }

    @ViewBuilder
    private func list(_ section: QuickPanelGitSection) -> some View {
        let selected = git.selectedIndex(section)
        let active = git.section == section
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    switch section {
                    case .files:
                        ForEach(Array(git.files.enumerated()), id: \.element.id) { index, file in
                            row(index, selected: selected, active: active, in: section) { fileLabel(file) }
                        }
                    case .branches:
                        ForEach(Array(git.branches.enumerated()), id: \.element.id) { index, branch in
                            row(index, selected: selected, active: active, in: section) {
                                Text(branch.isHead ? "* " : "  ").foregroundStyle(Ink.cyan)
                                    + Text(branch.name).foregroundStyle(branch.isHead ? Ink.title : Ink.primary)
                                    + Text(branch.upstream.isEmpty ? "" : "  → \(branch.upstream)")
                                    .foregroundStyle(Ink.meta)
                                    + Text("  \(branch.age)").foregroundStyle(Ink.meta)
                            }
                        }
                    case .commits:
                        ForEach(Array(git.commits.enumerated()), id: \.element.id) { index, commit in
                            row(index, selected: selected, active: active, in: section) {
                                Text(commit.hash).foregroundStyle(Ink.gold) + Text(" \(commit.subject)")
                                    + Text("  \(commit.age)").foregroundStyle(Ink.meta)
                            }
                        }
                    case .stash:
                        ForEach(Array(git.stashes.enumerated()), id: \.element.id) { index, stash in
                            row(index, selected: selected, active: active, in: section) {
                                Text(stash.ref).foregroundStyle(Ink.gold) + Text(" \(stash.subject)")
                                    + Text("  \(stash.age)").foregroundStyle(Ink.meta)
                            }
                        }
                    }
                }
            }
            .onChange(of: selected) { _, index in proxy.scrollTo(index) }
            .overlay {
                if git.count(of: section) == 0 {
                    Text(emptyText(section)).foregroundStyle(Ink.meta)
                }
            }
        }
    }

    private func emptyText(_ section: QuickPanelGitSection) -> String {
        if git.loading { return "Reading…" }
        switch section {
        case .files: return "Working tree clean"
        case .branches: return "No branches"
        case .commits: return "No commits"
        case .stash: return "No stashes"
        }
    }

    private func fileLabel(_ file: QuickPanelGitFile) -> Text {
        let index = Text(String(file.index)).foregroundStyle(file.isConflict ? Ink.coral : Ink.cyan)
        let worktree = Text(String(file.worktree)).foregroundStyle(file.isConflict ? Ink.coral : Ink.coral)
        let name = Text(" " + (file.originalPath.map { "\($0) → " } ?? "") + file.path)
            .foregroundStyle(file.hasStaged && !file.hasUnstaged ? Ink.cyan : Ink.primary)
        return index + worktree + name
    }

    private func row<Label: View>(
        _ index: Int, selected: Int, active: Bool, in section: QuickPanelGitSection,
        @ViewBuilder label: () -> Label
    ) -> some View {
        label()
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
            .pascalSelection(index == selected, focused: active)
            .contentShape(Rectangle())
            .onTapGesture { git.select(index, in: section) }
            .id(index)
    }

    @ViewBuilder
    private var prompt: some View {
        if let confirmation = git.confirmation {
            HStack(spacing: 8) {
                Text("!").foregroundStyle(Ink.coral)
                Text(confirmation.prompt).foregroundStyle(Ink.notice)
                Text("y confirm · n/esc cancel").foregroundStyle(Ink.meta)
            }
            .lineLimit(1)
        } else if let input = git.input {
            HStack(spacing: 8) {
                Text("\(input.prompt) >").foregroundStyle(Ink.title)
                TextField(input == .commit ? "Summary of the staged changes" : "feature/name", text: $git.inputText)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onAppear { DispatchQueue.main.async { inputFocused = true } }
                    .accessibilityLabel(input.prompt)
            }
        }
    }
}
