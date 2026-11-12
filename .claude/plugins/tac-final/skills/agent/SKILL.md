---
name: agent
description: Designs and scaffolds specialized agents following one agent, one prompt, one purpose - Claude Code subagents (.claude/agents/*.md with focused tools, model, and system prompt) or custom Claude Agent SDK agents with their own system prompt and custom tools - plus hook-based guardrails. Use when creating a subagent, splitting a do-everything agent into specialists, choosing an agent's model or tools, adding custom tools, or governing what agents may do.
argument-hint: "[purpose of the agent] [--sdk]"
allowed-tools: Read, Glob, Grep
---

# Agent Design

Purpose: `$ARGUMENTS`. Specialized agents with focused context beat general agents; the job here is to decide
the Core Four (context, model, prompt, tools) for one purpose, then write it down as a reusable file.

## 1. Decide whether you need an agent

| Need | Use |
| --- | --- |
| Reusable instructions that run in the main conversation | A skill (`/tac-final:prompt create`) |
| Heavy reading or verbose output that should not flood the main context; enforced tool limits; parallel work | A **Claude Code subagent** |
| A product or pipeline outside Claude Code, a fully custom system prompt, or custom in-process tools | A **Claude Agent SDK** agent (`--sdk`) |

If an existing agent (check `.claude/agents/` and `/agents`) already covers the purpose, improve it instead.

## 2. Specify the Core Four

- **Purpose**: one sentence, one job. If it needs "and", consider two agents.
- **Model**: `haiku` for fast recon, search, and checks; `sonnet` for most building and review; `opus` for hard
  planning or architecture. Default `inherit` when unsure. Details: [references/model-and-tools.md](references/model-and-tools.md).
- **Tools**: the minimum set. Read-only agents get `Read, Grep, Glob` (plus `Bash` only if they must run commands).
  Every unused tool is context overhead and risk.
- **Context**: what it must read first (files, expertise, a spec path in the delegation message). Subagents do
  not see the parent conversation; the delegation message must carry the inputs.

## 3. Write it

**Subagent** (default): create `.claude/agents/<name>.md` from [assets/subagent-template.md](assets/subagent-template.md).

- `description` decides when Claude delegates: say what it does and when; add "Use proactively" if it should be
  picked automatically.
- The body is the system prompt: role, inputs it expects, numbered process, constraints, and an exact output
  format the caller can consume (JSON or a fixed markdown block).
- Optional fields: `isolation: worktree` (parallel builders), `memory: project` (persistent learnings),
  `maxTurns` (bound the run), `skills` (preload skill content).

**SDK agent** (`--sdk`): follow [references/sdk-agents.md](references/sdk-agents.md) for the system prompt
choice (append to the Claude Code preset vs. full override), custom tools, and a runnable skeleton.

## 4. Guardrails

Prompts are requests; hooks are guarantees. For anything that must never happen (destructive commands, writes to
protected paths, secrets), add a hook: [references/governance.md](references/governance.md). Plugin-shipped agents
cannot carry their own hooks, so put guardrails in project or user settings.

## 5. Verify

Run the agent on one real task, read its full output, and tighten the prompt or tools. Test in isolation before
wiring it into `/tac-final:adw` or `/tac-final:orchestrate`. Report the file created and how to invoke it
(`@agent-<name>` or "use the <name> agent to ...").
