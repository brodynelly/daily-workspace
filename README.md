# Daily Workspace

> Owner update, 2026-11-13: Luuna/Missions owns project issues and plans; project Markdown holds context. Org remains external and is not routed through this app. T00 B and E approve only reviewed vault Markdown saves; the owner declined Luuna and Org app writes and scheduled jobs.

One calm Mac window over Apple Calendar and Reminders, your Obsidian vault and daily note, native Luuna/Missions project boards and tickets, the app's own tasks, and optional read-only Mail metadata. Each item keeps its owner and status. Assistant tools cite their sources but never receive Mail data. The look follows Luuna's desktop design system, and the editor has a spring-animated caret.

Native macOS · Swift · SwiftUI + AppKit · local-first · read-only views of external systems · optional AI Assistant · no telemetry.

> **Status:** the native Luuna and Quick Access Pascal cutover still needs automated and hands-on verification. The panel bundles a VGA font but uses a monospaced system fallback when the font is unavailable at runtime. Permission-dependent integrations, panel focus/keyboard parity and performance need owner-run checks; see [docs/TESTING.md](docs/TESTING.md). External Org and Luuna writes are not available.

## Build and run

Requires macOS 14+ and Xcode 15+ command line tools (Swift 5.9 or newer).

```sh
swift test                              # unit tests
./scripts/build_and_run.sh --verify     # build, bundle, launch, confirm the process is running
scripts/bundle.sh release               # standalone build/DailyWorkspace.app
```

