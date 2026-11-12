# System Inventory

The named parts of Daily Workspace, written before the next features are generated. Read this with [ARCHITECTURE.md](ARCHITECTURE.md) (how the code is organized today) and [`AGENTS.md`](../AGENTS.md) (the rules every agent follows). When the architecture changes, update this file in the same change.

Inputs: the staged refactor at `2790699` (+99 staged files), the vault at `~/github/brodynelly-brain`, and the Daily Workspace–Luuna research (`03-resources/research/daily-workspace-luuna/research/notes/final_report_luuna-workspace-bridge-cadfad.md` in the vault). Owner decisions recorded 2026-11-12.

## 0. The one-line system

**Daily Workspace is one Mac window over the systems that already own Brody's day — Calendar, Org, Seeds/Plot, Luuna, the app's own task list and the Obsidian vault — that shows each item with its source and native status, routes every action back to its owner, and helps resume a project from verified context.**

Remove-the-AI test: navigation, open loops, calendar, notes and capture keep working without a model. That is deliberate: the federated view must stay useful when the Assistant, the network or Luuna is unavailable. What the AI adds is grounded questions across all sources and a drafted restart record at the end of a project session. Without it, the restart loop below still works by hand, only slower. The compounding asset is the restart ledger, not the model.

## 1. The closed loop

> **When Brody resumes or closes a project session, the app captures a reviewed restart record — the sources read (path + hash + observed time), the decision made and the next exact action — so the next resume of that project, and the Assistant's context for it, starts from verified state instead of a cold re-read.**

