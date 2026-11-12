#!/usr/bin/env bash
# Builds a double-clickable DailyWorkspace.app (macOS only). Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/DailyWorkspace"
APP="build/DailyWorkspace.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DailyWorkspace"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Outfit (SIL OFL 1.1) for headings; Info.plist ATSApplicationFontsPath points here.
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
codesign --force --sign - "$APP"
echo "Built $APP"
