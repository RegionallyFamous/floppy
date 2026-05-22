# Xcode Signing-Ready Setup

FloppyMac is SwiftPM-first for development, but public macOS distribution needs an Xcode project or workspace that owns both targets:

- `FloppyMac`: containing app.
- `FloppyFileProvider`: File Provider extension.

## Generate A Project

The repo includes an XcodeGen spec:

```bash
cd FloppyMac
xcodegen generate
```

Open `FloppyMac.xcodeproj`, set `DEVELOPMENT_TEAM`, and confirm the generated targets match the wiring below.

## Required Target Wiring

App target:

- Sources: `Sources/FloppyMac/*.swift`, `Sources/FloppyCore/*.swift`.
- Info: `Packaging/Info.plist`.
- Entitlements: `Packaging/FloppyMac.entitlements`.
- Icon: `Packaging/FloppyIcon.icns`.
- Hardened runtime: enabled for Developer ID distribution.

File Provider extension target:

- Sources: `Sources/FloppyFileProvider/*.swift`, `Sources/FloppyCore/*.swift`.
- Info: `Extension/Info.plist`.
- Entitlements: `Extension/FloppyFileProvider.entitlements`.
- Extension point: `com.apple.fileprovider-nonui`.
- Embedded in the containing app.

Both targets must share:

- App Group: `group.com.floppy.mac`.
- Keychain access group: `$(AppIdentifierPrefix)com.floppy.mac`.
- The same Developer Team.

## Doctor

Run this before archiving:

```bash
FloppyMac/Scripts/xcode-doctor.sh
```

The doctor builds Swift targets, runs tests, verifies the File Provider source target, and checks the signing-ready plist/entitlement files.

## Archive

See [Archive, Sign, And Notarize](archive-sign-notarize.md) for Developer ID export and notarization.
