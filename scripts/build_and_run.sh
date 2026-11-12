#!/usr/bin/env bash
# Build, bundle and launch the debug app.
#   run (default)  launch           --verify   launch and confirm the process is running
#   --debug        run under lldb   --logs     stream all of the process's log output
#   --app-logs     stream only the app's os.Logger output (subsystem app.dailyworkspace.mac)
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
case "$MODE" in
  run|--debug|--logs|--app-logs|--verify) ;;
  *) echo "usage: $0 [run|--verify|--debug|--logs|--app-logs]" >&2; exit 2 ;;
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
bash scripts/bundle.sh debug
APP="$PWD/build/DailyWorkspace.app"
if [[ "$MODE" == --debug ]]; then
  exec lldb -- "$APP/Contents/MacOS/DailyWorkspace"
fi
/usr/bin/open -n "$APP"
case "$MODE" in
  --verify) sleep 2; pgrep -x DailyWorkspace >/dev/null ;;
  --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "DailyWorkspace"' ;;
  --app-logs) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "app.dailyworkspace.mac"' ;;
esac
