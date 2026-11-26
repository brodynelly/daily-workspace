# AGENTS.md

> Owner update, 2026-11-13: Luuna/Missions owns project issues and plans; project notes hold context and coordination. Org owns personal actions outside Daily Workspace; the owner removed all Org app routing without migration. T00 B and E approve only individually reviewed vault Markdown saves. This does not approve Luuna or Org app writes, scheduled jobs or publication.

Daily Workspace is a native macOS app (Swift, SwiftUI + AppKit): one window over the systems that already own Brody's day. It shows each item with its source and native status, routes every action back to its owner, and helps resume a project from verified context. Claude Code and Codex both work in this repo; this file is the shared brief.

## Read first

1. [docs/SYSTEM-INVENTORY.md](docs/SYSTEM-INVENTORY.md): the named system, the closed loop, sources of truth, fallbacks and delivery increments. Build against it; don't invent a parallel shape.
2. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): where code goes, stores, protocol boundaries, persistence.
3. [CONTRIBUTING.md](CONTRIBUTING.md): build, lint and test commands, vault-safety invariants, commit rules.

## Commands

```sh
swift build && swift test
swift format lint --strict --recursive Sources Tests Package.swift
swiftlint --strict
./scripts/build_and_run.sh --verify
```

Report the real exit status of `swift test`, not filtered output.

## Rules a newcomer would break by accident

**Ownership: the app is an interface, not a task store**
- Org remains the owner of personal actions outside this app; the owner explicitly opted out of routing Org through Daily Workspace. Luuna/Missions owns project issues and plans; visible project notes hold coordination; each repo's tracker owns its work. Do not read or write Org from the app or move its contents into `tasks.json`. Show every in-app item with its native source and status.
- Never copy an external item into `tasks.json` or any app store. `tasks.json` is preserved as-is: don't migrate, merge or reshape it without an approved proposal.
- Historical Markdown checkboxes are context, not current tasks. Never surface them as open loops or infer status from them.
- A Luuna run `completed` does not mean a task is closed. Never derive one owner's status from another's.
- External Luuna and Org writes are explicitly declined for this app. On 2026-11-13 the owner approved only T00 rows B (reviewed Quick Notes/Inbox Markdown capture) and E (Assistant-guided reviewed Markdown drafts) under their exact path, confirmation and conflict rules; declined C (Luuna writes) and D (scheduled automation).

**The vault** (`~/github/brodynelly-brain`, chosen by the user through a security-scoped bookmark)
- Do not edit the vault's `AGENTS.md` or change task ownership rules from this repo.
- Daily-note paths come from `.obsidian/daily-notes.json`. Never guess a path and never write to the vault root.
- Apply the exclusion policy (SYSTEM-INVENTORY §8.5) before reading any content: archive, templates, generated automation, raw ingest, `_`-prefixed paths, nested repos and generated boards.
- Use the verified runtime CLI at `~/.local/bin/lu` for project work; do not restore retired tooling or use local component commands to bypass runtime policy.
- Never run direct component commands from an arbitrary vault directory; verify the selected existing store and source identity first.
- Never delete, rename or move vault files (CONTRIBUTING invariants 1–6).

**Luuna** (Increment 3)
- The app reads runtime-backed project and ticket data only through fixed-argv `~/.local/bin/lu … --json`, with source identity checks, distinct source states and stale-response rejection. Resolve the executable to an absolute path; never start or initialize the runtime from the app.
- The canonical developer checkout is `~/github/luuna/luuna`, distinct from the managed runtime source. Never treat a checkout as the selected runtime store; Luuna and Org app writes were declined.

**The Assistant**
- Model tools are read-only. The Assistant can propose cited note drafts, but only a user-selected, explicitly confirmed, conflict-checked Notes UI action may save them under approved T00 rows B and E. Accepted restart records remain app-owned.
- Statuses, owners, paths and dates in the UI come from adapters, never from model text. Claims must cite a record ID or path.
- Note text leaves the Mac only when the user has enabled the Assistant. Keys live in the Keychain. Never log note text, chat or keys.
- Keep the transcript append-only and in memory only; replay thinking blocks unchanged. The owner declined on-disk chat persistence.

