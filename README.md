# Daily Workspace

A calm, local-first Mac workspace for today. It shows your Apple Calendar agenda, a short task list, and your daily Markdown note from an Obsidian vault, and it has a smooth, spring-animated typing caret.

Native macOS · Swift · SwiftUI + AppKit · local-first notes and tasks · optional OpenRouter chat · no telemetry.

> **Status:** builds and launches on macOS 14+. Unit tests cover the core logic and the app's stores. Integrations that depend on permissions or accounts still need a hands-on pass with your own accounts and vault; see [docs/TESTING.md](docs/TESTING.md).

## Build and run

Requires macOS 14+ and Xcode 15+ command line tools (Swift 5.9 or newer).

```sh
swift test                              # unit tests
./scripts/build_and_run.sh --verify     # build, bundle, launch, confirm the process is running
scripts/bundle.sh release               # standalone build/DailyWorkspace.app
```

`scripts/build_and_run.sh` also supports `--debug` (runs under lldb), `--logs` (all process output) and `--app-logs` (only the app's own log channels).

## First run

1. **Choose your vault.** Click *Choose Vault…* on Today or Notes, or use **File → Choose Vault…**. Pick the folder that holds your Obsidian vault.
2. **Set where daily notes go.** In **Settings → Vault → Daily note**, enter the folder and a file-name template using the tokens `YYYY`, `MM` and `DD`. The tab shows the resulting path for today.
3. **Allow Calendar and Reminders**, if you want them, in **Settings → Permissions** or from the Calendar and Reminders screens. Denying either never blocks notes or tasks.
4. **Optional: AI chat.** Add an OpenRouter API key in **Settings → AI**.

## Screens

| Screen | What it does |
| --- | --- |
| **Today** ⌘1 | Date, agenda, tasks due today, a preview of today's note (only when today's note is the one open), capture |
| **Notes** ⌘2 | Markdown editor working on the vault's real files, recent notes, live text preview, backlinks, save status, conflict handling |
| **Tasks** ⌘3 | Today / Inbox / Upcoming / Completed; edit, link to a note, delete with undo |
| **Calendar** ⌘4 | Agenda for one day (⌘← / ⌘→ to move), create events, edit or delete one occurrence |
| **Search** ⌘5 | Searches note names and contents across the vault |
| **Reminders** ⌘6 | Apple Reminders: incomplete items, add, complete |
| **AI Chat** ⌘7 | OpenRouter chat, with optional **Attach Open Note** |
| **Settings** ⌘, | **Vault** (folder, daily-note template, syncing) · **Editor** (caret) · **AI** (key, model) · **Permissions** (Calendar, Reminders) |

**Command Palette** (⌘K) lists every screen and command, with its shortcut.

### Notes on specific screens

- **Search** scans visible Markdown files in the vault. It skips symlinks and files over 2 MB, and matches every term you type against both file names and contents. Click Refresh after changing files outside the app.
- **Backlinks** finds wikilinks and Markdown file links that point to the open note. A wikilink that uses only a basename can match more than one note. Embeds, images and full Obsidian rendering are not supported, and Preview is a text-oriented Markdown preview, not Obsidian's renderer.
- **Calendar:** double-click an event, or use its context menu, to edit it. Deleting asks for confirmation. For a repeating event, changes apply to that occurrence only.
- **Reminders:** Add writes to your default Apple Reminders list, and the circle marks an item complete. Refresh fetches changes made elsewhere. Reminders are separate from the app's own Tasks.

## Capture

| Surface | Open it with | Notes |
| --- | --- | --- |
| Quick Capture sheet | ⌘N, the toolbar | A sheet in the main window |
| Capture window | ⌥⌘N, the menu-bar sun icon → *Capture Window…*, or ⌘⇧Space from any app | A separate small window |
| Today screen | The Capture row | Inline |

All three use the same form. **Task for Today** adds a task due today. **Today's Note** appends `- your text` to today's daily note, creating the note if needed, and does not switch the note that is open in the editor.

The capture form closes only when your text has been saved. If something blocks the save (a conflict on today's note, an unwritable vault or task store), the form says why and keeps your text.

If ⌘⇧Space is taken by another app, the global shortcut falls back to ⌃⌥Space; the menu-bar menu shows which one is active. If both are taken, use the menu-bar item or ⌥⌘N. Daily Workspace stays a regular Dock app.

## Keyboard shortcuts

| Shortcut | Command |
| --- | --- |
| ⌘N | Quick Capture… |
| ⌥⌘N | Capture Window… |
| ⌘⇧Space (fallback ⌃⌥Space) | Capture window from any app |
| ⇧⌘T | Open Today's Note |
| ⌘S | Save Note |
| ⇧⌘R | Reveal Note in Finder |
| ⌘K | Command Palette… |
| ⌘1 … ⌘7 | Today, Notes, Tasks, Calendar, Search, Reminders, AI Chat |
| ⌘← / ⌘→ | Previous / next day in Calendar |
| ⌘↩ | Send a chat message |
| ⌘, | Settings |

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

- Notes, tasks and settings stay on this Mac. The app's own files live in `~/.config/daily-workspace/`: `settings.json`, `tasks.json` and `recovery/` (Settings → Vault → App data shows the folder). The API key stays in the macOS Keychain, not in that folder.
- There is no telemetry. Diagnostic logs go only to the local macOS unified log (subsystem `app.dailyworkspace.mac`) and never contain note text, chat content or keys.
- **AI chat** sends messages to OpenRouter and its providers, which may incur charges. The text of a note is sent only when **Attach Open Note** is checked. The API key is stored in the macOS Keychain. Chat history is kept in memory only, and Stop and Clear are available. The app never creates a key or sends a paid request on its own.
- Calendar and Reminders access is requested only when you ask for it, and is used only for the screens described above.

## Syncing

Daily Workspace has no sync engine of its own. To use the vault on more than one Mac, put the vault inside iCloud Drive, Dropbox, OneDrive or another synced folder, and keep its files downloaded. The sync provider moves the Markdown files. The app picks up external changes every two seconds and whenever you return to it, and it handles conflicting edits as described above. Local tasks, settings and chat history do not sync. Calendar and Reminders sync through your Apple accounts. The details are also in **Settings → Vault → Syncing**.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is organized. Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Credits and licensing

MIT licensed. The caret idea is inspired by [Neovide](https://github.com/neovide/neovide) (MIT) and [Monkeytype](https://github.com/monkeytypegame/monkeytype) (GPL-3.0). **No Monkeytype code is used or copied**; the presets are this project's own tuning. The particle presets are original lightweight effects inspired by Neovide, not a port of its renderer. See [docs/RESEARCH.md](docs/RESEARCH.md).
