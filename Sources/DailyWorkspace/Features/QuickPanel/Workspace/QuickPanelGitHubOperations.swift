import AppKit
import Foundation

extension QuickPanelGitHub {
    // MARK: Operations

    /// Space / Return: stage or unstage a file, check out a branch, apply a stash, copy a commit hash.
    func primaryAction() {
        switch section {
        case .files: toggleStage()
        case .branches: checkoutSelectedBranch()
        case .stash: applyStash(pop: false)
        case .commits: copySelectedCommitHash()
        }
    }

    /// `d`: discard a file, delete a branch or drop a stash, each after confirmation.
    func requestDelete() {
        switch section {
        case .files: requestDiscard()
        case .branches: requestDeleteBranch()
        case .stash: requestDropStash()
        case .commits: break
        }
    }

    func toggleStage() {
        guard let file = selectedFile else { return }
        if file.hasUnstaged || file.isConflict {
            perform("Staging", ["add", "--", file.path])
        } else {
            perform("Unstaging", ["restore", "--staged", "--", file.path])
        }
    }

    func toggleStageAll() {
        if files.contains(where: { $0.hasUnstaged || $0.isConflict }) {
            perform("Staging all", ["add", "-A"])
        } else {
            perform("Unstaging all", ["reset", "-q"])
        }
    }

    func beginCommit(amend: Bool) {
        if amend {
            confirmation = .amend
            return
        }
        guard files.contains(where: \.hasStaged) else {
            show("Nothing staged. Stage files with space or a.", error: true)
            return
        }
        inputText = ""
        input = .commit
    }

    func beginNewBranch() {
        inputText = ""
        input = .newBranch
    }

    func submitInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = input else { return }
        guard !text.isEmpty else {
            show("\(kind.prompt) is empty", error: true)
            return
        }
        input = nil
        switch kind {
        case .commit: perform("Committing", ["commit", "-m", text], timeout: 120)
        case .newBranch:
            guard Self.isValidBranchName(text) else {
                show("Not a valid branch name", error: true)
                return
            }
            perform("Creating branch", ["switch", "-c", text])
        }
    }

    func requestDiscard() {
        guard let file = selectedFile else { return }
        confirmation = .discard(file)
    }

    func checkoutSelectedBranch() {
        guard let branch = selectedBranch, !branch.isHead else { return }
        perform("Switching to \(branch.name)", ["switch", branch.name])
    }

    func requestDeleteBranch() {
        guard let branch = selectedBranch else { return }
        guard !branch.isHead else {
            show("Can't delete the checked-out branch", error: true)
            return
        }
        confirmation = .deleteBranch(branch.name)
    }

    func requestMerge() {
        guard let branch = selectedBranch, !branch.isHead else { return }
        confirmation = .merge(branch.name)
    }

    func stashAll() {
        guard !files.isEmpty else {
            show("Nothing to stash", error: true)
            return
        }
        perform("Stashing", ["stash", "push", "--include-untracked"])
    }

    func applyStash(pop: Bool) {
        guard let stash = selectedStash else { return }
        perform(pop ? "Popping \(stash.ref)" : "Applying \(stash.ref)", ["stash", pop ? "pop" : "apply", stash.ref])
    }

    func requestDropStash() {
        guard let stash = selectedStash else { return }
        confirmation = .dropStash(stash.ref)
    }

    func push() {
        if head.upstream.isEmpty {
            guard !head.branch.isEmpty, head.branch != "HEAD" else {
                show("Detached HEAD has no branch to push", error: true)
                return
            }
            perform("Pushing \(head.branch)", ["push", "--set-upstream", "origin", head.branch], timeout: 120)
        } else {
            perform("Pushing", ["push"], timeout: 120)
        }
    }

    func pull() { perform("Pulling", ["pull", "--ff-only"], timeout: 120) }
    func fetch() { perform("Fetching", ["fetch", "--all", "--prune"], timeout: 120) }

    func copySelectedCommitHash() {
        guard let commit = selectedCommit else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commit.hash, forType: .string)
        show("Copied \(commit.hash)")
    }

    func openSelectedFile() {
        guard let path, let file = selectedFile else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path).appendingPathComponent(file.path))
    }

    func confirm() {
        guard let confirmation else { return }
        self.confirmation = nil
        switch confirmation {
        case .discard(let file):
            if file.isUntracked {
                trash(file)
            } else if file.index == "A" {
                let trashFile: @MainActor () -> Void = { [weak self] in self?.trash(file) }
                perform(
                    "Discarding \(file.path)", ["rm", "--cached", "--force", "-q", "--", file.path], then: trashFile)
            } else {
                perform(
                    "Discarding \(file.path)",
                    ["restore", "--source=HEAD", "--staged", "--worktree", "--", file.path])
            }
        case .deleteBranch(let name): perform("Deleting \(name)", ["branch", "-d", name])
        case .merge(let name): perform("Merging \(name)", ["merge", "--no-edit", name], timeout: 120)
        case .dropStash(let ref): perform("Dropping \(ref)", ["stash", "drop", ref])
        case .amend: perform("Amending", ["commit", "--amend", "--no-edit"], timeout: 120)
        }
    }

    func cancelPrompt() {
        input = nil
        confirmation = nil
    }

    private func trash(_ file: QuickPanelGitFile) {
        guard let path else { return }
        let root = URL(fileURLWithPath: path).standardizedFileURL
        let url = root.appendingPathComponent(file.path).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            show("Moved \(file.path) to the Trash")
        } catch {
            show("Could not move \(file.path) to the Trash", error: true)
        }
        Task { await reload() }
    }

    private func show(_ message: String, error: Bool = false) {
        notice = message
        noticeIsError = error
    }

    /// Runs one write. Only one runs at a time; the hub reloads afterwards either way.
    func perform(
        _ label: String, _ arguments: [String], timeout: TimeInterval = 30,
        then: (@MainActor () -> Void)? = nil
    ) {
        guard let path, unavailable == nil, busy == nil else { return }
        busy = label + "…"
        notice = nil
        let git = self.git
        Task {
            let result = await git.run(path, arguments, timeout: timeout, network: timeout > 30)
            guard self.path == path else { return }
            self.busy = nil
            if result.ok {
                let summary = result.message.isEmpty ? "\(label) done" : result.message
                self.show(summary)
                then?()
            } else {
                self.show(result.message.isEmpty ? "\(label) failed" : result.message, error: true)
            }
            await self.reload()
        }
    }
}
