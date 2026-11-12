---
name: prompt
description: Engineers reusable agentic prompts with TAC's seven-levels framework - creates new skills, commands, and workflow prompts at the right level, analyzes existing ones (level, sections, quality), and upgrades them to a higher level such as adding control flow, delegation, or self-improvement. Use when writing or improving a slash command, skill, plan template, meta-prompt, or any prompt that will be reused.
argument-hint: "[create|analyze|upgrade|levels] [level] [path or purpose]"
allowed-tools: Read, Glob, Grep
---

# Agentic Prompt Engineering

Arguments: `$ARGUMENTS` (first word is the subcommand). The prompt is the fundamental unit of engineering with
agents: write it once, version it, and improve it. Framework: [references/seven-levels.md](references/seven-levels.md).
Sections: [references/sections.md](references/sections.md).

## levels

Print the seven-levels table from the reference with one line of "use when" each, and the 80/20 note
(levels 2-4 cover most needs). Stop.

## create `[level]` `<purpose>`

1. Clarify the purpose until you can state the input, the steps, and the output. Ask if any is missing.
2. Choose the level: the lowest one that does the job (use the decision guide in the reference). If the user
   gave a level higher than needed, say so and proceed with theirs.
3. Choose the format for where it will live:
   - **Claude Code skill** (default): `.claude/skills/<name>/SKILL.md` with frontmatter (`name` = directory,
     lowercase-hyphens; third-person `description` saying what it does and when to use it; `argument-hint`;
     `disable-model-invocation: true` if it has side effects; `allowed-tools` only for safe tools). Keep the body
     under 500 lines; move long material to `references/`, templates to `assets/`, deterministic logic to `scripts/`.
   - Another agent's format (AGENTS.md section, Cursor rule, plain prompt file) if the user asks.
4. Compose it from sections in the reference: Purpose, Variables (`$ARGUMENTS`), Instructions, Workflow
   (numbered, the most important section), Report. Add Control Flow, Delegation, Plan Format, or Expertise
   sections only at the levels that need them.
5. Show the prompt, and write it to the target path once the user agrees.

## analyze `<path>`

Read the prompt and report: current level (with evidence), sections present and missing, frontmatter issues
(name rules, description quality, risky `allowed-tools`, missing `disable-model-invocation` on side effects),
ambiguity, unbounded loops, missing output format, and the top 3 improvements. Do not edit the file.

## upgrade `<path>` `<target level>`

1. Analyze it first. If the target is not higher than the current level, say so and stop.
2. Add only what the target level needs (for example level 3: conditions and STOP rules; level 4: delegation
   to subagents with explicit inputs and outputs; level 5: accept a prompt or plan file as input; level 6: a
   template the prompt fills; level 7: a step that updates an expertise or memory file from results).
3. Preserve existing behavior and wording that works. Show a diff-style summary, then edit on approval.

## Principles

- Three repetitions mark a pattern: save the prompt, then level it up.
- Write for the stakeholder trifecta: you, your team, and your agents. Clear sections serve all three.
- Specific beats clever: name files, commands, formats, and limits. Every loop needs a bound.
- A prompt that cannot be re-run unchanged (because it depends on chat history) is not reusable yet.
