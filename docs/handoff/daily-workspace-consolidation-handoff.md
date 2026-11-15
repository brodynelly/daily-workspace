# Handoff: Daily Workspace consolidation project

> **Historical plan (2026-11-13), not current operating instructions.** Owner decisions
> in `AGENTS.md` supersede proposed vault moves, external writes and automation.
> Live cutover evidence is in `docs/TESTING.md`; use
> `~/github/dotfiles-mac/skhd/README.md` for the current rollback procedure.
> A raw revert of the original dotfiles cutover commit now conflicts with later edits.

For: the Obsidian vault agent working in `~/github/brodynelly-brain`.
From: the Daily Workspace build session, 2026-11-13.
Your job: create a new project under `01-projects/` with its plan and migration notes, and create the opening tickets **in Luuna through the `lu` CLI** (`~/.local/bin/lu`), exactly as described here. **Create notes and tickets only. Do not change any application code.** Tickets live in Luuna (Missions behind the runtime), not in another tracker. Follow the vault's root `AGENTS.md` and `01-projects/personal/brodynelly-brain/workspace-operations.md` wherever they are stricter than this document.

---

## 1. What we are building (the decision)

Brody chose one app to drive his day: **Daily Workspace** (`~/github/misc/daily-workspace`, Swift/SwiftUI, macOS-only).

- **Quick Access Pascal (QAP)** is rebuilt *exactly* inside Daily Workspace as a hotkey-summoned quick-launch panel: same views, rows, keys, F-key grammar, Turbo Pascal look, music player and attention handling. QAP's code is a reference, not a dependency.
- **Daily Workspace drives everything else**:
  - vault-connected AI chat
  - agents running on the Luuna runtime
  - notes, tickets and issues
  - ticket status and kanban
  - calendar and email
  - automations
- **Quick Access Modern (QAM)** is retired. Its Luuna-styled visual mapping and its CLI-bridge pattern (fixed argv, deadlines) are carried over as references.
- **Luuna** (`~/github/luuna/luuna`, the canonical tree) is the agent back end, and **`lu` is the one interface to it**: for people, for the vault agent and for Daily Workspace itself. Daily Workspace calls `lu <command> --json` through a fixed-argv runner, passing `LUUNA_URL` and `LUUNA_API_TOKEN` from the Keychain. It has no hand-written client for Luuna writes, runs or the board. Luuna has no ACP; its agent engine is Pi 1.3.0 over JSONL on stdio, inside the runtime. The runtime runs as a loopback service.
- **Platform:** macOS only (decided; a Tauri port was considered and not chosen).

Why: Daily Workspace already has the Assistant, notes, Open Loops, Calendar, a Luuna client, about 290 tests and green CI. QAP and QAM are single-commit launchers whose UI is one hand-written AppKit file.

## 2. Facts the agent must know (verified 2026-11-13)

| Fact | Consequence |
| --- | --- |
| The Luuna runtime is up (`lu health`: runtime ok, Pi 1.3.0). `lu projects` lists one project, **`brodynelly-brain` (the vault itself)**. | Tickets go through `lu`. The daily-workspace repo is **not registered yet**, so §4 registers it. |
| An `01-projects/daily-workspace/daily-workspace.md` hub already exists. It is repository-linked. | Do not replace it. The new project is the consolidation programme; link the two both ways. |
| `lu create-ticket <project>` takes `--title`, `--intent`, a repeatable `--criterion`, `--repository`, `--purpose feature\|testing_setup` and `--key` (idempotency), and has no dependency flag. | Put "Depends on: Txx" in the intent, and use `--key dwc-Txx` so re-running never duplicates. Check with `lu create-ticket --help` first. |
| `vault-catalog.md` is generated. | Run `just vault-catalog-refresh`, then `just vault-check`. Never hand-edit the catalog. `vault-check` has known unrelated failures; report them, don't fix them. |
| Luuna paths in the app's docs (`~/github/luuna-ai/luuna`, `~/github/luuna-ai-os-main`) no longer exist on this Mac. | Ticket T03 fixes the app docs. QAP's Workspaces view also scans `~/github/luuna-ai-os-main`, which ticket T07 fixes. |
| `lu board [--project <p>] [--json]` shows tickets by workflow state with their runs, and `lu home` shows what needs attention. | Daily Workspace's board is `lu board --json` (T14); there is no client-side rebuild. |
| `lu missions\|atlas\|beacon …` run component CLIs **in the current directory** (`.luuna/missions/` etc.), with no runtime and no approval. | Never use `lu missions` for these tickets: it writes a local store in whatever folder you're in. Use the runtime commands (`lu create-ticket`, `lu tickets`, `lu board`). |
| QAP is not installed: no `~/Applications` app, no `~/.local/bin/qap`, and its dotfiles patch is not applied. Hammerspoon is still live for some routes. | The migration retires Hammerspoon routes and QAP together (§6). |

