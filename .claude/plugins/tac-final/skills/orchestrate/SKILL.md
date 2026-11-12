---
name: orchestrate
description: Orchestrates large or multi-part work across parallel agents - scouts the codebase, decomposes the task into independent work items with specs, builds each in its own git worktree, integrates the branches, validates, reviews every item against its spec, and refreshes the agent experts the combined change touched. Use for compound requests, large refactors, or several independent changes that would overflow one agent's context.
argument-hint: "[--no-learn] [task | #issue | list of tasks]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Write, Edit, Bash(git status *), Bash(git log *), Bash(git diff *), Bash(git branch *), Bash(git worktree list *), Bash(mkdir -p .tac/*)
---

# Orchestrate

Task: `$ARGUMENTS`

You are the orchestrator: one interface that creates, commands, and retires specialized agents. Keep your own
context small: delegate reading and building, keep only summaries, and track everything in files.
Background: the three pillars (orchestrator, agent lifecycle, observability) and the R&D framework in
[../guide/references/context-engineering.md](../guide/references/context-engineering.md).

Use `/tac-final:adw` instead when the task is a single coherent change; orchestration pays off only when work splits.

## 0. Initialize

Create run id and `.tac/runs/<run-id>/state.json` (contract in
[../guide/references/conventions.md](../guide/references/conventions.md)). Require validation commands
(TAC section); without them stop and recommend `/tac-final:setup`. Require a clean working tree. Record the
starting commit as `base` in `state.json` (`git log -1 --format=%H`): Learn diffs from it.

## 1. Scout (parallel, read-only)

Launch 2-4 `tac-final:scout` agents in parallel, one per area the task touches (for example API, data model, UI,
tests). Each returns files, patterns, and risks in under ~40 lines.

## 2. Decompose

From the scout reports, split the task into work items. Each item must be:

- **Independent**: buildable and testable without another item's unmerged changes, or explicitly dependent.
- **Small**: one agent, one prompt, one purpose; roughly one spec's worth of work.
- **Checkable**: has its own acceptance criteria and validation commands.

Group items into **waves**: items in a wave run in parallel; a wave starts after the previous one is integrated.
Two items that edit the same files belong in the same item or in different waves.

Write `.tac/runs/<run-id>/work-items.md` (table: id, title, type, depends on, wave, spec). Then delegate one
`tac-final:planner` agent per item (in parallel) to write its spec; record each `SPEC:` path.

**Checkpoint:** show the work breakdown and waves; ask the user to confirm before building unless they asked
for an unattended run.

Then create the integration branch and commit the specs to it, so isolated builders can see them (fresh
worktrees contain only committed files, and they branch from the default branch, not from your checkout):

```bash
git switch -c orchestrate/<run-id>
git add <specs-dir>/<each item spec>
git commit -m "docs: add specs for orchestrate run <run-id>"
```

## 3. Build (per wave, parallel, isolated)

For each item in the wave, launch a `tac-final:builder` agent **with worktree isolation**, giving it the spec path and
these extra instructions: "Work only in your worktree. First run `git merge --ff-only orchestrate/<run-id>` so your
worktree has the specs and every earlier wave's work; if that fails, stop and report. After validation passes,
commit on your branch with a Conventional Commit message referencing the spec, and report your branch name."

Track each agent's status in `state.json` (`items[]`: id, spec, branch, status). Agents that fail validation
after their own retries are marked `failed`; continue with the rest of the wave.

See [references/worktree-environments.md](references/worktree-environments.md) when worktrees need env files,
dependencies installed, or distinct ports.

## 4. Integrate

1. Stay on the integration branch `orchestrate/<run-id>` created in step 2.
2. Merge each passed item branch in dependency order (`git merge --no-ff <branch>`). On conflicts, resolve them
   preserving both items' intent; if the intent conflicts, stop and ask.
3. Delegate the full validation stack to the `tac-final:tester` agent on the integration branch. Fix integration
   failures (or patch-plan them) before the next wave.

## 5. Review

Run one `tac-final:reviewer` agent per item in parallel (each against its spec, on the integration branch). Blockers
get a patch plan and a builder, at most 2 rounds per item; then escalate.

## 6. Learn (once, best-effort; skipped with `--no-learn`)

After the last wave is integrated and reviewed, refresh the agent experts the whole run touched, once, following
the "Learn hook" contract in [../expert/SKILL.md](../expert/SKILL.md). Do not run Learn per item: items
that share a domain would race on the same expertise file.

1. Skip when no `.claude/experts/*/expertise.yaml` exists, or when every item failed.
2. Changed files = the union over all integrated items: `git diff --name-only <base>...orchestrate/<run-id>` plus
   uncommitted changes, excluding `.tac/`.
3. Select domains whose `core_files[].path` equals a changed path or is a directory prefix (ends in `/`) of one;
   at most 5, list the rest as skipped.
4. Delegate one `tac-final:expertise-curator` agent per selected domain, in parallel, in `improve` mode (as
   `/tac-final:expert improve <domain>` does), on the integration branch. Each edits only its own
   `.claude/experts/<domain>/` and does not commit.
5. Record `learn` in `state.json` as `passed`, `skipped`, or `failed` with reasons. A failed refresh never changes
   the orchestration result.

Leave the expertise edits uncommitted on `orchestrate/<run-id>`: `/tac-final:ship` puts them in the same PR as the
code, so the human who approves the change also approves what the experts learned.

## 7. Lessons

For every escalated or failed item, and for a `failed` or `partial` orchestration, append one input line to the
committed ledger `.tac/lessons.md` (create it with a `# Lessons` heading if missing), in the `adw` format:

```markdown
- 2026-10-23 run a1b2c3d4 | workflow orchestrate item 3 | escalated at review-2 | log `.tac/runs/a1b2c3d4/state.json` | spec `specs/feature-x.md`
```

Do not classify or fix here; `/tac-final:retro` turns these lines into leverage-point fixes.

## 8. Report

```markdown
## Orchestration <run-id>: <passed|partial|failed>
- Integration branch: orchestrate/<run-id>
| Item | Spec | Build | Review | Notes |
| --- | --- | --- | --- | --- |
- Agents used: <n scouts, n planners, n builders, n reviewers, n curators>
- Learn: <domains refreshed / skipped / failed, or "skipped: no experts">
- Escalations: <items needing a human, with why> (logged to `.tac/lessons.md`)
- Next: `/tac-final:ship` from the integration branch; clean up item worktrees with `git worktree list` / `git worktree remove`
```

For a fully governed zero-touch pipeline (readiness gates, kill switch, audit hooks), use an external
zero-touch tool (none is bundled with this plugin); tac-final's orchestrate keeps a human checkpoint at decomposition and at ship.
After repeated escalations, run `/tac-final:retro` to find the leverage point behind them.
