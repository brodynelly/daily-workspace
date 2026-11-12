# TAC Doctrine

Condensed from the Tactical Agentic Coding course (lessons 1-8). The full course notes are external and not bundled here.

## Contents

- The eight tactics
- The Core Four
- The 12 leverage points
- The guiding question
- Problem classes, not problems

## The eight tactics

| # | Tactic | In one line | tac skill that embodies it |
| --- | --- | --- | --- |
| 1 | Stop coding | Your job moves to planning, reviewing, and building closed-loop structures; agents write the code | all of them |
| 2 | Adopt your agent's perspective | Every session starts blind; give it the context, tools, and commands you would use | `prime`, `setup` |
| 3 | Template your engineering | Encode how you solve a class of problem (feature, bug, chore) into a reusable plan template | `plan` |
| 4 | Stay out the loop | Prompt in, PR out: trigger workflows that run without you (PITER) | `adw` |
| 5 | Always add feedback loops | Work is useless unless tested; let agents act, validate, and correct until green | `test`, `review` |
| 6 | One agent, one prompt, one purpose | Specialized agents with focused context beat one agent doing everything | `adw`, `agents/` |
| 7 | Target zero-touch engineering | Make the system reliable enough that your review becomes the bottleneck, then remove it | `adw`, `orchestrate`, `assess` |
| 8 | Prioritize agentics | Spend 50%+ of engineering time on the agentic layer, not the application | `setup`, `assess` |

Tactics 1-3 are the 80/20: stop coding, give the agent your perspective, and template your work.

## The Core Four

Every agent run is the product of four in-agent levers. Change any one and you change the outcome.

| Lever | Question | Common mistake |
| --- | --- | --- |
| Context | Can the agent see everything it needs - and nothing it does not? | Bloated always-on memory, unused MCP servers |
| Model | Is the model matched to the difficulty? | A large model for trivial recon, a small one for architecture |
| Prompt | Is the instruction specific, structured, and reusable? | Ad hoc prompts that cannot be improved because they are not saved |
| Tools | Does the agent have exactly the tools the job needs? | Every tool enabled "just in case"; no way to run tests |

## The 12 leverage points

In-agent (the Core Four): **1 Context, 2 Model, 3 Prompt, 4 Tools.**

Through-agent (things in the codebase the agent can use):

| # | Lever | High-leverage state | Check |
| --- | --- | --- | --- |
| 5 | Standard out | Errors, logs, and command output are visible and readable | Do failures print what went wrong? |
| 6 | Types | Explicit types and schemas communicate contracts | Are interfaces typed or schema-validated? |
| 7 | Documentation | Agent-oriented docs: how to run, test, and where things live | Is there a short CLAUDE.md/AGENTS.md with real commands? |
| 8 | Tests | Fast, reliable tests the agent can run and trust | One command runs the suite? |
| 9 | Architecture | Consistent, navigable structure; small files with clear names | Can an agent find "where X happens" with grep? |
| 10 | Plans | Specs written before code, saved as files | Is there a `specs/` habit? |
| 11 | Templates | Reusable plan formats per problem class | Do feature/bug/chore plans share a format? |
| 12 | ADWs | Deterministic code that chains agent steps | Can one command go from issue to PR? |

Tests are usually the single highest leverage point: the value of every test is multiplied by the number of agent runs that execute it.

## The guiding question

> Am I investing enough in my agentic layer that agents can solve this class of problem without me?

When an agent fails, do not just fix the code. Ask which leverage point was missing (context? a test? a template?) and fix *that*, so the whole class of failure goes away. `/tac-final:retro` asks this question across many runs and records the answer in `.tac/lessons.md`.

## Problem classes, not problems

Solve classes of work once. A good template turns one sentence ("add CSV export") into a complete plan with
files, steps, and validation commands. Three repetitions of the same manual prompt mark a pattern: save it,
then move it up the prompt levels (see the `prompt` skill).

## Phase-two engineering

- Plans are scaled prompts; great planning is great prompting.
- Meta-prompts build prompts (a plan template fills itself out into a plan).
- Higher-order prompts take prompts as input (`implement` takes a plan).
- Review the plan harder than the code: one bad line of plan becomes hundreds of bad lines of code.
