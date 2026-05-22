# Floppy for Mac

Floppy for Mac is the native companion for the WordPress Floppy plugin.

This source tree includes:

- `FloppyCore`: REST client, models, browser-approval parsing, Keychain token storage, and a local JSON ledger.
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

WordPress core does not install arbitrary GitHub ZIP URLs through `/wp/v2/plugins`; that endpoint installs WordPress.org slugs. The GitHub-first flow therefore keeps the GitHub ZIP source while using WordPress' native upload screen for the one browser-approved install step.

## Finder Sync

The File Provider extension source is present, but it must be added to an Xcode app-extension target to create the Finder-native domain. See `docs/file-provider-extension.md`.
