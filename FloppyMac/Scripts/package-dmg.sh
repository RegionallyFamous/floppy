#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT/.build/export/FloppyMac.app}"
DMG_PATH="${DMG_PATH:-$ROOT/.build/FloppyMac.dmg}"
VOLUME_NAME="${VOLUME_NAME:-Floppy}"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-Floppy.app}"
DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_PASSWORD="${APPLE_PASSWORD:-}"
NOTARY_TEAM_ID="${NOTARY_TEAM_ID:-${DEVELOPMENT_TEAM:-}}"
XCRUN="${XCRUN:-/usr/bin/xcrun}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle was not found at $APP_PATH" >&2
    exit 2
fi

if [[ ! -x "$XCRUN" ]]; then
    echo "xcrun was not found at $XCRUN" >&2
    echo "Set XCRUN to the xcrun executable path." >&2
    exit 2
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
"$XCRUN" stapler validate "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

mkdir -p "$(dirname "$DMG_PATH")"
STAGING_DIR="$(mktemp -d "$ROOT/.build/dmg-staging.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

ditto "$APP_PATH" "$STAGING_DIR/$APP_BUNDLE_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -fs HFS+ \
    -ov \
    "$DMG_PATH"
hdiutil verify "$DMG_PATH"

if [[ -n "$DMG_SIGN_IDENTITY" ]]; then
    codesign --force --timestamp --sign "$DMG_SIGN_IDENTITY" "$DMG_PATH"
    codesign --verify --verbose=4 "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    "$XCRUN" notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "$APPLE_ID" && -n "$APPLE_PASSWORD" && -n "$NOTARY_TEAM_ID" ]]; then
    "$XCRUN" notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$NOTARY_TEAM_ID" \
        --wait
fi

if [[ -n "$NOTARY_PROFILE" || ( -n "$APPLE_ID" && -n "$APPLE_PASSWORD" && -n "$NOTARY_TEAM_ID" ) ]]; then
    "$XCRUN" stapler staple "$DMG_PATH"
    "$XCRUN" stapler validate "$DMG_PATH"
fi

if [[ -n "$DMG_SIGN_IDENTITY" ]]; then
    codesign --verify --verbose=4 "$DMG_PATH"
fi
hdiutil verify "$DMG_PATH"

echo "$DMG_PATH"
