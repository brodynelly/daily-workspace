# Worktree Environments for Parallel Agents

Parallel agents need isolated, working environments. Git worktrees give each agent its own checkout and branch
while sharing history. Claude Code creates them for you:

- `claude --worktree <name>` starts a session in `.claude/worktrees/<name>` (branch `worktree-<name>`).
- Subagents launched with worktree isolation (or agents with `isolation: worktree`) get a temporary worktree
  that is removed automatically if they made no changes.
- Add `.claude/worktrees/` to `.gitignore`.

A checkout alone is often not enough to run tests. Before building in a fresh worktree, check:

## 1. Untracked configuration

Worktrees contain only tracked files. If tests need `.env` or local config, copy them in from the main checkout
(never commit them):

```bash
for f in .env .env.local .env.test; do [ -f "$MAIN/$f" ] && cp "$MAIN/$f" "$WT/$f"; done
```

## 2. Dependencies

Install with the project's lockfile-respecting command inside the worktree (`npm ci`, `pnpm install --frozen-lockfile`,
`uv sync`, `poetry install`, `bundle install`, `go mod download`, `cargo fetch`). Detection output from
`../../setup/scripts/detect-project.sh` names the package manager.

## 3. Ports and shared resources

Two agents running dev servers or databases on the same port will collide. Give each worktree an offset:

```bash
offset=$(( $(printf '%s' "$WT" | cksum | cut -d' ' -f1) % 100 ))
printf 'PORT=%s\n' $(( 3000 + offset )) >> "$WT/.env"
```

Use per-worktree databases (SQLite files, schema names, or containers) for tests that write data.

## 4. Cleanup

```bash
git worktree list
git worktree remove .claude/worktrees/<name>   # add --force only if you are sure the changes are merged
git branch -d <branch>
```

If these steps are needed for every run, write them into the project's TAC section (or a `scripts/setup-worktree.sh`)
so every agent does the same thing.
