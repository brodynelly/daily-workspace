#!/usr/bin/env bash
# Builds a double-clickable DailyWorkspace.app (macOS only). Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/DailyWorkspace.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DailyWorkspace" "$APP/Contents/MacOS/DailyWorkspace"
cp "$BIN_DIR/daily" "$APP/Contents/MacOS/daily"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Outfit (SIL OFL 1.1) for headings; Info.plist ATSApplicationFontsPath points here.
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
# Keep the source font as portable text; decode and verify its original TrueType bytes
# in the generated bundle. Attribution and the CC BY-SA 4.0 license ship in Fonts/.
/usr/bin/base64 -D -i Resources/VGA.ttf.base64 -o "$APP/Contents/Resources/VGA.ttf"
echo "9feedbe215015cc22a74dfdf58b773beccd34ad5aedb1903de815173420c6ba1  $APP/Contents/Resources/VGA.ttf" | shasum -a 256 -c -
cp Resources/music.js "$APP/Contents/Resources/music.js"
if [ -d Resources/Shortcuts ]; then
    cp -R Resources/Shortcuts "$APP/Contents/Resources/Shortcuts"
fi
codesign --force --sign - "$APP"
echo "Built $APP"
