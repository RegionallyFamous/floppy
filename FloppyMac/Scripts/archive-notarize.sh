#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="${SCHEME:-FloppyMac}"
CONFIGURATION="${CONFIGURATION:-Release}"
EXPORT_METHOD="${EXPORT_METHOD:-developer-id}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT/.build/archives/FloppyMac.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT/.build/export}"
ZIP_PATH="${ZIP_PATH:-$ROOT/.build/FloppyMac-notarization.zip}"
XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCODE_PROJECT="${XCODE_PROJECT:-}"
XCODE_WORKSPACE="${XCODE_WORKSPACE:-}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_PASSWORD="${APPLE_PASSWORD:-}"
NOTARY_TEAM_ID="${NOTARY_TEAM_ID:-$DEVELOPMENT_TEAM}"

if [[ ! -x "$XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    echo "Xcode not found at $XCODE_DEVELOPER_DIR" >&2
    echo "Set DEVELOPER_DIR or install full Xcode." >&2
    exit 1
fi

if [[ -z "$XCODE_PROJECT" && -z "$XCODE_WORKSPACE" ]]; then
    XCODE_PROJECT="$(find "$ROOT" -maxdepth 2 -name '*.xcodeproj' -print -quit)"
fi

if [[ -z "$XCODE_PROJECT" && -z "$XCODE_WORKSPACE" ]]; then
    cat >&2 <<EOF
No Xcode project/workspace was found under $ROOT.

Create or point at the project that contains the FloppyMac app target and
File Provider extension target, then rerun with one of:

  XCODE_PROJECT=/path/to/FloppyMac.xcodeproj $0
  XCODE_WORKSPACE=/path/to/FloppyMac.xcworkspace $0
EOF
    exit 2
fi

BUILD_CONTAINER_ARGS=()
if [[ -n "$XCODE_WORKSPACE" ]]; then
    BUILD_CONTAINER_ARGS=(-workspace "$XCODE_WORKSPACE")
else
    BUILD_CONTAINER_ARGS=(-project "$XCODE_PROJECT")
fi

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$ZIP_PATH"

if [[ -z "$EXPORT_OPTIONS_PLIST" ]]; then
    EXPORT_OPTIONS_PLIST="$(mktemp "$ROOT/.build/export-options.XXXXXX.plist")"
    TEAM_XML=""
    if [[ -n "$DEVELOPMENT_TEAM" ]]; then
        TEAM_XML="  <key>teamID</key>
  <string>$DEVELOPMENT_TEAM</string>"
    fi
    cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>$EXPORT_METHOD</string>
  <key>signingStyle</key>
  <string>automatic</string>
$TEAM_XML
</dict>
</plist>
EOF
fi

ARCHIVE_ARGS=(
    "${BUILD_CONTAINER_ARGS[@]}"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -archivePath "$ARCHIVE_PATH"
    -destination "generic/platform=macOS"
    SKIP_INSTALL=NO
)

if [[ -n "$DEVELOPMENT_TEAM" ]]; then
    ARCHIVE_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi

DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcodebuild archive "${ARCHIVE_ARGS[@]}"

DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

APP_PATH="$(find "$EXPORT_PATH" -maxdepth 2 -name '*.app' -type d -print -quit)"
if [[ -z "$APP_PATH" ]]; then
    echo "Export succeeded, but no .app was found in $EXPORT_PATH" >&2
    exit 3
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" || true

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Created notarization ZIP: $ZIP_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "$APPLE_ID" && -n "$APPLE_PASSWORD" && -n "$NOTARY_TEAM_ID" ]]; then
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$NOTARY_TEAM_ID" \
        --wait
else
    echo "Notarization skipped. Set NOTARY_PROFILE, or APPLE_ID + APPLE_PASSWORD + NOTARY_TEAM_ID."
    echo "$APP_PATH"
    exit 0
fi

xcrun stapler staple "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" || true

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "$APP_PATH"
echo "$ZIP_PATH"
