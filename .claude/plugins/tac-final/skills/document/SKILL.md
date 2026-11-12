---
name: document
description: Writes concise, agent-readable documentation for implemented changes - what was built, how it works, how to use and test it - from the diff and its spec, saved to the project's docs directory. Answers "how does it work?" so future agents and people do not have to rediscover it. Use after a feature passes review, or when asked to document changes.
argument-hint: "[path-to-spec.md]"
allowed-tools: Read, Glob, Grep, Write, Edit, Bash(git diff *), Bash(git log *), Bash(git status *), Bash(git symbolic-ref *)
---

# Document

Document the changes on the current branch (spec: `$ARGUMENTS`, optional).

## Workflow

1. Gather everything the branch changes, committed or not: `git diff --stat <default-branch>...HEAD` for commits,
   `git diff HEAD --stat` for staged and unstaged edits, and `git status --porcelain` for new untracked files (read
   those directly). Workflows such as `/tac-final:adw` document before anything is committed, so the working tree is
   often the whole story. Then read the diffs of the significant files and the spec if given.
2. Find where docs live: `Docs:` in the TAC section, else an existing `docs/` directory, else create `docs/`.
   If the repo documents features somewhere specific (a docs site, ADRs, a CHANGELOG), follow that instead.
3. Write `<docs-dir>/<slug>.md` using the format below. Describe what was actually built, not what was planned;
   note deviations from the spec.
4. If a memory file or docs index lists docs by topic, add one line pointing to the new page so agents can find
   it on demand (conditional docs: "read docs/<slug>.md when working on <area>"). Do not paste the content into
   the memory file.

## Format

```markdown
# <Feature title>

- Date: <YYYY-MM-DD>
- Spec: <path or n/a>

## Overview
<2-3 sentences.>

## How it works
- <Key components and the flow between them, with file paths>

## Usage
<How to use it: commands, API calls, UI steps, configuration.>

## Testing
<How to verify it: test files and commands.>

## Notes
<Limitations, follow-ups.>
```

Keep it under ~80 lines; link to code rather than copying it.

## Output

End your response with the path of the doc you wrote as the last line, plain text at the start of the line
(no backticks): `DOC: <path>`.
