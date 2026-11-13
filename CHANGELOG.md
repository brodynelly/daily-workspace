# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

- **Calendar layout:** seven-day hourly grid with pinned day headers, an all-day row and overlapping event lanes; a right-side month picker selects a day and shows its agenda. Week arrows move seven days; existing EventKit editing and theme remain unchanged.

### Added
- **A new look, ported from Luuna's desktop design system:** Mantine's colours in light and dark (following macOS), the system font for text and the bundled Outfit font for headings, six status tones that each pair a colour with a shape, a 240 pt sidebar, a 56 pt top bar with **Go to… ⌘K**, page headers with one sentence each, record rows, stat tiles, callouts and empty states. Hover changes only the background; nothing lifts or slides.
- **Six screens instead of seven:** Today, Projects, Open Loops, Notes, Calendar and Assistant (⌘1…⌘6). Search lives inside Notes (⇧⌘F); Tasks and Reminders live inside Open Loops.
- **Collapsible sidebar:** the main-window top bar has an accessible hide/show button (⌃⌘S); the content column expands when the sidebar is hidden and the Go menu remains available.
- **Configurable keyboard shortcuts:** Settings → Keyboard searches a grouped reference and records one/two-key bindings, with conflict checks, Clear/Reset and persisted overrides. Superhuman-like `/` search, `?` contextual AI sidebar, F1 shortcut help and `G` then screen-letter navigation are defaults; menu, palette, calendar, Assistant and focused Quick Panel controls use effective bindings. Text editing and native modal keys retain their system behavior.
- **Open Loops** combines local tasks, Apple Reminders and separately opted-in read-only Mail metadata. Native Luuna board/ticket records stay in Projects; Mail is excluded from the Assistant.
- **Projects** combines Markdown hubs under `01-projects/` with native Luuna project board and ticket context and the latest restart record. Associations stay in the app folder.
- **Luuna** uses fixed-argument, read-only `lu` JSON CLI queries for project, board, ticket and Home data with a validated loopback origin; no in-app live HTTP client or external write path.
- **Native run reads** list bound-project Luuna runs and inspect one run's authoritative state in Assistant; Quick Panel Agents retains existing Kitty rows alongside native run-state rows. Bounded `lu follow` streams events from the last complete sequence and clears them on run or credential changes; start/cancel remain gated and absent.
- **Today** is rebuilt on Luuna's Home: stat tiles, what's due today and overdue (only items with their own date), the agenda, today's note and capture with an explicit destination.
- **Assistant**: grounded read-only model tools over eligible Markdown notes, local/Reminders loops, projects and calendar. Restart records save only on acceptance; cited answer text can become an editable vault-note draft, but only an exact-path before/after preview and separate human confirmation perform a conflict-checked save.
- **Contextual AI sidebar:** `?` opens the shared conversation beside any screen; Calendar day and eligible selected project/note paths attach only when asked. Quick Panel File → Quick AI Chat opens the same Assistant. On-device voice dictation is off until tapped, never auto-sends and needs explicit microphone/Speech permission; spoken final replies require a separate toggle.
- **Daily notes follow Obsidian's settings:** the path, format and template come from `.obsidian/daily-notes.json` (Moment tokens such as `MMM` and `dddd`). Settings → Vault offers Obsidian settings or Custom.
- One command registry (`AppCommand`) builds the menu bar and the command palette. The palette now lists every screen ("Go to …") and every command, including Save Note, Reveal Note in Finder and Capture Window, each with its real shortcut.
- **Settings → Permissions** shows the status of Calendar and Reminders and offers "Allow … Access…" or "Open System Settings".
- **Settings → AI** shows whether the selected provider's key is saved and offers Replace or Remove. The Assistant empty state hides its setup link once that provider has a key.
- **AI providers:** Settings → AI selects Anthropic or OpenRouter Messages streaming, with separate Keychain keys and model IDs. Provider changes clear the memory-only transcript; no Claude subscription OAuth or model write tools. The Assistant can discover eligible project hubs before reading native work or the vault's knowledge-base navigation notes.
- Empty states for Search ("No Markdown notes", no matches) and Reminders ("No open reminders").
- Structured logging through `os.Logger` (subsystem `app.dailyworkspace.mac`), with one channel per feature, instead of silently ignored failures.
- App-layer unit tests (`DailyWorkspaceTests`) for the note document, tasks, capture, Assistant, calendar and reminders, using fake services.
- swift-format and SwiftLint configurations, run as CI gates. CI also checks the Reminders usage string.
- `docs/ARCHITECTURE.md`, `docs/TESTING.md`, `CONTRIBUTING.md` and this changelog.
- **Quick Access Pascal panel** with route navigation, keyboard controls, and a bundled `daily` control CLI for opt-in skhd bindings. The symlink installer refuses to replace other files and never launches the app; the CLI may launch it when invoked. The bundled VGA font is registered for the panel with a system monospaced fallback if unavailable at runtime.
- **Quick-panel parity corrections:** the borderless window hides without stealing focus back when it loses key status, the Pascal panes use the available height, Attention keeps its All agents action without a selected preview, and music permission failures include actionable Automation guidance. File and palette changes refresh the opted-in Kitty border.
- Panel controls now include opt-in Zen pointer centering with Accessibility consent, explicit End Shuffle in both Music menus, and an on-screen lower-right corner placement. Notification-only `daily` refresh and clipboard commands no longer activate the app on cold start.
- The panel now shows Calendar and selected-run previews, and its control responses include clipboard-change metadata only when that integration is enabled. If quitting is blocked by an unsaved note conflict, Return to Notes reopens the workspace.
- **Settings → Permissions** offers separate off-by-default Mail metadata, clipboard change-count and Kitty border toggles; Mail requests Automation permission only on a read and never exposes bodies or Assistant context.

