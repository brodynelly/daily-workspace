#!/usr/bin/env bash
# guard.sh - tac-final guardrail for PreToolUse.
#
# Usage (from hooks.json): guard.sh bash|file   (hook JSON on stdin)
# Catastrophic commands are denied; risky-but-legitimate ones ask the user.
#
# This is a best-effort backstop, NOT a sandbox. Pattern matching on a shell string cannot see through every
# alias, variable, script file, or encoding, and it fails open: it allows the call if python3 is missing or the
# input cannot be parsed. Enforce hard limits with `permissions.deny` in .claude/settings.json and Claude
# Code's sandbox (or a container); see skills/agent/references/governance.md.
# Disable with TAC_GUARDRAILS=off.

set -u
[ "${TAC_GUARDRAILS:-on}" = off ] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# shellcheck disable=SC2016  # the single-quoted block is a Python program
mode="${1:-bash}" python3 -c '
import json, os, re, sys

def decide(decision, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": "tac-final guardrail: " + reason + " (set TAC_GUARDRAILS=off to disable)",
    }}))
    sys.exit(0)

# Whole-string patterns, matched against the command with quotes and backslashes removed.
DENY_RE = [
    (r"\bmkfs(\.\w+)?\b", "formatting a filesystem"),
    (r"\bdd\b[^|;&]*\bof=/dev/(sd|nvme|disk|hd|rdisk|mmcblk)", "writing directly to a disk device"),
    (r":\(\)\s*\{\s*:\|:&\s*\};:", "fork bomb"),
    (r"\bchmod\s+(-\w+\s+)*-\w*R\w*\s+(-\w+\s+)*0?777\s+/(\s|$)", "chmod 777 on /"),
    (r"--no-preserve-root\b", "rm --no-preserve-root"),
]
ASK_RE = [
    (r"\bgit\s+reset\s+--hard\b", "git reset --hard discards uncommitted work"),
    (r"\bgit\s+clean\s+(-\w+\s+)*-\w*f", "git clean deletes untracked files"),
    (r"\bgit\s+checkout\s+(--\s+)?\.(\s|$)", "git checkout . discards local changes"),
    (r"\bgit\s+branch\s+(-\w+\s+)*-D\b", "force-deleting a branch"),
    (r"(?i:\b(DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE)\b)", "destructive SQL"),
]

HOME = r"(~|\$HOME|\$\{HOME\})"
SYSTEM_DIRS = r"(bin|boot|dev|etc|home|lib|lib64|opt|root|sbin|srv|sys|usr|var|Users|System|Library|Applications)"
# Targets whose recursive delete is catastrophic: /, /*, ~, ~/, ~/*, $HOME..., top-level system dirs.
CATASTROPHIC = re.compile(r"^(/+\.?|/\*|" + HOME + r"/?\*?|/" + SYSTEM_DIRS + r"/?\*?)$")
# Targets outside the project: absolute, home-relative, or parent-relative.
OUTSIDE = re.compile(r"^(/|" + HOME + r"|\.\.(/|$))")
SEPARATORS = re.compile(r"\|\||&&|\$\(|[;&|\n`()]")

def segments(cmd):
    for seg in SEPARATORS.split(cmd):
        toks = seg.split()
        if toks:
            yield toks

def is_cmd(tok, name):
    return tok == name or tok.endswith("/" + name)

def check_rm(toks):
    for i, t in enumerate(toks):
        if not is_cmd(t, "rm"):
            continue
        recursive = force = False
        targets, opts_done = [], False
        for a in toks[i + 1:]:
            if not opts_done and a == "--":
                opts_done = True
            elif not opts_done and a.startswith("--"):
                recursive |= a == "--recursive"
                force |= a == "--force"
            elif not opts_done and a.startswith("-") and len(a) > 1:
                recursive |= "r" in a or "R" in a
                force |= "f" in a
            else:
                targets.append(a)
        if recursive and any(CATASTROPHIC.match(x) for x in targets):
            found.append(("deny", "recursive delete of /, home, or a system directory"))
        elif recursive and force and any(OUTSIDE.match(x) for x in targets):
            found.append(("ask", "recursive force delete outside the project"))

def check_find(toks):
    for i, t in enumerate(toks):
        if not is_cmd(t, "find"):
            continue
        rest = toks[i + 1:]
        roots = []
        for a in rest:
            if a.startswith("-") or a in ("!", "("):
                break
            roots.append(a)
        destructive = "-delete" in rest or any(
            a in ("-exec", "-execdir", "-ok") and j + 1 < len(rest) and is_cmd(rest[j + 1], "rm")
            for j, a in enumerate(rest))
        if destructive and any(CATASTROPHIC.match(r) for r in roots):
            found.append(("deny", "find -delete over /, home, or a system directory"))

def check_push(toks):
    for i, t in enumerate(toks):
        if t != "git" or i + 1 >= len(toks) or toks[i + 1] != "push":
            continue
        for a in toks[i + 2:]:
            if a in ("--force", "--mirror") or re.match(r"^-[a-zA-Z]*f[a-zA-Z]*$", a):
                found.append(("ask", "force push (prefer --force-with-lease)"))
            elif a.startswith("+"):
                found.append(("ask", "force push via +refspec (prefer --force-with-lease)"))

SECRET_PATH = re.compile(
    r"(^|/)("
    r"\.env(\.[\w-]+)?|[^/]*\.(pem|key|p12|pfx|tfvars|tfvars\.json)|id_(rsa|ed25519|ecdsa|dsa)"
    r"|credentials(\.json)?|\.npmrc|\.pypirc|\.netrc|_netrc"
    r"|\.ssh/[^/]+|\.aws/credentials|\.aws/config|\.kube/config|\.docker/config\.json"
    r")$")
SAFE_PATH = re.compile(r"(\.(example|sample|template|dist)|\.ssh/[^/]+\.pub)$")

try:
    data = json.load(sys.stdin)
    tool_input = data.get("tool_input") or {}
except Exception:
    sys.exit(0)

mode = os.environ.get("mode", "bash")
if mode == "bash":
    raw = str(tool_input.get("command") or "")
    # Strip quotes and backslash escapes so wrappers like bash -c "rm -rf /" are judged by their payload.
    cmd = re.sub(r"[\x27\"\\]", "", raw)
    found = [("deny", r) for p, r in DENY_RE if re.search(p, cmd)]
    for toks in segments(cmd):
        check_rm(toks)
        check_find(toks)
        check_push(toks)
    found += [("ask", r) for p, r in ASK_RE if re.search(p, cmd)]
    for decision in ("deny", "ask"):
        for d, reason in found:
            if d == decision:
                decide(d, reason)
else:
    path = str(tool_input.get("file_path") or tool_input.get("notebook_path") or "")
    if path and SECRET_PATH.search(path) and not SAFE_PATH.search(path):
        decide("ask", "editing a secrets or credentials file: " + os.path.basename(path))
sys.exit(0)
' 2>/dev/null
exit 0
