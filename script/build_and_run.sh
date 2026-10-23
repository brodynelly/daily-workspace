#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) ;;
  *) echo "usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
# Ask the running app to quit so its save/conflict protection can run.
if pgrep -x DailyWorkspace >/dev/null; then
  osascript -e 'tell application id "app.dailyworkspace.mac" to quit'
  for attempt in {1..20}; do
    if ! pgrep -x DailyWorkspace >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -x DailyWorkspace >/dev/null; then
    echo "App is still open. Resolve any unsaved note before relaunching." >&2
    exit 1
  fi
fi
bash Scripts/bundle.sh debug
APP="$PWD/build/DailyWorkspace.app"
if [[ "$MODE" == --debug ]]; then
  exec lldb -- "$APP/Contents/MacOS/DailyWorkspace"
fi
/usr/bin/open -n "$APP"
case "$MODE" in
  --verify) sleep 2; pgrep -x DailyWorkspace >/dev/null ;;
  --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "DailyWorkspace"' ;;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "app.dailyworkspace.mac"' ;;
esac
