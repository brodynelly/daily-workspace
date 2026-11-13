# AGENTS.md

> Owner update, 2026-11-13: Luuna/Missions owns project issues and plans. Project notes hold context and coordination; Org owns personal actions. This updates the target workflow. Legacy adapter code still requires implementation work; documentation changes do not certify its removal or enable external writes.

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
- Org owns personal actions; Luuna/Missions owns project issues and plans; visible project notes hold coordination; each repo's tracker owns its work (Luuna Missions where applicable); project Markdown holds context. Show the source and the native status verbatim, and route actions back to the owner.
- Never copy an external item into `tasks.json` or any app store. `tasks.json` is preserved as-is: don't migrate, merge or reshape it without an approved proposal.
- Historical Markdown checkboxes are context, not current tasks. Never surface them as open loops or infer status from them.
- A Luuna run `completed` does not mean a task is closed. Never derive one owner's status from another's.
- External sources are **read-only** until a write adapter is approved (SYSTEM-INVENTORY §12, increment 4). This covers Org and Luuna.

**The vault** (`~/github/brodynelly-brain`, chosen by the user through a security-scoped bookmark)
- Do not edit the vault's `AGENTS.md` or change task ownership rules from this repo.
- Daily-note paths come from `.obsidian/daily-notes.json`. Never guess a path and never write to the vault root.
- Apply the exclusion policy (SYSTEM-INVENTORY §8.5) before reading any content: archive, templates, generated automation, raw ingest, `_`-prefixed paths, nested repos and generated boards.
- Use the verified runtime `lu` interface for project work; do not restore retired tooling or use local component commands to bypass runtime policy.
- Never run direct component commands from an arbitrary vault directory; verify the selected existing store and source identity first.
- Never delete, rename or move vault files (CONTRIBUTING invariants 1–6).

**Luuna** (Increment 3)
- Loopback HTTP only, bearer token from the Keychain, no redirects, no caching. Never start or initialize the runtime.
- The two runtime trees (`~/github/luuna-ai/luuna`, `~/github/luuna-ai-os-main/luuna/luuna`) are distinct; never treat one as the other.

**The Assistant**
- Tools are read-only. Its only persistent output is a restart-record draft, saved after the user accepts it.
- Statuses, owners, paths and dates in the UI come from adapters, never from model text. Claims must cite a record ID or path.
- Note text leaves the Mac only when the user has enabled the Assistant. Keys live in the Keychain. Never log note text, chat or keys.
- Keep the transcript append-only; replay thinking blocks unchanged.

**UI and state**
- App-owned files (settings, `tasks.json`, recovery, and later the ledger and associations) live in `~/.config/daily-workspace/` via `WorkspaceDirectory`. Never write them to Application Support or the vault. Secrets stay in the Keychain.
- Every source has distinct states: unsupported, unauthorized, unavailable, uninitialized, refused, partial/stale, empty, populated. An inaccessible source is never shown as "nothing to do".
- "Captured" or "Saved" appears only after a durable local save. Capture destinations are always explicit.

**Working alongside other agents**
- Run `git status` before starting. If another agent's changes are staged or in progress, don't edit the same files and don't commit their work.
- Commit only when asked. Never sweep someone else's staged files into your commit.

## Decisions log

Add one dated line per session for any decision a future agent would otherwise re-litigate.

- 2026-11-13: Owner approved Luuna project `daily-workspace`, repository `app`, manifest revision 1 and managed Missions/Atlas/Beacon onboarding. Use the runtime source and CLI; baseline qualification is tracked separately and app write adapters remain pending T00.

- 2026-11-12: Sources of truth fixed by the owner (Org / project tracker / project Markdown / `tasks.json` preserved). Start with project navigation and read-only external views; capture and write adapters and any migration need a separate proposal.
- 2026-11-12: IA goes from 7 to 6 screens: Today, Projects, Open Loops, Notes, Calendar, Assistant. Reminders becomes a source in Open Loops; Search moves into Notes and ⌘K.
- 2026-11-12: The closed loop is the reviewed restart record (sources + hashes, decision, next action) in an app-owned ledger.
- 2026-11-12: App files moved to `~/.config/daily-workspace/` (settings.json replaces UserDefaults; legacy values imported once; legacy `tasks.json` copied, never moved). API keys stay in the Keychain.
- 2026-11-12: Increment 0 is the daily-note path bug (empty folder, no `MMM`/`dddd` tokens), which wrote `2026-11-12.md` to the vault root.
- 2026-11-12: Increments 0–3 built in parallel (worktree agents, merged on `main`). The UI follows Luuna's desktop design system (`~/github/luuna-ai/luuna/docs/DESIGN-SYSTEM.md`): tokens in `Shared/Theme`, components in `Shared/Components`; green only for verified or authorised states, never for "done".
- 2026-11-12: The Assistant talks to Anthropic directly (`AnthropicClient`, model `claude-opus-5-5`, off by default). The old OpenRouter chat is unreachable and due for removal.
- 2026-11-12: Lint with both swift-format 6.1 (CI's toolchain) and the local one; `.swift-format` must stay readable by 6.1.
- 2026-11-12: The Luuna token rule: `connectLuuna(token: nil)` keeps the saved token, `""` removes it.


## Luuna Project Onboarding

Registered 2026-11-13 after explicit owner approval:

- Runtime project: `daily-workspace`; repository: `app`; checkout: `/Users/bnelly/github/misc/daily-workspace`.
- Confirmed manifest revision: `1`; hash: `sha256:995f1f50a35d1fd44c1067558ac3fdc5bd240028052b625a1132347974781db4`.
- Missions, Atlas and Beacon are enabled in the managed workspace `/Users/bnelly/.luuna-data/components/projects/daily-workspace`. This is distinct from the developer checkout.
- Claude reads this file through `CLAUDE.md`'s existing `@AGENTS.md`; Codex reads this file directly.

Use runtime commands from a safe working directory: `lu health --json`, `lu project daily-workspace --json`, `lu tickets daily-workspace --json`, `lu show-ticket <id> --json`, and `lu board --project daily-workspace --json`. Read live help before mutations. Requested human/agent ticket filing uses `lu create-ticket daily-workspace ... --repository app --key <stable-key> --json`; the app's write adapters still require T00 approval.

For selected expertise, `lu memory daily-workspace --query <term> --json` reads Atlas through the runtime without private-user inclusion. `lu prompts daily-workspace --json` reads Beacon prompts. Do not automatically record memory, onboard hooks, synchronize or commit. Native component onboarding previews assumed local stores; no second local store was initialized. Direct component commands must target the explicitly verified managed source, never this checkout by accident.

Required baseline recipes are `swift build`, `swift test`, `swift format lint --strict --recursive Sources Tests Package.swift`, and `swiftlint --strict`. Qualification is tracked independently; SwiftLint was unavailable during setup, and no passing baseline is implied. Preserve dirty work.

Readable scope, migration and parity context is linked from `/Users/bnelly/github/brodynelly-brain/01-projects/daily-workspace/daily-workspace.md`. Native tickets own current scope and status. Plan confirmation does not approve implementation or publication.
