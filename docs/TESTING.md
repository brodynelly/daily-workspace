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
   With a disposable or stopped Luuna configuration, verify the selected `~/.local/bin/lu` launcher honors `LUUNA_NO_AUTO_START=1`: a read must refuse without building, starting or initializing the runtime. This is a launcher deployment contract; a fake reader or ordinary `swift test` cannot certify another Mac's wrapper.
13. With the owner's consent, leave Mail off and confirm no Automation prompt or Mail rows. Enable **Settings → Permissions → Enable Mail metadata**, trigger a read and grant then deny Apple Mail Automation in System Settings. Check flagged and Important unread metadata, blocked versus empty states, and verify no message body or Mail source appears in Assistant citations, prompts or tool results. Disable Mail again.
14. Separately opt into clipboard change count and Kitty window border under **Settings → Permissions**. Confirm clipboard contents and terminal text are not read, the border changes only when Kitty quick access is active, and disabling either toggle stops that integration. Check macOS Accessibility consent before testing border/window focus.

### Quick Access Pascal

15. In the bundled app, exercise all panel routes (Home, Agents, Sessions, Files, Projects, Workspaces, SSH, tmux, Shortcuts, Attention, System, Turbo Music and Calendar). With another app frontmost, show/toggle the panel and check keyboard focus moves to it and returns correctly on Escape, ⌘W or ⌥X. Check ⌘0…⌘9, ⇧⌘A/S, ⌘F, ⌘R, Tab/⇧Tab, arrows, Page Up/Down, Return and function-key actions with real selections; avoid destructive source actions. Compare Calendar today with the main agenda and check Music permission/failure states.
   Check End Shuffle in the native and SwiftUI music menus, the lower-right panel mouse corner, and opt-in Zen Browser pointer centering only after Accessibility consent. With another app frontmost, run notification-only `daily palette-reload`, `attention-refresh` and clipboard refresh on a cold app launch; none should bring the app forward.
   With the panel visible, open an AppKit menu or permission dialog and verify it stays open; switching to another app must still hide it without pulling focus back.
16. Bundle with `scripts/bundle.sh release`; inspect `build/DailyWorkspace.app/Contents/MacOS/daily`. Run `scripts/install_daily_cli.sh` only with the owner's consent: check that it creates only `~/.local/bin/daily`, refuses to overwrite an unrelated path and that `--remove` removes only its own symlink. The installer must not start the app. Invoke `daily status`, `show home`, `toggle projects`, `inspect` and `hide` deliberately, accounting for the CLI's app-starting behavior; check errors with the app unavailable.
   With the app installed under Applications, check `daily login status`, then explicitly `enable` and `disable` Start at Login and inspect the returned native status. `requiresApproval` is not a successful login registration; approve it in System Settings before relying on startup. Keep the old launchers until startup and rollback have both been exercised.
   On cold start, `daily status` must reach the app's control socket even if a login Keychain credential needs reauthorization. The Assistant defers its selected-provider key check until its page, inspector or AI Settings opens; Luuna remains not checked until its background token read finishes. Ad-hoc app updates or moving the bundle can cause macOS to request the login Keychain password for previously saved entries; do not automate, unlock or alter the owner's Keychain just to force that case. The blocked-reader tests exercise socket responsiveness and deferred Assistant loading.
17. Check that the bundled VGA font is present, renders legibly in the panel and retains its documented system monospaced fallback if the font is unavailable at runtime. Measure focus latency, panel refresh and large-list scrolling on the owner's hardware before claiming performance or original QAP manual parity; neither is certified here.

The old integration preview's `setup/check.sh` invoked `qap doctor`, which checked six helper files as well as the service. `daily status` and `daily inspect` do not check helper files, and `daily doctor` is not a supported command. The owning dotfiles `setup/check.sh` now checks those six paths directly and checks the live `daily` service only if it is already running; it does not start the app.

The QAP integration preview was used as a call-site inventory, not applied as a patch. The live dotfiles now route the QAP/QAM chords, SketchyBar actions, Kitty agent shortcuts and palette/attention notifications to `daily`; the Apple item uses `daily toggle system`, not QAP's `toggle apple`. The owning dotfiles `setup/check.sh` retains the six helper-file checks formerly performed by `qap doctor`. The retired QAP/QAM bundles remain in `dist/` for rollback, and independent Hammerspoon desktop/Focus/display routes remain loaded. Before replacing the bundled app, close or save any open note: `./scripts/build_and_run.sh --verify` asks the running app to quit.

#### Cutover evidence (2026-11-15)

