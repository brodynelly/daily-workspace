# Prior Art: Who Else Solves This Problem

TAC is one answer to a shared question: *how do you make coding agents reliable enough to hand them whole
classes of work?* These sources reach compatible conclusions. Use them to sanity-check or extend TAC ideas.
Sources were reviewed in October 2026; follow the links for the current wording.

## Contents

- Anthropic engineering guidance
- Claude Code documentation
- Spec-driven development (Spec Kit, Kiro)
- Open conventions (AGENTS.md)
- Practitioner frameworks (12-factor agents, research-plan-implement, Ralph loop)
- Where TAC differs

## Anthropic engineering guidance

| Source | Key ideas | TAC equivalent |
| --- | --- | --- |
| [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents) | Workflows (predefined code paths) vs agents; prompt chaining with gates, routing, parallelization, orchestrator-workers, evaluator-optimizer; start simple | ADWs, composable steps, `orchestrate`, closed loops |
| [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) | Smallest set of high-signal tokens; just-in-time retrieval; compaction; structured notes; subagents return short summaries | R&D framework, priming, files as memory |
| [Writing effective tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents) | Fewer, consolidated tools; meaningful outputs; actionable errors; evaluate tools with real tasks | Tools and standard-out leverage points |
| [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) | Initializer agent writes a feature list and progress file; one feature per session; git as state; end-to-end tests before "done" | Plans as artifacts, run state, out-loop ADWs |
| [Building agents with the Claude Agent SDK](https://claude.com/blog/building-agents-with-the-claude-agent-sdk) | Loop: gather context, act, verify, repeat; rules-based checks beat LLM-as-judge | Closed loops; tests before review |

## Claude Code documentation

| Source | Key ideas | Where tac uses it |
| --- | --- | --- |
| [Best practices](https://code.claude.com/docs/en/best-practices) | Give Claude a way to verify its work; explore, plan, code, commit; short CLAUDE.md; clear context between tasks | `setup`, `plan`, `test` |
| [Skills](https://code.claude.com/docs/en/skills) | SKILL.md under 500 lines, supporting files loaded on demand, `disable-model-invocation` for side effects, `context: fork` | Structure of every tac skill |
| [Subagents](https://code.claude.com/docs/en/sub-agents) | Focused agents with restricted tools and model; `isolation: worktree`; `memory` | `agents/`, `orchestrate`, `expert` |
| [Headless mode](https://code.claude.com/docs/en/headless) | `claude -p` with `--output-format json`, `--allowedTools`, `--max-turns` for scripts and CI | `adw/scripts/adw.sh` |
| [Common workflows: worktrees](https://code.claude.com/docs/en/common-workflows) | `claude --worktree <name>` for parallel sessions | `orchestrate` |
| [GitHub Actions](https://code.claude.com/docs/en/github-actions) | Issues, PR comments, and cron trigger Claude in CI | PITER trigger + environment |

## Spec-driven development

- [GitHub Spec Kit](https://github.com/github/spec-kit): a constitution plus specify, plan, tasks, and implement
  commands; review each artifact before continuing. Maps to the TAC section (constitution) and `plan` ->
  `implement`. If a repo already uses Spec Kit, point `Specs:` at its directory and use tac for test, review, and ship.
- [Kiro specs](https://kiro.dev/docs/specs/): `requirements.md` (EARS format: "WHEN <event> THE SYSTEM SHALL
  <behavior>"), `design.md`, `tasks.md`; tasks run in dependency waves. tac's feature template accepts EARS-style
  acceptance criteria, and `orchestrate` runs independent work items in waves.

## Open conventions

- [AGENTS.md](https://agents.md/): a README for agents (setup, test, style, PR rules), read by many coding agents.
  `/tac-final:setup` writes the TAC section into `AGENTS.md` when that is the repo's memory file, so the layer is
  usable from other tools too.

## Practitioner frameworks

- [12-factor agents (HumanLayer)](https://github.com/humanlayer/12-factor-agents): own your prompts, own your
  context window, own your control flow, small focused agents, trigger from anywhere. This is the ADW philosophy:
  the loop is code you control.
- [Advanced context engineering for coding agents (HumanLayer)](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents):
  research -> plan -> implement with deliberate compaction; review research and plans rather than code, because
  errors there multiply. Matches TAC's "review the plan harder than the code".
- [Ralph loop (Geoffrey Huntley)](https://ghuntley.com/ralph/): one prompt in a bash `while` loop, one item per
  iteration, tests as back-pressure. The simplest possible out-loop ADW.

## Where TAC differs

- **Problem-class templates** are first-class: the same feature/bug/chore/patch formats every time.
- **Agent experts** keep a curated, validated mental model per domain (Claude Code's subagent `memory` field
  is a lighter alternative; see the `expert` skill).
- **A gated self-improvement loop**: the learn step updates expertise inside the same reviewed PR, and
  `/tac-final:retro` writes lessons and proposes one fix plan; nothing rewrites the harness without a human.
- **Explicit maturity model** (In-Loop -> Out-Loop -> Zero-Touch, plus KPIs) tells you when to remove a human gate.
