# The Seven Levels of Agentic Prompts

From TAC lesson 10. Each level adds one capability to the one below it.

| Level | Name | Adds | Use when | Example in tac |
| --- | --- | --- | --- | --- |
| 1 | High-level prompt | A saved, reusable instruction | You repeat the same ad hoc prompt | - |
| 2 | Workflow prompt | Numbered sequential steps + report | The task has a fixed sequence | `prime`, `document` |
| 3 | Control flow | Conditions, loops, STOP rules | Steps depend on what is found | `test` (fix loop), `setup` |
| 4 | Delegation | Launches subagents with explicit inputs/outputs | Work is parallel or context-heavy | `orchestrate` |
| 5 | Higher-order | Takes another prompt or plan as input | Executing specs or prompt chains | `implement` |
| 6 | Template meta-prompt | Generates a prompt or plan from a template | Encoding a problem class | `plan` |
| 7 | Self-improving | Updates its own knowledge files from results | Long-lived domain expertise | `expert improve`, run by the `adw` learn step |

**80/20:** levels 2-4 cover most practical needs. Start low; level up only when a real limitation appears.

## Decision guide

1. Is it the same instruction every time? -> Level 1.
2. Does it have ordered steps? -> Level 2.
3. Do steps branch or repeat based on results? -> Level 3.
4. Would one agent's context overflow, or can parts run in parallel? -> Level 4.
5. Does it execute another prompt or plan? -> Level 5.
6. Does it produce prompts or plans in a fixed format? -> Level 6.
7. Should it get better from its own runs? -> Level 7: keep its knowledge in
   `.claude/experts/<domain>/expertise.yaml`, refresh it with `/tac-final:expert improve` (which diffs from the
   pinned `source_revision`), and let the `adw` learn step call it after passing runs. Changes land in the PR for
   a human to approve.

## Meta-agentics

Levels 6-7 are how the agentic layer grows itself: meta-prompts write prompts, meta-agents write agents
(`/tac-final:agent`), and self-improving experts maintain their own knowledge (`/tac-final:expert`, refreshed by the learn step).
`/tac-final:retro` closes the outer loop: it learns from the harness's own failures and proposes one fix at a time. A codebase with no meta
prompts grows its agentic layer only as fast as you type.
