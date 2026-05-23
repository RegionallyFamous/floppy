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

The SwiftPM bundle created by `Scripts/bundle-app.sh` is useful for testing onboarding and REST upload flows, but it cannot provide the Dropbox-style Finder folder because it does not embed or sign the File Provider extension. If macOS reports that it “couldn’t communicate with a helper application,” you are almost always running an unsigned build, a SwiftPM bundle, or targets whose App Group/Team values do not match.

## Required Target Wiring

App target:

- Sources: `Sources/FloppyMac/*.swift`, `Sources/FloppyCore/*.swift`.
- Info: `Packaging/Info.plist`.
- Entitlements: `Packaging/FloppyMac.entitlements`.
- Icon: `Packaging/FloppyIcon.icns`.
- Hardened runtime: enabled for Developer ID distribution.
- Sandbox: off for the containing app. The menu app needs to reveal the user-visible File Provider folder in Finder, and a sandboxed containing app can hit `permErr` when opening `~/Library/CloudStorage/...`.

File Provider extension target:

- Sources: `Sources/FloppyFileProvider/*.swift`, `Sources/FloppyCore/*.swift`.
- Info: `Extension/Info.plist`.
- Entitlements: `Extension/FloppyFileProvider.entitlements`.
- Extension point: `com.apple.fileprovider-nonui`.
- Embedded in the containing app.
- Sandbox: on for the extension.

Both targets must share:

- App Group: `$(TeamIdentifierPrefix)com.floppy.mac.sync`.
- Keychain access group: `$(AppIdentifierPrefix)com.floppy.mac`.
- The same Developer Team.

For local development, add your Apple ID in Xcode Settings > Accounts, then select the same Team for both the `FloppyMac` app target and the `FloppyFileProviderExtension` target. Xcode must produce real entitlements; ad-hoc signing is not enough for the Finder-native File Provider helper.

## Doctor

Run this before archiving:

```bash
FloppyMac/Scripts/xcode-doctor.sh
```

The doctor builds Swift targets, runs tests, verifies the File Provider source target, and checks the signing-ready plist/entitlement files.

## Archive

See [Archive, Sign, And Notarize](archive-sign-notarize.md) for Developer ID export and notarization.
