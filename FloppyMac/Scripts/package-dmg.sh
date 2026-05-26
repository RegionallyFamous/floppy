#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT/.build/export/FloppyMac.app}"
DMG_PATH="${DMG_PATH:-$ROOT/.build/FloppyMac.dmg}"
VOLUME_NAME="${VOLUME_NAME:-Floppy}"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-Floppy.app}"
DMG_BACKGROUND_SVG="${DMG_BACKGROUND_SVG:-$ROOT/Packaging/FloppyDMGBackground.svg}"
DMG_BACKGROUND_PNG="${DMG_BACKGROUND_PNG:-}"
DMG_WINDOW_WIDTH="${DMG_WINDOW_WIDTH:-720}"
DMG_WINDOW_HEIGHT="${DMG_WINDOW_HEIGHT:-500}"
DMG_BACKGROUND_WIDTH="${DMG_BACKGROUND_WIDTH:-720}"
DMG_BACKGROUND_HEIGHT="${DMG_BACKGROUND_HEIGHT:-460}"
DMG_BACKGROUND_SCALE="${DMG_BACKGROUND_SCALE:-2}"
DMG_ICON_SIZE="${DMG_ICON_SIZE:-96}"
DMG_APP_ICON_X="${DMG_APP_ICON_X:-190}"
DMG_APP_ICON_Y="${DMG_APP_ICON_Y:-276}"
DMG_APPLICATIONS_ICON_X="${DMG_APPLICATIONS_ICON_X:-530}"
DMG_APPLICATIONS_ICON_Y="${DMG_APPLICATIONS_ICON_Y:-276}"
DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_PASSWORD="${APPLE_PASSWORD:-}"
NOTARY_TEAM_ID="${NOTARY_TEAM_ID:-${DEVELOPMENT_TEAM:-}}"
XCRUN="${XCRUN:-/usr/bin/xcrun}"
RSVG_CONVERT="${RSVG_CONVERT:-}"
SIPS="${SIPS:-}"
TIFFUTIL="${TIFFUTIL:-}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle was not found at $APP_PATH" >&2
    exit 2
fi
if [[ ! -f "$APP_PATH/Contents/Resources/FloppyIcon.icns" ]]; then
    echo "App bundle is missing Contents/Resources/FloppyIcon.icns." >&2
    echo "Rebuild the Xcode archive so Finder does not fall back to the generic app icon." >&2
    exit 4
fi

if [[ ! -x "$XCRUN" ]]; then
    echo "xcrun was not found at $XCRUN" >&2
    echo "Set XCRUN to the xcrun executable path." >&2
    exit 2
fi

render_background() {
    local output="$1"
    local temp_dir
    local background_width
    local background_height
    local one_x_png
    local two_x_png
    local one_x_tiff
    local two_x_tiff

    if [[ -n "$DMG_BACKGROUND_PNG" ]]; then
        if [[ ! -f "$DMG_BACKGROUND_PNG" ]]; then
            echo "DMG background PNG was not found at $DMG_BACKGROUND_PNG" >&2
            exit 2
        fi
        cp "$DMG_BACKGROUND_PNG" "$output"
        return
    fi

    if [[ ! -f "$DMG_BACKGROUND_SVG" ]]; then
        echo "DMG background SVG was not found at $DMG_BACKGROUND_SVG" >&2
        exit 2
    fi

    if [[ -z "$RSVG_CONVERT" ]]; then
        RSVG_CONVERT="$(command -v rsvg-convert || true)"
    fi

    if [[ -z "$RSVG_CONVERT" ]]; then
        echo "rsvg-convert is required to render the DMG background SVG." >&2
        echo "Install librsvg or set DMG_BACKGROUND_PNG to a pre-rendered PNG." >&2
        exit 2
    fi

    if (( DMG_BACKGROUND_SCALE <= 1 )); then
        "$RSVG_CONVERT" -w "$DMG_BACKGROUND_WIDTH" -h "$DMG_BACKGROUND_HEIGHT" "$DMG_BACKGROUND_SVG" -o "$output"
        return
    fi

    if [[ -z "$SIPS" ]]; then
        SIPS="$(command -v sips || true)"
    fi
    if [[ -z "$TIFFUTIL" ]]; then
        TIFFUTIL="$(command -v tiffutil || true)"
    fi
    if [[ -z "$SIPS" || -z "$TIFFUTIL" ]]; then
        echo "sips and tiffutil are required to render a HiDPI DMG background." >&2
        echo "Set DMG_BACKGROUND_SCALE=1 or DMG_BACKGROUND_PNG to use a plain PNG background." >&2
        exit 2
    fi

    temp_dir="$(mktemp -d "$ROOT/.build/dmg-background.XXXXXX")"
    one_x_png="$temp_dir/background.png"
    two_x_png="$temp_dir/background@2x.png"
    one_x_tiff="$temp_dir/background.tiff"
    two_x_tiff="$temp_dir/background@2x.tiff"

    background_width=$((DMG_BACKGROUND_WIDTH * DMG_BACKGROUND_SCALE))
    background_height=$((DMG_BACKGROUND_HEIGHT * DMG_BACKGROUND_SCALE))
    "$RSVG_CONVERT" -w "$DMG_BACKGROUND_WIDTH" -h "$DMG_BACKGROUND_HEIGHT" "$DMG_BACKGROUND_SVG" -o "$one_x_png"
    "$RSVG_CONVERT" -w "$background_width" -h "$background_height" "$DMG_BACKGROUND_SVG" -o "$two_x_png"
    "$SIPS" -s format tiff "$one_x_png" --out "$one_x_tiff" >/dev/null
    "$SIPS" -s format tiff "$two_x_png" --out "$two_x_tiff" >/dev/null
    "$TIFFUTIL" -cathidpicheck "$one_x_tiff" "$two_x_tiff" -out "$output" >/dev/null
    rm -rf "$temp_dir"
}

