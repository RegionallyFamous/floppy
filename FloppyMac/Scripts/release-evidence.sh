#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCODE_PROJECT="${XCODE_PROJECT:-}"
XCODE_WORKSPACE="${XCODE_WORKSPACE:-}"
APP_PATH="${APP_PATH:-}"
ZIP_PATH="${ZIP_PATH:-$ROOT/.build/FloppyMac-notarization.zip}"
OUTPUT_PATH="${OUTPUT_PATH:-$ROOT/.build/release-evidence/floppy-mac-release-evidence.json}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_PASSWORD="${APPLE_PASSWORD:-}"
NOTARY_TEAM_ID="${NOTARY_TEAM_ID:-${DEVELOPMENT_TEAM:-}}"

json_escape() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '%s' "$value"
}

redact_path() {
    local value="${1:-}"
    if [[ -n "${HOME:-}" && "$value" == "$HOME"* ]]; then
        printf '~%s' "${value#"$HOME"}"
    else
        printf '%s' "$value"
    fi
}

checks=()

add_check() {
    local id="$1"
    local status="$2"
    local message="$3"
    local evidence="${4:-}"
    checks+=("{\"id\":\"$(json_escape "$id")\",\"status\":\"$(json_escape "$status")\",\"message\":\"$(json_escape "$message")\",\"evidence\":{\"detail\":\"$(json_escape "$evidence")\"}}")
}

if [[ -z "$XCODE_PROJECT" && -z "$XCODE_WORKSPACE" ]]; then
    XCODE_PROJECT="$(find "$ROOT" -maxdepth 2 -name '*.xcodeproj' -print -quit)"
fi

