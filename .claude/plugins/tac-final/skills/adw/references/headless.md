# Headless ADWs (Out-Loop)

`scripts/adw.sh` is a deterministic ADW: bash owns step order, retries, run state, and git; every step is a
fresh `claude -p` agent that uses one tac-final skill. Run `bash adw.sh --help` for all options. The script is
bash 3.2 compatible, so it runs on the macOS system shell.

## Contents

- Quick start
- How a run works
- Learn step
- Replan
- Lessons
- Permissions
- Triggers (PITER)
- Safety checklist

## Quick start

```bash
ADW="$(find ~/.claude/plugins -path '*tac-final/skills/adw/scripts/adw.sh' | head -1)"   # installed plugin copy
bash "$ADW" --dry-run "Add CSV export to the reports page"         # print the steps, change nothing
bash "$ADW" -w plan_build_review_fix --worktree "Add CSV export"   # isolated run, no commit
bash "$ADW" -w sdlc --worktree --pr --issue 123                    # issue in, PR out
bash "$ADW" --worktree --base origin/main --no-learn "Bump deps"   # branch from origin/main, skip Learn
```

Inside a Claude Code session the path is available as `${CLAUDE_SKILL_DIR}/scripts/adw.sh` (the `adw` skill prints it).

## How a run works

```text
plan  -> "SPEC: <path>"              (tac-final:plan)
build -> "BUILD: DONE|REPLAN|FAILED" (tac-final:implement; REPLAN -> plan again once; anything else but DONE fails)
test  -> "TESTS: PASS|FAIL"          (tac-final:test, with its own fix loop)
review-> "REVIEW: PASS|FAIL"         (tac-final:review --patch) --FAIL--> fix (tac-final:implement patch) -> test -> review
document                             (tac-final:document, sdlc only)
learn -> "LEARN: UPDATED|NONE|FAILED" (tac-final:expert improve; best-effort, never fails the run)
--pr  -> commit (code + expertise edits), push, gh pr create
```

- Steps communicate only through files and the marker lines above, so each agent starts with a clean context.
- Logs: `.tac/runs/<run-id>/<step>-<attempt>.log`; state: `.tac/runs/<run-id>/state.json`; KPIs: `.tac/kpis.md`;
  failed and escalated runs: `.tac/lessons.md`.
- Exit code 0 means passed; 1 means failed or escalated (read the logs, fix the plan or the leverage point,
  re-run with `--spec <path>` to skip planning).
- `--worktree` creates `.claude/worktrees/adw-<run-id>` on branch `adw/<run-id>`, branched from the commit you are
  on (`HEAD`), so it builds exactly what you just looked at. Pass `--base <ref>` (for example `origin/main`) to
  branch from somewhere else; uncommitted changes in your checkout are never copied in. Worktrees from headless runs
  are not removed automatically: `git worktree remove <path>` when done. Untracked files such as `.env` are not
  copied into the worktree; provide them if your tests need them.

## Learn step

After the last verifying step passes (and after `document` in `sdlc`), and before `--pr`, the script refreshes the
agent experts the run touched, following the Learn hook contract in [../../expert/SKILL.md](../../expert/SKILL.md):

| Condition | Result recorded in `state.json` |
| --- | --- |
| `--no-learn` | `learn: skipped` |
| No `.claude/experts/*/expertise.yaml` | `learn: skipped` |
| No expert's `core_files` path matches a changed file (`git diff --name-only HEAD` + untracked, minus `.tac/`) | `learn: skipped` |
| Up to 5 matching domains: one `claude -p` step runs `tac-final:expert` `improve` on them | `learn: passed` |
| That step exits non-zero, prints `LEARN: FAILED`, or prints no verdict | `learn: failed`; the run still passes |

Matching is exact path, or prefix when the `core_files` path ends in `/`. The step may edit only
`.claude/experts/`, never commits, and with `--pr` its edits are committed with the code, so the PR reviewer
approves what the expert learned together with the change. `--dry-run` prints the learn invocation with
placeholder file and domain lists.

## Replan

When the build step ends with `BUILD: REPLAN - <reason>`, the script runs the plan step once more (attempt 2),
asking `tac-final:plan` to revise the same spec with that reason, then builds again. The replan counts as an
attempt in `.tac/kpis.md`. A second `REPLAN` fails the run: two wrong plans mean the task or the codebase needs a
human (or `/tac-final:retro` should find the missing leverage point).