## 3. Project to create

- **Slug:** `daily-workspace-consolidation` (vault project slug; the Luuna project id is `daily-workspace`). If Brody prefers to grow the existing `daily-workspace` hub instead, stop and ask.
- **Location:** `01-projects/daily-workspace-consolidation/daily-workspace-consolidation.md`, plus `notes/`.
- **Hub frontmatter:** follow `templates/project.md` and the neighbouring hubs.
  - `type: project`, `status: active`, `start: 2026-11-13`, `project: daily-workspace-consolidation`.
  - `tags: [project, daily-workspace-consolidation, workspace]`.
  - No invented keys.
- **Hub body.** Use the existing `daily-workspace.md` hub as the shape, with these sections:
  1. `# Daily Workspace Consolidation`
  2. **Purpose and boundary:** §1 above in 4–6 sentences.
  3. **Repositories:** Daily Workspace (`file:///Users/bnelly/github/misc/daily-workspace/`), QAP (`…/misc/quick-access-pascal/`, reference, to retire), QAM (`…/misc/quick-access-modern/`, to retire), Luuna runtime (`/Users/bnelly/github/luuna/luuna`), dotfiles (`~/github/dotfiles-mac`: skhd, sketchybar and kitty helpers).
  4. **Task and agent authorities:** these tickets live in Luuna project `daily-workspace` (see them with `lu tickets daily-workspace` and `lu board --project daily-workspace`). The vault holds context only; it doesn't copy the tickets as checkboxes or duplicate issues. The app repo keeps its own docs (`AGENTS.md`, `docs/SYSTEM-INVENTORY.md`).
  5. **Decisions** (from §1) and **Open decisions** (from §7).
  6. **Context and sessions:** links to the notes below.
  7. Footer: `[[01-projects|All Projects]] · [[home|Home]]`.
  - **Do not copy the template's Tasks checkboxes.** Tickets live in Luuna (`lu`).
- **Notes** (`notes/`, kebab-case, each starting with frontmatter and one H1):
  - `plan.md`: §5 waves and tickets, as readable context with ticket ids filled in after creation.
  - `migration.md`: §6.
  - `qap-parity-checklist.md`: §8, the exact-recreation checklist.
  - `project-state.md`: from `templates/project-state.md`.
    - Current reality: Increments 0–3 shipped, QAP and QAM still separate.
    - Next executable action: T01.
    - Exact restart: `cd ~/github/misc/daily-workspace && swift build && swift test`.
- **Navigation:**
  - Add a bullet under "Repository-Linked Workspaces" in `01-projects.md` and bump its `updated:`.
  - Add a link from `01-projects/daily-workspace/daily-workspace.md` → the new hub, and back.
  - Refresh the catalog, then run `just vault-check`.

## 4. Order of operations for the vault agent

