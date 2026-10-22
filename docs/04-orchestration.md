# Daily Workspace — product orchestration and implementation specification

Status: **Proposed product specification** (standalone macOS companion; not a Luuna feature).  
Date: 2026-10-22.  
Companion plan: [plan.html](plan.html).

## 1. Product intent

Build a personal, local-first Mac workspace for the user's daily notes, a short actionable task list, and an at-a-glance Apple Calendar agenda, with an Obsidian vault as the home for Markdown notes. The experience should feel quick, calm, keyboard-friendly, and visually compact, taking general inspiration from Raycast Notes without copying its branding or assets. Motion may borrow the *feel* of Neovide's smooth editor cursor, but the product is not Neovide and must remain useful with animation off.

The central workflow is: open the workspace → see today's events and tasks → open or create today's note in the chosen vault → capture an idea or turn it into a task. Private note, event, and task contents remain on the user's Mac; no account, hosted service, model, or network connection is required for the core experience.

## 2. Product boundary and platform

- **Standalone macOS app**, implemented with SwiftUI and native system APIs. This is not part of Luuna's existing Tauri/React developer-workbench architecture and does not change Luuna's architecture, ADRs, requirements, or runtime.
- Minimum supported macOS version is **TBD before implementation**. Verify EventKit API and permission behavior against the chosen deployment target; the initial research assumes modern macOS (macOS 14+ for the documented full-event-access flow).
- Keep the app self-contained and local-first. Do not introduce a backend, cross-device sync service, agent, or broad sync engine in the MVP.
- Use SwiftUI for screens and controls; selectively bridge to AppKit only if a specific native editor or window behavior cannot be achieved with SwiftUI.
- “Raycast-like” means fast invocation, compact hierarchy, command-oriented capture, and keyboard focus—not a reproduction of Raycast's UI. “Neovide-like” means optional smooth movement in the app's own editor caret and restrained view transitions—not a global pointer replacement or a promise of pixel-identical rendering.

## 3. Users, jobs, and core screens

### Main jobs

1. See the next few events and the tasks that matter today without opening several apps.
2. Open or create the dated daily note in an explicitly selected Obsidian vault.
3. Capture a thought with minimal friction, then optionally turn it into a task or note.
4. Trust that permissions, external edits, and unavailable data are visible rather than silently ignored or overwritten.

### Screens

- **Today** (default): date and timezone; upcoming agenda; compact “today” task list; daily-note preview/open action; quick capture.
- **Notes**: current daily note and recently opened note references. MVP does not need to replace Obsidian as a complete editor or index every vault note.
- **Tasks**: a small app-managed inbox and due-today list; complete/reopen, edit, and optionally link to a note. No recurring-task engine in MVP.
- **Calendar**: initially a read-only day/agenda view, with calendar visibility controls only if they can be implemented without broad scope.
- **Settings**: vault selection and access state, Calendar permission/status, launch/shortcut preferences, appearance, and motion preferences.

Provide a compact quick-capture window or command surface with a configurable shortcut if feasible for the chosen macOS lifecycle. The main workflow must also work without a global shortcut.

## 4. Sources of truth and data ownership

| Information | MVP authority | App responsibility |
| --- | --- | --- |
| Notes and daily note content | Markdown files in the user-selected Obsidian vault | Read/write only the selected note paths; preserve existing content and conventions |
| Apple calendar events | macOS Calendar via EventKit | Read and display; no event creation/editing in MVP |
| App-managed tasks | Local app storage | Create, update, complete, and retain only the user's task records |
| Preferences | Local app preferences | Store vault bookmark/reference, UI settings and non-sensitive preferences |
| Search/index cache (if needed) | Rebuildable local cache | Never treat cache as authoritative; no full-vault indexing in the first slice |

Do not duplicate Calendar events or Obsidian note bodies into an independent authoritative store. Do not assume that a vault is exclusively owned by this app. Any cached previews or indexes must be reconstructible and deletable without deleting source files.

## 5. Obsidian and Markdown contract

