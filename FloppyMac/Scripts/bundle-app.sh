#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Floppy.app"
EXECUTABLE_NAME="FloppyMac"
ZIP_PATH="$ROOT/.build/Floppy.zip"

swift build --package-path "$ROOT" -c "$CONFIGURATION"

APP_DIR="$ROOT/.build/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT/.build/$CONFIGURATION/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ROOT/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT/Packaging/FloppyIcon.icns" "$RESOURCES_DIR/FloppyIcon.icns"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

if command -v codesign > /dev/null; then
    codesign --force --deep --sign - "$APP_DIR" > /dev/null
fi

if command -v ditto > /dev/null; then
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
fi

echo "$APP_DIR"
if [[ -f "$ZIP_PATH" ]]; then
    echo "$ZIP_PATH"
fi
