#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$ROOT_DIR/dist/BackAudioRecorder.app"
CONTENTS_DIR="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/BackAudioRecorder" "$CONTENTS_DIR/MacOS/BackAudioRecorder"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

ICONSET_DIR="$ROOT_DIR/.build/BackAudioRecorder.iconset"
ICON_FILE="$ROOT_DIR/.build/BackAudioRecorder.icns"
swift "$ROOT_DIR/scripts/generate-icon.swift" "$ICONSET_DIR" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
cp "$ICON_FILE" "$CONTENTS_DIR/Resources/AppIcon.icns"

chmod 755 "$CONTENTS_DIR/MacOS/BackAudioRecorder"

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
codesign --force --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