- Treat a vault as a user-selected folder containing ordinary Markdown files and attachments; do not depend on Obsidian internals, plugins, or a private database.
- Let the user choose the vault using the macOS system file picker. In a sandboxed distribution, use the required user-selected-file entitlement and persist scoped access/bookmark state appropriately. Re-authorize cleanly when access is revoked or the folder moves.
- Configure a daily-note folder and filename template. Proposed default: `YYYY-MM-DD.md` at the vault root; make this setting configurable before v1.1 if implementation scope allows. Never create a duplicate silently if an equivalent date note exists under a configured pattern.
- For new cross-note links, prefer standard relative Markdown links for interoperability. Preserve existing wikilinks, frontmatter, embeds, attachment references, formatting, and unknown content when opening or editing an existing file. Do not normalize or rewrite the entire file merely to display it.
- Save atomically where practical. Before replacing a file, detect external modification since the app loaded it (for example via file identity and modification metadata, with content comparison where needed). On conflict, stop and offer reload/compare/keep a recoverable copy; never silently clobber newer content.
- A moved, unavailable, or inaccessible vault is a visible recoverable state. Do not fall back to another folder or create replacement files in an unselected location.
- The first implementation may use a simple editor for today's Markdown note, but it must preserve text faithfully and support ordinary typing, selection, copy/paste, undo, and keyboard navigation. A full Obsidian-compatible editor is out of scope.

## 6. Calendar and task integration

### Calendar (MVP read-only)

- Use EventKit for calendar access. Request event authorization only when the user enables calendar features or opens the calendar view; explain why before presenting the system permission request.
- For macOS 14+ full event access, configure the required `NSCalendarsFullAccessUsageDescription` and request the appropriate EventKit authorization. A sandboxed app also needs the Calendar privacy entitlement. Confirm exact API and signing requirements for the final minimum OS and distribution channel.
- Permission denial, restriction, revocation, an empty calendar, and no selected calendars are normal UI states with explanations and a route to Settings/system privacy controls.
- Refetch after EventKit change notifications; notifications indicate the store changed and are not themselves a complete change record. Handle daylight-saving transitions, all-day events, time zones, overlapping events, deleted events, and calendar colors without implying that cached data is current.
- Do not request Reminders access unless a later approved scope adds Reminders integration. Keep tasks app-managed in MVP.

### Tasks (app-managed)

- Task fields: stable ID, title, optional note link, created/updated timestamps, optional due date (with explicit local date semantics), completion state and optional completion timestamp.
- MVP actions: quick add, edit title/due date/link, complete/reopen, list inbox/today, and delete with confirmation or undo.
- Tasks are local to this app in MVP. Do not imply they sync to Apple Reminders, Obsidian task plugins, or other devices.
- Persistence choice (SwiftData vs a small documented local store) is an implementation decision. Select one based on migration, backup, and test needs; keep the model independent of UI views.

## 7. Motion, interaction, and accessibility

- Use restrained, short transitions for screen changes, panel expansion, and task completion. Motion must communicate continuity or state, not distract from reading.
- Optional editor caret interpolation may use a spring-like approach inspired by Neovide's independently moving cursor geometry. Keep the native text insertion/caret semantics, selection, dictation, and accessibility intact. Do not animate the OS pointer.
- The animation prototype must preserve text input and caret accuracy; if custom caret rendering interferes with IME composition, selection, VoiceOver, or predictable typing, keep the native caret instead.
- Respect macOS Reduce Motion (`accessibilityReduceMotion`) by removing or materially reducing nonessential movement. Provide an in-app animation preference (system default / reduced / on) only if the setting remains consistent with system accessibility; never override a system reduce-motion request with a more animated mode.
- All actions must be keyboard accessible, focus visible, and usable without hover or animation. Test VoiceOver and keyboard-only operation. Use native semantic controls and labels; don't communicate task/event state by color alone.
- Animation is progressive enhancement. A static/reduced-motion rendering must retain the same information and task capability.

## 8. Privacy, security, and resilience

