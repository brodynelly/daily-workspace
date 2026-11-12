# The Agentic Layer

Condensed from TAC lessons 8 and 14.

The agentic layer is a ring around your codebase: the prompts, plans, agents, and workflows that operate the
application layer on your behalf. It is part of the repo, versioned and improved like any other code.

## Minimum viable agentic layer

You need only three things to start:

1. **Prompts** - reusable, versioned instructions (this plugin's skills, plus project skills in `.claude/skills/`)
2. **Plans** - a `specs/` directory where every non-trivial change starts as a file
3. **A workflow entry point** - one command that chains agent steps (`/tac-final:adw`, or `scripts/adw.sh` headless)

Plus one enabler the agent cannot invent: **known validation commands** (test, lint, typecheck, build) written
down where every agent will read them. `/tac-final:setup` creates exactly this and nothing more.

## Grading the layer (3 classes)

| Class | Grade | Component | You have it when |
| --- | --- | --- | --- |
| 1 Foundation | 1 | Memory files + prime prompts | Short CLAUDE.md/AGENTS.md with real commands; a priming command |
| | 2 | Subagents, plans, AI docs | Plans live in `specs/`; subagents do recon |
| | 3 | Skills, MCP, custom tools | Repeated tool patterns are packaged |
| | 4 | Closed-loop prompts | Build steps run tests and fix failures themselves |
| | 5 | Problem-class templates | Feature/bug/chore/patch plans share formats |
| | 6 | Prompt chains / workflows | One command chains plan -> build -> test -> review |
| | 7 | Agent experts | High-value domains have expertise files pinned to a commit, refreshed by the learn step |
| 2 Out-loop | 1 | Triggers and webhooks | Issues, cron, or `@claude` start work without you at the keyboard |
| | 2 | Headless ADWs | Deterministic scripts run the workflow and open PRs |
| 3 Orchestration | 1 | Orchestrator agent | One agent decomposes and dispatches work to others |
| | 2 | Orchestrated workflows | Parallel agents in isolated environments, results merged |
| | 3 | Autonomous pipelines | Orchestrated ADWs ship with prompt-only presence |

Build up the grades in order. Each grade multiplies the value of the ones below it; skipping (for example,
orchestration without closed loops) multiplies failure instead.

## What to build when

| Build | When |
| --- | --- |
| Memory file + validation commands | Day one, any repo |
| Plans in `specs/` | Any change you cannot describe as a one-sentence diff |
| Closed loops | As soon as there is a test command |
| Templates | When you have written the same kind of plan three times |
| Subagents | When reading or output would flood the main context |
| Agent experts | High-value, high-churn domains (billing, auth, data model) |
| Learn step + retro | Once ADWs run regularly and `.tac/kpis.md` has rows to learn from |
| Headless ADWs / triggers | After the in-session workflow succeeds repeatedly |
| Orchestration | Work that splits into independent pieces |

## Meta-agentics

Build the system that builds the system: prompts that write prompts (`/tac-final:prompt create`), agents that write
agents (`/tac-final:agent`), experts that update their own expertise (`/tac-final:expert improve`). Every mature layer has
these, because they make the layer cheaper to grow.

## The self-improvement loop

The layer keeps itself accurate with Act -> Learn -> Reuse, and a human gate on every change it makes to itself.

| Stage | What happens | Where it lands | Human gate |
| --- | --- | --- | --- |
| Act | An ADW or skill does the work | Code diff, `.tac/runs/`, `.tac/kpis.md`, `.tac/events.jsonl` | Plan and PR review |
| Learn | After a passing run, refresh experts whose `core_files` intersect the changed files; best-effort, never fails the run (`--no-learn` to skip) | `.claude/experts/<domain>/expertise.yaml`, new `source_revision` | Same PR as the code |
| Retro | `/tac-final:retro` (manual) reads KPIs, escalated runs, review `tech_debt`, and events | Dated entry in `.tac/lessons.md`; at most one fix plan in `specs/` | You run the plan, or not |
| Reuse | Every agent reads the expertise file and lessons before acting | Next run's context | - |

Retro never edits skills, experts, or code directly. Fixes go through the normal plan -> build -> review path,
so the harness changes itself only in reviewable diffs.
