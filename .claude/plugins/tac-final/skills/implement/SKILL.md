---
name: implement
description: Executes a plan file from specs/ step by step - reads the whole plan, makes the code changes, runs the plan's validation commands, fixes what they catch, and reports what changed. A higher-order prompt that takes a plan as input. Use after /tac-final:plan, or whenever asked to build, implement, or execute a spec.
argument-hint: "[path-to-plan.md]"
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git status *), Bash(git diff *)
---

# Implement

Execute the plan at `$ARGUMENTS`.

If no path was given, use the most recently modified file in the specs directory and say which one you chose.
If the argument is plan text rather than a path, execute it directly.

## Rules

- Read the entire plan before changing anything. Think hard about the approach.
- Follow Step by Step Tasks in order. Do not expand scope; if the plan is wrong or impossible, stop and say
  what needs re-planning instead of improvising a different design.
- Match the codebase's existing patterns. Write the tests the plan asks for.
- Do not commit. Committing belongs to `/tac-final:ship`, so a human or workflow can review first.

## Workflow

1. **Read** the plan and the files listed under Relevant Files.
2. **Execute** each task. Track progress with a todo list that mirrors the plan's numbered tasks.
3. **Validate**: run every command under Validation Commands (fall back to the TAC section if the plan has
   none). When one fails, fix the cause and re-run it. Stop after 3 failed attempts on the same command and report.
4. **Report.**

## Report

```markdown
## Implemented: <plan title>
- Plan: <path>
- Tasks: <done>/<total>
- Changes: <output of `git diff --stat`>
- Validation: <each command - pass/fail>
- Deviations from plan: <none, or what and why>
- Next: `/tac-final:review <plan>` then `/tac-final:ship`
```

End your response with exactly one verdict marker line, plain text at the start of the line (no backticks,
bullets, or code fence). `/tac-final:adw` takes the last line matching `^BUILD: *<value>`. One of:

```text
BUILD: DONE
BUILD: REPLAN - <why the plan must change>
BUILD: FAILED - <failing command>
```

`DONE` only when every task is complete and every validation command passed.
