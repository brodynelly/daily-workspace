# Daily Workspace

A calm, local-first Mac workspace for today: an agenda from Apple Calendar, a short task list, and your daily Markdown note in an Obsidian vault, with a smooth, spring-animated typing caret.

Native macOS · Swift · SwiftUI + AppKit · local-first notes and tasks · optional OpenRouter chat · no telemetry.

> **Status: builds and launches on macOS.** Core logic is unit-tested. Permission-dependent integrations and the interaction checks below still need a hands-on pass with your accounts and vault.

## What's in it

| Screen | What it does |
| --- | --- |
| **Today** | Date, agenda, tasks due today, today's note preview, quick capture |
| **Notes** | Markdown editor on the vault's real files, recent notes, live text preview, backlinks, save status, conflict handling |
| **Tasks** | Today / Inbox / Upcoming / Completed, edit, link to a note, delete with undo |
| **Calendar** | Day agenda, create events, edit/delete an occurrence (EventKit) |
| **Search** | Search vault Markdown names and contents |
| **Reminders** | Apple Reminders: incomplete items, add, complete |
| **AI Chat** | OpenRouter chat, optional explicit note attachment, Keychain credential |
| **Settings** | Vault, daily-note folder and file-name template, caret feel, calendar access |

Keyboard: `⌘⇧Space` global capture · `⌘N` quick capture · `⌘⇧T` today's note · `⌘1…7` switch screen · `⌘S` save · `⌘,` settings · `⌘←/→` change day in Calendar.

### Typing caret

The editor hides the system caret and draws its own: four corners, each on a critically damped spring (exact closed-form maths, stable at any frame rate), with a different duration per corner so a long jump stretches into a trail while typing glides. It stays solid while you type and blinks when idle.

| Preset | Feel |
| --- | --- |
| Off | System caret |
| Glide | Whole caret slides between characters (Monkeytype-style smooth caret) |
| Trail | Quick glide when typing, short trail on jumps |
| Comet | Long stretching trail (Neovide-style) |
| Railgun | Fading particle beam on caret movement |
| Pixiedust | Scattered fading sparks |

It falls back to the system caret during IME composition, while text is selected, when the preset is Off, and whenever macOS **Reduce Motion** is on.

### Safety rules for your vault

- Notes are saved only as the exact text you loaded plus your edits: frontmatter, wikilinks, embeds, CRLF line endings and Unicode survive byte for byte. No smart quotes or auto-replacement.
- Saves are atomic. If the file changed on disk since it was loaded (Obsidian, a sync client), saving pauses and you choose *Reload From Disk* or *Keep My Version*; the side you discard is written to `~/Library/Application Support/DailyWorkspace/Recovery`, never into the vault.
- It never deletes, renames or moves vault files. A file that is not valid UTF-8 is refused, not rewritten.
- A moved or revoked vault is a visible state with a button to choose it again. Calendar denial never blocks notes or tasks.

## Build and run (on a Mac, macOS 14+)

```sh
swift test                           # core tests
./script/build_and_run.sh --verify    # build, bundle, launch, confirm process
```

The Codex Run button uses the same script. `Scripts/bundle.sh` also builds a standalone release bundle. Requires Xcode 15+ command line tools (Swift 5.9 or newer).

### New workflows

