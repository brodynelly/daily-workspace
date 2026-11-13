# System Inventory

> Implementation inventory, 2026-11-13: Luuna/Missions owns project work and project notes hold context; Org personal actions remain external to this app by owner choice. T00 B/E approve only individually reviewed Markdown saves, not Org, Luuna or automation writes. Built code is not live-runtime or model qualification.

The named parts of Daily Workspace. Read with [ARCHITECTURE.md](ARCHITECTURE.md) for code boundaries and [`AGENTS.md`](../AGENTS.md) for agent rules. This inventory distinguishes implemented paths from separately gated proposals; it does not certify tests that have not been reported by the integration owner.

## 0. The one-line system

**Daily Workspace is one Mac window over Calendar, Reminders, native Luuna project work, the app's local tasks and the selected Obsidian vault; each item keeps its source and native status. Org is deliberately not an app source.**

Remove-the-AI test: navigation, open loops, calendar, notes and capture keep working without a model. That is deliberate: the federated view must stay useful when the Assistant, the network or Luuna is unavailable. What the AI adds is grounded questions across all sources and a drafted restart record at the end of a project session. Without it, the restart loop below still works by hand, only slower. The compounding asset is the restart ledger, not the model.

## 1. The closed loop

> **When Brody resumes or closes a project session, the app captures a reviewed restart record — the sources read (path + hash + observed time), the decision made and the next exact action — so the next resume of that project, and the Assistant's context for it, starts from verified state instead of a cold re-read.**

- Capture: the Assistant may draft from notes opened, cited native project tickets and today's agenda. Brody edits and accepts; the app ledger is not written until acceptance.
- Store (built): app-owned `RestartLedger` in `~/.config/daily-workspace/`. Publishing an accepted record to project `notes/` is a separate proposal, not a live write adapter.
- Return arrow (built): Projects shows the latest accepted record first; Assistant project context loads it and checks for changed source hashes.
- Return arrow traced? Code exists; test/live-model qualification must be reported separately.

## 2. Sources of truth (owner decisions, 2026-11-12–13)

Daily Workspace is a **unified interface, not a task store**. Every item keeps its owner. The app shows the source and the native status, and routes actions back.

| Kind of item | Owner | Built access in the app | Native status / pending boundary |
| --- | --- | --- | --- |
| Personal actions | Org, outside Daily Workspace | No app adapter, read or write | Existing Org data remains untouched; no migration into `tasks.json`. |
| Project issues and plans | Luuna/Missions | Read-only fixed-argv `~/.local/bin/lu … --json`: board, tickets, ticket detail, project and all-project Home, project identity/components | Ticket native ID/status if present, board's native lane; a run's `completed` state is **not** ticket closure. No Luuna writes approved. |
| Coordination context | Visible project notes linked to native IDs | Read project Markdown | Source context, not a ticket or action merely because a checkbox appears. |
| Repository work | The repo's established tracker (Luuna Missions where applicable) | Native Luuna work for an explicitly bound project; no separate generic tracker reader | Do not infer status from a checkout, Markdown checkbox or Luuna run. |
| Readable context, decisions, restart notes | Project Markdown in `01-projects/<project>/` | Read/open in editor, app-owned accepted restart ledger | n/a; historical checkboxes are **not** tasks. |
| Calendar events | Apple Calendar (EventKit) | Existing read + user-initiated edit; QuickPanel read-only today/next-event snapshot | EventKit, with distinct denied/unavailable states. |
| Reminders | Apple Reminders (EventKit) | Existing read, add, complete | EventKit. |
| Mail metadata | Apple Mail (Apple Events) | Read-only flagged/unread message subject, ID, native state **only after explicit opt-in** | No message body/headers, no Assistant exposure; revoke and clear on opt-out/failed recheck. |
| App-local tasks | `tasks.json` (`~/.config/daily-workspace/`) | Preserved existing edit/persist | Local; no migration approved. |