if [[ -x "$XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    version="$("$XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" -version 2>/dev/null | tr '\n' ' ')"
    add_check "xcodebuild" "pass" "Full Xcode is available." "$version"
else
    add_check "xcodebuild" "fail" "Full Xcode is required for signed File Provider builds." "$XCODE_DEVELOPER_DIR"
fi

if [[ -n "$XCODE_WORKSPACE" && -d "$XCODE_WORKSPACE" ]]; then
    add_check "xcode-container" "pass" "Xcode workspace found." "$(redact_path "$XCODE_WORKSPACE")"
elif [[ -n "$XCODE_PROJECT" && -d "$XCODE_PROJECT" ]]; then
    add_check "xcode-container" "pass" "Xcode project found." "$(redact_path "$XCODE_PROJECT")"
else
    add_check "xcode-container" "fail" "No Xcode project or workspace was found for archive export." "$(redact_path "$ROOT")"
fi

if grep -q "FloppyFileProviderExtension" "$ROOT/project.yml" && grep -q "embed: true" "$ROOT/project.yml"; then
    add_check "extension-embedding" "pass" "The app target declares the File Provider extension as embedded." "project.yml"
else
    add_check "extension-embedding" "fail" "The File Provider extension must be embedded in the app target." "project.yml"
fi

if grep -q "com.floppy.mac.sync" "$ROOT/Packaging/FloppyMac.entitlements" && grep -q "com.floppy.mac.sync" "$ROOT/Extension/FloppyFileProvider.entitlements"; then
    add_check "app-groups" "pass" "App and extension entitlements include the shared App Group." "com.floppy.mac.sync"
else
    add_check "app-groups" "fail" "App Group entitlement is missing from app or extension entitlements." "com.floppy.mac.sync"
fi

if /usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$ROOT/Extension/Info.plist" 2>/dev/null | grep -q "com.apple.fileprovider-nonui"; then
    add_check "extension-plist" "pass" "The extension Info.plist declares a non-UI File Provider extension." "Extension/Info.plist"
else
    add_check "extension-plist" "fail" "The extension Info.plist is not configured as a non-UI File Provider extension." "Extension/Info.plist"
fi

if [[ -x "$ROOT/Scripts/archive-notarize.sh" ]]; then
    add_check "archive-script" "pass" "Archive and notarization script is executable." "Scripts/archive-notarize.sh"
else
    add_check "archive-script" "fail" "Archive and notarization script is missing or not executable." "Scripts/archive-notarize.sh"
fi

identity_output="$(security find-identity -v -p codesigning 2>/dev/null || true)"
identity_count="$(printf '%s\n' "$identity_output" | { grep -E '^[[:space:]]+[0-9]+\)' || true; } | wc -l | tr -d ' ')"
if [[ "${identity_count:-0}" -gt 0 ]]; then
    add_check "code-signing-identity" "pass" "At least one valid code-signing identity is available." "$identity_count identity(s)"
else
    add_check "code-signing-identity" "warn" "No local code-signing identity was found; signing must happen on a configured Mac." "0 identities"
fi

if [[ -n "$NOTARY_PROFILE" || ( -n "$APPLE_ID" && -n "$APPLE_PASSWORD" && -n "$NOTARY_TEAM_ID" ) ]]; then
    add_check "notarization-credentials" "pass" "Notarization credentials are configured for this run." "configured"
else
    add_check "notarization-credentials" "fail" "Notarization credentials are required for public beta release evidence." "set NOTARY_PROFILE or Apple ID credentials"
fi

if [[ -n "$APP_PATH" ]]; then
    if codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null 2>&1; then
        add_check "codesign-verify" "pass" "Exported app passes strict codesign verification." "$(redact_path "$APP_PATH")"
    else
        add_check "codesign-verify" "fail" "Exported app failed strict codesign verification." "$(redact_path "$APP_PATH")"
    fi
else
    add_check "codesign-verify" "skipped" "No APP_PATH was supplied for exported app verification." "APP_PATH"
fi

if [[ -n "$APP_PATH" && -d "$APP_PATH/Contents/PlugIns/FloppyFileProviderExtension.appex" ]]; then
    add_check "embedded-extension-artifact" "pass" "Exported app contains the File Provider extension bundle." "$(redact_path "$APP_PATH")"
    if codesign --verify --strict --verbose=2 "$APP_PATH/Contents/PlugIns/FloppyFileProviderExtension.appex" >/dev/null 2>&1; then
        add_check "nested-extension-signature" "pass" "Embedded File Provider extension passes codesign verification." "FloppyFileProviderExtension.appex"
    else
        add_check "nested-extension-signature" "fail" "Embedded File Provider extension failed codesign verification." "FloppyFileProviderExtension.appex"
    fi
elif [[ -n "$APP_PATH" ]]; then
    add_check "embedded-extension-artifact" "fail" "Exported app does not contain FloppyFileProviderExtension.appex." "$(redact_path "$APP_PATH")"
else
    add_check "embedded-extension-artifact" "skipped" "No APP_PATH was supplied for extension artifact verification." "APP_PATH"
fi

if [[ -f "$ZIP_PATH" ]]; then
    add_check "notarization-zip" "pass" "Notarization ZIP exists." "$(redact_path "$ZIP_PATH")"
else
    add_check "notarization-zip" "skipped" "No notarization ZIP was found yet." "$(redact_path "$ZIP_PATH")"
fi

passed=0
warnings=0
failed=0
skipped=0
for check in "${checks[@]}"; do
    case "$check" in
        *'"status":"pass"'*) passed=$((passed + 1)) ;;
        *'"status":"warn"'*) warnings=$((warnings + 1)) ;;
        *'"status":"fail"'*) failed=$((failed + 1)) ;;
        *'"status":"skipped"'*) skipped=$((skipped + 1)) ;;
    esac
done

ready=false
if [[ "$failed" -eq 0 && "$skipped" -eq 0 ]]; then
    ready=true
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
{
    printf '{\n'
    printf '  "format": "floppy-mac-release-evidence-v2",\n'
    printf '  "generated_at": "%s",\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '  "project_path": "%s",\n' "$(json_escape "$(redact_path "$ROOT")")"
    printf '  "app_path": "%s",\n' "$(json_escape "$(redact_path "$APP_PATH")")"
    printf '  "zip_path": "%s",\n' "$(json_escape "$(redact_path "$ZIP_PATH")")"
    printf '  "summary": {"passed": %d, "warnings": %d, "failed": %d, "skipped": %d, "ready_for_public_beta": %s},\n' "$passed" "$warnings" "$failed" "$skipped" "$ready"
    printf '  "checks": [\n'
    for index in "${!checks[@]}"; do
        suffix=","
        if [[ "$index" -eq $((${#checks[@]} - 1)) ]]; then
            suffix=""
        fi
        printf '    %s%s\n' "${checks[$index]}" "$suffix"
    done
    printf '  ]\n'
    printf '}\n'
} > "$OUTPUT_PATH"

echo "$OUTPUT_PATH"
