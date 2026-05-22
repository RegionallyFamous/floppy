#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ACTIVE_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"

echo "Floppy Xcode Doctor"
echo

run_xcode_command() {
    if ! DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" "$@"; then
        echo
        echo "Xcode first-launch setup may still be incomplete." >&2
        echo "Run this in Terminal, then rerun this doctor:" >&2
        echo "sudo xcodebuild -license" >&2
        echo "sudo xcodebuild -runFirstLaunch" >&2
        exit 69
    fi
}

if [[ ! -x "$XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    echo "Xcode not found at: $XCODE_DEVELOPER_DIR" >&2
    echo "Install Xcode from the App Store or set DEVELOPER_DIR to the Xcode Developer path." >&2
    exit 1
fi

echo "Xcode:"
if ! DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcodebuild -version; then
    echo
    echo "Xcode is installed, but first-launch setup is not complete." >&2
    echo "Run this in Terminal, then rerun this doctor:" >&2
    echo "sudo xcodebuild -license" >&2
    echo "sudo xcodebuild -runFirstLaunch" >&2
    exit 69
fi
echo

echo "Active developer directory:"
echo "${ACTIVE_DEVELOPER_DIR:-not set}"
if [[ "$ACTIVE_DEVELOPER_DIR" != "$XCODE_DEVELOPER_DIR" ]]; then
    echo
    echo "Recommended switch:"
    echo "sudo xcode-select --switch \"$XCODE_DEVELOPER_DIR\""
fi
echo

echo "Swift package:"
run_xcode_command swift build --package-path "$ROOT"
run_xcode_command swift test --package-path "$ROOT"
echo

echo "File Provider source target:"
run_xcode_command swift build --package-path "$ROOT" --target FloppyFileProvider
echo

echo "Next Xcode steps:"
echo "1. Open FloppyMac/Package.swift in Xcode."
echo "2. Add a macOS File Provider extension app-extension target."
echo "3. Add Sources/FloppyFileProvider/*.swift to that extension target."
echo "4. Use Extension/Info.plist and Extension/FloppyFileProvider.entitlements."
echo "5. Set a real Team ID, App Group, and Keychain access group before signing."
echo "6. Use Scripts/archive-notarize.sh from that Xcode project/workspace for Developer ID export and notarization."