- Operate offline for the core Today/Notes/Tasks flow. No telemetry or upload of note contents, event details, or task titles in MVP.
- Keep EventKit and vault access narrowly scoped to the enabled feature. Do not request broader filesystem or calendar permissions than necessary. Explain access, allow the user to disable it, and handle permission revocation.
- Do not log private text, event titles, calendar descriptions, or full file paths. Diagnostics should use redacted errors and non-content metadata.
- Treat vault files as user data; never delete, bulk-rewrite, rename, or reorganize vault contents. Provide an app-level export/backup for app-owned task/preferences data if the selected persistence approach warrants it; never claim a backup includes the vault or Calendar database.
- Handle interrupted writes, malformed/large Markdown files, Unicode, moved vaults, stale bookmarks, changed files, invalid date templates, timezone shifts, and app restart without data loss.

## 9. Orchestration and state model

The app is a small deterministic local client, not an agent orchestrator. No agent may write notes, create tasks, or access Calendar in this specification. User actions are the only mutations in MVP.

Recommended state flow:

```text
launch
  -> load local preferences and app-managed tasks
  -> resolve vault access (available | needs_reauthorization | unavailable | not_configured)
  -> resolve Calendar status (not_requested | authorized | denied | restricted | unavailable)
  -> show Today with independent sections
  -> user action (open/edit note | capture task | complete task | inspect agenda)
  -> persist app-owned task/preferences or safely save the selected Markdown file
  -> refresh/refetch Calendar when EventKit reports changes
```

One unavailable integration must not block the others. For example, Calendar denial must not prevent opening the daily note or task list. Distinguish empty data from unavailable/unauthorized data. Show freshness/permission context in the relevant section, not as a global failure page.

## 10. MVP acceptance criteria

1. A clean Mac build launches to a usable Today screen with no account, network, vault, or Calendar permission prerequisite.
2. The user can select a vault, return after restart with scoped access still valid where supported, and reauthorize after relocation/revocation.
3. The app can open today's existing Markdown note or create it at the configured location without changing unrelated vault files.
4. Editing and saving preserves Unicode, line endings as far as practical, frontmatter, wikilinks, links, embeds, and unknown Markdown content; an external concurrent edit is detected and never silently overwritten.
5. The user can create/edit/complete/reopen/delete app-owned tasks; tasks survive restart, and optional links point to the intended vault note.
6. With Calendar permission granted, the agenda shows correct upcoming/all-day events across a tested timezone/day boundary and refreshes after store changes. With access denied/revoked, a clear local explanation appears and notes/tasks still work.
7. No Calendar event is edited and no Reminders permission is requested in MVP.
8. Keyboard-only and VoiceOver users can reach all primary actions and read agenda/task/note status. Reduce Motion removes or reduces nonessential animation; all features work with motion disabled.
9. Private content is absent from logs and no content is sent over the network. Permission descriptions and sandbox entitlements match actual use.
10. Automated tests cover date/template logic, task persistence and transitions, conflict detection, permission/state rendering, and timezone edge cases. A real native Mac smoke test verifies file picker/bookmark, EventKit permission, restart, and accessibility behavior; a unit test alone is not platform evidence.

## 11. Delivery sequence

### Slice 0 — Resolve decisions and native shell

Confirm app name, minimum macOS, distribution/sandbox model, daily-note naming/folder convention, task persistence choice, and what “Raycast Notes” means visually (compact panel, global hotkey, or both). Create a native SwiftUI shell and validate keyboard/focus/Reduce Motion on a real Mac.

### Slice 1 — Local vertical slice

Implement Today with sample state, local app-managed tasks, a user-selected vault, daily Markdown read/create/edit/save, explicit external-change detection, and no Calendar integration. Prove safe vault access and restart behavior before visual polish.

### Slice 2 — Read-only Calendar

Add EventKit agenda with just-in-time permission, denied/revoked states, change refresh, timezone handling, and sandbox entitlement. Keep Calendar read-only.

### Slice 3 — Product polish

Add keyboard shortcuts/quick capture and a constrained motion prototype. Test native caret fallback, Reduce Motion, VoiceOver, launch responsiveness, idle resource use, and representative event/note sizes. Remove effects that compromise reliability or readability.

### Slice 4 — Pilot and v1 decision