## Lessons

Every `failed` or `escalated` run appends one line to `.tac/lessons.md` in the main checkout (created with a header
if missing):

```markdown
- 2026-10-23 run a1b2c3d4 | workflow sdlc | escalated at review-3 | log `.tac/runs/a1b2c3d4/review-3.log` | spec `specs/feature-x.md`
```

These lines are raw input. `/tac-final:retro` reads them with `.tac/kpis.md` and the run logs, classifies each
failure by leverage point, appends a dated retro entry, and proposes one fix plan for a human to approve. Commit
`.tac/lessons.md`; keep `.tac/runs/` and `.tac/events.jsonl` ignored. Retro needs the run logs, so do not delete
them before it runs (in CI, keep the uploaded `.tac/` artifact).

## Permissions

Headless steps cannot answer permission prompts. Grant exactly what the workflow needs through `TAC_CLAUDE_ARGS`
(default `--permission-mode acceptEdits`, which allows file edits but not arbitrary shell commands):

```bash
export TAC_CLAUDE_ARGS='--permission-mode acceptEdits --max-turns 60 --allowedTools "Bash(npm run *)" "Bash(npx tsc *)" "Bash(git diff *)" "Bash(git status *)"'
```

Alternatives: add the same rules to `permissions.allow` in the project's `.claude/settings.json`, or run inside a
disposable container or CI runner where broader permissions are acceptable. Prefer allowlists over skipping
permission checks entirely.

The plugin must be available to the headless `claude`. If it is not installed for the user running the script
(for example in CI), add `--plugin-dir <path-to-tac>` to `TAC_CLAUDE_ARGS`.

## Triggers (PITER)

| Element | Option |
| --- | --- |
| Prompt input | `--issue <n>` (GitHub issue), a task string, or `--spec <path>` |
| Trigger | You, `cron`, a webhook handler, or a CI workflow on `issues: [labeled]` |
| Environment | `--worktree` locally; a CI runner or container for unattended runs |
| Review | `--pr` opens a pull request; humans (or a review bot) approve |

A ready-to-copy GitHub Actions workflow is bundled at
[../assets/github-action-adw.yml](../assets/github-action-adw.yml). Label an issue `adw` and it runs three jobs
(plus a failure comment): **gate** continues only when the labeler has write, maintain, or admin access; **agent**
runs `adw.sh` with no GitHub token and an exact command allowlist, passing the issue text as the task, and exports
the diff (including any Learn edits under `.claude/experts/`); **ship** applies that diff, refuses changes to
`.github/`, and opens the PR. Only `state.json`, `.tac/kpis.md`, and `.tac/lessons.md` are uploaded. Copy it to
`.github/workflows/tac-adw.yml`, add an `ANTHROPIC_API_KEY` secret, set `PLUGIN_REF` to a 40-character commit SHA,
and adapt `ALLOWED_TOOLS` to your validation commands.

For interactive triggers (`@claude` in issue and PR comments), the official
[Claude Code GitHub Action](https://code.claude.com/docs/en/github-actions) is the simpler route; point its prompt
at the same tac skills.

## Safety checklist

- Start in-loop (`/tac-final:adw` in a session) and move a workflow headless only after it passes repeatedly.
- Always `--worktree` or a disposable environment for unattended runs.
- Keep `--pr` (human review) until KPIs justify more: see the zero-touch gates in
  [../../guide/references/workflows.md](../../guide/references/workflows.md#in-loop-out-loop-zero-touch).
- Bound every run: `--max-turns` in `TAC_CLAUDE_ARGS`, `--max-fix` for review rounds; replan is fixed at 1 and
  Learn at 5 domains.
- Keep the plugin guardrail hooks on (`TAC_GUARDRAILS` unset or `on`): they deny catastrophic commands and ask
  before force pushes, hard resets, and secret-file edits. In headless runs an "ask" cannot be answered, so the
  action is refused, which is the safe outcome.
- Never give headless agents production credentials; the script never merges or deploys.
- The harness never changes itself without a human: Learn edits ride in the PR, and retro only writes a plan.
