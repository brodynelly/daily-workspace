# tac Conventions

Every tac skill follows these conventions, so steps can be chained by people, subagents, or scripts.
They are deliberately small, and every one can be overridden from the project's TAC section.

## Contents

- How skills find project settings
- The TAC section
- File layout
- Data contracts (test, review, markers, run state)
- Expert store and the Learn hook
- Lessons ledger
- Naming

## How skills find project settings

For any value (validation commands, specs directory, default branch, docs directory), resolve in this order:

1. The **TAC section** in `CLAUDE.md` or `AGENTS.md` (or `.claude/CLAUDE.md`).
2. **Detection**: run `bash <tac-plugin>/skills/setup/scripts/detect-project.sh` (skills reference it as
   `${CLAUDE_SKILL_DIR}/../setup/scripts/detect-project.sh`). It reads manifests and prints candidates.
3. **Ask** the user, then suggest `/tac-final:setup` so the answer is written down for next time.

Never guess a command silently. A wrong validation command turns a closed loop into a false green.

## The TAC section

`/tac-final:setup` writes this block into the project's memory file. Edit it by hand any time.

```markdown
## Agentic layer (tac)

- Specs: `specs/`
- Docs: `docs/`
- Default branch: `main`
- Validate (run in order, stop at first failure):
  - lint: `npm run lint`
  - typecheck: `npx tsc --noEmit`
  - test: `npm test`
  - build: `npm run build`
- E2E (optional): `npx playwright test`
- Expert adapter: atlas
```

Omit any line that does not apply. Keep the section under 20 lines. `Expert adapter: atlas` is optional: it tells
`tac-final:expertise-curator` to also sync expertise through Luuna Atlas's CLI (contract:
[../../expert/references/luuna-suite-ownership.md](../../expert/references/luuna-suite-ownership.md)).

## File layout

| Path | Written by | Purpose | Commit it? |
| --- | --- | --- | --- |
| `specs/<type>-<slug>.md` | `plan` | Plans. `<type>` is `feature`, `bug`, `chore`, or `patch` | Yes |
| `docs/<slug>.md` | `document` | Feature docs (or the repo's existing docs directory) | Yes |
| `.tac/runs/<run-id>/state.json` | `adw`, `orchestrate` | Run state and step results | No (gitignore `.tac/runs/`) |
| `.tac/kpis.md` | `adw` | One row per run: attempts, size, result | Optional |
| `.tac/lessons.md` | `adw`, `orchestrate` (run lines), `retro` (dated retro entries) | Append-only ledger of failed/escalated runs and leverage-point retros; input for `/tac-final:retro` | Yes |
| `.tac/events.jsonl` | plugin hooks | Tool and subagent event log, written only when `.tac/` exists (`TAC_EVENT_LOG=off` disables) | No (gitignore) |
| `.claude/experts/<domain>/expertise.yaml` | `tac-final:expertise-curator` | Agent-expert mental model, pinned by `source_revision` | Yes |
| `.claude/experts/<domain>/evals.yaml` | human + curator seed | Expert eval questions scored by `/tac-final:expert eval` | Yes |
| `.claude/worktrees/<name>/` | Claude Code (`--worktree`, `isolation: worktree`) | Isolated checkouts for parallel agents | No |

If the repo already has a spec convention (for example `docs/specs/`, `.specify/`, `.kiro/specs/`), set
`Specs:` in the TAC section to that directory instead of creating a second one.

## Data contracts

### Test result (`test` -> `tester` agent -> `adw`)

```json
[
  {"test_name": "lint", "passed": true, "execution_command": "npm run lint", "error": null},
  {"test_name": "test", "passed": false, "execution_command": "npm test", "error": "FAIL auth.test.ts: expected 200, got 401"}
]
```

Failed entries first. `error` is the shortest excerpt that identifies the failure.

### Review result (`review` -> `reviewer` agent -> `adw`)

```json
{
  "success": false,
  "summary": "Two of three acceptance criteria met; CSV header row missing.",
  "issues": [
    {"severity": "blocker", "description": "Export omits header row", "resolution": "Write header before rows in export.ts", "file": "src/export.ts"}
  ]
}
```

Severities: `blocker` (spec not met or user harmed; must fix), `tech_debt` (works, but should improve; record it),
`skippable` (polish). `success` is `true` exactly when there are no blockers. Keep `tech_debt` issues in the JSON
even when the review passes; `retro` looks for repeats.

### Marker lines (every step -> `adw.sh`)

Each step's response ends with its marker as the last matching line, in plain text at the start of the line (no
backticks, bullets, or code fence). `adw.sh` reads the last line matching `^KEY: *value`.

