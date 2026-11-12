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
  - `ChatService`
  - `CalendarService`
  - `RemindersService`

CI also runs both linters, bundles the app, and checks that the Calendar and Reminders usage strings are embedded in its `Info.plist`.

## Manual checks

These depend on real hardware, permissions, accounts or input methods. Run them from the bundle (`./scripts/build_and_run.sh`) against **a copy of a real vault**.

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

### Permissions and accounts

9. Grant and then deny Calendar and Reminders access in the built bundle. Use **Settings → Permissions** and the in-screen prompts, and check that "Open System Settings" opens the right privacy pane.
10. Create, edit and delete a test event occurrence. Add and complete a test reminder.
11. Enter your OpenRouter key and chosen model, and send a message. Attach a disposable note. Test Stop and an authentication failure, then remove the key. Live API calls need your credentials.

### Accessibility

12. Do a VoiceOver and keyboard-only pass over every screen, with Reduce Motion both on and off.

### Logs

13. Run `./scripts/build_and_run.sh --app-logs` and exercise conflicts, capture and permissions. Check that log lines appear and that none contains note text, chat content or keys.
