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
ARCHIVE_DESTINATION="${ARCHIVE_DESTINATION:-generic/platform=macOS}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_PASSWORD="${APPLE_PASSWORD:-}"
NOTARY_TEAM_ID="${NOTARY_TEAM_ID:-$DEVELOPMENT_TEAM}"
ALLOW_NOTARIZATION_SKIP="${ALLOW_NOTARIZATION_SKIP:-0}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-0}"
ALLOW_PROVISIONING_DEVICE_REGISTRATION="${ALLOW_PROVISIONING_DEVICE_REGISTRATION:-0}"
APP_STORE_CONNECT_KEY_PATH="${APP_STORE_CONNECT_KEY_PATH:-}"
APP_STORE_CONNECT_KEY_ID="${APP_STORE_CONNECT_KEY_ID:-}"
APP_STORE_CONNECT_ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-}"

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

AUTHENTICATION_ARGS=()
if [[ -n "$APP_STORE_CONNECT_KEY_PATH" || -n "$APP_STORE_CONNECT_KEY_ID" || -n "$APP_STORE_CONNECT_ISSUER_ID" ]]; then
    if [[ -z "$APP_STORE_CONNECT_KEY_PATH" || -z "$APP_STORE_CONNECT_KEY_ID" || -z "$APP_STORE_CONNECT_ISSUER_ID" ]]; then
        echo "APP_STORE_CONNECT_KEY_PATH, APP_STORE_CONNECT_KEY_ID, and APP_STORE_CONNECT_ISSUER_ID must be set together." >&2
        exit 2
    fi
    if [[ ! -f "$APP_STORE_CONNECT_KEY_PATH" ]]; then
        echo "App Store Connect key was not found at $APP_STORE_CONNECT_KEY_PATH" >&2
        exit 2
    fi
    AUTHENTICATION_ARGS=(
        -authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH"
        -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID"
        -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"
    )
fi

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$ZIP_PATH"

if [[ -z "$EXPORT_OPTIONS_PLIST" ]]; then
    EXPORT_OPTIONS_PLIST="$(mktemp "$ROOT/.build/export-options.plist.XXXXXX")"
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
    -destination "$ARCHIVE_DESTINATION"
    SKIP_INSTALL=NO
)

if [[ -n "$DEVELOPMENT_TEAM" ]]; then
    ARCHIVE_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi
if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    ARCHIVE_ARGS+=(-allowProvisioningUpdates)
fi
if [[ "$ALLOW_PROVISIONING_DEVICE_REGISTRATION" == "1" ]]; then
    ARCHIVE_ARGS+=(-allowProvisioningDeviceRegistration)
fi
ARCHIVE_ARGS+=("${AUTHENTICATION_ARGS[@]}")

DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcodebuild archive "${ARCHIVE_ARGS[@]}"

EXPORT_ARGS=(
    -exportArchive
    -archivePath "$ARCHIVE_PATH"
    -exportPath "$EXPORT_PATH"
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
)
if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    EXPORT_ARGS+=(-allowProvisioningUpdates)
fi
if [[ "$ALLOW_PROVISIONING_DEVICE_REGISTRATION" == "1" ]]; then
    EXPORT_ARGS+=(-allowProvisioningDeviceRegistration)
fi
EXPORT_ARGS+=("${AUTHENTICATION_ARGS[@]}")

if ! DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcodebuild "${EXPORT_ARGS[@]}"; then
    if [[ "$ALLOW_NOTARIZATION_SKIP" != "1" ]]; then
        exit 1
    fi
    ARCHIVED_APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' -type d -print -quit 2>/dev/null || true)"
    if [[ -z "$ARCHIVED_APP_PATH" ]]; then
        echo "Archive export failed and no archived app was found for local development packaging." >&2
        exit 3
    fi
    echo "Archive export failed; using archived app for local development only."
    mkdir -p "$EXPORT_PATH"
    ditto "$ARCHIVED_APP_PATH" "$EXPORT_PATH/$(basename "$ARCHIVED_APP_PATH")"
fi

APP_PATH="$(find "$EXPORT_PATH" -maxdepth 2 -name '*.app' -type d -print -quit)"
if [[ -z "$APP_PATH" ]]; then
    echo "Export succeeded, but no .app was found in $EXPORT_PATH" >&2
    exit 3
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
APP_SIGNATURE_DETAILS="$(codesign -d --verbose=4 "$APP_PATH" 2>&1)"
if ! grep -Eiq "flags=.*runtime|Runtime Version" <<<"$APP_SIGNATURE_DETAILS"; then
    echo "$APP_SIGNATURE_DETAILS" >&2
    echo "Exported app is not using the hardened runtime." >&2
    exit 4
fi

EXTENSION_PATH="$APP_PATH/Contents/PlugIns/FloppyFileProviderExtension.appex"
if [[ ! -d "$EXTENSION_PATH" ]]; then
    echo "Exported app is missing FloppyFileProviderExtension.appex." >&2
    exit 4
fi
codesign --verify --strict --verbose=2 "$EXTENSION_PATH"
if ! codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q "com.apple.security.application-groups"; then
    echo "Exported app is missing App Group entitlements." >&2
    exit 4
fi
if ! codesign -d --entitlements :- "$EXTENSION_PATH" 2>/dev/null | grep -q "com.apple.security.application-groups"; then
    echo "File Provider extension is missing App Group entitlements." >&2
    exit 4
fi
if ! spctl --assess --type execute --verbose "$APP_PATH"; then
    if [[ "$ALLOW_NOTARIZATION_SKIP" == "1" ]]; then
        echo "Gatekeeper assessment failed for a local development build; continuing because ALLOW_NOTARIZATION_SKIP=1."
    else
        exit 4
    fi
fi

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
    if [[ "$ALLOW_NOTARIZATION_SKIP" == "1" ]]; then
        echo "Notarization skipped for local development only. Set NOTARY_PROFILE, or APPLE_ID + APPLE_PASSWORD + NOTARY_TEAM_ID for release builds."
        echo "$APP_PATH"
        exit 0
    fi
    echo "Notarization credentials are required for signed release builds." >&2
    echo "Set NOTARY_PROFILE, or APPLE_ID + APPLE_PASSWORD + NOTARY_TEAM_ID. Use ALLOW_NOTARIZATION_SKIP=1 only for local development." >&2
    exit 4
fi

xcrun stapler staple "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --verify --strict --verbose=2 "$EXTENSION_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "$APP_PATH"
echo "$ZIP_PATH"