**UI and state**
- App-owned files (settings, `tasks.json`, recovery, and later the ledger and associations) live in `~/.config/daily-workspace/` via `WorkspaceDirectory`. Never write them to Application Support or the vault. Secrets stay in the Keychain.
- Every source has distinct states: unsupported, unauthorized, unavailable, uninitialized, refused, partial/stale, empty, populated. An inaccessible source is never shown as "nothing to do".
- "Captured" or "Saved" appears only after a durable local save. Capture destinations are always explicit.

**Working alongside other agents**
- Run `git status` before starting. If another agent's changes are staged or in progress, don't edit the same files and don't commit their work.
- Commit only when asked. Never sweep someone else's staged files into your commit.

## Decisions log

Add one dated line per session for any decision a future agent would otherwise re-litigate.

- 2026-11-26: Owner asked to review and improve the Assistant's agentic runtime. Kept the hand-written Messages loop (no framework) and added a configurable layer: `assistantRuntime` in settings.json / Settings → AI → Runtime (clamped rounds, output tokens, efforts, retries, tool deadline, result budget, `disabledTools`), SDK-style retries only before anything streams (a 429 without `retry-after` is final), tool deadlines reported as "unknown, not empty", result budgets with narrowing hints, content-free `AgentRunEvent` observers and per-answer token usage, 300 s stream idle timeout. Settings can only narrow the read-only tool set, never add tools or writes; history is never trimmed client-side (it would invalidate replayed thinking). See docs/AGENT-RUNTIME.md.
- 2026-11-26: The AI page opens on a fresh chat; the previous conversation is filed under CHATS (memory only, until the app quits, per the declined on-disk chat persistence) and reopened explicitly (Return/click, ⌘[ / ⌘]). A reopened chat replays its transcript unchanged only for the same provider, model and system prompt; otherwise answers show and follow-ups start fresh context.
- 2026-11-26: Owner asked for a tabbed Quick Panel workspace page: Overview (dashboard plus all action rows, Finder and copy path), Git (lazygit-style: stage, commit, amend, discard, branch, merge, stash, fetch/pull --ff-only/push via fixed `/usr/bin/git` argv; discard, delete, drop, merge and amend need `y`; untracked discards go to the Trash) and Harness (project `.claude`/`.agents`/`.pi`/`.codex`/… plus allow-listed global config; credential-like files never listed). `[`/`]` switch tabs. Harness saves only replace existing files after an on-disk hash check, and `?` attaches one redacted file to the next AI question only while the Assistant is enabled. Vault workspaces get no Git writes and read-only, never-sent harness files.
- 2026-11-26: The Quick Panel AI chat is a full-panel page, not a popup or sidebar: `?` and ⌘J open it with QUESTIONS, AI CHAT and ASK panes (⌃h/⌃j/⌃k/⌃l move between them; j/k, g/G and ⌘[/⌘] move between questions outside ASK). The `?` sidebar was removed so there is one AI surface. Monitor sorts processes with `<`/`>` and `i` and never signals them.
- 2026-11-26: Quick Panel ⌘J opens a Raycast-style AI chat popup over the shared in-memory Assistant (⌘K actions, `/` commands, ⇧⌘M model list fetched from the selected provider's models endpoint with the user's key, only while the Assistant is enabled; choosing a model starts a new chat). ⌘+/⌘-/⌘0 zoom each panel view and the popup separately, saved as `quickPanelZoom` in settings.json; Music keeps ⌘+/⌘- for volume. AI answers render block Markdown. The main window sidebar no longer lists recent notes (they stay on Notes).
- 2026-11-26: On Quick Panel Home, Return on a row with a directory (agent cwd, Kitty session path) opens an in-panel workspace page (read-only `git --no-optional-locks` stats, agent co-author share, running agents, launch rows); ⌘↵ keeps the row's own Kitty action. Commit subjects and file names are hidden for paths inside the vault. The Monitor view (btop-style CPU/memory/network/battery and `ps` process list) samples only while visible and never signals or kills processes.
- 2026-11-26: Quick Panel `/` opens search and `?` toggles an AI CHAT sidebar (Library-sidebar layout) over the shared in-memory Assistant conversation and draft; text is sent only on Return with the Assistant enabled, with no page focus. The menu-icon ribbon is replaced by a read-only stats bar; ⌘K, `m` and ⌥ menus open the same in-panel popup. Supersedes "`/` or `?` opens search" below.
- 2026-11-26: Keep the Luuna workspace and Pascal panel styles. Narrow layouts prioritize the selected project, conversation or calendar week, with the project list, conversation details and month picker reachable on demand.
- 2026-11-26: Owner asked for terminal-style (vim/lazygit/yazi) Quick Panel navigation instead of function keys. Outside the search field, plain and shifted characters plus ⌃d/u/f/b/e/y are fixed vim keys (j/k, gg/G, h/l, /, 1–0, [ ], r, z, m, q, dd, music n/p/-/+/s/S/x) and cannot be rebound; type-to-search is gone, so `/` or `?` opens search. The footer advertises no F-keys; old F-key handlers remain only as unadvertised fallbacks.
- 2026-11-15: Owner granted Calendar access to the installed app and expressed a preference for future Obsidian-associated reminders over Apple Reminders; this is not approval to migrate reminders or treat historical vault checkboxes as live work. Leave Reminders permission unrequested and Mail off. Synthetic hotkey dispatch is not physical Go60 parity; retain QAP/QAM rollback bundles and do not revoke their permissions until remaining manual checks pass.
- 2026-11-14: Owner confirmed the open note is safe to relaunch, delegated remaining migration/cutover decisions without more questions, and accepted the documented risk of Luuna's unauthenticated loopback token listener for this cutover. Historical HomeBase/KOTC/SprintBoard actions without verified current native owner/status remain provenance-only, not imported. The installed Luuna launcher honors `LUUNA_NO_AUTO_START=1` for app reads; any replacement launcher needs the same fail-closed contract. Live QAP/QAM routes can be switched only with verified parity and a retained rollback; unrelated Hammerspoon desktop-switch, Focus and display functions remain owned outside this migration.
- 2026-11-13: Owner requested publishing reviewed app work to `main`; this authorizes an app-repository commit and push, not live QAP/QAM launcher retirement, vault or dotfile edits, or other external writes. Keep the duplicate vault-notes directory out of the app commit.
- 2026-11-13: Owner removed Org from all app views, adapters and Assistant without migration; Org stays external. Owner approved T00 B for individually reviewed capture to existing `02-areas/personal-development/quick-notes.md` or a user-named new `00-inbox/*.md`, and E for cited Assistant drafts saved only after a separate exact-path before/after review in Notes. Owner explicitly declined C (Luuna writes/cancellation), D (scheduled jobs) and saved Assistant transcripts (keep memory-only). Owner also requested Quick AI Chat in Quick Panel and opt-in voice chat; launcher retirement has not been approved.
- 2026-11-13: Owner approved Luuna project `daily-workspace`, repository `app`, manifest revision 1 and managed Missions/Atlas/Beacon onboarding. Use the runtime source and CLI; baseline qualification is tracked separately and app write adapters remain pending T00.
- 2026-11-13: Fixed-argv `~/.local/bin/lu` JSON reads replaced the obsolete HTTP client and historical Seeds/Plot readers; native ticket status and run status remain separate. Live Keychain reads use a noninteractive authentication context and run off the main actor so a stalled security daemon cannot block panel startup; explicit credential saves may prompt.
- 2026-11-13: Consolidation panel keeps the existing Dock icon and keeps the app running when the main window closes; this is the conservative implementation choice for T02, not an approval of write adapters or launcher retirement.
- 2026-11-13: Read-only selected-run `lu follow` uses bounded incremental NDJSON, resumes after the last complete sequence, and clears events on run or credential changes. Run start/cancel and runtime shutdown remain outside the app pending owner approval.
- 2026-11-13: Assistant providers now use separate Anthropic/OpenRouter Messages transports, Keychain entries and model settings; switching clears the transcript. Vault project discovery is read-only; Claude subscription OAuth is not a supported third-party app login, and AI-generated vault writes remain gated on an approved reviewed adapter.
- 2026-11-13: The main-window sidebar collapses with its top-bar button or ⌃⌘S; visibility stays window-local, while Go and ⌘1…⌘6 retain navigation when hidden.
- 2026-11-13: Shortcut overrides are app-owned settings; a focused key recorder validates and persists them, while the global capture hotkey is suspended during recording. Settings remains in the main window. Quick Panel contextual route/music keys and standard modal/editing keys remain fixed; this does not grant any Assistant/vault write authority.
- 2026-11-13: `?` now opens the contextual AI inspector on any workspace screen; F1 opens Keyboard help. The panel and full Assistant page share a conversation and draft; selected page metadata is transmitted only on Ask and must pass vault scope checks. This does not approve Assistant write tools or external owner changes.

