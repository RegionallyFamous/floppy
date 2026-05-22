# Floppy

Floppy is a private WordPress-owned file drive with a macOS companion app.

This repository contains:

- `floppy/`: the WordPress plugin for private file storage, Desktop Mode integration, sync APIs, device tokens, quotas, audit logs, and diagnostics.
- `FloppyMac/`: the Swift macOS companion app and File Provider source target for Finder-native sync.

## GitHub-First Onboarding

Floppy for Mac starts from a GitHub-hosted plugin ZIP:

1. Enter the WordPress site URL.
2. Enter the GitHub release ZIP URL for the Floppy plugin.
3. Approve Floppy through WordPress' native Application Password screen.
4. Floppy for Mac downloads and reveals the ZIP, opens WordPress' plugin upload screen, then polls until the plugin is installed.
5. Floppy activates the plugin, creates a scoped device token, revokes the temporary Application Password, and stores only the Floppy token in Keychain.

WordPress core does not install arbitrary GitHub ZIP URLs through `/wp/v2/plugins`; that endpoint installs WordPress.org slugs. The GitHub-first flow keeps the source on GitHub while preserving a browser-approved plugin upload step.

## Quick Checks

```bash
find floppy -name '*.php' -print0 | xargs -0 -n1 php -l
node --check floppy/assets/js/desktop-mode.js
swift build --package-path FloppyMac
swift test --package-path FloppyMac
```

