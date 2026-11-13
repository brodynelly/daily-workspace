# Testing

## Automated

```sh
swift test
```

- `Tests/DailyCoreTests` covers the pure logic: spring and caret physics, the daily-note template, vault load/save/conflict/append, path containment (including symlinks), tasks, persistence, and the search index.
- `Tests/DailyWorkspaceTests` covers the app's stores against fakes (see [ARCHITECTURE.md](ARCHITECTURE.md#protocol-boundaries)):
  - `NoteDocument`: autosave, external changes, conflict resolution, recovery failures
  - `TaskStore`
  - `AppModel`: capture, and today-note identity
  - `AssistantSession` and `AnthropicClient`
  - `CalendarService`
  - `RemindersService`

CI is intended to run both linters, bundle the app, and check that Calendar, Reminders and Mail Automation usage strings are embedded in its `Info.plist`. This document does not certify the current build, tests or linters as passing.

## Manual checks

These depend on real hardware, permissions, accounts or input methods. Run them from the bundle (`./scripts/build_and_run.sh`) against **a copy of a real vault**, with the owner's consent for each external permission and live account. Do not write to Org or Luuna or exercise shutdown/cancellation: the owner declined those app actions. Reviewed B/E Markdown saves are permitted only in the disposable vault after explicit confirmation.

### Editor and caret

1. The animated caret lines up with the real insertion point in all of these situations:
   - while typing
   - when lines wrap
   - while scrolling
   - after resizing the window
   - after undo
   - with an IME (try Japanese or Pinyin)

   If it drifts, fix it in `CaretTextView.caretRect()`.
2. The system caret is actually hidden while the animated one is showing (`setNativeCaret`). On macOS 14+ this relies on `NSTextInsertionIndicator.displayMode` plus a clear `insertionPointColor`.
3. Check Railgun and Pixiedust in Light and Dark mode. Their particles should disappear when Reduce Motion is on, while text is selected, and during IME composition.

### Vault

4. The vault bookmark survives a restart. Moving the vault shows the "Vault unavailable" state.
5. Edit the open note in Obsidian while it is open here:
   - With no unsaved changes here, the note reloads.
   - With unsaved changes here, the conflict banner appears.

   Try both *Reload From Disk* and *Keep My Version*. Check that the discarded version appears in the recovery folder.
6. Capture to **Today's Note** while a different note is open. The editor should stay on that note, and today's note on disk should gain the line.
7. With a synced vault on two Macs (or a disposable synced vault), check that external updates arrive and that conflicting edits are handled. Availability and offline behaviour are the sync provider's responsibility.

### Capture

8. Test ⌘⇧Space from another app, with the main window closed, and after cancelling a capture. If the shortcut is unavailable, check that the menu-bar fallback works.
   In a disposable copy of the vault, capture to the existing Quick Notes file and a named new `00-inbox/*.md`: confirm each exact before/after preview, inspect the resulting Markdown and verify nothing changed on Cancel. An existing Inbox filename, missing parent, excluded folder, dirty open editor, edited target between preview and confirmation, or switched vault must refuse and retain the draft. For a cited Assistant answer, edit the proposed body, choose an eligible existing or new path yourself, review the full before/after and confirm; the model must not select a destination or save by itself.

### Permissions and accounts

9. Grant and then deny Calendar and Reminders access in the built bundle. Use **Settings → Permissions** and the in-screen prompts, and check that "Open System Settings" opens the right privacy pane.
10. Create, edit and delete a test event occurrence. Add and complete a test reminder.
11. Enable the Assistant, enter an Anthropic or OpenRouter key, and send a message using a disposable note. Test Stop and an authentication failure, then remove the key. Live API calls need your credentials. From Quick Panel File → Quick AI Chat, confirm the shared contextual Assistant opens without duplicating the conversation.
   With separate permission consent on the built bundle, tap the microphone in Assistant and check dictation fills the draft but does not send it. Deny or revoke either microphone or Speech Recognition permission and confirm no recording continues; if on-device recognition is unavailable, confirm the app refuses instead of falling back to remote recognition. Turn spoken replies on, send a disposable question, verify only the final reply is read aloud, then turn it off and confirm speech stops. Close the composer while dictating and verify the microphone stops.

### Native project data and Mail

12. With owner-provided Luuna loopback credentials and `~/.local/bin/lu` installed, check the native JSON CLI project board, ticket detail and Home projections against the owner's actual runtime. In Projects compare linked and unlinked projects, empty versus unavailable sources, ticket status, due dates and the Markdown hub context. Local tasks, Reminders and opt-in Mail appear in Open Loops instead. Confirm the app only performs fixed read-only CLI queries; do not approve external writes by testing this.
   In Assistant and Quick Panel Agents, select a historical run and compare native run detail and `lu follow <run> --after 0 --json` event sequences. Confirm the event stream resumes without duplicate rows on a dropped read, disconnect or token switch clears old events, and the run's state never closes its related ticket. Do not start or cancel a live run to exercise this.
