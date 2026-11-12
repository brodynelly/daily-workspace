---
name: plan
description: Turns a one-line request, a GitHub issue, or review findings into a complete implementation plan saved to specs/ - classifies the work as feature, bug, chore, or patch and fills the matching template with relevant files, step-by-step tasks, and validation commands. Plans only; writes no code. Use before any change that is more than a one-sentence diff, or when asked to spec, scope, or plan work.
argument-hint: "[feature|bug|chore|patch] [description | #issue | spec-path + review findings]"
allowed-tools: Read, Glob, Grep, Bash(git status *), Bash(git log *), Bash(git diff *), Bash(git ls-files *), Bash(gh issue view *)
---

# Plan

Write a plan for: `$ARGUMENTS`

You are writing a plan, NOT implementing it. A plan is a scaled prompt: a fresh agent with no memory of this
conversation must be able to execute it exactly. Think hard about the approach before writing.

## 1. Resolve the input

- `#123` or an issue URL: fetch it with `gh issue view <n> --json title,body,labels` (if `gh` is unavailable,
  ask the user to paste the issue).
- A spec path plus review findings (JSON or text): this is a **patch** of that spec.
- Otherwise the text is the request. If it is too vague to plan (no observable outcome), ask one clarifying
  question, then continue.

## 2. Classify

If the first word is `feature`, `bug`, `chore`, or `patch`, use it. Otherwise classify:

| Type | Choose when | Template |
| --- | --- | --- |
| `feature` | New user-facing capability or behavior | [assets/feature.md](assets/feature.md) |
| `bug` | Something that should work does not (errors, wrong output, regressions) | [assets/bug.md](assets/bug.md) |
| `chore` | Maintenance with no behavior change: deps, refactors, cleanup, docs, CI | [assets/chore.md](assets/chore.md) |
| `patch` | A small, surgical fix to an existing spec's implementation (usually from `/tac-final:review`) | [assets/patch.md](assets/patch.md) |

Tie-breaks: choose the primary purpose; between chore and feature prefer chore; a question or discussion is
not plannable - say so and stop.

## 3. Research (proportionate to the task)

- Read the project rules (`CLAUDE.md` / `AGENTS.md`) and the TAC section for specs dir and validation commands
  (resolution order in [../guide/references/conventions.md](../guide/references/conventions.md)).
- If `.claude/experts/<domain>/expertise.yaml` covers the area, read it first as a map to verify, not as truth:
  confirm every path and claim you rely on against the code, and report drift for
  `/tac-final:expert improve <domain>`. Store and format: [../expert/SKILL.md](../expert/SKILL.md).
- Find the files involved with Grep/Glob. For broad or unfamiliar areas, delegate to the `tac-final:scout` agent and
  use its summary. Match existing patterns; do not invent new architecture without saying why.
- For bugs: find the root cause, not just the symptom. Reproduce it if a cheap command exists.

## 4. Write the plan

Read the template for the type and fill **every** section. Requirements:

- Name real files and functions. Mark new files as new.
- Step by Step Tasks are numbered, ordered, and each is independently checkable.
- Validation Commands are real commands from the TAC section (or detection), plus at least one check that proves
  this specific change works (a new test, a command, a reproduction that now passes). Never write placeholder commands.
- State what is out of scope. Keep the plan as small as the request allows.

Save to `<specs-dir>/<type>-<slug>.md` (`slug`: kebab-case, at most 40 characters; if the file exists, append
`-2`). For a patch of `specs/feature-x.md`, save `specs/patch-x-<short-desc>.md`.

## 5. Report

Summarize the plan in 3-5 bullets (approach, files touched, risk) and suggest the next command:
`/tac-final:implement <path>`, or `/tac-final:adw plan_build_test` style workflows for the full loop.
End your response with exactly one line, so scripts can parse it:

```text
SPEC: <path-to-plan>
```
