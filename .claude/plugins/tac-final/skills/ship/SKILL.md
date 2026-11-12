---
name: ship
description: Ships validated work - creates a branch if needed, writes a Conventional Commit, pushes, and opens a pull request linked to its spec and issue; merges only when explicitly asked and checks pass. Use when changes are reviewed and ready to commit, push, open a PR, or merge.
argument-hint: "[spec-path] [#issue] [--no-pr] [--merge]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git symbolic-ref *)
---

# Ship

Arguments: `$ARGUMENTS`. Deliver the current changes safely. Every step has an abort condition; when one
triggers, stop and report instead of working around it.

## 1. Pre-flight

- `git status`: there must be changes or unpushed commits. Nothing to ship -> stop.
- Find the default branch (TAC section, else `git symbolic-ref --short refs/remotes/origin/HEAD`, else `main`).
- Validation: if this session has not run `/tac-final:test` green since the last edit, run the TAC validation
  commands now. Any failure -> stop and suggest `/tac-final:test`.
- If a spec is given and no review has passed for it in this session, suggest `/tac-final:review <spec>` first and
  ask whether to continue.
- Never ship secrets: scan the staged diff for `.env` files, keys, and tokens. Found -> stop.

## 2. Branch

If on the default branch, create one following the repo's convention, else
`<feat|fix|chore>/<slug>` (type from the spec's Metadata, or inferred from the diff). Never commit directly to
the default branch unless the user explicitly asks.

## 3. Commit

- Stage only files that belong to this change (review `git status`; never `git add` unrelated or generated junk).
  Expertise edits from the learn step (`.claude/experts/<domain>/`) belong to the change: stage them with it so
  the reviewer of the code also reviews what the expert learned.
- Message: the repo's convention if it has one (check `git log --oneline -10`, CONTRIBUTING, memory files),
  else Conventional Commits: `<type>(<scope>): <summary>` (summary under 72 characters, imperative mood), with a
  body that says why and references the spec and issue (`Refs: specs/...`, `Closes #123`).
- Sign commits if the repo or user configuration requires it.

## 4. Push and pull request (skip PR with `--no-pr`)

- `git push -u origin <branch>`.
- If `gh` is available, open a PR against the default branch. Use the repo's PR template if one exists
  (`.github/pull_request_template.md` and variants); otherwise:

  ```markdown
  ## Summary
  <what and why, 2-4 sentences>

  ## Changes
  - <bullets>

  ## Validation
  - <commands run and results; review verdict if available>

  ## Expertise updated
  - <`.claude/experts/<domain>/expertise.yaml` - what changed, or "none">

  Spec: <path>  Closes #<issue>
  ```

- Without `gh`, print the compare URL and the PR body for the user to paste.

## 5. Merge (only with `--merge`)

Merge only when the user passed `--merge`, CI is green, and the PR is approved or the repo has no review
requirement. Prefer `gh pr merge --squash` (or the repo's configured strategy) over a local merge into the
default branch. Never force-push the default branch.

## Output

```markdown
## Shipped
- Branch: <name>  Commit: <short sha> <subject>
- PR: <url or "not created">  Merge: <merged | not requested | blocked: reason>
```
