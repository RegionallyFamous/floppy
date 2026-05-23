# Desktop Mode And Release Evidence

Floppy's Desktop Mode app is the WordPress-native control surface for files, shares, conflicts, versions, sync, devices, jobs, diagnostics, and beta release evidence. It must use public Desktop Mode APIs only: `wp.desktop`, `wp.desktop.HOOKS`, and `wp.hooks`.

## Desktop Mode Smoke Evidence

The Desktop Mode shell records a redacted smoke snapshot in the Release Evidence panel:

- Native window callback registration for `floppy-drive`.
- Feature detection for native windows, command palette, OS Settings, title bar buttons, file openers, broadcasts, badges, and OS placement settings.
- Required public hook registrations for file drops, native window lifecycle, dock tiles, desktop icons, and icon context menus.
- Current support correlation ID, loaded file count, selected count, sync cursor, conflict count, endpoint availability, health, deep health, and repair dry-run status.

The shell does not read private Desktop Mode storage, scrape host DOM, patch shadow roots, or use legacy hook names.

## Panels

- **My Drive**: list-first private file browser with search, filters, sorting, keyboard selection, bounded large-list rendering, upload, folder creation, sharing, rename, download, and trash actions.
- **Shared**: exact user/role grants and recent share activity.
- **Conflicts**: conflict center using the optional conflicts endpoint when present, with sync-feed fallback for current beta sites.
- **Versions**: version-history shell using the optional versions endpoint when present, with current content and metadata versions as fallback evidence.
- **Sync**: cursor, event feed, conflict count, latest/load-more controls.
- **Devices**: approved Mac devices and revoke actions.
- **Diagnostics**: compatibility and health checks.
- **Jobs**: queue summary from deep health plus an export drill job.
- **Evidence**: release gates, Desktop Mode hook smoke, debug bundle download, repair dry-run, and client-side evidence JSON download.
- **Settings**: OS placement controls and onboarding reminders.

## CI Evidence

`node floppy/tests/desktop-mode/audit-hooks.mjs --format=json` statically checks the Desktop Mode script for required public hooks/APIs, required panels, and banned private integration patterns.

`node floppy/tests/release/build-evidence-sidecar.mjs` creates `dist/floppy-release-evidence.json` from attached evidence artifacts. In CI it includes:

- `dist/evidence/load-10k.json`
- `dist/evidence/desktop-mode-hook-audit.json`

The sidecar intentionally records artifact hashes, sizes, summaries, and missing manual gates instead of embedding full private diagnostics.

## Public Beta Tag Rule

A public beta tag needs:

- Passing CI-generated release sidecar.
- 100k load-budget sidecar attachment.
- 1M metadata stress evidence before public announcement.
- Sync torture notes from a live WordPress site.
- Private-storage probe matrix for the target host.
- Export/restore drill with checksum verification.
- Matching WordPress and Mac support correlation IDs.
- Signing/notarization proof before distributing the Mac app.