### Changed
- The app's own files now live in `~/.config/daily-workspace/`: settings in `settings.json` (readable JSON instead of UserDefaults), tasks in `tasks.json` and conflict recovery copies in `recovery/`. On first launch, existing settings are imported and `tasks.json` is copied from `~/Library/Application Support/DailyWorkspace/`; the old files are left in place. **Settings → Vault → App data** shows the folder. Anthropic, OpenRouter and Luuna credentials stay in separate Keychain entries.
- The source is organized into `App/`, `Features/<Feature>/` and `Shared/`, and `DailyCore` into `Caret/`, `Vault/` and `Tasks/`.
- `AppState` is split into an `AppModel` coordinator and focused stores (`AppNavigation`, `Preferences`, `VaultSession`, `NoteDocument`, `TaskStore`). Every `UserDefaults` key now lives in `Preferences`.
- Disk, EventKit, Keychain and external reads now go through protocols (`TaskPersisting`, `RecoveryStoring`, `CalendarStore`, `ReminderStore`, `APIKeyStore`, `AgentTransport`, native Luuna readers). Assistant conversations stay in memory; HTTPS requests go only to the explicitly selected AI provider.
- Capture uses one form with local Task for Today, the configured daily note, the existing Quick Notes capture section and a user-named new `00-inbox/*.md` destination. Quick Notes and Inbox require editing, a full before/after preview and a separate path-specific confirmation; the inline Today capture stays compact.
- The Quick Capture sheet and floating window show four destination cards and a multiline entry field; only durable saves close the form.
- Capturing to Today's Note appends to today's note on disk without switching the note open in the editor.
- Capture reports success only once the text is saved. Otherwise it explains why and keeps the draft.
- Settings tabs are regrouped as Vault (including Syncing), Editor, Keyboard, AI, Luuna and Permissions.
- Settings now replaces content in the main app window with a Back control; no separate Settings window is created.
- Calendar and Reminders share one permission prompt and one set of wording.
- Recent notes, backlinks and search results show the note title together with its folder.
- "Search Actions…" is renamed **Command Palette…** (⌘K). The sidebar no longer has its own search field, so "Search" now means only the vault search screen.
- `Scripts/` and `script/` are merged into `scripts/`. `build_and_run.sh --telemetry` is renamed `--app-logs`.
- Caret preset names live in the app. `DailyCore` exposes `CaretPreset.effect` for the particle presets.
- The README is reordered for first-time users. The manual checklists moved to `docs/TESTING.md`.
- The owner removed Org from app sources, Today, Open Loops and Assistant without migrating existing Org content. Luuna app writes, scheduled jobs and persisted Assistant chats were explicitly declined; only reviewed vault Markdown adapters B/E were approved.

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
- A bound project's Markdown hub and restart context remain citeable when native Luuna ticket reads fail; the Assistant labels the native work state unavailable rather than falsely empty. Board cards label completed runs as run states, separate from native ticket status.
- The synthetic nested-repository exclusion fixture is recreated during tests so a clean Git checkout checks the same policy; CI also checks bundled microphone and speech usage descriptions.

### Removed
- The `DailyCore` library product. It is still a target; nothing outside the app used the product.
- The old plain AI chat and its separate model setting; the Assistant replaces it.
- The original product spec and plan moved to `docs/archive/`, marked as superseded.
- Retired Seeds/Plot parsing and direct loopback Luuna HTTP live reads from the current workflow.
- The obsolete Org parser and app integration; Org remains external and no Org vault files are changed.

## [0.1.0] - 2026-10-26

### Added
- Native SwiftUI/AppKit app with a spring-animated four-corner caret (Off, Glide, Trail, Comet, Railgun, Pixiedust) that respects Reduce Motion.
- Vault-safe daily notes: byte-preserving atomic saves, external-change conflict detection, and a recovery folder.
- App-owned tasks (Today, Inbox, Upcoming, Completed), linking tasks to notes, and undoable deletes.
- Apple Calendar agenda with event creation and editing of a single occurrence.
- Vault search, a backlinks inspector, and a live Markdown preview.
- Apple Reminders screen, AI chat (key stored in Keychain), and a command palette.
- Quick capture sheet, a capture window, a menu-bar extra, and a global ⌘⇧Space shortcut with a fallback.

### Changed
- Native macOS styling across the workspace. Sidebar screens switch instantly instead of crossfading.
