# Mac Public Beta Release Evidence

Floppy's Mac beta is only release-ready when the app can prove the signed Finder-native build is present, the File Provider helper is embedded, entitlements match, notarization is configured, hardened runtime is active, nested signatures verify, and the exported artifacts are verifiable.

Generate the local evidence bundle:

```bash
FloppyMac/Scripts/release-evidence.sh
```

The script writes:

```text
FloppyMac/.build/release-evidence/floppy-mac-release-evidence.json
```

For a completed archive, pass the exported app and ZIP:

```bash
APP_PATH=FloppyMac/.build/export/Floppy.app \
ZIP_PATH=FloppyMac/.build/FloppyMac-notarization.zip \
FloppyMac/Scripts/release-evidence.sh
```

The report includes redacted paths, pass/warn/fail/skipped counts, Xcode availability, project/workspace detection, extension embedding, App Group entitlements, File Provider plist validation, signing identity availability, notarization credential readiness, strict codesign verification, embedded extension verification, and notarization ZIP presence.

`ready_for_public_beta` is only true when every release evidence check passes without skipped items. Notarization credentials, strict codesign verification, nested extension signature verification, and exported app shape are hard failures for public beta evidence. Warnings are allowed for local development, but public beta evidence should have no failures and no skipped checks.
