# Context Engineering: the R&D Framework

Condensed from TAC lessons 6, 9, and 13.

A focused agent is a performant agent. The context window is a limited, temporary resource, and every
token in it is something the agent has to reason around. There are only two moves:

## Reduce

Put less in the window.

- **Measure first.** Run `/context` to see what is consuming the window (system, tools, MCP, memory, history).
- **Trim always-on context.** CLAUDE.md/AGENTS.md should hold only what prevents mistakes: how to run,
  test, and lint, and the non-obvious conventions. Ask of each line: "would removing this cause a mistake?"
  Aim for well under 200 lines.
- **Disable unused MCP servers** for the task at hand; their tool definitions cost tokens every turn.
- **Prime instead of preloading.** Use a task-shaped priming prompt (`/tac-final:prime bug`) to load the few files a
  task needs, rather than growing a memory file forever.
- **Minimum context principle.** Give the agent the minimum context needed to solve the problem; every extra
  file is another variable to reason about.

## Delegate

Move work out of the main window.

- **Subagents for heavy reading.** Scouting, log analysis, and test runs happen in a subagent that returns a
  short summary (the `scout` and `tester` agents).
- **Fresh agent per step.** Plan, build, test, and review each start clean and communicate through files.
- **Files as memory.** Plans in `specs/`, run state in `.tac/runs/`, expertise in `.claude/experts/`, lessons in
  `.tac/lessons.md` - the next agent reads what it needs instead of inheriting a long conversation. Expertise is
  pinned to a `source_revision`, so a reader can tell how stale it is with `git diff <sha> -- <core_files>`.
- **Parallel agents** in isolated worktrees for independent work (`/tac-final:orchestrate`).

## Signs of context trouble

| Symptom | Likely cause | Move |
| --- | --- | --- |
| Agent ignores an instruction it followed earlier | Window is crowded; instruction is far back | `/clear`, re-prime, restate |
| Agent edits the wrong area | Too many loosely related files loaded | Reduce: prime for the task type |
| Two corrections in a row failed | Polluted context from failed attempts | Fresh session with a better prompt or plan |
| Slow, expensive runs on simple tasks | Big model + big context for small work | Delegate to a `haiku` subagent |

## Priming vs memory files

| | Memory file (CLAUDE.md) | Priming prompt (`/tac-final:prime`) |
| --- | --- | --- |
| Loaded | Every session, automatically | When you ask, per task type |
| Grows | Forever unless curated | Stays fixed; reads current files |
| Best for | Commands, conventions, guardrails | Task-specific files and recent history |

Use both: a short memory file with the commands, and priming for everything task-specific.
