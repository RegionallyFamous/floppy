#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ACTIVE_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
SWIFT_SCRATCH_PATH="${SWIFT_SCRATCH_PATH:-${TMPDIR:-/tmp}/floppy-xcode-doctor-build}"

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

echo "Code signing identities:"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
echo "$IDENTITIES"
if echo "$IDENTITIES" | grep -q "0 valid identities found"; then
    echo
    echo "No local code-signing identity was found. The SwiftPM app can run, but the Finder-native File Provider helper will not work until Xcode has a signing Team/certificate." >&2
    echo "Open Xcode > Settings > Accounts, add your Apple ID, then select a Team for both FloppyMac targets." >&2
fi
echo

echo "Swift package:"
rm -rf "$SWIFT_SCRATCH_PATH"
run_xcode_command swift build --package-path "$ROOT" --scratch-path "$SWIFT_SCRATCH_PATH"
run_xcode_command swift test --package-path "$ROOT" --scratch-path "$SWIFT_SCRATCH_PATH"
echo

echo "File Provider source target:"
run_xcode_command swift build --package-path "$ROOT" --scratch-path "$SWIFT_SCRATCH_PATH" --target FloppyFileProvider
echo

echo "Signing-ready assets:"
required_files=(
    "$ROOT/Packaging/Info.plist"
    "$ROOT/Packaging/FloppyMac.entitlements"
    "$ROOT/Packaging/FloppyIcon.icns"
    "$ROOT/Extension/Info.plist"
    "$ROOT/Extension/FloppyFileProvider.entitlements"
    "$ROOT/Sources/FloppyFileProvider/FloppyFileProviderExtension.swift"
    "$ROOT/project.yml"
)
for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "Missing required signing/extension file: $file" >&2
        exit 1
    fi
    echo "ok ${file#"$ROOT"/}"
done

if ! /usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$ROOT/Extension/Info.plist" | grep -q "com.apple.fileprovider-nonui"; then
    echo "Extension/Info.plist is not configured as a non-UI File Provider extension." >&2
    exit 1
fi
for entitlement in "$ROOT/Packaging/FloppyMac.entitlements" "$ROOT/Extension/FloppyFileProvider.entitlements"; do
    if ! grep -q "com.floppy.mac.sync" "$entitlement"; then
        echo "App Group com.floppy.mac.sync is missing from ${entitlement#"$ROOT"/}." >&2
        exit 1
    fi
done
echo

echo "Next Xcode steps:"
echo "1. Generate the project with: cd FloppyMac && xcodegen generate"
echo "2. Open FloppyMac.xcodeproj and set a real Team ID."
echo "3. Confirm the app embeds the File Provider extension target."
echo "4. Confirm App Group and Keychain access group match across both targets."
echo "5. Use Scripts/archive-notarize.sh from that Xcode project/workspace for Developer ID export and notarization."
