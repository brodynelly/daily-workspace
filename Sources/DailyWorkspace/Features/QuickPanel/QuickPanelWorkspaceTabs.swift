import AppKit
import Combine

/// The workspace page's tabs. Overview keeps the dashboard and every action row (Kitty, agent launches, Finder,
/// copy path); Git is a lazygit-style hub; Harness shows and edits agent configuration.
enum QuickPanelWorkspaceTab: String, CaseIterable, Identifiable {
    case overview, git, harness

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .git: "Git"
        case .harness: "Harness"
        }
    }
}

extension QuickPanelController {
    static let vaultGitReason = "Git actions are off for the vault: the app never changes vault files through Git."
    static let vaultHarnessReason = "Vault files are read-only here (shown, never edited or sent)."

    func workspacePathChanged() {
        workspaceTab = .overview
        gitHub.close()
        harness.close()
    }

    func selectWorkspaceTab(_ tab: QuickPanelWorkspaceTab) {
        guard let path = workspacePath else { return }
        workspaceTab = tab
        pendingVimPrefix = nil
        focusedPane = "document"
        switch tab {
        case .overview: break
        case .git:
            if gitHub.path != path {
                gitHub.open(path: path, unavailable: isVaultPath(path) ? Self.vaultGitReason : nil)
            } else {
                Task { await gitHub.reload() }
            }
        case .harness:
            if harness.path != path {
                harness.open(path: path, readOnlyReason: isVaultPath(path) ? Self.vaultHarnessReason : nil)
            }
        }
    }

    func cycleWorkspaceTab(reverse: Bool) {
        let tabs = QuickPanelWorkspaceTab.allCases
        let position = tabs.firstIndex(of: workspaceTab) ?? 0
        selectWorkspaceTab(tabs[(position + (reverse ? tabs.count - 1 : 1)) % tabs.count])
    }

    /// Overview rows handled in the panel itself rather than by a helper.
    func workspaceLocalRows(_ path: String) -> [QuickPanelDataRow] {
        [
            .init(
                id: "detail:local:git", title: "Git hub", detail: "Stage, commit, branch, stash, push and pull",
                group: "Workspace", keys: "]"),
            .init(
                id: "detail:local:harness", title: "Agent harness",
                detail: ".claude · .agents · .pi · .codex · AGENTS.md, plus your global configs", group: "Workspace"),
            .init(
                id: "detail:local:finder", title: "Reveal in Finder", detail: shortPath(path), group: "Workspace"),
            .init(id: "detail:local:copy", title: "Copy path", detail: shortPath(path), group: "Workspace"),
        ]
    }

    func activateWorkspaceLocalRow(_ row: QuickPanelDataRow) -> Bool {
        guard let path = workspacePath, row.id.hasPrefix("detail:local:") else { return false }
        switch row.id.dropFirst("detail:local:".count) {
        case "git": selectWorkspaceTab(.git)
        case "harness": selectWorkspaceTab(.harness)
        case "finder": NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case "copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        default: return false
        }
        return true
    }

    /// Attaches the selected harness file to the next AI question and opens the AI page.
    func askAboutHarnessFile() {
        guard let model, let attachment = harness.attachment() else { return }
        // Open first: the AI page starts a fresh chat, which would drop an attachment set before it.
        if !aiPopup.isVisible { toggleAIPopup() }
        model.assistant.attachment = attachment
        let name = harness.selectedFile?.name ?? "file"
        aiPopup.notice =
            model.preferences.assistantEnabled
            ? "Attached \(name) to your next question (secrets redacted)"
            : "Attached \(name). Turn on the Assistant in Settings → AI to ask."
        harness.attachmentWatch = aiPopup.$isVisible.dropFirst().first { !$0 }.sink { [weak model] _ in
            MainActor.assumeIsolated { model?.assistant.attachment = nil }
        }
    }

    // MARK: Keys

    private var workspaceTextActive: Bool {
        guard workspacePath != nil, !aiPopup.isVisible, !palette.isVisible else { return false }
        switch workspaceTab {
        case .overview: return false
        case .git: return gitHub.input != nil
        case .harness: return harness.editing || harness.filtering
        }
    }