`scripts/build_and_run.sh` also supports `--debug` (runs under lldb), `--logs` (all process output) and `--app-logs` (only the app's own log channels).

### Optional `daily` control CLI for skhd

`scripts/bundle.sh release` includes `daily` at the absolute path
`$(pwd)/build/DailyWorkspace.app/Contents/MacOS/daily` when run from the
repository root. The CLI controls the running app over its local socket; it
does not replace the app. Keep the bundle at that path if you use a symlink.

To opt in to a stable skhd command path, run `scripts/install_daily_cli.sh`
from the repository root. It creates only `~/.local/bin/daily`, a symlink to
the bundled executable, and refuses to replace another file or symlink. For
an app moved elsewhere, pass its absolute `.app` path as the argument instead.
The installer never runs `daily` or starts the app. Use the absolute
`$HOME/.local/bin/daily` path (expanded to your actual home path) in skhd
bindings; for example, `$HOME/.local/bin/daily toggle home` in a shell command.

Check the installation without starting the app with
`test -x "$HOME/.local/bin/daily"`. When you *explicitly* want to query the
socket, run `"$HOME/.local/bin/daily" status`; like other control commands,
`status` starts Daily Workspace if it is not already running. To undo the
symlink safely, run `scripts/install_daily_cli.sh --remove` (or pass the same
absolute `.app` path used at installation). Removal refuses to touch anything
other than that exact symlink.

### Quick Access Pascal panel

The bundled Quick Panel offers Home, Agents, Sessions, Files, Projects, Workspaces, SSH, tmux, Shortcuts, Attention, System, Turbo Music and Calendar routes; it is distinct from the six main workspace screens below. From a focused panel use ⌘0 for Music, ⌘1…⌘9 for Home through Shortcuts, ⇧⌘A for Attention and ⇧⌘S for System by default. ⌘F focuses search, ⌘R refreshes, Tab/⇧Tab cycles panes, arrows and Page Up/Down select rows, Return opens a selection, and Escape backs out or dismisses. ⌘W or ⌥X closes the panel. Panel routes, search, refresh, zoom and help can be rebound in Settings → Keyboard; contextual F2/F4–F8, music controls, pane navigation and ⌘W remain fixed. Panel controls are not global hotkeys: bind the absolute `daily` path in your own skhd configuration if desired.

`daily show <view>` and `daily toggle <view>` accept `home`, `agents`, `sessions`, `files`, `projects`, `workspaces`, `ssh`, `tmux`, `shortcuts`, `attention`, `system`, `music` or `calendar`; `daily hide`, `status` and `inspect` control or inspect the panel. The CLI starts the app when needed and waits up to 15 seconds for its control socket; installing its symlink does not launch anything. Panel configuration lives at `~/.config/daily-workspace/quick-panel.json`. The VGA font is bundled and registered for the panel; if a requested face is unavailable at runtime, the panel uses the system monospaced font.

Workspaces come from the dotfiles `workspace.py catalog` helper; unavailable helpers are shown as unavailable, not as an empty catalog. Kitty launch actions activate Kitty after a successful helper call. Music shuffle uses fresh order per invocation while keeping the selected first track.

On Attention, **All agents** remains available without a selected alert. Music Automation failures show an explicit permission message; clipboard and Kitty border integrations remain opt-in.


## First run

1. **Choose your vault.** Click *Choose Vault…* on Today or Notes, or use **File → Choose Vault…**. Pick the folder that holds your Obsidian vault.
2. **Check where daily notes go.** By default the app uses the vault's Obsidian Daily notes settings (`.obsidian/daily-notes.json`: folder, Moment format and template). **Settings → Vault → Daily note** shows today's path, or lets you choose Custom.
3. **Allow Calendar and Reminders**, if you want them, in **Settings → Permissions** or from Calendar and Open Loops. Denying either never blocks notes or tasks.
4. **Optional: the Assistant.** In **Settings → AI**, enable it, choose **Anthropic** (default `claude-opus-5-5`) or **OpenRouter** (default `anthropic/claude-sonnet-4`, with an editable model ID), then save that provider's API key in the Keychain. Switching providers starts a new conversation and does not copy keys or model IDs. Claude subscription OAuth cannot authenticate this third-party app; use a Claude Console API key for direct Anthropic access. OpenRouter routes through its chosen upstream model provider; model tool/JSON support and charges depend on that model.
5. **Optional: Luuna.** Install the native `lu` CLI at `~/.local/bin/lu`, then enter a loopback runtime address and token in **Settings → Luuna**. The app invokes fixed, read-only JSON CLI commands for project boards, tickets, Home and bound-project runs; it does not connect to the runtime directly. Assistant shows run list, selected run detail and bounded live `lu follow` events even with AI off. Quick Panel Agents adds native run-state rows without replacing Kitty agent rows; open a run to inspect its detail and recent events. Event status belongs to the run, never to a ticket. No run start, cancellation or runtime shutdown is enabled.
6. **Optional: Mail and panel integrations.** In **Settings → Permissions**, separately enable Mail metadata, clipboard change count or Kitty window border only if you want each integration. Mail requests Automation permission on a subsequent read; no message bodies are read and Mail is excluded from the Assistant.

## Screens

| Screen | What it does |
| --- | --- |
| **Today** ⌘1 | Stat tiles, what's due today and overdue (only items with their own date), the agenda, today's note and capture with an explicit destination |
| **Projects** ⌘2 | Project hubs from `01-projects/`: context, decisions, repositories, native Luuna board/ticket status and the latest restart record |
| **Open Loops** ⌘3 | Local tasks, Apple Reminders and opted-in Mail metadata with source and native status; native Luuna project work remains in Projects |
| **Notes** ⌘4 | Markdown editor on the vault's real files, recent notes, preview, backlinks, save status, conflict handling, and vault search (⇧⌘F) |
| **Calendar** ⌘5 | Seven-day hourly grid with all-day events, week controls and a month picker; select a day for its agenda, create events, edit or delete one occurrence |
| **Assistant** ⌘6 | Read-only Luuna run list and cited questions about notes, local/Reminders loops, projects and calendar; reviewed restart drafts and separately confirmed Markdown note drafts |
| **Settings** ⌘, | Opens **inside the main window**, with Back returning to the prior screen: **Vault** (folder, daily note, app data, syncing) · **Editor** (caret) · **Keyboard** (search and rebind shortcuts) · **AI** (Assistant) · **Luuna** (native CLI connection) · **Permissions** (Calendar, Reminders, Mail, optional panel integrations) |

**Command Palette** (⌘K by default) lists every screen and command with its current shortcut. Settings → Keyboard provides a searchable, grouped reference: select Rebind, press a key (and optionally a second key), or choose Save One Key. Clear disables a binding; Reset or Reset All restores defaults. Conflicts, system-reserved keys and unsupported global hotkeys are refused. Shortcuts persist in `~/.config/daily-workspace/settings.json`; credentials remain in the Keychain.

On any workspace screen, press `?` (outside a text field) or use **Ask AI** in the top bar to open a right-side Assistant. It shares the Assistant screen's in-memory conversation and draft, follows the current screen, and supplies the selected Calendar day or an eligible selected project/note path as navigation context **only after Ask**. Context is not source evidence: answers still use cited read-only tools, and excluded notes and Mail remain unavailable. Close the panel with its close button (`?` also toggles it while not editing text); F1 opens the Keyboard reference. Both keys can be rebound in Settings → Keyboard.

The main-window sidebar can be hidden or shown with the leading toolbar button or ⌃⌘S by default. The choice is local to that window; navigation remains available through Go, ⌘1…⌘6 or the configurable `G` then screen-letter sequences while it is hidden. Bare shortcuts work only outside text editors, search fields and modal sheets.


### Notes on specific screens

- **Search** scans visible Markdown files in the vault. It skips symlinks and files over 2 MB, and matches every term you type against both file names and contents. Click Refresh after changing files outside the app.
- **Backlinks** finds wikilinks and Markdown file links that point to the open note. A wikilink that uses only a basename can match more than one note. Embeds, images and full Obsidian rendering are not supported, and Preview is a text-oriented Markdown preview, not Obsidian's renderer.
- **Calendar:** double-click an event, or use its context menu, to edit it. Deleting asks for confirmation. For a repeating event, changes apply to that occurrence only.
- **Open Loops:** Local tasks and Apple Reminders use their own stores; Mail metadata is read-only and off by default. Org remains entirely outside the app; Luuna project work appears in Projects with native status. Markdown checkboxes are not tasks. Archived, template and generated files are skipped before reading.

## Capture

| Surface | Open it with | Notes |
| --- | --- | --- |
| Quick Capture sheet | ⌘N, the toolbar | A sheet in the main window |
| Capture window | ⌥⌘N, the menu-bar sun icon → *Capture Window…*, or ⌘⇧Space from any app | A separate small window |
| Today screen | The Capture row | Inline |

The Quick Capture sheet, floating window and inline Today capture offer four explicit destinations: **Task for Today** saves to local tasks, **Today's Note** appends to the configured daily note, **Quick Notes** adds an entry under Capture in the existing `02-areas/personal-development/quick-notes.md`, and **Inbox Note** creates a named new Markdown note directly under `00-inbox/`. The latter two require editing the draft, previewing the exact before/after text and path, then separately confirming a conflict-checked save. Cancelling the review retains the edited draft in its capture form. No new folders, implicit vault-root files, automation/ingest writes or Org items are created.

If the target changes or the bookmark is unavailable, the draft remains for a fresh preview; the form reports why nothing was saved. The local task and daily-note destinations retain their existing durability checks.

If ⌘⇧Space is taken by another app, the global shortcut falls back to ⌃⌥Space; the menu-bar menu shows which one is active. If both are taken, use the menu-bar item or ⌥⌘N. Daily Workspace stays a regular Dock app.

## Keyboard shortcuts (defaults; change them in Settings → Keyboard)

| Shortcut | Command |
| --- | --- |
| ⌘N | Quick Capture… |
| ⌥⌘N | Capture Window… |
| ⌘⇧Space (fallback ⌃⌥Space) | Capture window from any app |
| ⇧⌘T | Open Today's Note |
| ⌘S | Save Note |
| ⇧⌘R | Reveal Note in Finder |
| ⌘K | Command Palette… |
| ⌘1 … ⌘6, or G then T/P/O/N/C/A | Today, Projects, Open Loops, Notes, Calendar, Assistant |
| / | Search notes (outside text editing) |
| ? | Open searchable Keyboard settings (outside text editing) |
| ⌃⌘S | Hide / show the main-window sidebar |
| ⇧⌘F | Search notes |
| ⌘← / ⌘→ | Previous / next week in Calendar |
| ⌘↩ | Ask the Assistant |
| ⌘, | Settings inside the main window |

## Typing caret

The editor hides the system caret and draws its own. Each of the caret's four corners moves on its own critically damped spring, computed in exact closed form so it is stable at any frame rate. The corners have different durations, so a long jump stretches into a trail while ordinary typing glides. The caret stays solid while you type and blinks when you stop.

| Preset | Feel |
| --- | --- |
| Off | System caret |
| Glide | Whole caret slides between characters (Monkeytype-style smooth caret) |
| Trail | Quick glide when typing, short trail on jumps |
| Comet | Long stretching trail (Neovide-style) |
| Railgun | Fading particle beam on caret movement |
| Pixiedust | Scattered fading sparks |

The app switches back to the system caret in these cases:
- during IME composition
- while text is selected
- when the preset is Off
- whenever macOS **Reduce Motion** is on

## Safety rules for your vault

- A note is saved exactly as the text you loaded plus your edits. Frontmatter, wikilinks, embeds, CRLF line endings and Unicode survive byte for byte, and there are no smart quotes or automatic replacements.
- Saves are atomic. If the file changed on disk after it was loaded (by Obsidian or a sync client), saving pauses and you choose *Reload From Disk* or *Keep My Version*. The version you discard is written to `~/.config/daily-workspace/recovery/`, never into the vault. If that copy cannot be written, nothing is discarded.
- The app never deletes, renames or moves vault files. A file that is not valid UTF-8 is refused, not rewritten. Paths, including symlinks inside the vault, can never lead outside the vault.
- A vault that has moved or whose access was revoked shows as its own state, with a button to choose it again.

## Privacy

- Notes, tasks and settings stay on this Mac. The app's own files live in `~/.config/daily-workspace/`: `settings.json`, `tasks.json`, `recovery/`, `restart-ledger.jsonl`, `associations.json`, `luuna-host.json` and optional `quick-panel.json` (Settings → Vault → App data shows the folder). API keys and the Luuna token stay in the macOS Keychain.
- The app invokes the native `lu` CLI with fixed read-only JSON arguments, a validated loopback Luuna address and `LUUNA_NO_AUTO_START=1`. The installed launcher must honor that flag by refusing reads when the runtime is stopped; a launcher that ignores it may start Luuna. Daily Workspace does not request runtime changes, shutdown or cancellation.
- There is no telemetry. Diagnostic logs go only to the local macOS unified log (subsystem `app.dailyworkspace.mac`) and never contain note text, chat content or keys.
- **The Assistant** is off until you enable it. When on, questions and the selected vault Markdown notes, non-Mail open loops, project details and events its tools read are sent to Anthropic or OpenRouter and its routed provider; charges may apply. `list_projects` finds vault hubs; `get_project` reads selected hub/native records, and `search_notes`/`read_note` navigate eligible Markdown only. Unavailable sources are not reported as empty. Model tools remain read-only: AI cannot write a vault note or Luuna ticket. For an answer with source paths, **Review draft in Notes** transfers editable cited text into the Notes screen without selecting a destination; choose **Review Assistant draft**, enter an eligible Markdown path, preview the full before/after and confirm a conflict-checked save. Cancel retains edits in memory. An accepted restart record is app-owned; conversation remains in memory. Opt-in voice dictation requires microphone and Apple Speech Recognition permission and on-device recognition; it fills a draft, never auto-sends. Spoken final replies require a separate explicit toggle; disabling it stops speech.
- Calendar and Reminders access is requested when you ask for it. Mail is separately opt-in, reads only message identifiers, subjects and flagged/unread status, and requests macOS Automation permission on a read. Clipboard change count and Kitty border integrations are separately opt-in; the clipboard integration does not read contents and the border integration does not read terminal contents.

## Syncing

Daily Workspace has no sync engine of its own. To use the vault on more than one Mac, put the vault inside iCloud Drive, Dropbox, OneDrive or another synced folder, and keep its files downloaded. The sync provider moves the Markdown files. The app picks up external changes every two seconds and whenever you return to it, and it handles conflicting edits as described above. Local tasks and settings do not sync; the Assistant transcript stays in memory and is not synced. Calendar and Reminders sync through your Apple accounts. The details are also in **Settings → Vault → Syncing**.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is organized. Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Credits and licensing

MIT licensed. The caret idea is inspired by [Neovide](https://github.com/neovide/neovide) (MIT) and [Monkeytype](https://github.com/monkeytypegame/monkeytype) (GPL-3.0). **No Monkeytype code is used or copied**; the presets are this project's own tuning. The particle presets are original lightweight effects inspired by Neovide, not a port of its renderer. See [docs/RESEARCH.md](docs/RESEARCH.md).
