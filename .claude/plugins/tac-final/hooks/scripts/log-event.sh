#!/usr/bin/env bash
# log-event.sh - append a compact JSONL record of tool, tool-failure, and subagent events to .tac/events.jsonl.
#
# Logs only in projects that opted into tac (a .tac/ directory exists, created by /tac-final:adw or
# /tac-final:setup) so the plugin never creates files in repos that do not use it.
# Likely secrets in the logged detail (NAME=value for token/secret/password/key/auth names, bearer tokens,
# sk-/ghp_/github_pat_/AKIA keys, URL userinfo) are replaced with [REDACTED] before truncation. Redaction is
# best-effort; keep .tac/events.jsonl out of git (setup adds it to .gitignore) and out of CI artifacts.
# Disable with TAC_EVENT_LOG=off. Never blocks: always exits 0.

set -u
[ "${TAC_EVENT_LOG:-on}" = off ] && exit 0
root="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$root/.tac" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

TAC_LOG="$root/.tac/events.jsonl" python3 -c '
import datetime, json, os, re, sys

R = "[REDACTED]"
REDACTIONS = [
    # URL userinfo: scheme://user:secret@host -> scheme://[REDACTED]@host
    (re.compile(r"(\b[a-zA-Z][\w+.-]*://)[^/\s@]+@"), r"\1" + R + "@"),
    # Authorization headers and bearer/basic tokens
    (re.compile(r"(?i)\b(bearer|basic|token)\s+[A-Za-z0-9._~+/=-]{8,}"), r"\1 " + R),
    # NAME=value / NAME: value / --name=value where the name looks secret
    (re.compile(r"(?i)\b([\w.-]*(TOKEN|SECRET|PASSWORD|PASSWD|KEY|AUTH|CREDENTIAL)[\w.-]*)(\s*[=:]\s*|=)(\x27[^\x27]*\x27|\"[^\"]*\"|[^\s\x27\"]+)"), r"\1\3" + R),
    # Well-known key formats
    (re.compile(r"\bsk-[A-Za-z0-9_-]{16,}"), R),
    (re.compile(r"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}"), R),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"), R),
    (re.compile(r"\b(AKIA|ASIA)[A-Z0-9]{16}\b"), R),
    (re.compile(r"\bxox[abposr]-[A-Za-z0-9-]{10,}"), R),
]
def redact(text):
    for pattern, repl in REDACTIONS:
        text = pattern.sub(repl, text)
    return text

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
detail = ti.get("command") or ti.get("file_path") or ti.get("pattern") or ti.get("skill") or ti.get("subagent_type") or ti.get("description") or ""
rec = {
    "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "session": d.get("session_id"),
    "event": d.get("hook_event_name"),
    "tool": d.get("tool_name"),
    "agent": d.get("agent_type"),
    "detail": redact(str(detail))[:200],
}
with open(os.environ["TAC_LOG"], "a") as f:
    f.write(json.dumps({k: v for k, v in rec.items() if v}) + "\n")
' 2>/dev/null
exit 0
