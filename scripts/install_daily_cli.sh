#!/usr/bin/env bash
# Opt-in symlink for the bundled control CLI; never runs the CLI or starts the app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
ACTION=install
if [[ "${1:-}" == "--remove" ]]; then
    ACTION=remove
    shift
fi
if (( $# > 1 )); then
    echo "Usage: $0 [--remove] [path/to/DailyWorkspace.app]" >&2
    exit 2
fi
APP="${1:-$ROOT/build/DailyWorkspace.app}"
case "$APP" in
    /*) ;;
    *) APP="$PWD/$APP" ;;
esac
CLI="$APP/Contents/MacOS/daily"
DEST_DIR="$HOME/.local/bin"
DEST="$DEST_DIR/daily"

# Never follow a replacement directory to an unexpected location.
if [[ -L "$HOME/.local" || -L "$DEST_DIR" ]]; then
    echo "Refusing symlinked ~/.local or ~/.local/bin" >&2
    exit 1
fi

if [[ "$ACTION" == remove ]]; then
    if [[ -L "$DEST" && "$(readlink "$DEST")" == "$CLI" ]]; then
        rm "$DEST"
        echo "Removed $DEST"
    else
        echo "Refusing to remove $DEST: it is not the symlink to $CLI" >&2
        exit 1
    fi
    exit 0
fi

if [[ ! -f "$CLI" || ! -x "$CLI" ]]; then
    echo "Missing executable $CLI; bundle the app first with scripts/bundle.sh" >&2
    exit 1
fi
if [[ -L "$DEST" ]]; then
    if [[ "$(readlink "$DEST")" == "$CLI" ]]; then
        echo "Already installed: $DEST -> $CLI"
        exit 0
    fi
    echo "Refusing to replace unrelated symlink $DEST" >&2
    exit 1
fi
if [[ -e "$DEST" ]]; then
    echo "Refusing to replace existing $DEST" >&2
    exit 1
fi
mkdir -p "$DEST_DIR"
ln -s "$CLI" "$DEST"
echo "Installed $DEST -> $CLI"
