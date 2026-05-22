#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN_DIR="$ROOT/floppy"
DIST_DIR="$ROOT/dist"
TMP_DIR="$(mktemp -d)"
ZIP_PATH="$DIST_DIR/floppy.zip"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ ! -f "$PLUGIN_DIR/floppy.php" ]]; then
    echo "Could not find $PLUGIN_DIR/floppy.php" >&2
    exit 1
fi

mkdir -p "$DIST_DIR"
mkdir -p "$TMP_DIR/floppy"

rsync -a \
    --exclude-from "$PLUGIN_DIR/.distignore" \
    "$PLUGIN_DIR/" "$TMP_DIR/floppy/"

rm -f "$ZIP_PATH"
(cd "$TMP_DIR" && zip -qr "$ZIP_PATH" floppy)

echo "$ZIP_PATH"