Use the app with a real vault on a Mac; record file conflict behavior and usability findings. Only then decide whether to add reminders, broader note search, calendar writes, sync, or an additional platform. Each is a scope expansion requiring its own decision and acceptance criteria.

## 12. Risks, unresolved decisions, and research limits

| Topic | Current proposal | Must confirm |
| --- | --- | --- |
| Standalone vs Luuna | Standalone Mac companion | Owner has approved separate docs path; product remains separate |
| Minimum OS | Modern macOS; initial research assumes 14+ EventKit flow | Exact deployment target and API fallback |
| Calendar permission | Read-only events, just in time | Calendar selection granularity and app distribution/signing |
| Reminders | Not in MVP | Whether users require Apple Reminders rather than app-owned tasks |
| Daily note path | `YYYY-MM-DD.md` at vault root | User's existing Obsidian daily-note folder/template |
| Task persistence | Local app-owned | SwiftData vs another local persistence mechanism and backup/migration behavior |
| Editor caret | Native by default; optional prototype later | Whether custom caret can coexist with native text/accessibility behavior |
| Quick invocation | Keyboard shortcut desired, global hotkey optional | App lifecycle/permissions and user preference |
| Sync/conflicts | No custom sync; detect external changes | Specific cloud provider/Obsidian Sync behavior must be tested; no universal conflict-free guarantee is assumed |
| Visual identity | Inspired by compact quick capture, original design | User validation; no copying Raycast branding/assets |

Research supports the platform capabilities and format basics, not a performance guarantee or proof that any animation is desirable. Verify current Apple documentation at implementation time, especially EventKit permissions/entitlements for the selected macOS target. Obsidian vaults are folders of Markdown files, but wikilinks, embeds, and attachments are ecosystem conventions that require careful preservation. External file sync behavior varies; no source reviewed proves third-party conflict-free concurrent editing.

## 13. Primary references

- Apple, [Accessing Calendar using EventKit and EventKitUI](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui)
- Apple, [Accessing the Event Store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- Apple, [Accessing files from the macOS app sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- Apple, [SwiftUI AppKit integration](https://developer.apple.com/documentation/swiftui/appkit-integration)
- Apple, [SwiftUI Reduce Motion environment value](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
- Apple, [Accessibility Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/accessibility/)
- Obsidian, [How Obsidian stores data](https://obsidian.md/help/data-storage)
- Obsidian, [Internal links](https://obsidian.md/help/Linking%20notes%20and%20files/Internal%20links)
- Obsidian, [Attachments](https://obsidian.md/help/attachments)
- Obsidian, [Sync security and privacy](https://help.obsidian.md/Obsidian%2BSync/Security%2Band%2Bprivacy)
- Obsidian, [Sync version history](https://help.obsidian.md/Obsidian%2BSync/Version%2Bhistory)
- Raycast, [Notes](https://www.raycast.com/core-features/notes) and [Notes manual](https://manual.raycast.com/notes)
- Neovide, [Configuration](https://github.com/neovide/neovide/blob/main/website/docs/configuration.md)

## 14. Implementation handoff prompt

> Build the standalone macOS Daily Workspace specified in `docs/daily-workspace/04-orchestration.md`. First inspect the existing repository and its instructions; do not turn this into a Luuna feature or modify Luuna's architecture. Begin with a native SwiftUI shell and a tested vertical slice: local app-owned tasks, explicit user-selected Obsidian vault access, and safe daily Markdown open/create/edit/save with external-change conflict detection. Keep Apple Calendar read-only and out of the first slice. Preserve all unrecognized Markdown content; never silently overwrite a changed file. Do not add networking, telemetry, Reminders access, AI, sync, or global cursor replacement. Use native controls/caret initially; any Neovide-inspired motion is optional, must respect macOS Reduce Motion, and must not compromise text input, VoiceOver, keyboard operation, or selection. Ask only when an unresolved decision blocks implementation; otherwise use the defaults and document assumptions. Add focused tests and report actual Mac/platform checks separately from unit tests. Follow `docs/daily-workspace/plan.html` for sequence and acceptance criteria.