- 2026-11-12: Sources of truth fixed by the owner (Org / project tracker / project Markdown / `tasks.json` preserved). Start with project navigation and read-only external views; capture and write adapters and any migration need a separate proposal.
- 2026-11-12: IA goes from 7 to 6 screens: Today, Projects, Open Loops, Notes, Calendar, Assistant. Reminders becomes a source in Open Loops; Search moves into Notes and ⌘K.
- 2026-11-12: The closed loop is the reviewed restart record (sources + hashes, decision, next action) in an app-owned ledger.
- 2026-11-12: App files moved to `~/.config/daily-workspace/` (settings.json replaces UserDefaults; legacy values imported once; legacy `tasks.json` copied, never moved). API keys stay in the Keychain.
- 2026-11-12: Increment 0 is the daily-note path bug (empty folder, no `MMM`/`dddd` tokens), which wrote `2026-11-12.md` to the vault root.
- 2026-11-12: Increments 0–3 built in parallel (worktree agents, merged on `main`). The UI follows Luuna's desktop design system (`~/github/luuna/luuna/docs/DESIGN-SYSTEM.md`): tokens in `Shared/Theme`, components in `Shared/Components`; green only for verified or authorised states, never for "done".
- 2026-11-12: The Assistant talks to Anthropic directly (`AnthropicClient`, model `claude-opus-5-5`, off by default). The old OpenRouter chat is unreachable and due for removal.
- 2026-11-12: Lint with both swift-format 6.1 (CI's toolchain) and the local one; `.swift-format` must stay readable by 6.1.
- 2026-11-12: The Luuna token rule: `connectLuuna(token: nil)` keeps the saved token, `""` removes it.


## Luuna Project Onboarding

Registered 2026-11-13 after explicit owner approval:

- Runtime project: `daily-workspace`; repository: `app`; checkout: `/Users/bnelly/github/misc/daily-workspace`.
- Registration initially confirmed manifest revision `1` (`sha256:995f1f50a35d1fd44c1067558ac3fdc5bd240028052b625a1132347974781db4`); the current runtime reports revision `2` (`sha256:e22f2cbaf615a833b532e310720ecd8f11c58a1b36f13593ce4ef23a98c20291`). Always read `lu project daily-workspace --json` before relying on a revision.
- Missions, Atlas and Beacon are enabled in the managed workspace `/Users/bnelly/.luuna-data/components/projects/daily-workspace`. This is distinct from the developer checkout.
- Claude reads this file through `CLAUDE.md`'s existing `@AGENTS.md`; Codex reads this file directly.

Use the verified CLI at `~/.local/bin/lu` from a safe working directory for human/agent reads: `~/.local/bin/lu health --json`, `~/.local/bin/lu project daily-workspace --json`, `~/.local/bin/lu tickets daily-workspace --json`, `~/.local/bin/lu show-ticket <id> --json`, and `~/.local/bin/lu board --project daily-workspace --json`. The app now uses fixed-argv read-only CLI JSON, but scripted coverage does not certify a live runtime. Read live help before separately requested human/agent mutations. Human/agent ticket filing outside the app uses `~/.local/bin/lu create-ticket daily-workspace ... --repository app --key <stable-key> --json`; Luuna app writes were explicitly declined under T00.

For selected expertise, `~/.local/bin/lu memory daily-workspace --query <term> --json` reads Atlas through the runtime without private-user inclusion. `~/.local/bin/lu prompts daily-workspace --json` reads Beacon prompts. Do not automatically record memory, onboard hooks, synchronize or commit. Native component onboarding previews assumed local stores; no second local store was initialized. Direct component commands must target the explicitly verified managed source, never this checkout by accident.

Required baseline recipes are `swift build`, `swift test`, `swift format lint --strict --recursive Sources Tests Package.swift`, and `swiftlint --strict`. `lu baselines daily-workspace --json` reports a passing revision-2 baseline at exact commit `d6b70d7e7d2ff97b0b823255f17f23d0301eb6a7`; this does not qualify subsequent dirty changes. Preserve dirty work.

Readable scope, migration and parity context is linked from `/Users/bnelly/github/brodynelly-brain/01-projects/daily-workspace/daily-workspace.md`. Native tickets own current scope and status. Plan confirmation does not approve implementation or publication.