0. **Authority and setup check.** The owner confirmed on 2026-11-13 that Luuna/Missions owns project issues and plans. Run documented health/project reads and verify the intended app binding. Retired tooling is not a prerequisite. Obtain authorization for new registration and show the discovered manifest before confirmation.
1. Create the hub, the notes and the navigation links (§3). These are vault writes only.
2. **Register the app repo in Luuna** (from any directory except the vault):
   ```sh
   lu register daily-workspace app /Users/bnelly/github/misc/daily-workspace
   lu discover daily-workspace          # read-only manifest proposal
   lu confirm daily-workspace <manifest-revision>   # Brody confirms the exact revision
   lu enable-components daily-workspace # Missions, Atlas and Beacon, so tickets have an authoritative source
   ```
   Check each command's `--help` first. Confirming the manifest is Brody's call; show him the proposal.
3. Create the tickets in §5 in order with `lu create-ticket daily-workspace … --key dwc-Txx --json`, and record each returned ticket id in `notes/plan.md`.
4. Check them with `lu tickets daily-workspace` and `lu board --project daily-workspace`.
5. `just vault-catalog-refresh`, then `just vault-check`. Report the results.
6. Report back the hub path, the ticket ids, the commands that ran and anything blocked.

## 5. Plan and tickets

Each ticket below is one Luuna ticket. Its title is `--title`. The context and dependencies go in `--intent`, and each AC item is one `--criterion`. The **[decision]** tickets need Brody's answer before implementation. All app work happens in `~/github/misc/daily-workspace` and must pass `swift build && swift test`, both swift-format versions (CI uses 6.1) and `swiftlint --strict`.

Example command shape (adapt the flags):

```sh
lu create-ticket daily-workspace \
  --title "T01 Remove the dead OpenRouter chat from Daily Workspace" \
  --intent "Context … Depends on: none" \
  --criterion "No OpenRouter reference remains" \
  --criterion "swift build, swift test, swift-format 6.1 and local, swiftlint --strict all pass" \
  --repository app --key dwc-T01 --json
```

### Wave 0: decisions and baseline

- **T00 [decision] Approve Increment 4 (write adapters and automations) for Daily Workspace.**
  - Context: the app's `AGENTS.md` and `docs/SYSTEM-INVENTORY.md` §12 keep Org and Luuna read-only. Creating tickets and notes, and running automations, needs an approved proposal. Proposed: **all Luuna writes go through `lu`** (`create-ticket`, `edit-ticket`, `plan`, `approve`, `implement`, `publish`) with a confirmation before each one and a `--key` for idempotency. Vault notes go through `NoteVault`. Project work uses Luuna/Missions; coordination stays in visible notes.
  - AC: a written proposal in the app repo (`docs/proposals/write-adapters.md`), Brody's recorded approval, and the `AGENTS.md` decisions log updated.
  - Blocks: T16–T20.
- **T01 Remove the dead OpenRouter chat.**
  - Delete `Features/Chat/{OpenRouterClient,ChatService,ChatView}.swift`, `ChatServiceTests`, `FakeTransport` and `AppModel.chat`.
  - Move `APIKeyStore.swift` to `Shared/` (Assistant and Luuna use it).
  - Drop the `openRouterModel` setting (the decoder ignores unknown keys), fix the "Chat history stays in memory" copy and update the docs.
  - AC: no `OpenRouter` reference left; all checks green.
- **T02 [decision] Dock icon or menu-bar-only.**
  - QAP is an accessory app with no Dock icon; Daily Workspace forces `.regular`.
  - Options:
    - keep the Dock icon and add the panel;
    - accessory by default and `.regular` while the main window is open (recommended);
    - a separate helper process.
  - Also decide whether closing the main window keeps the app running (it must, for the panel).
  - AC: the decision is logged in the app's `AGENTS.md`.
- **T03 Make `lu` the Luuna interface and fix the paths.**
  - Update the app's `AGENTS.md` and `SYSTEM-INVENTORY.md`: Luuna is reached only through `lu … --json`; the canonical tree is `~/github/luuna/luuna`; the `lu` binary is `~/.local/bin/lu`.
  - Remove the old `luuna-ai` paths.
  - Decide whether the existing Swift `LuunaRuntimeClient` stays for read-only polling or is replaced by `lu` (recommended: replace it, so there is one contract).
  - AC: no doc names a missing path, and the decision is logged.

