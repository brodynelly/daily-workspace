#!/usr/bin/env bash
# Build a release DailyWorkspace.app and install or update it in /Applications.
#   scripts/install_app.sh [--skip-checks] [--no-launch]
# Runs the baseline recipes, quits the running app gracefully, backs up any
# installed copy to ~/.config/daily-workspace/backups/, installs, verifies the
# signature, links ~/.local/bin/daily, launches, and enables Start at Login.
# Never touches the vault, dotfiles, skhd, Luuna or tasks.json.
set -euo pipefail
cd "$(dirname "$0")/.."
CHECKS=1 LAUNCH=1
for arg in "$@"; do
  case "$arg" in
    --skip-checks) CHECKS=0 ;;
    --no-launch) LAUNCH=0 ;;
    *) echo "usage: $0 [--skip-checks] [--no-launch]" >&2; exit 2 ;;
  esac
done
DEST=/Applications/DailyWorkspace.app
CLI="$HOME/.local/bin/daily"
step() { printf '\n==> %s\n' "$*"; }

if (( CHECKS )); then
  step "Baseline: build, test, lint"
  swift build
  swift test
  swift format lint --strict --recursive Sources Tests Package.swift
  swiftlint --strict
fi

step "Bundle release"
bash scripts/bundle.sh release

if pgrep -x DailyWorkspace >/dev/null; then
  step "Quit running app"
  osascript -e 'tell application id "app.dailyworkspace.mac" to quit' || true
  for _ in {1..50}; do pgrep -x DailyWorkspace >/dev/null || break; sleep 0.1; done
  if pgrep -x DailyWorkspace >/dev/null; then
    echo "App is still open (unsaved note?). Resolve it, then rerun." >&2
    exit 1
  fi
fi

if [[ -e "$DEST" ]]; then
  BACKUP_DIR="$HOME/.config/daily-workspace/backups"
  mkdir -p "$BACKUP_DIR"
  BACKUP="$BACKUP_DIR/DailyWorkspace-$(date +%Y%m%d-%H%M%S).app"
  step "Back up existing install -> $BACKUP"
  mv "$DEST" "$BACKUP"
fi

step "Install $DEST"
ditto build/DailyWorkspace.app "$DEST"
codesign --verify --deep --strict "$DEST"
echo "signature OK"

step "Link daily CLI"
# Replace only a dangling symlink; install_daily_cli.sh refuses anything unexpected.
if [[ -L "$CLI" && ! -e "$CLI" ]]; then rm "$CLI"; fi
if [[ "$(readlink "$CLI" 2>/dev/null)" != "$DEST/Contents/MacOS/daily" ]]; then
  scripts/install_daily_cli.sh "$DEST"
else
  echo "already linked"
fi

if (( LAUNCH )); then
  step "Launch and verify"
  /usr/bin/open "$DEST"
  for _ in {1..30}; do pgrep -x DailyWorkspace >/dev/null && break; sleep 0.2; done
  "$CLI" status
  "$CLI" login enable
  "$CLI" login status
fi
step "Done. Note: ad-hoc re-signing may reset Calendar permission; re-grant in the app if asked."