- Capture: the Assistant drafts the record from the session (notes opened, Seeds/Plot rows viewed, today's agenda). Brody edits and accepts it. Nothing is saved without that acceptance.
- Store (phase 1): app-owned `RestartLedger` in `~/.config/daily-workspace/`. A later, separately approved write adapter can publish an accepted record into the project's `notes/` folder.
- Return arrow: Projects shows the latest accepted record first; the Assistant's project context loads it; changed source hashes are flagged as "changed since you last read it".
- Return arrow traced? **Yes**, once Increments 1 and 2 ship.

## 2. Sources of truth (owner decisions, 2026-11-12)

Daily Workspace is a **unified interface, not a task store**. Every item keeps its owner. The app shows the source and the native status, and routes actions back.

| Kind of item | Owner | Phase-1 access in the app | Status shown as |
| --- | --- | --- | --- |
| Personal actions | Org (`org/inbox.org`, `org/projects.org`) | Read-only parser | Org keyword verbatim (`TODO`, `NEXT`, `DONE`…) plus `SCHEDULED`/`DEADLINE` |
| Vault-managed project issues and plans | Seeds (`.seeds/`), labelled `project:<slug>` | Read-only parser | Seeds `status` verbatim |
| Coordination events | Plot (`.plot/`) | Read-only parser | Plot event/state verbatim |
| Repository work | The repo's established tracker (Luuna Missions where applicable) | Not yet (Increment 3, qualified reader) | Native status; a Luuna run `completed` is **not** a closed task |
| Readable context, decisions, restart notes | Project Markdown in `01-projects/<project>/` | Read (open in editor) | n/a. Historical checkboxes are **not** tasks |
| Calendar events | Apple Calendar (EventKit) | Existing read + edit | EventKit |
| Reminders | Apple Reminders (EventKit) | Existing read, add, complete | EventKit |
| App-local tasks | `tasks.json` (`~/.config/daily-workspace/`) | **Preserved unchanged**: existing edit/persist | Local |

Not decided here, and each needs its own proposal and approval: capture or write adapters for Org, Seeds, Quick Notes and Luuna; any migration of `tasks.json`; any change to the vault's `AGENTS.md` or task ownership.

## 3. Information architecture (sidebar: 7 → 6)

| Screen | Contents | Replaces |
| --- | --- | --- |
| **Today** | Agenda · local tasks due today · Org items whose own `SCHEDULED`/`DEADLINE` is today · today's daily note (correct path) · capture with an explicit destination | Today |
| **Projects** *(new)* | Project list from `01-projects` hubs. Detail: hub purpose and decisions, latest restart record, checkout references, Seeds issues for `project:<slug>`, Plot events, related notes. Luuna panel later | — |
| **Open Loops** | One list across Local, Org, Seeds and Reminders (Luuna later). Source badge, native status, observed time; filter by source/project. Actions route to the owner; external rows are read-only | Tasks, Reminders |
| **Notes** | Editor, recent notes, backlinks, vault search (search also in ⌘K) | Notes, Search |
| **Calendar** | Day agenda and event editing | Calendar |
| **Assistant** | Grounded chat with read-only tools; drafts restart records | AI Chat |

Today never invents daily attention for undated Seeds or Luuna items (research: "Daily attention convenience versus native workflow meaning"). An opt-in focus list can come later without changing ownership.

## 4. The Brain (reasoning)

| Role | Model | Why | Fallback |
| --- | --- | --- | --- |
| Assistant (Q&A over sources, restart drafts) | `claude-opus-5-5`, adaptive thinking, effort set explicitly per route (`low` for chat, `medium` for restart drafts), streaming | Current default Claude model; strong tool use over long context | Server-side `fallbacks: "default"` for refusals; for outages, the deterministic views (the Assistant shows "unavailable"; nothing else depends on it) |

- **Transport (decision pending, recommended):** add an `AgentTransport` that speaks the Anthropic Messages API directly over HTTPS (Swift has no official SDK). The existing `ChatTransport.complete(...) -> String` returns text only, so it cannot carry tool calls. Tool use, prompt caching, refusal fallbacks and thinking-block replay are first-party API features that an OpenAI-compatible route may not pass through. `OpenRouterClient` can stay as a plain-chat transport. No API key is configured today.
- Model choice and any cheaper tier are Brody's call, configured in Settings → AI. Nothing downgrades automatically.
- Forced `tool_choice` (`any`/`tool`) is rejected on this model: use `auto`, `strict: true` tools and the prompt.
- Determinism: no model output is ever the source of a status, an owner, a path or a date (see §8).

## 5. Memory (what it knows)

| Layer | What it stores | Tech | Refresh |
| --- | --- | --- | --- |
| Agent master files | Rules for agents building this app | `AGENTS.md` (+ `CLAUDE.md` → `@AGENTS.md`) | A line per session in the decisions log |
| Assistant system context | App rules (§8) + the vault's root `AGENTS.md` (read-only, hash recorded) | Frozen system prompt; cached prefix | On vault switch or `AGENTS.md` hash change |
| Vault retrieval | Note text for search, backlinks and `read_note` | `VaultIndex`: lexical, in memory. The **exclusion policy runs before any read** (§8.5) | On activation / Refresh; reports incomplete traversal |
| Source observations | Org, Seeds and Plot rows, EventKit items, `tasks.json` | One `SourceAdapter` per owner → `OpenLoop` rows (authority, id, kind, project, native status, revision/hash, observed-at) | On activation and on file change; the last successful observation is kept with its timestamp |
| Associations *(Increment 3)* | Hub ↔ checkouts ↔ optional Luuna project | App registry in `~/.config/daily-workspace/`; host access (bookmarks, origins, tokens) stored separately | Explicit user edits |
| **Restart ledger** *(the loop)* | Accepted restart records with source hashes | App store in `~/.config/daily-workspace/` | Append on acceptance |
| Chat transcript | Current conversation | In memory, **append-only** (thinking blocks replayed unchanged) | Cleared by the user |

There is no vector store in phase 1. About 2,700 notes with lexical search plus `read_note` is enough. Revisit if answer quality says otherwise.

## 6. Planning (how the Assistant decides)

- Pattern: one manual tool-use loop in Swift (`stop_reason == "tool_use"` → run tools → append results in **one** user message → repeat).
- Guardrails: at most 8 tool rounds per turn, a per-turn output-token cap, a 120-second timeout, Stop cancels. `refusal` and `max_tokens` stop reasons are checked before any tool runs.
- Human-on-the-loop: Brody asks; the Assistant answers with record IDs and paths it can cite.
- **Human-in-the-loop: every persistent change.** In phase 1 the Assistant has **no write tools**. Its only persistent output is a restart-record draft, saved to the app ledger after Brody accepts it. Capture suggestions are drafts that Brody sends through the capture form, with the destination chosen explicitly.
- Prompt-cache order: tools (fixed, sorted) → system (app rules + vault `AGENTS.md`) → messages. Volatile data (today's date, observations) goes after the last cache breakpoint. Mid-conversation operator notes are appended as system messages, never by editing earlier turns.

## 7. Tools

### Assistant tools (all read-only)

| Tool | What it does | Blast radius if it misfires | Gate |
| --- | --- | --- | --- |
| `search_notes(query, limit)` | Lexical search over non-excluded notes; returns paths + snippets | Note text leaves the Mac for the API provider | Assistant must be enabled explicitly; sent paths are listed in the turn |
| `read_note(path, max_bytes)` | Reads one note | Same; refuses excluded paths and anything outside the vault | Path resolved by `NoteVault.resolve` |
| `list_open_loops(source?, project?, status?)` | Federated `OpenLoop` rows | Read-only | — |
| `get_project(slug)` | Hub summary, checkouts, Seeds/Plot rows, latest restart record | Read-only | — |
| `get_agenda(day)` | EventKit events for a day | Event titles leave the Mac | Needs Calendar permission |

### App adapters (deterministic, no model)

| Adapter | Read/write | Blast radius | Gate |
| --- | --- | --- | --- |
| `NoteVault` (existing) | Load / atomic save / append | A vault note | The six vault-safety invariants in `CONTRIBUTING.md` |
| `TaskStore` (existing) | `tasks.json` read/write | Local tasks | Save-then-update (existing) |
| Calendar / Reminders (existing) | EventKit read + user-initiated writes | The user's Apple accounts | System permission + explicit UI action |
| `OrgReader` *(new)* | **Read-only** | none | Never writes `.org` files |
| `SeedsReader`, `PlotReader` *(new)* | **Read-only** file parse of `.seeds/*.jsonl` and `.plot/*.json` | none | Never runs `sd`/`plot`, never touches locks, keeps unknown fields |
| `DailyNoteResolver` *(new, fixes a bug)* | Reads `.obsidian/daily-notes.json` | Wrong path means a note in the wrong place | Refuses unsupported format tokens; never falls back to the vault root |
| `LuunaRuntimeReader` *(Increment 3)* | **Read-only** HTTP | none, if qualified | Loopback origin only, bearer token from Keychain, no redirects, no caching, never starts/initializes the runtime; first profile = health, project list/detail, component status |
| `AgentTransport` *(Increment 2)* | HTTPS to the model API | Cost; selected text leaves the Mac | Key in Keychain; explicit enable; per-turn caps |

## 8. Fallbacks: answers that must never be wrong

1. **Daily-note path.** Comes from `.obsidian/daily-notes.json` (`folder`, `format`, `template`) through a deterministic Moment-format renderer in `DailyCore` that covers at least `YYYY MM MMM DD dddd` (this vault: `250-daily/YYYY/MM-MMM/YYYY-MM-DD-dddd`). An unsupported token means refuse and ask; never write to the vault root. *Today the template supports only `YYYY/MM/DD`, an empty folder put `2026-11-12.md` in the vault root, and `MM` replacement corrupts `MMM`.*
2. **Status and ownership.** Taken verbatim from the owning source's parser and rendered from the row, never from model text. A Luuna `completed` run does not close a task. Markdown checkboxes are never promoted to current tasks.
3. **Source state.** `unsupported`, `unauthorized`, `unavailable`, `uninitialized`, `refused`, `partial/stale`, `empty` and `populated` are distinct UI states. An inaccessible folder is never shown as "nothing to do". Results from an old vault, project or connection are discarded.
4. **Capture.** The destination is always explicit. "Captured" appears only after a durable local save. An external handoff that isn't confirmed shows as *Draft — not submitted*.
5. **Exclusions before reads.** Hidden and `_`-prefixed paths, `04-archive/`, `templates/`, `00-inbox/automation/`, raw ingest, nested repositories, and generated boards (for example `01-projects/nas/operations/*-board.md`, which alone holds about 1,600 alert checkboxes) are skipped before any content is read. Incomplete traversal is reported.
6. **Assistant claims.** Any statement about a task, status or date must cite the record ID or path returned by a tool. Uncited claims are shown as unverified.
7. **Vault safety.** The invariants in `CONTRIBUTING.md` hold for every write, including future adapters.

## 9. Agents

There is one Assistant agent plus deterministic adapters. There is no gateway or multi-agent setup: the tools are read-only and the job is one conversation. Revisit only if a specialist (for example a restart-record drafter run in batch) proves its worth.

## 10. Evaluation and safety

- Before the Assistant is on by default: a golden set of about 20 questions over a **synthetic fixture vault** (`Tests/Fixtures/vault/`, no real notes). Cover status questions ("is X done?" must cite the native status), project restart, an excluded-path request (must refuse), a Luuna-completed-but-open item, and an empty source vs an unavailable one.
- Privacy: the Assistant is off until enabled. Logs never contain note text, chat or keys (existing `Log` rules).
- Increment 3 uses the research's disposable-state matrix (wrong token, redirect, unknown build, vault switch mid-request).

## 11. External dependencies and risks

| Dependency | Used for | Single point of failure? | Mitigation |
| --- | --- | --- | --- |
| Model API | Assistant only | For the Assistant only | Every other screen is deterministic |
| EventKit | Agenda, Reminders | No | Permission-denied state; notes and tasks unaffected |
| Vault bookmark | Notes, Org/Seeds/Plot reads | Yes, for vault-backed views | Existing re-authorize state |
| Seeds/Plot file formats | Read-only views | No | Pin the parser to observed fields, keep unknown fields, report parse errors as partial |
| Luuna runtime | Increment 3 panels | No | Optional; human context stays usable; timestamped last observation |

## 12. Delivery increments

| # | Outcome | Notes |
| --- | --- | --- |
| 0 | `DailyNoteResolver` + Moment tokens; capture and Today use the real daily note | A bug that writes to the wrong place today; fix first |
| 1 | IA 7 → 6; **Projects** (hubs, decisions, checkouts) and **Open Loops** (Local + Org + Seeds + Plot + Reminders, read-only external); visual system refresh across the new screens | `tasks.json` untouched; no writes to external owners |
| 2 | Assistant v1: `AgentTransport`, read-only tools, restart-record drafts → `RestartLedger` | Needs the transport decision and a key; golden-set eval |
| 3 | Association registry + qualified `LuunaRuntimeReader` (health, projects, component status) | Pick the runtime build/checkout; disposable fixtures |
| 4 | **Proposal only:** capture/write adapters per owner (Org inbox, Seeds via the vault launcher with an explicit actor, Quick Notes, Luuna) and any `tasks.json` migration | Separate review and approval before any code |

## 13. Open questions and logic debt

- Brain transport: Anthropic direct (recommended) or OpenRouter. Either way, a key is needed.
- Which Luuna runtime build and checkout to qualify first; which tracker owns this repo's implementation work.
- Long-term relationship between `tasks.json` and the external owners (proposal pending).
- `VaultIndex` keeps all note text in memory; fine at about 2,700 notes, revisit if the vault grows a lot.
- Chat transcripts are not persisted; decide once the restart ledger exists.
- A stray `2026-11-12.md` sits in the vault root from the template bug. Brody decides whether to delete it; the app never deletes vault files.
