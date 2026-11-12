# Prompt Sections

Composable sections, like building blocks. Pick the ones the level needs, in this order.

| Section | Tier | Purpose | Needed from |
| --- | --- | --- | --- |
| Frontmatter | - | Discovery and execution settings (skills: `name`, `description`, `argument-hint`, `allowed-tools`, `disable-model-invocation`, `context`, `model`) | Any saved skill |
| Title | - | `# Action-oriented name` | Level 1 |
| Purpose | B | 1-2 sentences: what the prompt achieves | Level 1 |
| Variables | A | Inputs: `$ARGUMENTS` (or `$0`, `$1`... 0-based), defaults, static values | Level 2 |
| Instructions | B | Rules, constraints, edge cases, what not to do | When rules exist |
| Relevant Files | C | Files and docs to read first | Project-specific prompts |
| Workflow | **S** | Numbered steps the agent executes in order | Level 2 |
| Control Flow | A | `If ... then ...`, loops with a maximum, `STOP and ask` conditions | Level 3 |
| Delegation | A | Which subagent, with what input, returning what output; parallel or sequential | Level 4 |
| Input Prompt | B | The plan or prompt being executed (`$ARGUMENTS` as a path) | Level 5 |
| Template / Plan Format | A | The exact format to produce | Level 6 |
| Expertise | B | Knowledge file to read first and update after | Level 7 |
| Examples | A | One or two concrete input/output pairs | Ambiguous tasks |
| Report | C | Exact output format (markdown block, JSON, or a parseable last line) | Whenever output is consumed |

## Writing rules

- The Workflow section carries the prompt. Each step is one action with a checkable result.
- Variables are referenced by name in the workflow; never make the agent guess an input.
- Put machine-consumed output in a fixed shape (JSON, or a last line like `SPEC: <path>`) so scripts can chain it.
- Every loop has a maximum and an escalation path.
- Prefer one good example over a list of rules when format matters.
