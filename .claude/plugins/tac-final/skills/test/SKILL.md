---
name: test
description: Runs the project's validation stack (lint, typecheck, tests, build, optional E2E) and closes the loop - on failure it reproduces, fixes the root cause, and re-runs until green or three attempts, reporting structured JSON. Use whenever asked to run tests, lint, typecheck, build, verify, or validate, when tests or CI are failing, or after implementing a change - even in an unfamiliar repo, since it finds the commands itself.
argument-hint: "[--report-only] [--e2e] [test name or path]"
allowed-tools: Read, Glob, Grep, Bash(git status *), Bash(git diff *)
---

# Test (Closed Loop)

Arguments: `$ARGUMENTS`. Request -> Validate -> Resolve, until the work is proven or the loop is exhausted.

## 1. Find the commands

Use the `Validate` list from the TAC section in `CLAUDE.md`/`AGENTS.md`. If missing, run
`bash "${CLAUDE_SKILL_DIR}/../setup/scripts/detect-project.sh"` and use its candidates, and recommend `/tac-final:setup`.
If a test name or path was given, run only the matching narrow command first (for example a single test file).
Add the E2E command only with `--e2e` or when the user asks.

## 2. Run (Request + Validate)

Run each command in order (fast to slow). Stop at the first failure. For long output, keep only the lines that
identify the failure. For large suites, delegate execution to the `tac-final:tester` agent so logs stay out of this context.

## 3. Resolve (skip with `--report-only`)

For each failure:

1. Reproduce with the exact `execution_command`.
2. Find the root cause. Fix the code, not the test - change a test only when it is provably wrong, and say so.
3. Re-run the failing command, then the whole stack to catch regressions.
4. Maximum 3 attempts per failure. Then stop and escalate with what you tried and what you suspect.

For E2E failures, read any screenshots, traces, or videos the runner produced before changing code; timing
issues need proper waits or loading states, not sleeps.

## Output

Return the JSON result (contract in
[../guide/references/conventions.md](../guide/references/conventions.md#test-result-test---tester-agent---adw)),
failed entries first, then a short summary:

```json
[{"test_name": "test", "passed": true, "execution_command": "npm test", "error": null}]
```

```markdown
Result: <all green | n failing> - fixes applied: <files or "none"> - attempts: <n>
```

End your response with exactly one verdict marker line, plain text at the start of the line (no backticks,
bullets, or code fence). `/tac-final:adw` takes the last line matching `^TESTS: *<value>`:

```text
TESTS: PASS
```

or, when anything is still failing (including after `--report-only`):

```text
TESTS: FAIL - <failing command> - <one-line diagnosis>
```

`PASS` only when every command in the stack passed on the final run.
