---
name: review
description: Reviews the current changes against their spec - checks every requirement and acceptance criterion, classifies gaps as blocker, tech_debt, or skippable, and returns a JSON verdict; with blockers it can write a patch plan. Answers "is what we built what we asked for?", which tests cannot. Use after implementation and testing, before shipping or opening a PR.
argument-hint: "[path-to-spec.md] [--patch]"
allowed-tools: Read, Glob, Grep, Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git symbolic-ref *)
---

# Review Against Spec

Review the working changes against the spec at `$ARGUMENTS` (if no path is given, use the most recently
modified spec in the specs directory and say so).

## Workflow

1. Read the spec: requirements, Acceptance Criteria, Out of Scope, Validation Commands.
2. Find the default branch (TAC section, or `git symbolic-ref refs/remotes/origin/HEAD`, else `main`). Inspect
   the changes: `git diff <default>...HEAD`, plus `git diff` and `git status` for uncommitted work.
3. For each requirement and acceptance criterion: is it implemented, and does it match the spec? Cite file:line.
4. Check for scope creep: changes the spec did not ask for.
5. If the project has a UI and a way to run it, capture evidence (screenshots or command output) for the key paths.
6. Classify every issue:
   - `blocker`: a requirement or criterion is unmet, or users are harmed
   - `tech_debt`: works, but quality, maintainability, or performance should improve
   - `skippable`: polish or preference

For large diffs, delegate steps 2-6 to the `tac-final:reviewer` agent (pass it the spec path) and keep only its JSON.
Do not re-run the whole test suite - that is `/tac-final:test`. Do run a validation command when it is the only way
to confirm a criterion.

## Output

Return the review JSON (contract in
[../guide/references/conventions.md](../guide/references/conventions.md#review-result-review---reviewer-agent---adw)).
`success` is true exactly when there are no blockers.

If `--patch` was given and there are blockers, also write a patch plan for them using the template at
[../plan/assets/patch.md](../plan/assets/patch.md) (`specs/patch-<spec-slug>-<short-desc>.md`) and add `"patch_plan": "<path>"` to the JSON.

Record every `tech_debt` issue in the JSON even when the verdict is PASS: `/tac-final:retro` reads it later.

End your response with the verdict marker lines, plain text at the start of the line (no backticks, bullets,
or code fence), so workflows can parse them. `/tac-final:adw` takes the last line matching `^REVIEW: *<value>`:

```text
REVIEW: PASS
```

or, with blockers:

```text
REVIEW: FAIL
PATCH: specs/patch-<spec-slug>-<short-desc>.md
```

Write `PATCH:` only when `--patch` actually wrote that file; it must be the path from `patch_plan`.
