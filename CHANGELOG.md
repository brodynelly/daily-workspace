# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **A new look, ported from Luuna's desktop design system:** Mantine's colours in light and dark (following macOS), the system font for text and the bundled Outfit font for headings, six status tones that each pair a colour with a shape, a 240 pt sidebar, a 56 pt top bar with **Go to… ⌘K**, page headers with one sentence each, record rows, stat tiles, callouts and empty states. Hover changes only the background; nothing lifts or slides.
- **Six screens instead of seven:** Today, Projects, Open Loops, Notes, Calendar and Assistant (⌘1…⌘6). Search lives inside Notes (⇧⌘F); Tasks and Reminders live inside Open Loops.
- **Open Loops** shows every open item across the systems that own it (Org, Seeds, Plot, local tasks and Apple Reminders) with its source and the owner's own status word. Each source reports its state honestly ("unavailable" is never shown as "nothing open"). Org, Seeds and Plot are read-only; their rows offer only **Open source**.
- **Projects** lists the project hubs under `01-projects/` with their purpose, decisions, repositories, Seeds issues, Plot coordination and the latest restart record. Linking a checkout or a Luuna project writes only `associations.json` in the app folder.
- **Luuna** (read-only): connect to a loopback Luuna runtime in **Settings → Luuna** (the token stays in the Keychain) and see a linked project's identity and component status, with last-observed times.
- **Today** is rebuilt on Luuna's Home: stat tiles, what's due today and overdue (only items with their own date), the agenda, today's note and capture with an explicit destination.
- **Assistant**: grounded questions over notes, open loops, projects and the calendar through read-only tools that cite what they read, using Claude via the Anthropic API (off until enabled in **Settings → AI**). It can draft a restart record for a project; nothing is saved until you accept it, and each accepted record keeps the hashes of the files it was based on so a later change is flagged.
- **Daily notes follow Obsidian's settings:** the path, format and template come from `.obsidian/daily-notes.json` (Moment tokens such as `MMM` and `dddd`). Settings → Vault offers Obsidian settings or Custom.
- One command registry (`AppCommand`) builds the menu bar and the command palette. The palette now lists every screen ("Go to …") and every command, including Save Note, Reveal Note in Finder and Capture Window, each with its real shortcut.
- **Settings → Permissions** shows the status of Calendar and Reminders and offers "Allow … Access…" or "Open System Settings".
- **Settings → AI** shows whether a key is saved and offers Replace or Remove. The chat empty state hides its setup link once a key exists.
- Empty states for Search ("No Markdown notes", no matches) and Reminders ("No open reminders").
- Structured logging through `os.Logger` (subsystem `app.dailyworkspace.mac`), with one channel per feature, instead of silently ignored failures.
- App-layer unit tests (`DailyWorkspaceTests`) for the note document, tasks, capture, chat, calendar and reminders, using fake services.
- swift-format and SwiftLint configurations, run as CI gates. CI also checks the Reminders usage string.
- `docs/ARCHITECTURE.md`, `docs/TESTING.md`, `CONTRIBUTING.md` and this changelog.

### Changed
- The app's own files now live in `~/.config/daily-workspace/`: settings in `settings.json` (readable JSON instead of UserDefaults), tasks in `tasks.json` and conflict recovery copies in `recovery/`. On first launch, existing settings are imported and `tasks.json` is copied from `~/Library/Application Support/DailyWorkspace/`; the old files are left in place. **Settings → Vault → App data** shows the folder. The API key stays in the Keychain.
- The source is organized into `App/`, `Features/<Feature>/` and `Shared/`, and `DailyCore` into `Caret/`, `Vault/` and `Tasks/`.
- `AppState` is split into an `AppModel` coordinator and focused stores (`AppNavigation`, `Preferences`, `VaultSession`, `NoteDocument`, `TaskStore`). Every `UserDefaults` key now lives in `Preferences`.
- Disk, EventKit, Keychain and network access now go through protocols (`TaskPersisting`, `RecoveryStoring`, `CalendarStore`, `ReminderStore`, `APIKeyStore`, `ChatTransport`).
- Capture uses one form and one set of labels ("Task for Today" / "Today's Note", "Capture") on the sheet, the window and the Today screen. The floating window is called "Capture Window…" everywhere.
- Capturing to Today's Note appends to today's note on disk without switching the note open in the editor.
- Capture reports success only once the text is saved. Otherwise it explains why and keeps the draft.
- Settings tabs are regrouped as Vault (now with a Syncing section), Editor, AI and Permissions.
- Calendar and Reminders share one permission prompt and one set of wording.
- Recent notes, backlinks and search results show the note title together with its folder.
- "Search Actions…" is renamed **Command Palette…** (⌘K). The sidebar no longer has its own search field, so "Search" now means only the vault search screen.
- `Scripts/` and `script/` are merged into `scripts/`. `build_and_run.sh --telemetry` is renamed `--app-logs`.
- Caret preset names live in the app. `DailyCore` exposes `CaretPreset.effect` for the particle presets.
- The README is reordered for first-time users. The manual checklists moved to `docs/TESTING.md`.

### Fixed
- Today's note was created in the vault root (`2026-11-12.md`) because the template knew only `YYYY`, `MM` and `DD` and the folder was empty; `MM` also corrupted `MMM`. The Obsidian source now never creates a note in the vault root.
- CI's swift-format 6.1 could not read `.swift-format` (the string form of `reflowMultilineStringLiterals`), so lint failed before checking any file.
- Today's "Today's Note" panel showed whichever note was open (for example last week's) as today's note. It now previews only today's note.
- Calendar's heading and its events fell out of sync when the app was reactivated or the day changed. The browsed day is now kept.
- New notes in a vault reached through a `/private` path (such as `/tmp`) were rejected as "outside the vault".
- A symlink inside the vault could resolve to a location outside it. Such paths are now refused.
- Resolving a conflict could discard a version when it could not be written to the recovery folder. Resolution now stops instead.
- Opening a recent note or a linked note that no longer exists failed silently. It now says so.
- A task change that could not be saved (complete, edit, delete, undo) stayed on screen and then disappeared on relaunch. Such changes are now rolled back and the reason is shown.
- "Keep My Version" reported success even when the save failed.
- A Keychain read failure showed as "no key saved". It is now reported as an error.

### Removed
- The `DailyCore` library product. It is still a target; nothing outside the app used the product.
- The original product spec and plan moved to `docs/archive/`, marked as superseded.

## [0.1.0] - 2026-10-26

### Added
- Native SwiftUI/AppKit app with a spring-animated four-corner caret (Off, Glide, Trail, Comet, Railgun, Pixiedust) that respects Reduce Motion.
- Vault-safe daily notes: byte-preserving atomic saves, external-change conflict detection, and a recovery folder.
- App-owned tasks (Today, Inbox, Upcoming, Completed), linking tasks to notes, and undoable deletes.
- Apple Calendar agenda with event creation and editing of a single occurrence.
- Vault search, a backlinks inspector, and a live Markdown preview.
- Apple Reminders screen, OpenRouter AI chat (key stored in Keychain), and a command palette.
- Quick capture sheet, a capture window, a menu-bar extra, and a global ⌘⇧Space shortcut with a fallback.

### Changed
- Native macOS styling across the workspace. Sidebar screens switch instantly instead of crossfading.
