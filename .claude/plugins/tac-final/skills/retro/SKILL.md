---
name: retro
description: Runs a retrospective over the agentic layer's own evidence - KPIs, failed and escalated run logs, review tech_debt, hook event patterns, and expert eval scores - classifies each failure to one of the 12 leverage points, appends a dated entry to the committed ledger .tac/lessons.md, and writes at most one leverage-point fix as a chore or patch plan in specs/ for a human to approve. Never edits skills, agents, experts, or code. Use after failed or escalated runs pile up, on a regular cadence, or when asked why agents keep failing the same way.
argument-hint: "[--since YYYY-MM-DD] [--runs N]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Write, Edit, Bash(git log *), Bash(wc *), Bash(ls *)
---

# Retro

Arguments: `$ARGUMENTS`. This is the harness's LEARN step for itself: the runs acted, retro finds the leverage point
behind their failures, and a human decides whether the harness changes.

## Boundaries (read first)

- **Write only two things**: append to `.tac/lessons.md`, and create at most ONE new plan file in the specs
  directory (TAC section `Specs:`, default `specs/`). Never edit skills, agents, hooks, expertise files, evals,
  `CLAUDE.md`, settings, or code, even when the fix is obvious. The plan is the proposal; the human is the gate.
- **Append, never rewrite**: past ledger entries are history. Do not reorder, correct, or delete them.
- **Bounded**: at most `--runs` runs (default 20, maximum 50), at most the last 2000 lines of `.tac/events.jsonl`,
  one pass, no retries, one plan.

## 1. Scope

1. `--since`: if given, use it. Otherwise use the date of the last `### <date> retro` heading in `.tac/lessons.md`;
   if there is none, the last 30 days.
2. Collect run ids already classified by earlier retro entries (lines `- <run-id> ...` under a retro heading); skip them.
3. If `.tac/` does not exist, stop: "No run evidence yet. Run `/tac-final:adw` or `/tac-final:orchestrate` first."

## 2. Gather evidence (read-only)

| Source | What to extract |
| --- | --- |
| `.tac/kpis.md` | Rows in scope: count by Result; Attempts > 1 (replans and fix rounds); mean attempts; Type of failing rows |
| `.tac/lessons.md` `run` lines | Failed and escalated runs: run id, workflow, failing step (`<step>-<attempt>`), log path |
| `.tac/runs/<id>/state.json` | Steps for those runs, plus any `learn: failed` and `build: replan` steps in passed runs |
| `.tac/runs/<id>/<step>-<attempt>.log` | The last ~60 lines of each failing step's log: the verdict, the error, the command |
| Review results in those logs | `tech_debt` issues that repeat across runs (same file or same resolution) |
| `.tac/events.jsonl` (tail 2000) | Tool-failure patterns: guard denials and permission refusals, the same Bash `detail` repeated 3+ times in one session (retry storms), `PostToolUseFailure` events if logged, subagents stopped without a verdict |
| `.claude/experts/*/expertise.yaml` | `last_eval` scores under 80%, `source_revision` far behind `git log`, Learn failures above |
| `git log --oneline --since=<since>` | Context: what shipped in the window |

`events.jsonl` `detail` values may contain `[REDACTED]` placeholders; never try to recover them. Events and step
logs are gitignored and not uploaded by CI, so run retro locally where the runs happened to see them.
Missing sources are fine; note them in the report. If no failed or escalated run, replan, Learn failure, low eval
score, or repeated tool failure is in scope, append a "no actionable pattern" retro entry and stop without a plan.

## 3. Classify

Assign every failure one primary leverage point from
[the 12 leverage points](../guide/references/doctrine.md#the-12-leverage-points). Pick the earliest point where a
change would have prevented it, not where it surfaced.

| # | Lever | Typical evidence |
| --- | --- | --- |
| 1 | Context | Agent edited the wrong area or missed a file; stale expertise (low eval, Learn failed); scout reports missed it |
| 2 | Model | Correct context and prompt, still wrong reasoning on a hard step (rare; prove 1, 3, 4 first) |
| 3 | Prompt | Missing or malformed verdict marker; skill instruction ambiguous; agent did extra or less than asked |
| 4 | Tools | Permission refused in a headless step, missing `--allowedTools` rule, guard denial, tool error loop |
| 5 | Standard out | The log does not say what failed; the agent guessed |
| 6 | Types | Contract mismatch the type system or a schema would have caught |
| 7 | Documentation | Agent could not find how to run, test, or configure something; TAC section incomplete |
| 8 | Tests | Escalated at `test`; flaky, slow, or missing tests; validation command does not exist |
| 9 | Architecture | Same file conflicts or ripple failures across runs; "where X happens" not greppable |
| 10 | Plans | `BUILD: REPLAN`; review blockers "spec not met"; plan lacked a step or validation command |
| 11 | Templates | Several plans of one type miss the same section or check |
| 12 | ADWs | Runner bug: wrong step order, lost state, wrong branch or base, bad marker parsing |

Then rank levers by: number of runs affected, then severity (`failed` over `escalated` over replan or Learn
failure), then recency. The top lever is the leverage point to fix.

## 4. Append the ledger entry

Append to `.tac/lessons.md` (create it with a `# Lessons` heading if missing):

```markdown
### 2026-10-23 retro (since 2026-09-23; 14 runs, 3 escalated, 1 failed, mean attempts 1.6)
- a1b2c3d4 escalated at test-1 -> 8 Tests: e2e auth test times out on cold start (`.tac/runs/a1b2c3d4/test-1.log`)
- b5c6d7e8 failed at build-2 -> 10 Plans: second REPLAN, spec never named the migration file
- events: 9 refused `Bash(npx prisma *)` calls in headless sessions -> 4 Tools
- experts: billing last_eval 6/10 -> 1 Context
- Top lever: 8 Tests (2 runs). Fix proposed: `specs/chore-retro-stabilize-e2e-auth.md` (status: proposed)
```

One line per classified run or pattern, each with its evidence path. If a previous retro's proposed fix for the
same lever has no matching implementation yet (its spec exists, no commit references it), say "still open:
`<spec>`" instead of proposing a duplicate.

## 5. Propose ONE fix

Write exactly one plan for the top lever (none if step 2 found nothing actionable or step 4 found it still open):

- Use [the chore template](../plan/assets/chore.md) for a harness or codebase improvement (a test, a doc, a
  permission rule, a template section, a runner fix), or [the patch template](../plan/assets/patch.md) when it
  corrects one defect in an existing spec or skill.
- Save as `<specs-dir>/chore-retro-<slug>.md` or `<specs-dir>/patch-retro-<slug>.md`. In Metadata, set Source to
  `retro <date>` and list the run ids as evidence.
- The fix must be the smallest change that would have prevented the most runs in the entry. It may target
  skills, agents, experts, or code; retro only describes the change. Validation Commands must prove it (for
  example, re-run the failing check, or `bash adw.sh --dry-run`).

## 6. Report and stop

```markdown
## Retro <date> (since <date>)
| Lever | Runs | Example |
| --- | --- | --- |
| 8 Tests | 2 | a1b2c3d4 test-1: e2e auth timeout |
- Ledger: appended to `.tac/lessons.md`
- Proposed fix: `specs/chore-retro-stabilize-e2e-auth.md` (lever 8)
- Missing evidence: <sources not found>
- Next: review the plan, then `/tac-final:implement specs/chore-retro-stabilize-e2e-auth.md` to approve it,
  or delete it to reject. Commit `.tac/lessons.md` either way.
```

Stop after the report. Do not implement the plan, run workflows, or start another retro.
