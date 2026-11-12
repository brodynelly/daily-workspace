# tac-final - Tactical Agentic Coding, the complete plugin

Turn any git repository into one that agents can plan, build, test, review, and ship on their own, with less
and less of your presence. Based on [Tactical Agentic Coding](https://agenticengineer.com/tactical-agentic-coding)
by @IndyDevDan and rebuilt on current Claude Code primitives: skills, subagents, hooks, an output style, evals,
and a headless/CI workflow.

```bash
/plugin install tac-final@bnelly-claude-software
```

This copy lives at `recipiebook/tac-final/` in the Library; the path inside a marketplace repo may differ (for
example `plugins/tac-final/`). Paths below are relative to the plugin root.

## The idea in 30 seconds

Stop hand-writing code. Build the **agentic layer** around your codebase instead: a few reusable prompts, plans
saved as files, validation commands agents can run, and workflows that chain it all. Every failure becomes a
question: *which leverage point was missing?* Fix that, and the whole class of failure goes away.

```text
  idea -> plan -> specs/x.md -> implement -> test -> review -> document -> learn -> PR   (you review the PR)
          \____________________________ adw (one command) ______________________/   (out-loop)
                         orchestrate (many in parallel, one learn after integration)   (toward zero-touch)

  learn:  experts whose core_files the diff touched refresh in the SAME PR    (Act -> Learn -> Reuse)
  retro:  .tac/kpis.md + failed runs + events -> .tac/lessons.md + ONE fix plan in specs/   (you approve)
```

The harness improves itself, but never silently: every change it makes to its own experts rides in a PR a human
reviews, and every change retro proposes to skills, agents, or code is a plan a human chooses to implement.

## Quick start (any repo, AI-initialized or not)

```text
/tac-final:setup                                   # detect stack + validation commands, write a short TAC section
/tac-final:assess                                  # where does this repo stand? top 3 next moves
/tac-final:adw plan_build_review_fix "Add CSV export to the reports page"
/tac-final:ship specs/feature-csv-export.md        # branch, commit, push, open a PR
```

`setup` works whether the repo has nothing, a `CLAUDE.md`, an `AGENTS.md`, or another tool's rules. It only adds
a `## Agentic layer (tac)` section (under 20 lines) and a `specs/` directory. Every other skill reads that section,
falls back to auto-detection, and asks before guessing. Not sure where to start? `/tac-final:guide`.

## What is in the box

| Component | What you get |
| --- | --- |
| 16 skills | The full workflow, from setup to orchestration, plus the learn loop and `retro` (below) |
| 7 subagents | Focused workers the skills delegate to (below) |
| Guardrail hooks | Always on, best-effort: deny catastrophic commands, ask before risky ones and secret-file edits, log redacted events |
| Output style `tac` | Optional: plan-first, evidence-based answers ending in Done / Evidence / Next |
| Headless ADW script | `skills/adw/scripts/adw.sh` runs the workflow with `claude -p` from a terminal, cron, or CI |
| GitHub Action template | `skills/adw/assets/github-action-adw.yml`: label an issue `adw`, get a PR (gated, token-less agent job, SHA-pinned) |
| Evals | `evals/`: trigger, non-trigger, and expert-quality checks for `claude plugin eval` |
| Doctrine | The course condensed into on-demand references in `skills/guide/references/` |

## Skills

All are invoked as `/tac-final:<name>`.

### Start

| Skill | What it does |
| --- | --- |
| `guide` | Explains TAC, inspects the repo, recommends the next skill. Holds the doctrine references |
| `setup` | Bootstraps the minimum viable agentic layer: TAC section, validation commands, `specs/` |
| `assess` | Scores the 12 leverage points, grades the layer, checks context health and ZTE readiness (read-only) |
| `prime` | Loads task-shaped context (`bug`, `feature`, `review`, `chore`, or an area) |

### The loop (one step each)

| Skill | Question it answers | Output |
| --- | --- | --- |
| `plan` | What are we building? | `specs/<feature\|bug\|chore\|patch>-<slug>.md` from a template |
| `implement` | Did we make it real? | Code changes + validation run |
| `test` | Does it work? | Closed loop: run, fix, re-run; JSON results |
| `review` | Is it what we asked for? | JSON verdict (blocker / tech_debt / skippable), optional patch plan |
| `document` | How does it work? | `docs/<slug>.md` |
| `ship` | Is it delivered? | Conventional commit, push, PR; merges only with `--merge` |

### Automate

| Skill | What it does |
| --- | --- |
| `adw` | Chains the loop with each step in a fresh subagent (`plan_build`, `plan_build_test`, `plan_build_review_fix`, `sdlc`), then the learn step (`--no-learn` to skip); one replan allowed; includes the headless script and the GitHub Action template |
| `orchestrate` | Scouts, decomposes into work items, builds each in its own worktree in parallel, integrates, reviews, then learns once over the whole diff |

### Grow the layer

| Skill | What it does |
| --- | --- |
| `expert` | Agent experts: `create`, `ask`, `improve`, `run`, `eval`, `list` a validated per-domain mental model pinned to a commit (`source_revision`); `eval` scores it against `evals.yaml` (Act -> Learn -> Reuse) |
| `retro` | Retrospective over run evidence: classifies failures to the 12 leverage points, appends to `.tac/lessons.md`, and proposes one fix plan for a human to approve (manual only) |
| `prompt` | Seven-levels prompt engineering: `create`, `analyze`, `upgrade` skills, commands, and templates |
| `agent` | Design subagents or Agent SDK agents: purpose, model, tools, system prompt, hook guardrails |

Skills with side effects (`setup`, `ship`, `adw`, `orchestrate`, `retro`) only run when you invoke them; Claude will not
start them on its own.

## Agents

Seven focused subagents (one agent, one prompt, one purpose), available as `@agent-tac-final:<name>`:

| Agent | Model | Tools | Job |
| --- | --- | --- | --- |
| `scout` | haiku | read-only | Fast reconnaissance; returns a compact map of an area |
| `planner` | opus | read + write specs | Writes plans and patch plans |
| `builder` | sonnet | full | Implements a plan and runs its validation |
| `tester` | sonnet | full | Runs the validation stack, fixes failures, returns JSON |
| `reviewer` | sonnet | read-only | Checks the diff against the spec, returns a verdict |
| `documenter` | haiku | read + write docs | Writes feature docs |
| `expertise-curator` | sonnet | read + write expertise | The only writer of expertise: seed, improve (diff from `source_revision`), answer, eval |

## Guardrail hooks

`hooks/hooks.json` is active whenever the plugin is enabled. The hooks are a **best-effort backstop, not a
sandbox**: they match command text, so they cannot see through variables, aliases, script files, or encodings,
and they fail open.

| Hook | Behavior |
| --- | --- |
| `PreToolUse` on `Bash` | **Denies** recursive force-deletes of `/`, `~`, `$HOME`, or top-level system directories in any flag form (`-rf`, `-r -f`, `--recursive --force`), including inside `bash -c`/`sh -c` payloads; `find <root> -delete` or `-exec rm`; `--no-preserve-root`; `mkfs`, raw disk writes, fork bombs, `chmod -R 777 /`. **Asks** before force pushes (`--force`, `-f`, `--mirror`, `+refspec`; not `--force-with-lease`), `git reset --hard`, `git clean -f`, `git checkout .`, `git branch -D`, destructive SQL, and `rm -rf` outside the project |
| `PreToolUse` on `Edit`/`Write` | **Asks** before editing `.env*` (not `.env.example`), keys, certificates, `.ssh/*` (not `.pub`), `.netrc`, `.aws/credentials`, `.kube/config`, `.docker/config.json`, `*.tfvars`, `.npmrc`, `.pypirc` |
| `PostToolUse`, `PostToolUseFailure`, `SubagentStop` | Appends a compact record to `.tac/events.jsonl` with likely secrets replaced by `[REDACTED]`, only in repos that already have a `.tac/` directory |

Known trade-off: a command that merely quotes catastrophic text (`git commit -m "never rm -rf /"`) is denied;
rephrase it. Opt out per shell or CI job with `TAC_GUARDRAILS=off` and `TAC_EVENT_LOG=off`. The hooks need
`python3`; without it they allow everything rather than block your work.

For hard limits, layer `permissions.deny` in `.claude/settings.json`, Claude Code's sandbox (or a container), and
an exact `permissions.allow` list for your validation commands, then keep these hooks as the last line. Example
and layering table: [skills/agent/references/governance.md](skills/agent/references/governance.md).

## Output style

Choose **tac** in `/config` -> Output style, or set `"outputStyle": "tac-final:tac"` in a settings file. It keeps
Claude Code's coding behavior and adds: plan before non-trivial changes, prove changes with the validation commands,
and end with a Done / Evidence / Next block.

## Files tac-final creates in your repo

| Path | Purpose | Commit? |
| --- | --- | --- |
| `## Agentic layer (tac)` in `CLAUDE.md` or `AGENTS.md` | Validation commands, specs/docs dirs, default branch | Yes |
| `specs/` | Plans | Yes |
| `docs/<slug>.md` | Feature docs | Yes |
| `.claude/experts/<domain>/expertise.yaml` | Agent-expert mental models, pinned by `source_revision` | Yes |
| `.claude/experts/<domain>/evals.yaml` | Optional expert eval questions for `/tac-final:expert eval` | Yes |
| `.tac/lessons.md` | Append-only ledger: failed/escalated run lines and dated retro entries | Yes |
| `.tac/runs/<id>/` | ADW run state and logs | No (gitignore) |
| `.tac/kpis.md` | One row per ADW run: attempts, size, result | Optional |
| `.tac/events.jsonl` | Hook event log | No (gitignore) |

Full contracts (JSON shapes, naming): [skills/guide/references/conventions.md](skills/guide/references/conventions.md).

## From In-Loop to Zero-Touch

| Level | How you work | Move on when |
| --- | --- | --- |
| In-Loop | `plan` -> `implement` -> `test` -> `review` -> `ship`, reviewing each step | Plans and tests are reliable |
| Out-Loop | `/tac-final:adw ...` or `adw.sh --worktree --pr`; you review the PR (code and expert edits) | 85%+ of runs pass without a retry (`.tac/kpis.md`) |
| Zero-Touch | The GitHub Action (or cron) triggers `adw.sh` with gates you trust | 90%+ over 20+ runs, review rarely finds issues |

For a governed zero-touch pipeline (readiness gates, kill switch, audit hooks), use an external tool; none is
bundled with this plugin. tac-final keeps a human at plan review and at merge by default. When runs keep failing,
`/tac-final:retro` turns the evidence into one fix plan instead of a guess.

## Doctrine (load on demand)

- [Doctrine](skills/guide/references/doctrine.md): eight tactics, Core Four, 12 leverage points, guiding question
- [Workflows](skills/guide/references/workflows.md): SDLC as questions, composable steps, ADWs, PITER, ZTE, KPIs
- [Context engineering](skills/guide/references/context-engineering.md): Reduce and Delegate
- [Agentic layer](skills/guide/references/agentic-layer.md): minimum viable layer, 3-class grading, what to build when
- [Prior art](skills/guide/references/prior-art.md): Anthropic guidance, Claude Code docs, Spec Kit, Kiro, AGENTS.md, 12-factor agents, Ralph

The original course notes are external and not bundled with this plugin.

## Evals

```bash
claude plugin eval recipiebook/tac-final         # 14 cases: 9 must trigger, 4 must not, 1 quality
```

See [evals/README.md](evals/README.md). Run them after editing any skill description.

## Requirements

- Git. `gh` CLI is optional (issues as input, PRs as output).
- `python3` for the guardrail and event-log hooks.
- A way to check work (tests, lint, build). `setup` finds it; if there is none, adding one is the first
  recommendation, because every closed loop depends on it.
- Headless runs need the `claude` CLI on the PATH (see [adw headless reference](skills/adw/references/headless.md)).

## Layout

```text
recipiebook/tac-final/      (marketplace path may differ)
  .claude-plugin/plugin.json, icon.png
  agents/            7 subagents
  skills/<name>/     16 skills: SKILL.md + references/ (docs), assets/ (templates), scripts/ (run, not read)
  hooks/             hooks.json + scripts/ (guard.sh, log-event.sh)
  output-styles/     tac.md
  evals/             trigger, non-trigger, and quality cases for `claude plugin eval`
```

## Relationship to `tac`

The original `tac` plugin (93 skills, 38 agents, course notes) is a separate project and is not bundled here.
tac-final is its consolidated successor; install one or the other, since both cover the same workflows. Coming
from tac:

| tac | tac-final |
| --- | --- |
| `feature`, `bug`, `chore`, `patch`, `classify-issue`, `plan-generation`, `patch-design`, `issue-classification`, `template-engineering` | `plan` |
| `test`, `resolve-failed-test`, `test-e2e`, `resolve-failed-e2e-test`, `e2e-test-design`, `closed-loop-design`, `test-suite-setup` | `test` |
| `review`, `review-workflow-design`, `validate-workflow` | `review` |
| `ship`, `commit-with-agent`, `generate-branch-name`, `pull-request` | `ship` |
| `start-adw`, `scout-and-build`, `adw-design`, `composable-step-design`, `composable-primitives`, `track-kpis`, `agentic-kpi-tracking`, `piter-setup`, `gateway-script-design` | `adw` |
| `orchestrate`, `deploy-team`, `install-worktree`, `git-worktree-setup`, `task-based-multiagent`, `orchestrator-design`, `orchestration-prompts`, `agent-lifecycle-management`, `multi-agent-observability`, `swimlane-visualization`, `broadcast-event`, `hook-event-architecture` | `orchestrate` |
| `prime`, `context-prime`, `load-context-bundle`, `context-status` | `prime` (use built-in `/context` for status) |
| `scaffold-layer`, `minimum-viable-agentic`, `conditional-docs-setup`, `standard-out-setup`, `context-hierarchy-design` | `setup` |
| `agentic-layer-audit`, `agentic-layer-assessment`, `leverage-point-audit`, `context-audit`, `reduce-delegate-framework`, `zte-progression` | `assess` |
| `create-expert`, `seed-expertise`, `query-expert`, `improve-expertise`, `agent-expert-creation`, `expertise-file-design`, `self-improve-prompt-design`, `product-expert-design` | `expert` |
| `create-prompt`, `analyze-prompt`, `upgrade-prompt`, `list-prompt-levels`, `prompt-level-selection`, `prompt-section-design`, `template-meta-prompt-creation`, `meta-agentic-creation` | `prompt` |
| `create-agent`, `create-tool`, `list-agent-tools`, `tools`, `custom-agent-design`, `system-prompt-engineering`, `tool-design`, `model-selection`, `agent-specialization`, `agent-governance`, `configure-hooks` | `agent` (plus the plugin's guardrail hooks) |
| `document` | `document` |
| `tac-orchestrate`, `zte-init`, `load-tac-context`, `library-sync` | not included (external zero-touch tooling) |
| `memory/` (57 files) | `skills/guide/references/` |

Agents: `plan-generator`, `sdlc-planner`, `patch-planner`, `issue-classifier` -> `planner`; `plan-implementer`,
`sdlc-implementer` -> `builder`; `test-runner`, `test-resolver`, `e2e-test-runner`, `e2e-test-resolver` ->
`tester`; `spec-reviewer`, `workflow-validator` -> `reviewer`; `documentation-generator` -> `documenter`;
`scout-fast` -> `scout`; `expertise-seeder`, `expertise-validator`, `self-improver`, `expert-question` ->
`expertise-curator`. Design and coordination agents became skills: `prompt-generator`, `prompt-analyzer`,
`workflow-designer` -> `prompt`; `agent-builder`, `tool-scaffolder`, `hook-designer` -> `agent`;
`layer-auditor`, `context-specialist`, `kpi-tracker` -> `assess`; `layer-scaffolder` -> `setup`;
`adw-orchestrator`, `workflow-coordinator`, `shipper` -> `adw` / `ship`; `orchestration-planner`,
`event-broadcaster`, `worktree-installer` -> `orchestrate`; `zte-orchestrator`, `zte-system-iterator`,
`issue-decomposer`, `team-dispatcher` -> not included (external zero-touch tooling).

Behavior differences from tac:

- Skill `name` fields are plain directory names; the `tac-final:` namespace is added by Claude Code.
- Arguments are read from `$ARGUMENTS` (tac's `$1` was actually the second argument; substitution is 0-based).
- `ship` opens a PR by default and never merges into the default branch unless you pass `--merge`.
- Expertise files live in `.claude/experts/<domain>/` instead of `.claude/commands/experts/<domain>/`.

## Version history

- **1.1.0** - Self-improving harness with a human gate on every self-change.
  - Learn step in `adw` and `orchestrate`: experts whose `core_files` the diff touched are refreshed by
    `expertise-curator` and ship in the same PR; best-effort, at most 5 domains, `--no-learn` to skip.
  - Experts: canonical store `.claude/experts/<domain>/expertise.yaml` pinned to `source_revision`; new
    `expert eval` with `evals.yaml`; Luuna Atlas is an optional adapter.
  - New manual `retro` skill and committed `.tac/lessons.md` ledger; failed/escalated runs append to it.
  - `adw.sh`: one replan, `--base`, `--no-learn`, input validation, every failure records its step; marker lines
    (`SPEC`/`BUILD`/`TESTS`/`REVIEW`/`PATCH`/`DOC`/`LEARN`) aligned across skills and agents.
  - Security: hardened `guard.sh` (split `rm` flags, `find -delete`, `+refspec` force push, `bash -c` payloads,
    more secret paths); `log-event.sh` redacts secrets and also logs `PostToolUseFailure`; `detect-project.sh`
    strips credentials from remote URLs; CI template splits gate/agent/ship jobs, gives the agent no GitHub token,
    and pins actions and the plugin to SHAs.
  - Evals: 14 cases (expert ask, assess, retro and adw non-trigger, expert answer quality).
  - Removed references to bundled `tac`, `zte`, and observability plugins (none are bundled).

- **1.0.0** - Initial release: 15 skills, 7 agents, guardrail and event-log hooks, `tac` output style, headless
  ADW script, GitHub Action template, trigger evals, doctrine references with a prior-art map.

## License

Educational. Course content (c) Agentic Engineer; see the
[course page](https://agenticengineer.com/tactical-agentic-coding).
