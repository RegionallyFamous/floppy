# Archive, Sign, And Notarize Floppy For Mac

`Scripts/bundle-app.sh` creates a local SwiftPM `.app` for smoke testing. Distribution builds should come from the Xcode project or workspace that owns both the containing macOS app target and the File Provider extension target.

## Prerequisites

1. Full Xcode is installed and selected.
2. The app target and File Provider extension target share:
   - App Group: `$(TeamIdentifierPrefix)com.floppy.mac.sync` in Xcode, which resolves to `com.floppy.mac.sync` in the checked entitlements.
   - Keychain group: `$(AppIdentifierPrefix)com.floppy.mac`
3. The extension target uses `Extension/Info.plist` and `Extension/FloppyFileProvider.entitlements`.
4. The app target uses `Packaging/FloppyMac.entitlements`.
5. Developer ID Application signing is available for the selected Team ID.
6. A notarytool profile exists, or Apple ID credentials are available.

Run the doctor first:

```bash
FloppyMac/Scripts/xcode-doctor.sh
```

## Archive And Export

Point the script at the project or workspace that contains the app and extension targets:

```bash
XCODE_PROJECT=/path/to/FloppyMac.xcodeproj \
SCHEME=FloppyMac \
DEVELOPMENT_TEAM=TEAMID12345 \
FloppyMac/Scripts/archive-notarize.sh
```

For a workspace:

```bash
XCODE_WORKSPACE=/path/to/FloppyMac.xcworkspace \
SCHEME=FloppyMac \
DEVELOPMENT_TEAM=TEAMID12345 \
FloppyMac/Scripts/archive-notarize.sh
```

The script writes:

- `.build/archives/FloppyMac.xcarchive`
- `.build/export/Floppy.app` or the exported app name from Xcode
- `.build/FloppyMac-notarization.zip`
- `.build/FloppyMac.dmg` when `Scripts/package-dmg.sh` is run after notarization

## Notarization

Preferred setup:

```bash
xcrun notarytool store-credentials floppy-notary \
  --apple-id you@example.com \
  --team-id TEAMID12345 \
  --password app-specific-password
```

Then run:

```bash
NOTARY_PROFILE=floppy-notary \
XCODE_PROJECT=/path/to/FloppyMac.xcodeproj \
DEVELOPMENT_TEAM=TEAMID12345 \
FloppyMac/Scripts/archive-notarize.sh
```

The script submits the ZIP, waits for notarization, staples the exported app, verifies signing, and rebuilds the ZIP around the stapled app.

## DMG Installer

After the app is notarized and stapled, create a drag-to-Applications DMG:

```bash
APP_PATH=FloppyMac/.build/export/FloppyMac.app \
DMG_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID12345)" \
NOTARY_PROFILE=floppy-notary \
FloppyMac/Scripts/package-dmg.sh
```

`APP_BUNDLE_NAME` defaults to `Floppy.app` inside the DMG. The script verifies the stapled app, creates `.build/FloppyMac.dmg`, optionally signs and notarizes the DMG when credentials are provided, staples the DMG ticket, and validates the final image.

After export, create the beta evidence report:

```bash
APP_PATH=.build/export/Floppy.app \
ZIP_PATH=.build/FloppyMac-notarization.zip \
FloppyMac/Scripts/release-evidence.sh
```

The evidence report should have no failures or skipped checks before a public beta artifact is published.

## Manual Checks

```bash
codesign --verify --deep --strict --verbose=2 .build/export/Floppy.app
spctl --assess --type execute --verbose .build/export/Floppy.app
xcrun stapler validate .build/export/Floppy.app
```

If the File Provider extension is missing from the archive, check target membership for `Sources/FloppyFileProvider/*.swift`, the extension embedding phase, App Group entitlements, and the archive scheme's build action.
