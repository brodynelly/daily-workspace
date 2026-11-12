# Governing Agents with Hooks

Instructions in prompts and CLAUDE.md are requests. Hooks are deterministic: Claude Code runs them on events and
can block the action. Use them for rules that must hold every time.

| Goal | Event | Behavior |
| --- | --- | --- |
| Block destructive shell commands | `PreToolUse` (matcher `Bash`) | Exit code 2 blocks the call; stderr is shown to Claude |
| Protect paths (`.env`, migrations, lockfiles) | `PreToolUse` (matcher `Edit\|Write`) | Block or require confirmation |
| Audit trail | `PostToolUse` | Append tool name and input to a JSONL log |
| Enforce a test gate before stopping | `Stop` | Run validation; block stopping while it fails |

Example `.claude/settings.json` entry and script:

```json
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/block-dangerous.sh"}]}
    ]
  }
}
```

```bash
#!/usr/bin/env bash
# .claude/hooks/block-dangerous.sh - reads the hook JSON on stdin
cmd="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))')"
if printf '%s' "$cmd" | grep -Eq 'rm -rf /|git push (-f|--force)|git reset --hard|DROP (TABLE|DATABASE)'; then
  echo "Blocked by policy: $cmd" >&2
  exit 2
fi
exit 0
```

Hooks that pattern-match command strings are a backstop, not a boundary: an agent (or an injected prompt) can
reach the same effect through a script file, a variable, or an encoding the pattern never sees. Layer the
controls:

| Layer | Use it for | Enforced by |
| --- | --- | --- |
| `permissions.deny` in `.claude/settings.json` | Tools and paths an agent must never touch | Claude Code, before any hook |
| Sandbox (Claude Code sandboxing, a container, or a CI runner) | Limit filesystem and network reach for everything, including scripts | The OS / runtime |
| `permissions.allow` with exact commands | Let headless runs execute validation without wildcards like `Bash(npx *)` | Claude Code |
| PreToolUse hooks (this page, tac-final's `guard.sh`) | Catch common catastrophic mistakes and ask on risky ones | Best effort |

Example hard limits:

```json
{
  "permissions": {
    "deny": [
      "Read(./.env)", "Read(./.env.*)", "Read(~/.ssh/**)", "Read(~/.aws/credentials)",
      "Bash(rm -rf /)", "Bash(git push --force *)", "Bash(curl *)"
    ]
  }
}
```

Notes:

- Verify event names, input fields, and permission rule syntax against the current
  [hooks reference](https://code.claude.com/docs/en/hooks) and
  [settings reference](https://code.claude.com/docs/en/settings) before relying on them.
- Plugin-shipped agents ignore `hooks`, `mcpServers`, and `permissionMode` in their frontmatter; configure these
  in project or user settings instead.
- tac-final ships plugin-level guardrails (`hooks/hooks.json`) as a best-effort backstop:
  - `guard.sh` denies recursive deletes of `/`, home, or system directories (any flag order, including inside
    `bash -c "..."`), `find / -delete`, `mkfs`, raw disk writes, and fork bombs; it asks before force pushes
    (`--force`, `-f`, `+refspec`), hard resets, `git clean`, destructive SQL, recursive deletes outside the
    project, and edits to secret files (`.env`, keys, `.ssh/*` except `.pub`, `.netrc`, `.aws/credentials`,
    `.kube/config`, `*.tfvars`). It fails open if `python3` is missing, and may deny a command that merely
    quotes a catastrophic one (for example in a commit message); rephrase it.
  - `log-event.sh` appends events to `.tac/events.jsonl` in repos that have a `.tac/` directory, redacting
    likely secrets first. Redaction is best effort: keep the log out of git and out of CI artifacts.
  - Turn them off with `TAC_GUARDRAILS=off` and `TAC_EVENT_LOG=off`. Add project hooks and `permissions.deny`
    rules for anything specific to your codebase.
- Headless and CI runs read untrusted input (issue bodies, PR text). Give the agent step no write token, an exact
  command allowlist, and a separate step that ships its diff for human review; see
  [../../adw/assets/github-action-adw.yml](../../adw/assets/github-action-adw.yml).
- For observability across many agents, log hook events to JSONL first; dashboards come later (an external
  observability tool can render them; none is bundled with this plugin).