    /// While a workspace text field is focused it gets every key except its own Escape/Return/⌘S handling.
    func handleWorkspaceTextKey(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> Bool? {
        guard workspaceTextActive else { return nil }
        if workspaceTab == .git {
            switch keyCode {
            case 53: gitHub.cancelPrompt()
            case 36, 76: gitHub.submitInput()
            default: return false
            }
            return true
        }
        if harness.editing {
            if keyCode == 53 {
                harness.escapeEdit()
            } else if modifiers.contains(.command) && characters.lowercased() == "s" {
                harness.save()
            } else {
                return false
            }
            return true
        }
        return handleHarnessFilterKey(keyCode)
    }

    private func handleHarnessFilterKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 53:
            harness.filter = ""
            harness.filtering = false
        case 36, 76: harness.filtering = false
        case 125: harness.move(by: 1)
        case 126: harness.move(by: -1)
        default: return false
        }
        return true
    }

    /// Workspace page keys: `[` / `]` switch tabs everywhere; the Git and Harness tabs own the rest except the
    /// panel-wide q, z, m, ?, digits and ⌘ shortcuts. `nil` continues normal handling.
    func handleWorkspaceTabKey(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> Bool? {
        guard workspacePath != nil, focusedPane != "command" else { return nil }
        let plain = modifiers.isDisjoint(with: [.command, .option, .control])
        if plain, characters == "[" || characters == "]" {
            cycleWorkspaceTab(reverse: characters == "[")
            return true
        }
        guard workspaceTab != .overview, modifiers.isDisjoint(with: [.command, .option]) else { return nil }
        if keyCode == 53 { return handleWorkspaceEscape() }
        let key = characters.count == 1 ? characters.first : nil
        if workspaceTab == .git, gitHub.confirmation != nil {
            if key == "y" || keyCode == 36 || keyCode == 76 {
                gitHub.confirm()
            } else if key == "n" {
                gitHub.cancelPrompt()
            }
            return true
        }
        if plain, let key, "qzm:?0123456789".contains(key), !(workspaceTab == .harness && key == "?") { return nil }
        let control = modifiers.contains(.control)
        return workspaceTab == .git
            ? handleGitKey(keyCode: keyCode, key: key, control: control, shift: modifiers.contains(.shift))
            : handleHarnessKey(keyCode: keyCode, key: key, control: control)
    }

    private func handleWorkspaceEscape() -> Bool? {
        if workspaceTab == .git, gitHub.confirmation != nil || gitHub.input != nil {
            gitHub.cancelPrompt()
            return true
        }
        if workspaceTab == .harness, !harness.filter.isEmpty {
            harness.filter = ""
            return true
        }
        return nil
    }

    private typealias PanelAction = @MainActor (QuickPanelController) -> Void

    private static let previewScrollKeys: [Character: Int] = ["d": 15, "u": -15, "e": 1, "y": -1]
    private static let pageKeys: [UInt16: Int] = [121: 15, 116: -15]

    private static let gitKeys: [Character: PanelAction] = [
        "j": { $0.gitHub.move(by: 1) }, "k": { $0.gitHub.move(by: -1) },
        "h": { $0.gitHub.cycleSection(reverse: true) }, "l": { $0.gitHub.cycleSection(reverse: false) },
        "g": { $0.gitHub.section == .stash ? $0.gitHub.applyStash(pop: true) : $0.gitHub.select(0) },
        "G": { $0.gitHub.select(Int.max) },
        "J": { $0.gitHub.scrollPreview(by: 3) }, "K": { $0.gitHub.scrollPreview(by: -3) },
        " ": { $0.gitHub.primaryAction() },
        "a": { if $0.gitHub.section == .files { $0.gitHub.toggleStageAll() } },
        "c": { $0.gitHub.beginCommit(amend: false) }, "A": { $0.gitHub.beginCommit(amend: true) },
        "d": { $0.gitHub.requestDelete() }, "D": { $0.gitHub.requestDelete() },
        "s": { $0.gitHub.stashAll() }, "n": { $0.gitHub.beginNewBranch() },
        "M": { if $0.gitHub.section == .branches { $0.gitHub.requestMerge() } },
        "P": { $0.gitHub.push() }, "p": { $0.gitHub.pull() }, "f": { $0.gitHub.fetch() },
        "y": { if $0.gitHub.section == .commits { $0.gitHub.copySelectedCommitHash() } },
        "o": { if $0.gitHub.section == .files { $0.gitHub.openSelectedFile() } },
        "r": { panel in Task { await panel.gitHub.reload() } },
        "R": { panel in Task { await panel.gitHub.reload() } },
    ]

    private static let harnessKeys: [Character: PanelAction] = [
        "j": { $0.harness.move(by: 1) }, "k": { $0.harness.move(by: -1) },
        "g": { $0.harness.select(0) }, "G": { $0.harness.select(Int.max) },
        "J": { $0.harness.scrollPreview(by: 3) }, "K": { $0.harness.scrollPreview(by: -3) },
        "e": { $0.harness.beginEdit() }, "i": { $0.harness.beginEdit() }, "l": { $0.harness.beginEdit() },
        "/": { $0.harness.filtering = true }, "?": { $0.askAboutHarnessFile() },
        "o": { $0.harness.openSelectedExternally() }, "y": { $0.harness.copySelectedPath() },
        "r": { $0.harness.rescan() }, "R": { $0.harness.rescan() },
    ]

    private func handleGitKey(keyCode: UInt16, key: Character?, control: Bool, shift: Bool) -> Bool? {
        guard gitHub.unavailable == nil, gitHub.path != nil else { return key == "h" ? nil : true }
        if control { return handleGitControlKey(key) }
        if let lines = Self.pageKeys[keyCode] {
            gitHub.scrollPreview(by: lines)
            return true
        }
        switch keyCode {
        case 48: gitHub.cycleSection(reverse: shift)
        case 125: gitHub.move(by: 1)
        case 126: gitHub.move(by: -1)
        case 36, 76: gitHub.primaryAction()
        default:
            guard let key else { return nil }
            // Unknown keys are swallowed: overview rows are hidden and must not act.
            Self.gitKeys[key]?(self)
        }
        return true
    }

    private func handleGitControlKey(_ key: Character?) -> Bool? {
        guard let key else { return nil }
        if let lines = Self.previewScrollKeys[key] {
            gitHub.scrollPreview(by: lines)
        } else if "hjkl".contains(key) {
            gitHub.cycleSection(reverse: key == "h" || key == "k")
        } else {
            return nil
        }
        return true
    }

    private func handleHarnessKey(keyCode: UInt16, key: Character?, control: Bool) -> Bool? {
        if control {
            guard let key, let lines = Self.previewScrollKeys[key] else { return nil }
            harness.scrollPreview(by: lines)
            return true
        }
        if let lines = Self.pageKeys[keyCode] {
            harness.scrollPreview(by: lines)
            return true
        }
        switch keyCode {
        case 125: harness.move(by: 1)
        case 126: harness.move(by: -1)
        case 36, 76: harness.beginEdit()
        case 48: break
        default:
            guard let key, key != "h" else { return nil }  // h goes back, as everywhere.
            Self.harnessKeys[key]?(self)
        }
        return true
    }

    var workspaceTabHints: [(String, String)]? {
        guard workspacePath != nil, focusedPane != "command" else { return nil }
        switch workspaceTab {
        case .overview:
            return [
                ("j/k", "Move"), ("↵", "Open"), ("[ ]", "Tabs"), ("h", "Back"), ("/", "Find"), ("?", "AI"),
                ("⌘K", "Commands"), ("q", "Hide"),
            ]
        case .git:
            if gitHub.confirmation != nil { return [("y", "Confirm"), ("n/esc", "Cancel")] }
            if gitHub.input != nil { return [("↵", "Submit"), ("esc", "Cancel")] }
            let section: [(String, String)]
            switch gitHub.section {
            case .files: section = [("␣", "Stage"), ("a", "All"), ("c", "Commit"), ("A", "Amend"), ("d", "Discard")]
            case .branches: section = [("␣", "Checkout"), ("n", "New"), ("M", "Merge"), ("d", "Delete")]
            case .commits: section = [("y", "Copy hash"), ("J/K", "Scroll")]
            case .stash: section = [("␣", "Apply"), ("g", "Pop"), ("d", "Drop")]
            }
            return [("j/k", "Move"), ("h/l", "Panels")] + section + [
                ("s", "Stash"), ("p/P", "Pull/Push"), ("f", "Fetch"), ("[ ]", "Tabs"), ("esc", "Back"),
            ]
        case .harness:
            if harness.editing { return [("⌘S", "Save"), ("esc", "Done")] }
            if harness.filtering { return [("↵", "Keep filter"), ("esc", "Clear")] }
            return [
                ("j/k", "Move"), ("e", "Edit"), ("?", "Ask AI"), ("/", "Filter"), ("J/K", "Scroll"), ("o", "Open"),
                ("y", "Copy path"), ("r", "Rescan"), ("[ ]", "Tabs"), ("h", "Back"),
            ]
        }
    }
}