| QAP §8 parity area | Observed on the unlocked desktop | Remaining live checks |
| --- | --- | --- |
| Panel and views | Signed release installed in `~/Applications`; all 13 routes responded through `daily show`/`inspect` and rendered. Home, System and settled Music were compared with QAP; other routes showed explicit SSH/tmux empty states and unavailable Luuna runs. F1 opened the Help dialog; F10 and ⌥P/⌥S opened native Music menus, including End Shuffle. Finder → panel → ⌘W restored Finder; app switches hid the panel without focus theft. | SketchyBar obscures the native status item, so Option-click has not been witnessed. Full view-by-view pixel comparison and VoiceOver still need hands-on checks. |
| Keys and look | With the panel focused, Down, Page Down, End, Home, Tab/⇧Tab, typed search, Escape, ⌘0…9, ⌘⇧A/S, ⌘W, ⌥X and route-specific F-keys changed the expected state. Pointer selection returned focus to document typing. Music F5/F6 visibly moved volume by 10% and were restored to 100%; the menu steps passed a focused automated test. End Shuffle left playback stopped. Synthetic skhd dispatch reached the installed app for QAP/QAM chords; Home/System/Music showed bundled VGA typography. | Physical Go60 key travel, Space playback (not invoked on the owner's library), precise styling and accessibility/VoiceOver remain unverified. |
| Integrations and permissions | Native login registration returned `enabled → notRegistered → enabled` and remains enabled; old QAP/QAM app processes and their login-item names were absent. Opted-in clipboard change-count drew then cleared SketchyBar feedback without reading contents. Kitty quick access produced a border exactly 2 pt larger on each side and cleared it when closed, without reading terminal text. Music Automation accepted read/volume commands. Calendar was granted by the owner and Settings showed **Allowed**; Mail remains off. | Reminders shows **Not allowed yet** and is deliberately left off at the owner's request pending a separate Obsidian ownership proposal. Do not power-cycle Bluetooth, restart macOS, revoke old permissions or claim a live rollback based on static review. |
| Performance and source state | Hidden-panel `top` snapshots 2–5 each showed 0.2% CPU (first snapshot 0.0%), matching QAP's historical hidden-idle figure under a different process/sample. Five **locked-session** `daily show shortcuts` CLI-to-ready samples had a 29.23 ms median (12.05, 34.56, 28.43, 29.23, 34.87 ms); QAP's historical CLI-to-UI-state median was 34.84 ms under its own methodology. These samples do **not** measure a visible frame. | Measure unlocked visible-frame latency and large-list scrolling before claiming QAP's approximately 12 ms show target or full manual speed parity. |

Independent reviewers checked each §8 Panel, Views, Keys, Look and Behaviour/performance bullet against implementation and tests. The review found and corrected the canonical Luuna workspace scan, Music Play/Shuffle menus, pointer-to-keyboard pane focus, Escape Music polling, attention warning color/prefix and sleep/wake handling, the `daily --help` route list, and the on-demand offline doctor check. The unlocked pass additionally caught Music volume-step and stale busy-feedback regressions. Source and automated-test findings do **not** complete the remaining manual cells above.

The owner later unlocked the desktop for the focused checks above. Keep retained QAP/QAM bundles and the scoped rollback plan (`dotfiles-mac/skhd/README.md`) until physical-key, status-item, permission-dependent and live rollback checks are complete. The reverse route patch passed its preflight, and an isolated checkout of the pre-cutover configuration passed skhd lint (65 bindings); a live rollback has not yet been exercised.

Alongside Xcode 27.2's swift-format 6.4.4, locally built official swift-format 601.0.0 passed `lint --strict --recursive Sources Tests Package.swift`. It was compiled with Swift 6.4.2, so this checks 6.1 formatter rules, not the macOS 15 CI environment or Swift 6.1 compilation. These unpublished commits still need CI after publication.

### Main-window sidebar

With the main window open, click the leading toolbar button and press ⌃⌘S to hide and restore the sidebar. Check that the screen column expands, Go and ⌘1…⌘6 still navigate while hidden, and VoiceOver announces “Hide Sidebar” or “Show Sidebar” for the current state.

### Settings and configurable keys

In the main window, open Settings through the sidebar, ⌘, and Command Palette; each must replace the current content rather than open another window. Back must restore the prior screen. In Keyboard, search for a command, record a single key and a two-key sequence, clear and reset them, then relaunch to confirm the binding persists. Verify conflicts and reserved keys are refused without losing the prior binding. `/` opens Notes search, `?` opens the AI sidebar, F1 opens Keyboard, and `G` then `P` opens Projects only while a text field is **not** focused. While recording, an existing menu shortcut must not fire and global capture must be suspended. Verify a remapped Quick Panel route no longer responds to its old key; contextual F2/F4–F8 and modal keys retain their fixed behavior. Check the current menu, sidebar, tooltips and palette labels after remapping. Use a disposable vault and never invoke write actions without consent.

On each workspace page, toggle the right-side AI inspector using `?` or Ask AI in the top bar. At wide width it shares space; at minimum window width it overlays the current page without shrinking its content. Confirm closing and switching screens keep the same in-memory transcript and unsent draft. In Calendar select a day other than today; in Projects select a hub; in Notes open an eligible note. Verify navigation alone never contacts the provider and an explicit Ask includes only the displayed day or scope-checked project/note identifier, with source-backed citations. An excluded note path and Mail metadata must not be sent. The Assistant must stay off until explicitly enabled with a key; live API checks require credentials and a disposable vault.

### Accessibility

18. Do a VoiceOver and keyboard-only pass over every screen and the quick panel, with Reduce Motion both on and off.

### Logs

19. Run `./scripts/build_and_run.sh --app-logs` and exercise conflicts, capture and permissions. Check that log lines appear and that none contains note text, chat content or keys.
