---
name: expert
description: Creates and runs agent experts - per-domain expertise files (verified mental models) that agents read before working and refresh after, following Act-Learn-Reuse. Subcommands create (seed from the codebase), ask (answer from the model, verified), improve (diff from the pinned revision and fix drift), run (plan, build, then improve), list, and eval (score the model against its question set). Use when a high-value or high-churn domain (billing, auth, the data model, a public API) keeps being re-explored, when asked to create, refresh, or check an expert, or when a workflow's Learn step refreshes touched domains.
argument-hint: "[create|ask|improve|run|list|eval] [domain] [question or task]"
allowed-tools: Read, Glob, Grep, Bash(git log *), Bash(git diff *), Bash(git rev-parse *), Bash(git ls-files *)
---

# Agent Experts

Arguments: `$ARGUMENTS` (first word is the subcommand, second is the domain in kebab-case).

An expert is a compact **mental model** of one domain. It is a map to verify, never truth: current code, tests,
and accepted decisions are authoritative, and every `improve` re-validates the model against them. Agents that
read it first skip most exploration. Let `improve` keep the file honest; do not hand-edit it as the main workflow.

## The store (one contract for every reader and writer)

| File | Required | Holds |
| --- | --- | --- |
| `.claude/experts/<domain>/expertise.yaml` | Yes | The model, pinned by `source_revision` (commit SHA) and `last_validated` (date) |
| `.claude/experts/<domain>/evals.yaml` | No | 5-10 verifiable question/answer pairs scored by `eval` |

Agents always read these files. Templates: [assets/expertise-template.yaml](assets/expertise-template.yaml) and
[assets/expert-evals-template.yaml](assets/expert-evals-template.yaml). Schema, limits, and the validation
checklist: [references/expertise-format.md](references/expertise-format.md).

Every reader (`tac-final:planner`, `tac-final:scout`, `/tac-final:prime`, `/tac-final:plan`) uses this sentence:

> If `.claude/experts/<domain>/expertise.yaml` covers the area, read it first as a map to verify, not as truth:
> confirm every path and claim you rely on against the code, and report drift for `/tac-final:expert improve <domain>`.

Every write goes through the `tac-final:expertise-curator` agent.

## create `<domain>` `[focus areas]` (ACT)

1. If `.claude/experts/<domain>/expertise.yaml` exists with real content, stop and suggest `improve`.
2. Delegate to `tac-final:expertise-curator` in `seed` mode: "Seed `.claude/experts/<domain>/expertise.yaml`
   (focus: <areas>) from the codebase using `${CLAUDE_SKILL_DIR}/assets/expertise-template.yaml`, and seed
   `evals.yaml` from `${CLAUDE_SKILL_DIR}/assets/expert-evals-template.yaml`. Every path and symbol must exist.
   Set `source_revision` to `git rev-parse HEAD`."
3. Report coverage (sections filled, `<lines>/<line_limit>`), the eval score, and suggest committing both files.

## ask `<domain>` `<question>` (REUSE)

1. Read the expertise file (missing -> suggest `create`).
2. Answer from the model. Verify every claim the answer depends on with cheap, targeted reads of the referenced
   files. If the model was wrong, say so and suggest `improve`.
3. Cite source paths and the expertise file used.

For high-stakes questions, scale compute: ask up to 3 `tac-final:expertise-curator` agents in `answer` mode in
parallel (read-only) and reconcile their answers.

## improve `<domain>` (LEARN)

Delegate to `tac-final:expertise-curator` in `improve` mode: "Improve `.claude/experts/<domain>/expertise.yaml`:
diff from its `source_revision`, validate every path, symbol, and claim, fix drift, add what is missing, remove
what is stale, enforce `line_limit`, set `source_revision` and `last_validated`, then run its evals."

Report the curator's output: added / corrected / removed, the new `source_revision`, and the eval score.
The edits are a working-tree diff for a human to review; `improve` never commits.

## run `<domain>` `<task>` (ACT -> LEARN)

1. Read the expertise file (REUSE), then write a plan with `/tac-final:plan`, giving it the relevant sections.
2. Build with the `tac-final:builder` agent (spec path) and validate with `/tac-final:test`.
3. On a passing build, run `improve` for the domain so the model learns from the change (LEARN).

## list

Glob `.claude/experts/*/expertise.yaml` and print a table: domain, `<lines>/<line_limit>`, `last_validated`,
short `source_revision`, commits since it (`git log --oneline <source_revision>..HEAD | wc -l`), last eval score.
Flag a domain as stale when its pinned revision is unknown to git or more than 50 commits behind.

## eval `<domain>` (verify the model)

Read-only except for recording the score. Delegate to `tac-final:expertise-curator` in `eval` mode, which:

1. Read `evals.yaml` (missing -> suggest seeding it from the template; stop).
2. For each item (at most 10): answer `question` from `expertise.yaml` alone, then compare with `answer`.
   Run the item's `check` against its `evidence` path to confirm the expected answer is still true in the code.
3. Score each item: `pass` (model answer matches and check passes), `fail` (model answer wrong or missing),
   `stale` (check fails: the eval itself is out of date and needs a human).
4. Report `score: <pass>/<total>` with each failure. The curator records it as `last_eval` in `expertise.yaml`.

A score under 80% means run `improve`; a `stale` item means fix the eval, not the model.

## Learn hook (used by `/tac-final:adw` and `/tac-final:orchestrate`)

After a run passes its tests and review, the workflow refreshes the experts it touched. Contract:

1. **Input**: the run's changed paths, `git diff --name-only <base>...HEAD` plus uncommitted changes.
2. **Select**: a domain is touched when any changed path equals a `core_files[].path` in its `expertise.yaml`,
   or starts with one that ends in `/`. Reference selector (POSIX shell, no YAML library):

   ```bash
   for f in .claude/experts/*/expertise.yaml; do
     [ -f "$f" ] || continue
     d=$(basename "$(dirname "$f")")
     sed -nE 's/^[[:space:]]*-[[:space:]]*path:[[:space:]]*"?([^"#]*[^"#[:space:]])"?.*$/\1/p' "$f" |
       while IFS= read -r p; do
         printf '%s\n' "$CHANGED" | grep -qxF "$p" && { echo "$d"; break; }
         case "$p" in */) printf '%s\n' "$CHANGED" | awk -v p="$p" 'index($0,p)==1{f=1}END{exit !f}' &&
           { echo "$d"; break; } ;; esac
       done
   done | sort -u
   ```

3. **Improve**: run `improve` on each selected domain, at most 5 per run (list the rest as skipped).
4. **Best-effort**: a failed or skipped refresh is recorded in the run log as `learn: <domain> <ok|failed|skipped>
   <reason>` and never fails the run.
5. **Human gate**: the expertise edits land in the same branch, diff, and PR as the code, so the reviewer of the
   code also reviews what the expert learned. Nothing is committed separately.
6. **Opt out**: `--no-learn` skips the hook.

## Optional adapter: Luuna Atlas

When a project declares Atlas, the curator also syncs the expertise through Atlas's supported CLI after writing
the file. Agents still read the file; Atlas is never the only copy. Contract and declaration:
[references/luuna-suite-ownership.md](references/luuna-suite-ownership.md).

## Alternative: subagent memory

Claude Code subagents support a `memory` field (`project` scope stores notes in `.claude/agent-memory/<agent>/`).
That is lighter weight and self-managed. Prefer tac experts for a structured, validated, reviewable model of a
domain; prefer `memory` for an agent's free-form learnings.
