# Workflows: SDLC, ADWs, and the Road to Zero-Touch

Condensed from TAC lessons 4-7 and 14.

## Contents

- The SDLC as questions
- Composable steps and their contracts
- AI Developer Workflows (ADWs)
- PITER: the four elements of AFK agents
- In-Loop, Out-Loop, Zero-Touch
- Agentic KPIs
- Learn and retro

## The SDLC as questions

| Step | Question it answers | tac skill | Output |
| --- | --- | --- | --- |
| Plan | What are we building? | `plan` | `specs/<type>-<slug>.md` |
| Build | Did we make it real? | `implement` | Code changes + validation run |
| Test | Does it work? | `test` | JSON results, fixes applied |
| Review | Is what we built what we planned? | `review` | JSON verdict with severities |
| Document | How does it work? | `document` | `docs/...` page |
| Ship | Is it delivered? | `ship` | Commit, branch, PR |
| Learn | What did the harness learn? | `expert improve` (via `adw`) | Updated `.claude/experts/<domain>/expertise.yaml` in the same diff |

Testing and review are different questions. Tests prove behavior; review proves alignment with the spec.

## Composable steps and their contracts

The real secret of TAC is not the SDLC, it is **composable agentic primitives**: steps with fixed inputs and
outputs that can be chained in whatever order a problem class needs.

| Step | Input | Output contract | Done when |
| --- | --- | --- | --- |
| plan | task text (+ issue, + scout notes) | Spec file at a known path with every template section filled | File exists, has Step by Step Tasks and Validation Commands |
| build | spec path | Code changes; validation commands executed; last line `BUILD: DONE\|REPLAN\|FAILED` | Every task done, validation commands pass |
| test | (repo) | JSON array: `test_name, passed, execution_command, error`; last line `TESTS: PASS` or `TESTS: FAIL - <command> - <diagnosis>` | All entries `passed: true` |
| review | spec path | JSON: `success`, `issues[]` with `blocker / tech_debt / skippable`; last line `REVIEW: PASS` or `REVIEW: FAIL` (+ `PATCH: <path>`) | No blockers |
| fix | review issues or failing test JSON | Patch plan + changes | Re-run of the failing check passes |
| document | spec path + diff | Doc file path; last line `DOC: <path>` | File written |
| learn | changed files | Refreshed expertise for experts whose `core_files` intersect them | Best-effort; failure is recorded, never fails the run |

Rules that make steps composable:

- Each step runs in a **fresh agent** (one agent, one prompt, one purpose). Fresh context frees tokens,
  forces the step's inputs to be explicit, and prepares the step to run headless.
- Steps communicate through **files at known paths**, not conversation history.
- Loops are **bounded** (default 3 attempts) and escalate to a human when the bound is hit.

## AI Developer Workflows (ADWs)

An ADW is deterministic code that orchestrates non-deterministic agents.

```text
Deterministic (script / orchestrator)     Non-deterministic (agent)
- step order, retries, attempt limits     - reasoning about the task
- file paths, ids, branch names           - writing plans and code
- state file, logs, git operations        - diagnosing failures
```

Standard compositions (used by `/tac-final:adw`):

| Workflow | Steps | Use when |
| --- | --- | --- |
| `plan_build` | plan -> build | Small, low-risk, well-understood |
| `plan_build_test` | plan -> build -> test(fix loop) | Default for most changes |
| `plan_build_review_fix` | plan -> build -> test -> review -> fix loop | You would otherwise review it yourself |
| `sdlc` | plan -> build -> test -> review -> fix -> document | Features you will ship |

Every workflow that passes ends with the learn step unless you pass `--no-learn`.

Start with a workflow that is mostly in-loop. Promote it to headless only after it succeeds repeatedly.

## PITER: the four elements of AFK agents

| Element | Meaning | Practical options |
| --- | --- | --- |
| **P**rompt input | Where the task comes from | GitHub issue, a `specs/` file, a ticket |
| **T**rigger | What starts the run | You, a cron job, a webhook, `@claude` on an issue (Claude Code GitHub Action) |
| **E**nvironment | Where the agent runs safely | A git worktree, a container, a CI runner |
| **R**eview | How you check the result | A pull request (with the `review` step's JSON in the body) |

## In-Loop, Out-Loop, Zero-Touch

| Level | You are present for | Presence KPI | Move up when |
| --- | --- | --- | --- |
| In-Loop | Every step | Constant | Plans and tests are templated; the loop mostly works |
| Out-Loop | Prompt + PR review | Two touches | 85%+ of runs finish without a retry; tests catch regressions before review |
| Zero-Touch | Prompt only | One touch | 90%+ success over 20+ runs; review rarely finds new issues; rollback tested |

Zero-touch is a direction, not a switch. Keep humans on irreversible actions (merging to protected branches,
deploys, migrations) until the KPIs say otherwise. For a governed zero-touch pipeline with hooks and readiness
gates, look at an external zero-touch tool; none is bundled with this plugin.

## Agentic KPIs

| KPI | Want | Measured as |
| --- | --- | --- |
| Attempts | Down | 1 + re-plans (at most 1) + patch rounds per task |
| Size | Up | Lines of plan / diff an agent delivers per run |
| Streak | Up | Consecutive runs with attempts <= 2 |
| Presence | Down | Human touches per task |

`/tac-final:adw` appends one row per run to `.tac/kpis.md`; `/tac-final:assess` reads it. Failed and escalated runs also
append a line to the committed `.tac/lessons.md`; with `/tac-final:retro` that closes the improve loop on the
harness itself.

## Learn and retro

Markers make steps parseable: `/tac-final:adw` reads the last line matching `^KEY: *value` (`SPEC`, `BUILD`,
`TESTS`, `REVIEW`, `PATCH`, `LEARN`), so every step ends with its marker as plain text.

- **Learn** (every passing run): experts touched by the diff are refreshed from their `source_revision`; edits
  ship in the same PR.
- **Retro** (periodically, or when the streak breaks): `/tac-final:retro` turns `.tac/kpis.md`, escalated runs in
  `.tac/runs/`, review `tech_debt`, and `.tac/events.jsonl` into a dated `.tac/lessons.md` entry and at most one
  leverage-point fix plan in `specs/`.