| Marker | Written by | Values |
| --- | --- | --- |
| `SPEC:` | `plan`, `planner` | `SPEC: <path>` |
| `BUILD:` | `implement`, `builder` | `BUILD: DONE`, `BUILD: REPLAN - <reason>` (one replan per run), `BUILD: FAILED - <command>` |
| `TESTS:` | `test`, `tester` | `TESTS: PASS`, `TESTS: FAIL - <command> - <diagnosis>` |
| `REVIEW:` | `review`, `reviewer` | `REVIEW: PASS`, `REVIEW: FAIL` |
| `PATCH:` | `review --patch` | `PATCH: <path>` on the line after `REVIEW: FAIL`, only when the patch plan was written |
| `DOC:` | `document`, `documenter` | `DOC: <path>` |
| `LEARN:` | `expert` (Learn step) | `LEARN: UPDATED <domains>`, `LEARN: NONE`, `LEARN: FAILED - <reason>` |

### Run state (`.tac/runs/<run-id>/state.json`)

```json
{
  "run_id": "a1b2c3d4",
  "workflow": "plan_build_review_fix",
  "task": "Add CSV export to reports",
  "issue": null,
  "type": "feature",
  "spec": "specs/feature-csv-export.md",
  "branch": "feat/a1b2c3d4-csv-export",
  "worktree": null,
  "steps": [{"name": "plan", "status": "passed", "attempt": 1}],
  "status": "running",
  "started_at": "2026-10-22T14:03:00Z"
}
```

`status` is one of `running`, `passed`, `failed`, `escalated`. Timestamps are UTC ISO-8601.

Step `name` is one of `plan`, `build`, `test`, `review`, `fix`, `document`, `learn`, `ship`; `learn` comes after
the last verifying step. Step `status` is `passed` or `failed`, and may also be `skipped` (Learn with nothing to do,
or `--no-learn`) or `replan` (a build that returned `BUILD: REPLAN`). `orchestrate` adds `"base": "<sha>"` (the
starting commit Learn diffs from) and `items[]` (id, spec, branch, status).

## Expert store and the Learn hook

One contract for every reader and writer (full format:
[../../expert/references/expertise-format.md](../../expert/references/expertise-format.md)):

- **Store**: `.claude/experts/<domain>/expertise.yaml`, plus optional `evals.yaml`. Agents always read the file;
  the Atlas adapter, when declared, is a sync target, never the only copy.
- **Writer**: only `tac-final:expertise-curator` (via `/tac-final:expert create|improve|eval`) writes under
  `.claude/experts/<domain>/`. It never commits.
- **Pinning**: `source_revision` is the commit SHA the model was validated against; `last_validated` is the date.
  `improve` diffs from `source_revision` (falling back to `last_validated` when the SHA is not in history), then
  sets it to `git rev-parse HEAD`.
- **Readers** (`scout`, `planner`, `prime`, `plan`, `expert ask`): read the expertise first as a map to verify,
  not as truth.
- **Learn hook** (`adw`, `orchestrate`): after a passing run, changed paths = `git diff --name-only <base>...HEAD`
  plus uncommitted changes. A domain is touched when a changed path equals one of its `core_files[].path`, or
  starts with one ending in `/`. Improve at most 5 domains; log `learn: <domain> <ok|failed|skipped> <reason>`;
  never fail the run. Edits land in the same branch and PR as the code. `--no-learn` skips it.

## Lessons ledger (`.tac/lessons.md`)

Committed and append-only; never reorder or rewrite past entries. Two kinds of entry:

```markdown
- 2026-10-23 run a1b2c3d4 | workflow sdlc | escalated at review-3 | log `.tac/runs/a1b2c3d4/review-3.log` | spec `specs/feature-x.md`

### 2026-10-23 retro (since 2026-09-23; 14 runs, 3 escalated, 1 failed, mean attempts 1.6)
- a1b2c3d4 escalated at review-3 -> 10 Plans: spec never named the migration file
- Top lever: 10 Plans (2 runs). Fix proposed: `specs/chore-retro-<slug>.md` (status: proposed)
```

`adw` and `orchestrate` append `run` lines for failed or escalated runs. `/tac-final:retro` appends the dated
entries and writes at most one fix plan in the specs directory; it never edits skills, agents, experts, or code.
Gitignore `.tac/runs/` and `.tac/events.jsonl`, never all of `.tac/`.

## Naming

- Run ids: 8 lowercase hex characters.
- Branches: `<feat|fix|chore>/<run-id>-<slug>` (slug: kebab-case, at most 40 characters), unless the repo's
  memory file defines another pattern.
- Commits: Conventional Commits (`feat: ...`, `fix: ...`, `chore: ...`), unless the repo defines its own style.