T00 B and E were separately approved on 2026-11-13 for user-reviewed Markdown capture and cited Assistant note drafts. Org was removed from app scope; Luuna writes, scheduled external actions and `tasks.json` migration remain unapproved. Vault ownership rules are unchanged.

## 3. Information architecture (sidebar: 7 → 6)

| Screen | Built contents and owner | Replaces |
| --- | --- | --- |
| **Today** | Apple Calendar agenda · local tasks and Reminders due today · today's daily note · capture with an explicit destination. Undated Luuna/Mail work is not assigned a fabricated due date. | Today |
| **Projects** | Project hubs, decisions and accepted restart record; bound Luuna native board, tickets, detail and Home shown read-only with source state and observed time. | — |
| **Open Loops** | Local tasks, Reminders and opted-in Mail with source badge, native status, observed time and owner action. Native Luuna tickets appear in Projects. | Tasks, Reminders |
| **Notes** | Editor, recent notes, backlinks, vault search (also in ⌘K) | Notes, Search |
| **Calendar** | EventKit day agenda and user-initiated event editing | Calendar |
| **Assistant** | Read-only grounded model tools over permitted sources; app-owned restart drafts; cited, explicitly reviewed Markdown note drafts. Mail and Org excluded. | AI Chat |

**QuickPanel** is a separate reusable app panel, not a seventh workspace screen: routes for sessions, files, projects, workspaces, attention, system, music and a read-only Calendar snapshot (today's events and next upcoming event). File → Quick AI Chat opens the shared contextual Assistant. The `daily` control executable sends allowlisted JSON commands over a same-user Unix socket in `~/Library/Caches/DailyWorkspace/`; it cannot send arbitrary tools, paths or commands. Clipboard-count feedback and Kitty border are opt-in. The generated app bundles a decoded, SHA-256-verified VGA font via `scripts/bundle.sh`; `BundledFonts.vgaName` registers it once, with a fallback when unavailable. Visual parity requires a separate smoke pass.

Settings is an in-window destination, not a seventh screen or second window. The searchable Keyboard tab stores per-action shortcut overrides in app-owned `settings.json`; system/typing keys and conflicting bindings are rejected. Only the scoped main-window and focused QuickPanel receive local shortcuts, with Carbon registration reserved for explicit global capture.

The `?` shortcut or Ask AI top-bar button opens a contextual right-side Assistant on every screen; F1 opens the keyboard reference. Its shared conversation stays in memory across navigation. Only an explicit Ask sends the current page focus (selected Calendar day or an eligible selected project/note identifier) along with the question. Focus is not evidence; read-only tools verify the source, and excluded notes and Mail remain outside the Assistant.

## 4. The Brain (reasoning)

| Role | Model | Why | Fallback |
| --- | --- | --- | --- |
| Assistant (Q&A over sources, restart drafts) | `claude-opus-5-5`, adaptive thinking, effort set explicitly per route (`low` for chat, `medium` for restart drafts), streaming | Current default Claude model; strong tool use over long context | Server-side `fallbacks: "default"` for refusals; for outages, the deterministic views (the Assistant shows "unavailable"; nothing else depends on it) |

- **Transports (updated 2026-11-13):** `AnthropicClient` uses the Anthropic Messages API directly, retaining Anthropic adaptive thinking, caching, structured drafts and tool-use replay. `OpenRouterClient` uses OpenRouter's Messages-format endpoint with bearer-key authentication, tool streaming, and a provider-neutral request body. Non-Claude OpenRouter models may not support all tool or JSON features; OpenRouter restart drafts request JSON in the prompt and are validated before review. Keys/model IDs are separate, provider changes clear the transcript, and the Assistant stays off by default. The old text-only `ChatTransport` is not restored. Claude subscription OAuth is not offered inside a third-party app: do not extract or intermediate Claude Code/Claude.ai credentials. No live provider-key qualification is implied by scripted tests.
- Model choice and any cheaper tier are Brody's call, configured in Settings → AI. Nothing downgrades automatically.
- Forced `tool_choice` (`any`/`tool`) is rejected on this model: use `auto`, `strict: true` tools and the prompt.
- Determinism: no model output is ever the source of a status, an owner, a path or a date (see §8).

## 5. Memory (what it knows)

| Layer | What it stores | Tech | Refresh |
| --- | --- | --- | --- |
| Agent master files | Rules for agents building this app | `AGENTS.md` (+ `CLAUDE.md` → `@AGENTS.md`) | A line per session in the decisions log |
| Assistant system context | App rules (§8) + the vault's root `AGENTS.md` (read-only, hash recorded) | Frozen system prompt; cached prefix | On vault switch or `AGENTS.md` hash change |
| Vault retrieval | Note text for search, backlinks and `read_note` | `VaultIndex`: lexical, in memory. The **exclusion policy runs before any read** (§8.5) | On activation / Refresh; reports incomplete traversal |
| Source observations | Opted-in Mail metadata, native Luuna project/tickets/board/Home, EventKit items, `tasks.json` | `OpenLoopsStore` owns local/Reminders/Mail; `LuunaStore` and `LuunaWorkStore` own CLI projections, scoped to selected runtime/project. Mail clears on opt-out or failed permission recheck. | Activation/explicit refresh and vault/connection changes; last success retained for non-Mail sources. |
| Associations *(built)* | Hub ↔ checkouts ↔ optional Luuna project | App registry in `~/.config/daily-workspace/`; host access and tokens stored separately | Explicit user edits to app-owned association only. |
| **Restart ledger** *(the loop)* | Accepted restart records with source hashes | App store in `~/.config/daily-workspace/` | Append on acceptance |
| Chat transcript | Current conversation | In memory, **append-only** (thinking blocks replayed unchanged) | Cleared by the user |

There is no vector store in phase 1. About 2,700 notes with lexical search plus `read_note` is enough. Revisit if answer quality says otherwise.

## 6. Planning (how the Assistant decides)

- Pattern: one manual tool-use loop in Swift (`stop_reason == "tool_use"` → run tools → append results in **one** user message → repeat).
- Guardrails: at most 8 tool rounds per turn, a per-turn output-token cap, a 120-second timeout, Stop cancels. `refusal` and `max_tokens` stop reasons are checked before any tool runs.
- Human-on-the-loop: Brody asks; the Assistant answers with record IDs and paths it can cite.
- **Human-in-the-loop: every persistent change.** The Assistant has **no write tools**. Brody may accept a restart-record draft into the app ledger, or use a cited Assistant answer as an editable Markdown draft: select the exact eligible path, inspect the full before/after and separately confirm the conflict-checked vault save. Capture suggestions likewise go through an explicit destination and review.
- Prompt-cache order: tools (fixed, sorted) → system (app rules + vault `AGENTS.md`) → messages. Volatile data (today's date, observations) goes after the last cache breakpoint. Mid-conversation operator notes are appended as system messages, never by editing earlier turns.

## 7. Tools

### Assistant tools (all read-only)

| Tool | What it does | Blast radius if it misfires | Gate |
| --- | --- | --- | --- |
| `search_notes(query, limit)` | Lexical search over non-excluded notes; returns paths + snippets | Note text leaves the Mac for the API provider | Assistant must be enabled explicitly; sent paths are listed in the turn |
| `read_note(path, max_bytes)` | Reads one note | Same; refuses excluded paths and anything outside the vault | Path resolved by `NoteVault.resolve` |
| `list_open_loops(source?, project?, status?)` | Federated `OpenLoop` rows | Read-only | — |
| `list_projects()` | Bounded eligible vault hub inventory with citeable paths and source state | Hub metadata leaves the Mac for the API provider | Requires an available selected vault |
| `get_project(slug)` | Hub summary, checkouts, native project records, latest restart record | Read-only | — |
| `get_agenda(day)` | EventKit events for a day | Event titles leave the Mac | Needs Calendar permission |

### App adapters (deterministic, no model)

| Adapter | Read/write | Blast radius | Gate |
| --- | --- | --- | --- |
| `NoteVault` (existing) | Load / atomic save / append | A vault note | The six vault-safety invariants in `CONTRIBUTING.md` |
| `TaskStore` (existing) | `tasks.json` read/write | Local tasks | Save-then-update (existing) |
| Calendar / Reminders (existing) | EventKit read + user-initiated writes | The user's Apple accounts | System permission + explicit UI action |
| `VaultNoteReview` (approved B/E) | Explicitly previewed Markdown creation or snapshot-checked save | One selected visible note | Selected security-scoped vault, allowed scope, existing parent, exact path and separate confirmation; open notes save through `NoteDocument`. No model write tool. |
| `LuunaCLIReader` (built) | **Read-only** fixed `lu … --json` argv: `health`, `projects`, `project`, `components`, `board`, `tickets`, `show-ticket`, project/global `home`, `runs --project`, `run <id>` | No external writes | Absolute `~/.local/bin/lu`; validated loopback origin and Keychain token passed in environment; bounded output/time, no shell; project/origin binding and stale-response checks; never initializes the runtime. Removed HTTP client and Seeds/Plot parsers are not live. |

| Mail metadata reader (built) | **Read-only**, opt-in Apple Events | Message subjects/IDs on this Mac | Fixed script, no message bodies or headers; disabled by default, no Assistant tool access, clears on opt-out or failed recheck. |
| `DailyNoteResolver` | Reads `.obsidian/daily-notes.json` | Wrong path means a note in the wrong place | Refuses unsupported format tokens; never falls back to the vault root. |
| `AgentTransport` | HTTPS to the model API, only if enabled | Cost; selected text leaves the Mac | Key in Keychain; explicit enable; per-turn caps. |

T15 read-only boundary: bound-project `lu runs --project <p> --json` and selected `lu run <r> --json` are projected in Assistant and Quick Panel Agents (alongside existing QAP rows). Native run state is kept distinct from ticket state. `LuunaRunFollower` streams bounded incremental `lu follow --after … --json` events, retaining the last complete sequence for reconnect and discarding foreign run/project IDs. Run start/cancellation and external writes were declined under T00. Live-runtime qualification remains separate from scripted coverage.

## 8. Fallbacks: answers that must never be wrong

1. **Daily-note path.** Comes from `.obsidian/daily-notes.json` (`folder`, `format`, `template`) through deterministic Moment-format rendering in `DailyCore` (`YYYY MM MMM DD dddd` among supported tokens). Unsupported tokens refuse; never write to the vault root as a fallback.
2. **Status and ownership.** Luuna ticket native status/board placement and local/Reminders states come from their owning observations, not model prose. A run's `completed` state is not ticket closure. Org remains external. Markdown checkboxes are not current tasks.
3. **Source state.** `unsupported`, `unauthorized`, `unavailable`, `uninitialized`, `refused`, `partial/stale`, `empty` and `populated` are distinct UI states. An inaccessible folder is never shown as "nothing to do". Results from an old vault, project or connection are discarded.
4. **Capture.** The destination is always explicit. "Captured" appears only after a durable local save. An external handoff that isn't confirmed shows as *Draft — not submitted*.
5. **Exclusions before reads.** Hidden and `_`-prefixed paths, `04-archive/`, `templates/`, `00-inbox/automation/`, raw ingest, nested repositories, and generated boards (for example `01-projects/nas/operations/*-board.md`, which alone holds about 1,600 alert checkboxes) are skipped before any content is read. Incomplete traversal is reported.
6. **Assistant claims.** Tool results carry owner IDs and paths for citation; scripted fixture answers are pinned separately. Live-model answer quality has not been qualified.
7. **Vault safety.** The invariants in `CONTRIBUTING.md` hold for every write, including future adapters.

## 9. Agents

There is one Assistant agent plus deterministic adapters. There is no gateway or multi-agent setup: the tools are read-only and the job is one conversation. Revisit only if a specialist (for example a restart-record drafter run in batch) proves its worth.

## 10. Evaluation and safety

- Before enabling the Assistant by default: `AssistantGoldenSetTests` runs scripted questions against a **synthetic fixture vault** (`Tests/Fixtures/vault/`, no real notes), plus synthetic native Luuna ticket/run cases. Cases cover local/Reminders statuses, restart hashes, exclusions, historical checkboxes and unavailable Calendar. Fixture tests are not a live-model evaluation.
- Privacy: the Assistant is off until enabled; opted-in Mail remains excluded from Assistant tools. Logs must not contain note text, chat or keys.
- CLI qualification against an installed, running Luuna build and a separate consented real-model evaluation remain pending; fake reader/scripted fixture coverage is not live-runtime certification.

## 11. External dependencies and risks

| Dependency | Used for | Single point of failure? | Mitigation |
| --- | --- | --- | --- |
| Model API | Assistant only | For the Assistant only | Every other screen is deterministic |
| EventKit | Agenda, Reminders | No | Permission-denied state; notes and tasks unaffected |
| Vault bookmark | Notes, reviewed Quick Notes/Inbox capture and project-context reads | Yes, for vault-backed views | Re-authorize state and no write after an unavailable/changed vault |
| Luuna ticket contract | Native project work | No | Built read-only CLI JSON with fixed argv and runtime/project binding; distinguish source failures and missing native status. Installed-runtime qualification is separate. |
| Luuna runtime | Project/board/ticket/Home panels | No | Optional; hub context stays usable, last observation is timestamped; the app never starts the runtime. |
| Mail Automation | Opted-in Open Loops metadata | No | No access until opt-in; absent permission is not an empty inbox, subjects are cleared on failed recheck/opt-out and never reach Assistant. |

## 12. Delivery increments

| # | Outcome | Status and boundary |
| --- | --- | --- |
| 0 | `DailyNoteResolver` + Moment tokens; capture and Today use the configured daily note | **Built** 2026-11-12. |
| 1 | IA 7 → 6; Projects hubs and Open Loops across Local + Reminders, native project views and opt-in Mail | **Built**. Org/Seeds/Plot readers retired; no external owner migration; `tasks.json` unchanged. |
| 2 | Assistant v1: `AgentTransport`, read-only tools and app-owned accepted restart ledger | **Built**, off by default. Scripted fixture outcomes and hands-on model run have not been reported here; never mistake synthetic responses for model validation. |
| 3 | Association registry + CLI read-only health, projects, components, native board/tickets/detail/Home (T13/T14/T27) | **Built code**. Fixed-argv `~/.local/bin/lu … --json` is the sole production Luuna transport; HTTP client retired. Live-runtime qualification remains separate, and the app never initializes a runtime. |
| QuickPanel | Reusable panel + `daily` control executable and private same-user socket; opt-in integrations; read-only Calendar snapshot | **Built code**. Calendar permission/next-event state and font fallback do not constitute a new source owner. |
| T15 read-only | Native run list/detail and bounded follow events in Assistant and Quick Panel Agents | **Built code with scripted tests, not qualified against a live runtime**. `LuunaRunFollower` streams incremental CLI output and resumes at the last complete sequence; run start/cancellation were declined. |
| 4 / T00 | Reviewed Quick Notes/Inbox Markdown capture and cited Assistant draft saves | **B/E approved and implemented** with exact-path preview and conflict guards. Org removed from app scope; Luuna writes and automation were declined, and no `tasks.json` migration was approved. |

## 13. Open questions and logic debt

- Long-term relationship between `tasks.json` and the external owners (proposal pending).
- `VaultIndex` keeps all note text in memory; fine at about 2,700 notes, revisit if the vault grows a lot.
- Chat transcripts are not persisted: the owner chose memory-only conversation state.
- A stray `2026-11-12.md` sits in the vault root from the template bug. Brody decides whether to delete it; the app never deletes vault files.
