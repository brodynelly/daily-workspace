# Daily Workspace

One calm Mac window over the systems that already own your day: Apple Calendar and Reminders, your Obsidian vault and its daily note, Org, Seeds and Plot, the app's own task list, and (optionally) a Luuna runtime. Every item keeps its owner and shows the owner's own status; actions route back to the owner. A read-only Assistant answers questions over all of it and cites what it read. The look follows Luuna's desktop design system, and the editor has a smooth, spring-animated typing caret.

Native macOS · Swift · SwiftUI + AppKit · local-first · read-only views of external systems · optional Claude Assistant · no telemetry.

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
2. **Check where daily notes go.** By default the app uses the vault's Obsidian Daily notes settings (`.obsidian/daily-notes.json`: folder, Moment format and template). **Settings → Vault → Daily note** shows today's path, or lets you choose Custom.
3. **Allow Calendar and Reminders**, if you want them, in **Settings → Permissions** or from Calendar and Open Loops. Denying either never blocks notes or tasks.
4. **Optional: the Assistant.** In **Settings → AI**, turn on **Enable the Assistant**, save an Anthropic API key (it goes to the Keychain) and, if you like, change the model (default `claude-opus-5-5`).
5. **Optional: Luuna.** Enter a loopback runtime address and token in **Settings → Luuna**.

## Screens

| Screen | What it does |
| --- | --- |
| **Today** ⌘1 | Stat tiles, what's due today and overdue (only items with their own date), the agenda, today's note and capture with an explicit destination |
| **Projects** ⌘2 | Project hubs from `01-projects/`: purpose, decisions, repositories, Seeds issues, Plot coordination, the latest restart record and an optional read-only Luuna panel |
| **Open Loops** ⌘3 | Every open item across Org, Seeds, Plot, local tasks and Apple Reminders, with its source and the owner's status. Local tasks and reminders keep their actions; the others open their source |
| **Notes** ⌘4 | Markdown editor on the vault's real files, recent notes, preview, backlinks, save status, conflict handling, and vault search (⇧⌘F) |
| **Calendar** ⌘5 | Agenda for one day (⌘← / ⌘→ to move), create events, edit or delete one occurrence |
| **Assistant** ⌘6 | Questions over your notes, open loops, projects and calendar through read-only tools that cite what they read; drafts restart records for your review |
| **Settings** ⌘, | **Vault** (folder, daily note, app data, syncing) · **Editor** (caret) · **AI** (Assistant) · **Luuna** (runtime connection) · **Permissions** (Calendar, Reminders) |

**Command Palette** (⌘K) lists every screen and command, with its shortcut.

### Notes on specific screens

- **Search** scans visible Markdown files in the vault. It skips symlinks and files over 2 MB, and matches every term you type against both file names and contents. Click Refresh after changing files outside the app.
- **Backlinks** finds wikilinks and Markdown file links that point to the open note. A wikilink that uses only a basename can match more than one note. Embeds, images and full Obsidian rendering are not supported, and Preview is a text-oriented Markdown preview, not Obsidian's renderer.
- **Calendar:** double-click an event, or use its context menu, to edit it. Deleting asks for confirmation. For a repeating event, changes apply to that occurrence only.
- **Open Loops:** Org, Seeds and Plot are read, never written; Markdown checkboxes are not treated as tasks. Archived, template, generated and board files are skipped before anything is read. New task adds to the app's own `tasks.json`; New reminder adds to your default Apple Reminders list.

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
| ⌘1 … ⌘6 | Today, Projects, Open Loops, Notes, Calendar, Assistant |
| ⇧⌘F | Search notes |
| ⌘← / ⌘→ | Previous / next day in Calendar |
| ⌘↩ | Ask the Assistant |
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

- Notes, tasks and settings stay on this Mac. The app's own files live in `~/.config/daily-workspace/`: `settings.json`, `tasks.json`, `recovery/`, `restart-ledger.jsonl`, `associations.json` and `luuna-host.json` (Settings → Vault → App data shows the folder). API keys and the Luuna token stay in the macOS Keychain, never in that folder.
- Luuna connections are accepted only on this Mac's loopback address; the app only reads, never starts or changes the runtime.
- There is no telemetry. Diagnostic logs go only to the local macOS unified log (subsystem `app.dailyworkspace.mac`) and never contain note text, chat content or keys.
- **The Assistant** is off until you enable it. When on, your questions and the notes, open loops, project details and events its tools read are sent to Anthropic, which may incur charges. Its tools are read-only. The conversation is kept in memory only; an accepted restart record is saved to the app folder. The app never creates a key or sends a request on its own.
- Calendar and Reminders access is requested only when you ask for it, and is used only for the screens described above.

## Syncing

Daily Workspace has no sync engine of its own. To use the vault on more than one Mac, put the vault inside iCloud Drive, Dropbox, OneDrive or another synced folder, and keep its files downloaded. The sync provider moves the Markdown files. The app picks up external changes every two seconds and whenever you return to it, and it handles conflicting edits as described above. Local tasks, settings and chat history do not sync. Calendar and Reminders sync through your Apple accounts. The details are also in **Settings → Vault → Syncing**.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is organized. Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Credits and licensing

MIT licensed. The caret idea is inspired by [Neovide](https://github.com/neovide/neovide) (MIT) and [Monkeytype](https://github.com/monkeytypegame/monkeytype) (GPL-3.0). **No Monkeytype code is used or copied**; the presets are this project's own tuning. The particle presets are original lightweight effects inspired by Neovide, not a port of its renderer. See [docs/RESEARCH.md](docs/RESEARCH.md).