### Wave 1: the exact QAP quick-launch panel inside Daily Workspace (depends on T02)

- **T04 Quick panel shell.**
  - A borderless `NSPanel` hosting SwiftUI:
    - 1060×680, clamped to the mouse screen's visible frame minus 36, centred;
    - modal-panel level; joins the active Space and full-screen auxiliary; movable by background; shadow;
    - glass background (`NSGlassEffectView`, tint `#081b40` at 0.48), with the `#0d203b` fallback under Reduce Transparency.
  - Focus behaviour: remember the frontmost app and window on show. Esc or an action restores them. An outside click, a lost key status or an app switch hides without restoring.
  - Opens in ≤100 ms (QAP measured a 12 ms native show).
  - AC: the parity checklist §8 "Panel" items pass by hand.
- **T05 Pascal skin and layout.**
  - Double-line pane frames, top menu strip, bottom band, command pane, document pane, preview pane, colours, fonts (JetBrains Mono default; VGA optional and bundled with its CC BY-SA licence) and column fractions, exactly per §8 "Look".
  - The skin is a theme of the panel; the main window keeps the Luuna design system.
  - AC: side-by-side screenshots match QAP.
- **T06 Key grammar.**
  - All keys in §8 "Keys": type-to-search, AND matching and modifier aliases, arrows, Return, ⌘Return, ⌘Delete, the Esc ladder, Tab panes, ⌘1…9/0, ⌘⇧S/A, F1–F11, Option-menus, ⌘R/F/W.
  - Footer hints with gold F-keys.
  - AC: unit tests for the search grammar (port QAP's `model.rs` tests) plus a manual key checklist.
- **T07 Data views.**
  - Home, Agents, Sessions, Files, Projects, SSH, tmux, Workspaces, the Launch in workspace page, and the Shortcuts index and drill-in, all reading the same dotfiles helpers.
  - Helpers are called through one fixed-argv runner: 15 s deadline, process-group kill, 16 MiB cap, Homebrew PATH. Take the pattern from QAP `src/command.rs` and QAM `bridge.rs`.
  - Fix the Workspaces scan root from `~/github/luuna-ai-os-main` to the real tree.
  - Watch `hammerspoon/shortcuts` and `colorscheme/active` live.
  - AC: §8 "Views" rows match QAP for the same machine state.
- **T08 Attention.**
  - Watch `/tmp/sketchybar-opencode-agents.json`.
  - Attention rows with a 40-line terminal preview; Go to agent, Dismiss and All agents.
  - Auto-open on new attention, but **not** at launch for items already pending; QAP likely does this, and it should be fixed.
  - AC: the parity items pass; no auto-open at launch.
- **T09 System panel.**
  - Preferences, Activity, Lock Screen (display sleep), BT Restart, Restart (native confirmation).
  - Anchored near the mouse under the menu bar.
  - AC: each action works, and Restart always asks first.
- **T10 Turbo Music.**
  - Port `music.js` JXA: library and playlists, play/pause/stop/next/prev, volume ±, status polling at 900 ms only while visible or queueing, the shuffle queue and its animation, Reduce Motion.
  - Map error 1743 to an Automation-permission message, and keep a read-only preview fixture.
  - AC: the music parity items pass.
- **T11 Integrations.**
  - Clipboard feedback (changeCount poll every 0.15 s and the sketchybar item).
  - The Kitty quick-access window border (AX plus a fallback timer; colour from the active colorscheme).
  - `QAP_INTEGRATIONS`-style off switch, sleep/wake handling.
  - AC: integrations stop on sleep and resume on wake.
- **T12 Control surface.**
  - A 0600 Unix socket and a CLI (`daily show|toggle <view>`, `hide`, `status`, `inspect`, `attention-refresh`, `palette-reload`, `clipboard`, `mouse center|corner`) with the same accepted-action allow-list as QAP's `ipc.rs`, plus `--config`.
  - Starts the app if it isn't running.
  - Config file at `~/.config/daily-workspace/quick-panel.json`, mirroring QAP's keys.
  - AC: skhd can drive every view.

### Wave 2: Luuna through `lu` as the driver (depends on T03; writes depend on T00)

- **T13 `lu` runner and runtime lifecycle.**
  - One fixed-argv runner in Daily Workspace for `lu <command> --json`: absolute path `~/.local/bin/lu`, deadlines, process-group kill, an output cap, and `LUUNA_URL`/`LUUNA_API_TOKEN` passed from the Keychain in the environment. The token is never written to a file.
  - Parse `--json` records, and map `lu` failures to the source states (unauthorized, unavailable, refused…).
  - Lifecycle: `lu health` for status, `lu shutdown` to stop. Starting the runtime when it is down is a decision for Brody (auto-start vs leaving it to him).
  - Never run `lu missions|atlas|beacon` from the app (they write `.luuna/` in the working directory).
  - AC: health, projects and errors are shown correctly; tests use a fake runner.
- **T14 Projects, home and board through `lu`.**
  - `lu projects --json`, `lu project <p> --json` and `lu home --json` feed Projects and Today.
  - `lu board --project <p> --json` feeds a board view, with the runtime's workflow states shown verbatim.
  - `lu tickets <p>` and `lu show-ticket <t>` feed ticket detail.
  - AC: the board matches `lu board` for `daily-workspace`.
- **T15 Agent runs through `lu`.**
  - `lu start-session <prompt>` for isolated Pi sessions; `lu runs`, `lu run <r>` and `lu follow <r>` (streamed) for runs; `lu cancel <r>`.
  - Shown in the Assistant screen and in the quick panel's Agents view.
  - A run's `completed` status never closes a ticket.
  - AC: a session streams live, resumes after a reconnect and can be cancelled.

### Wave 3: writes and automations (depend on T00 approval)

- **T16 Tickets through `lu`.**
  - `lu create-ticket` (with `--key`) and `lu edit-ticket` (at the expected revision), then `lu plan`, `lu approve` (an exact hash, shown to Brody) and `lu implement`; `lu publish` stays Brody's call.
  - Confirm before every write; "Saved" appears only after `lu` returns the record.
  - AC: a retry never duplicates, and a stale edit is refused.
- **T17 Capture to Luuna.**
  - Quick capture gets an explicit "Luuna ticket" destination (project picker), which calls `lu create-ticket`.
  - AC: a captured ticket appears in `lu tickets` and on the board.
- **T18 Create vault notes and append to Org inbox.**
  - Through `NoteVault`'s atomic, conflict-checked writes.
  - The Org append must not race with Emacs.
  - AC: the vault-safety invariants hold.
- **T19 Automations.**
  - App-owned scheduled jobs stored in `~/.config/daily-workspace`, invoking `lu` commands or read-only refreshes.
  - A visible owner and log for each run; no unattended writes or model calls without explicit opt-in.
  - AC: an approved first automation runs and is logged.
- **T20 Persisted Assistant transcripts.**
  - Append-only files in `~/.config/daily-workspace`, mode 0600, thinking blocks byte-identical, with a defined meaning for "Clear".
  - AC: restore after relaunch.

### Wave 4: life consolidation

- **T21 Email as a read-only Open Loops source.**
  - Mail.app or the Gmail API; a permission state that never reads as "nothing to do".
  - Excluded from the Assistant unless enabled.
  - AC: flagged or unread-important mail appears with its source.
- **T22 Calendar in the quick panel.** Today's agenda rows and a "next event" in the panel; Calendar is already built.
- **T23 Assistant golden-set eval.** About 20 questions over a synthetic vault (SYSTEM-INVENTORY §10) before the Assistant is on by default.
- **T24 Polish.** Format Org timestamps (`<2026-11-12 Thu>` → a readable date) and render Markdown in hub prose.

### Wave 5: migration and retirement (see §6)

- **T25 Switch the hotkeys and integrations to Daily Workspace.**
- **T26 Retire QAP, QAM and the remaining Hammerspoon routes.**

## 6. Migration plan

1. **Run in parallel.**
   - Keep QAP's dev build and QAM installed until T04–T12 pass the parity checklist.
   - Give Daily Workspace's panel temporary different chords while testing, so the existing Option-Shift F12/F13/F16/F17 (QAP) and F2–F5 (QAM) keep working.
2. **Dotfiles changes** (`~/github/dotfiles-mac`, one commit, reversible):
   - `skhd/skhdrc` L124-132: point the QAP launcher at `daily toggle <view>`. Decide on the QAM block (L116-122) and the planned `ctrl+alt+cmd - k/m` (L58, L60), which currently call Hammerspoon.
   - `skhd/quick-access-pascal.sh`: replace with a `daily-quick.sh` launcher that keeps the same view names.
   - `sketchybar/items/apple.sh:4` and `sketchybar/plugins/opencode.sh`: use the new CLI for the Apple menu and attention refresh.
   - Reuse `quick-access-pascal/docs/integration-preview.patch` as the checklist of every Hammerspoon call site to replace (including `agents.sh`, `zshrc/colorscheme-set.sh`, `setup/check.sh`).
3. **State to carry over.**
   - QAP config (`~/.config/quick-access-pascal/config.json`, if present) becomes `~/.config/daily-workspace/quick-panel.json`.
   - The shortcut JSON stays in dotfiles (read live).
   - Music and shuffle state are in-memory only; nothing to migrate.
   - Daily Workspace data is already in `~/.config/daily-workspace/`.
4. **Login and start-up.**
   - Daily Workspace becomes the single login item.
   - Remove QAP's LaunchAgent `dev.bnelly.quick-access-pascal` or its SMAppService entry, and QAM's launcher.
5. **Permissions.** Grant Accessibility, Automation (Music, System Events) and Bluetooth to Daily Workspace, then revoke them from QAP and QAM.
6. **Retire.**
   - Archive QAP and QAM: README pointing to Daily Workspace, repos kept, no deletion.
   - Move their vault hubs, if any, to `04-archive/` through the vault workflow.
   - Remove the Hammerspoon modules only after nothing calls them.
7. **Rollback.** Revert the dotfiles commit and re-enable the QAP login item; QAP's build stays in `dist/`.

## 7. Open decisions for Brody (put these in the hub)

1. **T00:** approve writes and automations (which owners, confirmation per write).
2. **T02:** Dock icon vs menu-bar-only.
3. **Project slug:** a new project vs growing the existing `daily-workspace` hub.
4. **QAM:** retire it entirely, or keep its F2–F5 chords mapped onto Daily Workspace views.
5. **Email source:** Mail.app or the Gmail API.
6. **Vault exclusions:** should `00-inbox/openwhispr-notes` and `00-inbox/copilot` be hidden from the Assistant and Open Loops? They are currently included.
7. **Root note:** the stray `2026-11-12.md` in the vault root from the old daily-note bug; delete it by hand if wanted.
8. **Runtime start:** should Daily Workspace start the Luuna runtime when it is down, or only show that it's down?

## 8. QAP parity checklist (put in `notes/qap-parity-checklist.md`)

Source of truth: `~/github/misc/quick-access-pascal`. `native/app.m` holds the UI, `src/backend.rs` the behaviour and `src/model.rs` the search.

**Panel**
- Borderless glass panel, 1060×680, clamped, centred.
- Modal-panel level, joins the active Space, full-screen auxiliary.
- Starts hidden.
- Menu-bar item `▣`: left-click toggles Home; Option-click opens the menu (Open, Agent sessions, Keyboard shortcuts, Turbo Music, System, Accessibility Settings…, Start at login, Quit). The title shows `▣ !` on error.
- Focus restore on Esc or an action; hide without restore on an outside click or app switch.

**Views**
- Home: agents, kitty sessions, Claude and Codex desktop apps and their windows. Search also covers files, workspaces and targets.
- Agents, Sessions (⌘Delete closes), Files.
- Projects, SSH and tmux from `kitty-zoxide-session.sh --targets`. ⌘Return on a project opens the actions page. A typed path gives "New session at…".
- Workspaces, then Launch in workspace (opencode, claude, codex, pi, verify scripts, via the kitty remote socket).
- Shortcuts: 13 tools, drill-in, search across all.
- Attention: preview, focus, ack.
- System. Music.
- Document title `<VIEW>.PAS`. Version label "QUICK ACCESS / PASCAL" (rename for Daily Workspace).

**Keys**
- Type-to-search with AND matching, diacritic-insensitive; single-letter exact key-name match; modifier aliases.
- Arrows, Home/End, Page Up/Down (page = height ÷ 28).
- Return, double-click, ⌘Return (alternate), ⌘Delete (remove).
- The Esc ladder: clear search → unzoom → hide preview → back → hide.
- ⌥X and ⌘W hide; Tab and ⇧Tab cycle panes.
- ⌘R refresh, ⌘F find, F9 refresh.
- ⌘1…9: Workspace, Agents, Sessions, Files, Projects, Workspaces, SSH, tmux, Shortcuts. ⌘0 Music, ⌘⇧S System, ⌘⇧A Attention.
- F1 help, F2 Agents, F3 find, F4 Projects, F5 Sessions, F6 Files, F7 Workspaces, F8 Keys, F10 menu, F11 zoom.
- Music F-keys: F2 Random, F4 Shuffle, F5/F6 volume, F7 Prev, F8 Play, F9 Next. ⌘+/− volume ±5.
- ⌥F/E/P/S/W/H menus. Space plays in any non-command pane.

**Look**
- Pane frames: double-line frames (outer rule inset 0.5, inner 3.5), pane fill `#06172f` at 0.2, active border `#b4ebf1`, inactive `#81a1b7`.
- Pane titles: on the border, title box `#102541`, active title `#f3dd96`.
- Bands and overlay: bands `#42627d` at 0.45, overlay `#09234a` at 0.36.
- Rows and table: 28 pt rows, header `#0a2444` with text `#78e0e6`, selection `#38bad0` at 0.36. Column fractions 4.5/30/43.5/22 (music 5.5/40/24.5/21.5/8.5).
- Text: primary `#e0edf4`, meta `#8bb3c6`, attention prefix `! ` in `#ffa99a`.
- Footer and notices: footer `#d8eaf0` with F-keys in `#f3ce83`, notice `#f4cd81`, prompt `>` in `#f3dd96`.
- Fonts: 13 pt body, 11 pt footer.
- The Kitty quick-access border defaults to `#37f499` or comes from the colorscheme.

**Behaviour and performance**
- Helpers run off the UI thread with deadlines.
- Music polls only while visible.
- Sleep and wake stop and resume timers.
- Hidden idle CPU about 0.2% and show time about 12 ms (QAP's measured numbers; match or beat them).
- Known QAP issues *not* to copy: attention auto-opens at launch; `--help` omits workspaces; the README understates the Space key.

## 9. Rules for whoever implements the tickets

- **App rules:** follow `~/github/misc/daily-workspace/AGENTS.md`:
  - every item keeps its owner and its native status;
  - external sources stay read-only until T00 is approved;
  - app files live in `~/.config/daily-workspace/`, and secrets stay in the Keychain;
  - green only for verified states.
- **Luuna hazards:**
  - Use `lu` for everything Luuna; never call the HTTP API by hand and never run `lu missions|atlas|beacon` (or `lms`) from the vault: Direct component commands select stores by working directory; verify the selected source before use.
  - The existing vault registration is separate from the application registration; verify identity and do not silently rebind either one.
- **Committing:** commit only when asked; never sweep another agent's staged work into a commit.
- **Reporting:** report the real exit status of `swift test`, and lint with swift-format 6.1 as well as the local version.