- Use the sun icon in the menu bar or **⌘⇧Space** for a separate capture window. If ⌘⇧Space is reserved, capture falls back to ⌃⌥Space; the menu shows the active shortcut. If both are reserved, use the menu action or ⌘⌥N inside the workspace. Daily Workspace stays a regular Dock app.
- **Search** scans visible Markdown files in the selected vault, skipping symlinks and files over 2 MB. Click Refresh after external changes. Search supports multiple terms across file names and contents. Notes has a live text preview and a Backlinks inspector for wikilinks and Markdown file links. Basename wikilinks can match multiple notes; embeds/images and full Obsidian rendering are not supported.
- **Calendar → New Event** creates an event. Double-click an agenda event or use its context menu to edit it. Delete asks for confirmation. Recurring changes affect this occurrence only.
- **Reminders → Connect Reminders** requests separate access. Add writes to your default Apple Reminders list; the circle marks an item complete. Refresh retrieves external changes. These are separate from local Tasks.
- **Settings → AI** accepts an OpenRouter API key and optional model ID. A blank model uses the OpenRouter account default. The key is stored in macOS Keychain. Chat is held in memory, has Stop/Clear actions, and sends note content only when “Attach open note” is checked. Messages go to OpenRouter and its providers and may incur charges. No key or paid request is created automatically.
- **Settings → Sync** connects a vault already inside your folder-sync service (iCloud Drive, Dropbox, OneDrive, etc.). Keep files downloaded. The provider transfers Markdown files; Daily Workspace detects external note changes and handles conflicts. This is folder-based integration, not a custom transfer engine. Local Tasks/settings and chat history do not sync through the vault; Calendar and Reminders follow their Apple accounts.

## Layout

```
Sources/DailyCore/        pure Foundation logic, unit-tested
  CriticallyDampedSpring  closed-form spring
  CaretAnimator           four-corner caret motion
  CaretPreset             Off / Glide / Trail / Comet tunings
  NoteVault               load / create / atomic save / conflict detection, DailyNoteTemplate
  Tasks                   TaskList value type + JSON persistence
  LocalDay                time-zone-free calendar day
Sources/DailyWorkspace/   SwiftUI + AppKit app
  CaretTextView           NSTextView with the animated caret overlay
  MarkdownEditor          NSViewRepresentable + attribute-only Markdown styling
  AppState                vault bookmark, notes, tasks, conflict handling
  CalendarService         read-only EventKit agenda
  Today / Notes / Tasks / Calendar / Settings views
Tests/DailyCoreTests/
Resources/Info.plist      permission strings
Scripts/bundle.sh         .app builder
docs/                     original spec (04-orchestration.md, plan.html) and research notes
```

## Needs a Mac check

Build and process launch have been checked on a Mac. These interaction and account-dependent checks remain:

1. The animated caret lines up with the real insertion point while typing, wrapping lines, scrolling, resizing the window, undo, and with an IME (try Japanese or Pinyin). If it drifts, `CaretTextView.caretRect()` is the place to fix.
2. The system caret is really hidden while the animated one shows (`setNativeCaret`). On macOS 14+ it relies on `NSTextInsertionIndicator.displayMode` plus a clear `insertionPointColor`.
3. Calendar permission prompt appears and events show up (run from the `.app` bundle).
4. Vault bookmark survives a restart; moving the vault shows the "unavailable" state.
5. Edit the daily note in Obsidian while it is open here: the clean case reloads, the dirty case shows the conflict banner.
6. VoiceOver and keyboard-only pass over all screens; Reduce Motion on/off.
7. Test with a real vault copy first.

## Integration checks

- Test ⌘⇧Space from another app, with the main window closed, and after cancelling capture. Check the menu-bar fallback if the shortcut is unavailable.
- Grant/deny Calendar and Reminders permissions in the built bundle. Create/edit/delete a test event occurrence and add/complete a test reminder. No account data was changed during development checks.
- Configure your OpenRouter key and chosen model, send a message, attach a disposable note, test Stop and authentication failures, then remove the key. Live API calls require your credential and have not been exercised during development.
- With two Macs or a disposable synced vault, verify external updates and conflicting edits. Provider availability/offline behavior is owned by the sync service.
- Check Railgun/Pixiedust in Light/Dark mode and verify particles disappear during Reduce Motion, text selection, and IME composition.

The particle presets are original lightweight effects inspired by Neovide, rather than a port of its renderer. Preview is a text-oriented Markdown preview, not an Obsidian plugin/runtime.

## Credits and licensing

MIT licensed. The caret idea is inspired by [Neovide](https://github.com/neovide/neovide) (MIT) and [Monkeytype](https://github.com/monkeytypegame/monkeytype) (GPL-3.0). **No Monkeytype code is used or copied**; the presets are this project's own tuning. See [docs/RESEARCH.md](docs/RESEARCH.md).
