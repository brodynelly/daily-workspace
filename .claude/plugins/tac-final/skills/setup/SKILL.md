---
name: setup
description: Bootstraps the minimum viable agentic layer in any repository - detects the stack and validation commands, then writes a short TAC section into CLAUDE.md or AGENTS.md and creates specs/. Works on repos with no AI setup and on repos that already have CLAUDE.md, AGENTS.md, Cursor, or Copilot instructions; idempotent. Use when starting tac in a repo or when tac skills cannot find validation commands.
argument-hint: "[--dry-run]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git status *), Bash(git ls-files *)
---

# Setup: Minimum Viable Agentic Layer

Make this repository agent-ready with the smallest possible footprint. Never overwrite existing content;
only add or update the `## Agentic layer (tac)` section.

## Workflow

Copy this checklist and work through it:

```text
- [ ] 1. Detect
- [ ] 2. Choose the memory file
- [ ] 3. Confirm validation commands
- [ ] 4. Propose changes
- [ ] 5. Apply (unless --dry-run)
- [ ] 6. Verify and report
```

### 1. Detect

Run the detection script (read-only):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/detect-project.sh"
```

Then read any `memory_file` it lists (only the first ~150 lines of each) so you respect existing conventions.
If `git: no`, stop and tell the user tac needs a git repository (`git init` first).

### 2. Choose the memory file

| Repo state | Write the TAC section to |
| --- | --- |
| `CLAUDE.md` exists (root or `.claude/`) | That file |
| Only `AGENTS.md` exists | `AGENTS.md`, and if there is no `CLAUDE.md`, create one containing just `@AGENTS.md` so Claude Code loads it |
| Neither exists | New `CLAUDE.md` from [assets/claude-md-template.md](assets/claude-md-template.md), filled from detection |
| Other tools' files only (`.cursorrules`, Copilot, Gemini) | New `CLAUDE.md`; mention the existing file under "Other agent instructions" instead of copying it |

If a `tac_section` already exists, this is an update: diff your proposal against it and change only stale lines.

### 3. Confirm validation commands

Validation commands are the most important output: every closed loop in tac depends on them.

- Start from the `validate_candidate` / `e2e_candidate` lines. Prefer project scripts (`npm run test`) over raw tools.
- Exclude anything that mutates files (formatters with `--write`, `--fix`, watch modes).
- Order them fast-to-slow: lint, typecheck, test, build.
- If a candidate is uncertain, run it once to see whether it works. Report failures; do not "fix" the project.
- If there are no candidates, ask the user how they check their work. A repo with no runnable check gets a
  `test:` line of `none yet` and a recommendation to add one.

### 4. Propose changes

Show the user exactly what will change before writing:

1. The TAC section (format in [../guide/references/conventions.md](../guide/references/conventions.md#the-tac-section)).
2. `specs/` directory with a `.gitkeep` (skip if a `specs_dir` was detected; point `Specs:` at it instead).
3. `.tac/runs/` and `.tac/events.jsonl` added to `.gitignore` (create entries only if missing). Do not ignore
   `.tac/` as a whole: `.tac/kpis.md` and `.tac/lessons.md` stay committable so KPIs and retro lessons are
   reviewed like code. Creating `.tac/` also turns on the plugin's event log for this repo.

Ask for confirmation unless the user already said to proceed.

### 5. Apply

Use Edit for existing files and Write for new ones. Keep the TAC section under 20 lines and the whole memory
file lean; do not add general advice, only facts an agent would otherwise get wrong.

### 6. Verify and report

- Re-run the detection script and confirm `tac_section` now points at the memory file.
- Run the first validation command once and report its result.
- Report:

```markdown
## tac setup complete
- Memory file: <path> (<created|updated>)
- Validation: <n> commands (<first command>: <pass|fail>)
- Specs: <dir>
- Next: `/tac-final:assess` for a maturity check, or `/tac-final:plan <task>` to start working
```

## Notes

- `--dry-run`: do steps 1-4 and stop.
- Setup never installs dependencies, changes CI, edits `.claude/settings.json`, or adds hooks. If the user wants
  agents to run validation without prompts, suggest adding the exact commands to `permissions.allow` in
  `.claude/settings.json` (exact commands, not wildcards like `Bash(npx *)`) and let them decide.
- The plugin's guard hook is a best-effort backstop, not a sandbox. Recommend `permissions.deny` rules for secret
  files and destructive commands, and Claude Code sandboxing or a container for unattended runs
  (see [../agent/references/governance.md](../agent/references/governance.md)).
- The `remote:` line from detection is `host/owner/repo` with any credentials stripped; never print the raw
  remote URL.