detach_mount() {
    local mountpoint="${1:-}"
    if [[ -n "$mountpoint" && -d "$mountpoint" ]]; then
        hdiutil detach "$mountpoint" >/dev/null 2>&1 || true
    fi
}

customize_finder_window() {
    local mountpoint="$1"

    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {120, 120, 120 + $DMG_WINDOW_WIDTH, 120 + $DMG_WINDOW_HEIGHT}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $DMG_ICON_SIZE
        set background picture of viewOptions to POSIX file "$mountpoint/.background/$DMG_BACKGROUND_FILE_NAME"
        set position of item "$APP_BUNDLE_NAME" of container window to {$DMG_APP_ICON_X, $DMG_APP_ICON_Y}
        set position of item "Applications" of container window to {$DMG_APPLICATIONS_ICON_X, $DMG_APPLICATIONS_ICON_Y}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
}

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
"$XCRUN" stapler validate "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

mkdir -p "$(dirname "$DMG_PATH")"
STAGING_DIR="$(mktemp -d "$ROOT/.build/dmg-staging.XXXXXX")"
MOUNT_DIR=""
RW_DMG="$ROOT/.build/$(basename "${DMG_PATH%.dmg}")-rw.dmg"
cleanup() {
    detach_mount "$MOUNT_DIR"
    rm -rf "$STAGING_DIR"
    rm -f "$RW_DMG"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR/.background"
if [[ -n "$DMG_BACKGROUND_PNG" || "$DMG_BACKGROUND_SCALE" -le 1 ]]; then
    DMG_BACKGROUND_FILE_NAME="background.png"
else
    DMG_BACKGROUND_FILE_NAME="background.tiff"
fi
render_background "$STAGING_DIR/.background/$DMG_BACKGROUND_FILE_NAME"
ditto "$APP_PATH" "$STAGING_DIR/$APP_BUNDLE_NAME"
ln -s /Applications "$STAGING_DIR/Applications"
if [[ -f "$ROOT/Packaging/FloppyIcon.icns" ]]; then
    cp "$ROOT/Packaging/FloppyIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
fi
if command -v SetFile >/dev/null; then
    SetFile -a V "$STAGING_DIR/.background" || true
    if [[ -f "$STAGING_DIR/.VolumeIcon.icns" ]]; then
        SetFile -a V "$STAGING_DIR/.VolumeIcon.icns" || true
    fi
fi

rm -f "$DMG_PATH" "$RW_DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -format UDRW \
    -fs HFS+ \
    -ov \
    "$RW_DMG"

ATTACH_PLIST="$(mktemp "$ROOT/.build/dmg-attach.XXXXXX.plist")"
hdiutil attach -readwrite -noverify -noautoopen -plist "$RW_DMG" > "$ATTACH_PLIST"
MOUNT_DIR="$(/usr/libexec/PlistBuddy -c 'Print :system-entities:0:mount-point' "$ATTACH_PLIST" 2>/dev/null || true)"
if [[ -z "$MOUNT_DIR" ]]; then
    MOUNT_DIR="$(/usr/libexec/PlistBuddy -c 'Print :system-entities:1:mount-point' "$ATTACH_PLIST" 2>/dev/null || true)"
fi
rm -f "$ATTACH_PLIST"
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    echo "Could not find mounted DMG volume." >&2
    exit 4
fi
if command -v SetFile >/dev/null; then
    if [[ -f "$MOUNT_DIR/.VolumeIcon.icns" ]]; then
        SetFile -a V "$MOUNT_DIR/.VolumeIcon.icns" || true
        SetFile -a C "$MOUNT_DIR" || true
    fi
fi
customize_finder_window "$MOUNT_DIR"
sync
hdiutil detach "$MOUNT_DIR"
MOUNT_DIR=""

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$RW_DMG"
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
