# Choosing Model and Tools

## Model

| Task shape | Model | Why |
| --- | --- | --- |
| Search, recon, classification, formatting checks | `haiku` | Fast and cheap; judgment needs are low |
| Implementation, test fixing, review against a spec | `sonnet` | Strong coding at moderate cost |
| Ambiguous planning, architecture, root-causing hard bugs | `opus` | Best reasoning; worth it where errors multiply |
| Should match whatever the user is running | `inherit` | Default when unsure |

Use aliases (`haiku`, `sonnet`, `opus`) rather than dated model IDs so agents track model upgrades. Measure: if
a cheaper model passes your validation commands as often, switch.

## Tools

| Agent type | Tools |
| --- | --- |
| Read-only analysis (scout, reviewer, auditor) | `Read, Grep, Glob` (+ `Bash` for git/log commands) |
| Test runner | `Read, Grep, Glob, Bash` |
| Builder / fixer | `Read, Grep, Glob, Edit, Write, Bash` |
| Docs writer | `Read, Grep, Glob, Write, Edit` |

Use `disallowedTools` to remove a tool from an otherwise inherited set (for example `disallowedTools: Write, Edit`).
MCP tools appear as `mcp__<server>__<tool>`; give an agent only the MCP servers it needs.

## Standard out and types are agent tools too

Agents act on what they can see. Make failures loud (clear error messages, non-zero exit codes, logs with
context) and contracts explicit (types, schemas). These raise every agent's success rate at once.
