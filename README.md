# Daily Workspace

A calm, local-first Mac workspace for today: an agenda from Apple Calendar, a short task list, and your daily Markdown note in an Obsidian vault, with a smooth, spring-animated typing caret.

Native macOS · Swift · SwiftUI + AppKit · no accounts, no network, no telemetry.

> **Status: first full implementation, written on Windows and not yet run on a Mac.** CI builds and unit-tests it on macOS. Everything under "Needs a Mac check" below still has to be tried by hand.

## What's in it

| Screen | What it does |
| --- | --- |
| **Today** | Date, agenda, tasks due today, today's note preview, quick capture |
| **Notes** | Markdown editor on the vault's real files, recent notes, save status, conflict handling |
| **Tasks** | Today / Inbox / Upcoming / Completed, edit, link to a note, delete with undo |
| **Calendar** | Read-only day agenda (EventKit), previous/next day |
| **Settings** | Vault, daily-note folder and file-name template, caret feel, calendar access |

Keyboard: `⌘N` quick capture · `⌘⇧T` today's note · `⌘1…4` switch screen · `⌘S` save · `⌘,` settings · `⌘←/→` change day in Calendar.

### Typing caret

The editor hides the system caret and draws its own: four corners, each on a critically damped spring (exact closed-form maths, stable at any frame rate), with a different duration per corner so a long jump stretches into a trail while typing glides. It stays solid while you type and blinks when idle.

| Preset | Feel |
| --- | --- |
| Off | System caret |
| Glide | Whole caret slides between characters (Monkeytype-style smooth caret) |
| Trail | Quick glide when typing, short trail on jumps |
| Comet | Long stretching trail (Neovide-style) |

It falls back to the system caret during IME composition, while text is selected, when the preset is Off, and whenever macOS **Reduce Motion** is on.

### Safety rules for your vault

- Notes are saved only as the exact text you loaded plus your edits: frontmatter, wikilinks, embeds, CRLF line endings and Unicode survive byte for byte. No smart quotes or auto-replacement.
- Saves are atomic. If the file changed on disk since it was loaded (Obsidian, a sync client), saving pauses and you choose *Reload From Disk* or *Keep My Version*; the side you discard is written to `~/Library/Application Support/DailyWorkspace/Recovery`, never into the vault.
- It never deletes, renames or moves vault files. A file that is not valid UTF-8 is refused, not rewritten.
- A moved or revoked vault is a visible state with a button to choose it again. Calendar denial never blocks notes or tasks.

## Build and run (on a Mac, macOS 14+)

```sh
swift test                 # unit tests (caret physics, vault safety, tasks, date templates)
swift run                  # quick run
Scripts/bundle.sh          # builds build/DailyWorkspace.app with Info.plist (use this for Calendar permission)
open build/DailyWorkspace.app
```

Requires Xcode 15+ command line tools (Swift 5.9 or newer). `swift run` embeds the Info.plist so the Calendar prompt works there too; the `.app` bundle is the more reliable path.

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

Written without a Swift toolchain at hand, so these are the things to verify first:

1. The animated caret lines up with the real insertion point while typing, wrapping lines, scrolling, resizing the window, undo, and with an IME (try Japanese or Pinyin). If it drifts, `CaretTextView.caretRect()` is the place to fix.
2. The system caret is really hidden while the animated one shows (`setNativeCaret`). On macOS 14+ it relies on `NSTextInsertionIndicator.displayMode` plus a clear `insertionPointColor`.
3. Calendar permission prompt appears and events show up (run from the `.app` bundle).
4. Vault bookmark survives a restart; moving the vault shows the "unavailable" state.
5. Edit the daily note in Obsidian while it is open here: the clean case reloads, the dirty case shows the conflict banner.
6. VoiceOver and keyboard-only pass over all five screens; Reduce Motion on/off.
7. Test with a real vault copy first.

## Not built (deliberately)

Global hotkey, menu-bar quick capture window, Reminders, calendar writes, sync, search/backlinks/live preview, AI chat, and Neovide's particle effects (railgun, pixiedust, …). Each is a scope decision of its own.

## Credits and licensing

MIT licensed. The caret idea is inspired by [Neovide](https://github.com/neovide/neovide) (MIT) and [Monkeytype](https://github.com/monkeytypegame/monkeytype) (GPL-3.0). **No Monkeytype code is used or copied**; the presets are this project's own tuning. See [docs/RESEARCH.md](docs/RESEARCH.md).
