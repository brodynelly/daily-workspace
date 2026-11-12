---
name: prime
description: Primes the agent with just enough codebase understanding for a task - tracked files, memory files, project conventions, and task-shaped extras (recent history for bugs, architecture for features, the diff for reviews). Use at the start of a session, after /clear, when context was lost, or before planning in an unfamiliar repo.
argument-hint: "[bug|feature|review|chore|area-or-path]"
allowed-tools: Read, Glob, Grep, Bash(git status *), Bash(git ls-files *), Bash(git log *), Bash(git diff *)
---

# Prime

Build a compact mental model of this repository for the task type `$ARGUMENTS` (default: general).
Reduce, do not hoard: read summaries and entry points, not every file.

## Workflow

1. **Map the repo.** Run `git ls-files | head -300` (and `git ls-files | wc -l`). If the repo is large, map by
   directory: `git ls-files | cut -d/ -f1-2 | sort | uniq -c | sort -rn | head -40`.
2. **Read the rules.** Read `CLAUDE.md`, `.claude/CLAUDE.md`, and `AGENTS.md` if present, plus the README (first
   ~150 lines). Note the `## Agentic layer (tac)` section if there is one.
3. **Load task-shaped context** (only for the matching type):

   | Type | Also do |
   | --- | --- |
   | `bug` | `git log --oneline -15`; find the area named in the request with Grep; read related tests |
   | `feature` | Find 1-2 existing features similar to the request and read their entry points and tests |
   | `review` | `git status`, `git diff --stat <default-branch>...HEAD`; read the spec under review if named |
   | `chore` | Read manifests (package.json, pyproject.toml, go.mod, ...), CI config, and scripts |
   | path or area | Read that area's entry points and tests |

4. **Check the agentic layer.** Note `specs/` (recent plans) and `.tac/runs/` (unfinished runs). If
   `.claude/experts/<domain>/expertise.yaml` covers the area, read it first as a map to verify, not as truth:
   confirm every path and claim you rely on against the code, and report drift for
   `/tac-final:expert improve <domain>`. Note its `last_validated` date.

If the repo is unfamiliar and large, delegate steps 3-4 to the `tac-final:scout` agent and keep only its summary.

## Report

Keep it under ~25 lines:

```markdown
## Primed: <repo> (<task type>)
- Purpose: <one line>
- Stack: <languages, frameworks>
- Layout: <key dirs and what they hold>
- Entry points: <files>
- Validate with: <commands from the TAC section, or "unknown - run /tac-final:setup">
- Conventions: <rules from memory files that matter for this task>
- Relevant to this task: <files, experts (with drift found, if any), open specs>
```
