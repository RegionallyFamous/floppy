#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
APP_SVG="$ROOT/Packaging/FloppyIcon.svg"
MENU_SVG="$ROOT/Packaging/FloppyMenuBarTemplate.svg"
ICONSET="$ROOT/Packaging/AppIcon.iconset"
PLUGIN_IMAGES="$REPO_ROOT/floppy/assets/images"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "rsvg-convert is required. Install librsvg, for example: brew install librsvg" >&2
    exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
    echo "iconutil is required and should be available on macOS with Xcode command line tools." >&2
    exit 1
fi

mkdir -p "$ICONSET" "$PLUGIN_IMAGES"

rsvg-convert -f pdf -w 18 -h 18 "$MENU_SVG" -o "$ROOT/Packaging/FloppyMenuBarTemplate.pdf"
rsvg-convert -w 1024 -h 1024 "$APP_SVG" -o "$ROOT/Packaging/FloppyIcon.png"

while read -r size filename; do
    rsvg-convert -w "$size" -h "$size" "$APP_SVG" -o "$ICONSET/$filename"
done <<'EOF'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
EOF

iconutil -c icns "$ICONSET" -o "$ROOT/Packaging/FloppyIcon.icns"

rsvg-convert -w 256 -h 256 "$APP_SVG" -o "$PLUGIN_IMAGES/floppy-icon-source.png"
rsvg-convert -w 256 -h 256 "$APP_SVG" -o "$PLUGIN_IMAGES/floppy-icon-256.png"
rsvg-convert -w 128 -h 128 "$APP_SVG" -o "$PLUGIN_IMAGES/floppy-icon-128.png"
rsvg-convert -w 20 -h 20 "$APP_SVG" -o "$PLUGIN_IMAGES/floppy-icon-admin.png"

echo "Regenerated Floppy A:/ app, menu bar, and WordPress icon assets."
