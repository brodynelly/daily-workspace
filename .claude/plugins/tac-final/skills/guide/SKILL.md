---
name: guide
description: Orients you in Tactical Agentic Coding (TAC) and the tac-final plugin - explains the doctrine, inspects the current repo, and recommends the next tac skill to run. Use when starting with tac, asking "what can tac do", choosing between plan/adw/orchestrate, or needing a TAC concept explained (leverage points, ADWs, closed loops, ZTE, R&D context, agent experts, the learn step and retro).
argument-hint: "[question or goal]"
allowed-tools: Read, Glob, Grep, Bash(git status *), Bash(git ls-files *)
---

# TAC Guide

Tactical Agentic Coding (TAC) is a way of working where you stop hand-writing code and instead build an
**agentic layer** around your codebase: reusable prompts, plans, validation loops, and workflows that
let agents plan, build, test, review, and ship with less and less of your presence. This plugin is that
layer, packaged so it works in any git repository.

## What you can do

| Goal | Run | What happens |
| --- | --- | --- |
| Make this repo agent-ready | `/tac-final:setup` | Detects stack + validation commands, writes a small TAC section into `CLAUDE.md`/`AGENTS.md`, creates `specs/` |
| See where the repo stands | `/tac-final:assess` | Scores the 12 leverage points, agentic-layer grade, ZTE readiness; returns the top 3 next moves |
| Load context for a task | `/tac-final:prime [bug\|feature\|review\|chore]` | Minimal, task-shaped context instead of reading everything |
| Turn an idea into a plan | `/tac-final:plan <description>` | Classifies (feature/bug/chore/patch) and writes `specs/<type>-<slug>.md` |
| Build a plan | `/tac-final:implement specs/<plan>.md` | Executes the plan step by step and runs its validation commands |
| Prove it works | `/tac-final:test` | Runs the validation stack; on failure, fixes and re-runs (closed loop) |
| Prove it is what you asked for | `/tac-final:review specs/<plan>.md` | Compares the diff to the spec; blockers become a patch plan |
| Capture how it works | `/tac-final:document` | Writes concise feature docs future agents can read |
| Commit, branch, PR | `/tac-final:ship` | Conventional commit, push, PR (merges only when you ask) |
| Run the whole loop | `/tac-final:adw <workflow> <task>` | Plan -> build -> test -> review -> fix -> document -> learn, each step in a fresh subagent (`--no-learn` to skip learn) |
| Split big work across agents | `/tac-final:orchestrate <task>` | Scouts, decomposes, builds in parallel worktrees, reviews, merges results |
| Give a domain an agent that learns | `/tac-final:expert create\|ask\|improve <domain>` | `.claude/experts/<domain>/expertise.yaml`, pinned to a commit; improve diffs from it (Act -> Learn -> Reuse) |
| Learn from the harness itself | `/tac-final:retro` | Reads KPIs, failed runs, tech debt, events; appends `.tac/lessons.md`; proposes at most one fix plan in `specs/` (manual only) |
| Write or level up a prompt | `/tac-final:prompt create\|analyze\|upgrade` | Seven-levels framework for commands, skills, and prompts |
| Build a custom agent | `/tac-final:agent <purpose>` | Subagent or Agent SDK agent with the right model, tools, and system prompt |

Always on (no command needed): guardrail hooks that block catastrophic commands and ask before force pushes,
hard resets, and secret-file edits; an event log in `.tac/events.jsonl` once a repo uses tac; and an optional
`tac` output style (`/config` -> Output style, or `"outputStyle": "tac-final:tac"`) that ends answers with
Done / Evidence / Next.

Typical progression (each step only needs the previous ones):

```text
setup -> prime -> plan -> implement -> test -> review -> ship -> learn   (in-loop, you drive)
                      \_________________ adw _________________/           (out-loop, one command)
                            orchestrate (many adws in parallel)           (toward zero-touch)
retro periodically (after a failure streak, or weekly)                    (the harness improves itself)
```

The learn step refreshes experts whose `core_files` the change touched; its edits land in the same diff (in `adw`,
before the PR opens), so the human reviewing the PR also approves what the harness learned. Retro only proposes; you decide.

## Workflow

1. If `$ARGUMENTS` asks a concept question, answer it from the references below (load only the one you need) and stop.
2. Otherwise, inspect the repo quickly: does a TAC section exist in `CLAUDE.md` or `AGENTS.md`? Is there a `specs/` directory? Are there tests? Is this a git repo?
3. Recommend the next one or two skills from the table above, with the exact command to run. Rules of thumb:
   - No TAC section, or no known validation commands: start with `/tac-final:setup`.
   - Small, clear change: `/tac-final:plan` then `/tac-final:implement`, or `/tac-final:adw plan_build` for one command.
   - Anything you would want reviewed: `/tac-final:adw plan_build_review_fix`.
   - Several independent changes, or a large refactor: `/tac-final:orchestrate`.
   - Agents keep failing the same way: `/tac-final:assess`, then `/tac-final:retro` to record the lesson and plan one fix.
4. Keep the answer short (under ~15 lines): one sentence on what tac-final is, a grouped one-line-per-stage
   summary (start / loop / automate / learn) instead of the full table, what you found in the repo, and the single
   command to run next with why. Show the full table only if the user asks for every command.

## References (load on demand)

- [references/doctrine.md](references/doctrine.md): the eight tactics, Core Four, 12 leverage points, guiding question
- [references/workflows.md](references/workflows.md): SDLC-as-questions, ADWs, composable steps, PITER, In-Loop/Out-Loop/ZTE, KPIs
- [references/context-engineering.md](references/context-engineering.md): the R&D framework, priming vs memory files, fresh agents
- [references/agentic-layer.md](references/agentic-layer.md): minimum viable layer, the 3-class grading system, what to build when, the self-improvement loop
- [references/conventions.md](references/conventions.md): file layout and contracts every tac skill shares
- [references/prior-art.md](references/prior-art.md): how TAC maps to Anthropic guidance, Spec Kit, Kiro, AGENTS.md, and others

The original course notes are external and not bundled with this plugin; the references above are self-contained.