13. With the owner's consent, leave Mail off and confirm no Automation prompt or Mail rows. Enable **Settings → Permissions → Enable Mail metadata**, trigger a read and grant then deny Apple Mail Automation in System Settings. Check flagged and Important unread metadata, blocked versus empty states, and verify no message body or Mail source appears in Assistant citations, prompts or tool results. Disable Mail again.
14. Separately opt into clipboard change count and Kitty window border under **Settings → Permissions**. Confirm clipboard contents and terminal text are not read, the border changes only when Kitty quick access is active, and disabling either toggle stops that integration. Check macOS Accessibility consent before testing border/window focus.

### Quick Access Pascal

15. In the bundled app, exercise all panel routes (Home, Agents, Sessions, Files, Projects, Workspaces, SSH, tmux, Shortcuts, Attention, System, Turbo Music and Calendar). With another app frontmost, show/toggle the panel and check keyboard focus moves to it and returns correctly on Escape, ⌘W or ⌥X. Check ⌘0…⌘9, ⇧⌘A/S, ⌘F, ⌘R, Tab/⇧Tab, arrows, Page Up/Down, Return and function-key actions with real selections; avoid destructive source actions. Compare Calendar today with the main agenda and check Music permission/failure states.
   Check End Shuffle in the native and SwiftUI music menus, the lower-right panel mouse corner, and opt-in Zen Browser pointer centering only after Accessibility consent. With another app frontmost, run notification-only `daily palette-reload`, `attention-refresh` and clipboard refresh on a cold app launch; none should bring the app forward.
16. Bundle with `scripts/bundle.sh release`; inspect `build/DailyWorkspace.app/Contents/MacOS/daily`. Run `scripts/install_daily_cli.sh` only with the owner's consent: check that it creates only `~/.local/bin/daily`, refuses to overwrite an unrelated path and that `--remove` removes only its own symlink. The installer must not start the app. Invoke `daily status`, `show home`, `toggle projects`, `inspect` and `hide` deliberately, accounting for the CLI's app-starting behavior; check errors with the app unavailable.
   On a cold start with a locked or slow login Keychain, `daily status` must still reach the app's control socket; Luuna remains not checked and the Assistant key shows Checking Keychain until their reads finish. Do not unlock or alter the owner's Keychain just to force this case; the automated blocked-reader test exercises it.
17. Check that the bundled VGA font is present, renders legibly in the panel and retains its documented system monospaced fallback if the font is unavailable at runtime. Measure focus latency, panel refresh and large-list scrolling on the owner's hardware before claiming performance or original QAP manual parity; neither is certified here.

Before T25, compare the **current** dotfiles call sites with the QAP integration preview; it is a checklist, not an applicable patch. QAP accepts `toggle apple` for its System popup, while the Daily Workspace CLI accepts `toggle system` and rejects `apple`. Map that SketchyBar call to `daily toggle system`; map each other route only after checking the CLI allowlist. Do not replace hotkeys or login items until the bundled app passes these hands-on checks and the owner approves cutover. `./scripts/build_and_run.sh --verify` asks an existing app to quit before launching a replacement, so do not run it over an unsaved note. Preserve existing QAP/QAM launchers and a verified rollback until T26 is separately authorized.

### Main-window sidebar

With the main window open, click the leading toolbar button and press ⌃⌘S to hide and restore the sidebar. Check that the screen column expands, Go and ⌘1…⌘6 still navigate while hidden, and VoiceOver announces “Hide Sidebar” or “Show Sidebar” for the current state.

### Settings and configurable keys

In the main window, open Settings through the sidebar, ⌘, and Command Palette; each must replace the current content rather than open another window. Back must restore the prior screen. In Keyboard, search for a command, record a single key and a two-key sequence, clear and reset them, then relaunch to confirm the binding persists. Verify conflicts and reserved keys are refused without losing the prior binding. `/` opens Notes search, `?` opens the AI sidebar, F1 opens Keyboard, and `G` then `P` opens Projects only while a text field is **not** focused. While recording, an existing menu shortcut must not fire and global capture must be suspended. Verify a remapped Quick Panel route no longer responds to its old key; contextual F2/F4–F8 and modal keys retain their fixed behavior. Check the current menu, sidebar, tooltips and palette labels after remapping. Use a disposable vault and never invoke write actions without consent.

On each workspace page, toggle the right-side AI inspector using `?` or Ask AI in the top bar. At wide width it shares space; at minimum window width it overlays the current page without shrinking its content. Confirm closing and switching screens keep the same in-memory transcript and unsent draft. In Calendar select a day other than today; in Projects select a hub; in Notes open an eligible note. Verify navigation alone never contacts the provider and an explicit Ask includes only the displayed day or scope-checked project/note identifier, with source-backed citations. An excluded note path and Mail metadata must not be sent. The Assistant must stay off until explicitly enabled with a key; live API checks require credentials and a disposable vault.

### Accessibility

18. Do a VoiceOver and keyboard-only pass over every screen and the quick panel, with Reduce Motion both on and off.

### Logs

19. Run `./scripts/build_and_run.sh --app-logs` and exercise conflicts, capture and permissions. Check that log lines appear and that none contains note text, chat content or keys.
