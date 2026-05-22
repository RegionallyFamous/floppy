# Floppy for Mac

Floppy for Mac is the native companion for the WordPress Floppy plugin.

This source tree includes:

- `FloppyCore`: REST client, models, browser-approval parsing, Keychain token storage, download-origin validation, GitHub ZIP validation, and a local SQLite ledger with JSON migration.
- `FloppyMac`: a SwiftUI container app for connecting WordPress sites, viewing sync state, and testing the server API.
- `FloppyFileProvider`: File Provider extension source scaffold for Finder-native sync.
- `Packaging`: app Info.plist, entitlements, icon assets, and a local bundle script.

## Build With Command Line Tools

```bash
swift build --package-path FloppyMac
swift test --package-path FloppyMac
FloppyMac/Scripts/bundle-app.sh
```

With full Xcode installed, run the doctor first:

```bash
FloppyMac/Scripts/xcode-doctor.sh
```

If `xcode-select` still points at Command Line Tools, switch it:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

SwiftPM builds the app executable and local `.app` bundle. Building the File Provider extension bundle, signing with a Developer ID, enabling entitlements, and notarizing require full Xcode.

## Archive, Sign, And Notarize

Use a real Xcode project or workspace that contains both the app target and the File Provider extension target:

```bash
XCODE_PROJECT=/path/to/FloppyMac.xcodeproj \
SCHEME=FloppyMac \
DEVELOPMENT_TEAM=TEAMID12345 \
NOTARY_PROFILE=floppy-notary \
FloppyMac/Scripts/archive-notarize.sh
```

See `docs/xcode-signing-ready.md` for target setup and `docs/archive-sign-notarize.md` for export options, notarytool setup, and manual verification commands.

## Package The WordPress Plugin ZIP

The GitHub-first onboarding expects a plugin ZIP whose root directory is `floppy/` and whose main file is `floppy/floppy.php`.

```bash
FloppyMac/Scripts/package-wordpress-plugin.sh
```

This writes `dist/floppy.zip`, suitable for attaching to a GitHub release as `floppy.zip`.

## Connect Flow

1. Start Floppy for Mac.
2. Enter a WordPress site URL.
3. Enter the GitHub release ZIP URL for the Floppy plugin and confirm the main plugin file, usually `floppy/floppy.php`.
4. Click **Install & Connect**.
5. WordPress opens its native Application Password authorization screen.
6. Floppy for Mac downloads the GitHub ZIP, reveals it in Finder, opens WordPress' plugin upload screen, and polls WordPress until the plugin appears.
7. After the admin installs the ZIP in the browser, Floppy activates the plugin through `/wp/v2/plugins/{plugin}` when needed.
8. The app calls Floppy's `/devices/authorize` endpoint to exchange the temporary WordPress credential for a scoped Floppy device token.
9. The temporary Application Password is revoked, and the scoped device token is stored in Keychain.
10. On disconnect, the app calls the Floppy device revoke endpoint before removing local Keychain, File Provider, and ledger state.

For the browser-only approval fallback, WordPress now returns a one-time `floppy://device-approved?...code=...` callback. The Mac app exchanges that short-lived code over HTTPS at `/floppy/v1/devices/exchange`, so raw device tokens are not placed in admin URLs.

WordPress core does not install arbitrary GitHub ZIP URLs through `/wp/v2/plugins`; that endpoint installs WordPress.org slugs. The GitHub-first flow therefore keeps the GitHub ZIP source while using WordPress' native upload screen for the one browser-approved install step.

The GitHub ZIP URL must be an HTTPS GitHub release asset URL. The downloaded ZIP is validated before upload guidance continues, including its central directory, root folder, and configured plugin main file.

## Finder Sync

The File Provider extension source is present, but it must be added to an Xcode app-extension target to create the Finder-native domain. File Provider item identifiers use stable Floppy UUIDs (`floppy:item:{uuid}`) with legacy numeric ID lookup retained only for migration. See `docs/file-provider-extension.md`.
