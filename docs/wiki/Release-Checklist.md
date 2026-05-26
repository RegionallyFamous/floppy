# Release Checklist

## WordPress Plugin

- Run `composer validate --strict`.
- Run `composer audit:composer`.
- Run `composer deps:outdated-safe`.
- Confirm `floppy/floppy.php` exists in the release ZIP.
- Run `composer lint:all` for PHP syntax, PHP compatibility, and WordPress API checks.
- Run Composer PHPUnit integration tests against the WordPress test suite and MySQL.
- Run `php floppy/tests/load/run-query-budget.php --scenario=10k --format=json` and keep the JSON report with the release notes.
- Run `node floppy/tests/desktop-mode/audit-hooks.mjs --format=json` and keep the hook-audit report with the release notes.
- Run `node floppy/tests/release/build-evidence-sidecar.mjs --load-report=dist/evidence/load-10k.json --hook-audit=dist/evidence/desktop-mode-hook-audit.json --output=dist/floppy-release-evidence.json`.
- Validate `.distignore` release ZIP shape so Composer, PHPUnit, GitHub, and test artifacts stay out of the plugin ZIP.
- Run WordPress Plugin Check against the built release ZIP contents. Keep documented ignores limited to Floppy's custom-table and private-blob streaming architecture.
- Verify activation, deactivation, reinstall, and uninstall behavior.
- Verify HTTPS, REST API, upload limits, cron health, private storage, and DB table/index diagnostics.
- Verify Desktop Mode is installed and active before Floppy activation.
- Download a repair dry run and debug bundle from the admin screen and confirm they do not leak `storage_key` or private paths.
- Download a Release Evidence JSON sidecar from the Desktop Mode Evidence panel and confirm it contains the support correlation ID, hook smoke, endpoint availability, repair dry-run status, and no tokens or private paths.
- Run the 100k load budget before public beta tagging and fail the tag if hot-path query plans full-scan metadata tables.
- Run the private-storage probe matrix for Studio, Apache, Nginx, and the target host. Production/LAN sites must block direct access before release.
- Run an export/restore drill and confirm restored metadata, blobs, checksums, tombstones, and attachment links match the source site.
- Confirm the release target still matches the current baseline: WordPress 7.0+, PHP 8.3+, and Desktop Mode active.

### Dependency Notes

- PHPUnit intentionally stays on the WordPress-compatible 9.6 line while the WordPress test harness calls APIs removed in later PHPUnit majors.
- PHPCS intentionally stays on the latest line supported by the active WordPress Coding Standards and PHPCompatibilityWP toolchain.
- Dependency freshness failures should distinguish real security/compatibility issues from ecosystem major-version blockers before release work is stopped.

## macOS App

- Run `swift package --package-path FloppyMac resolve`.
- Run Swift build and tests with `-Xswiftc -warnings-as-errors`.
- Run the Xcode doctor script.
- Run `bash -n FloppyMac/Scripts/*.sh` and `shellcheck -x FloppyMac/Scripts/*.sh`.
- Export a Mac diagnostics bundle from Settings and confirm tokens/query strings are redacted.
- Verify File Provider extension embedding.
- Verify App Group and File Provider entitlements.
- Build an archive with Developer ID signing settings.
- Notarize before distributing outside local beta testers.
- Package the stapled app with `FloppyMac/Scripts/package-dmg.sh`.
- Verify the DMG with `xcrun stapler validate`, `codesign --verify --verbose=4`, and `hdiutil verify`.
- Confirm the mounted DMG opens with the custom Finder background, app icon, and Applications symlink.
- Test disconnect/revoke behavior against a live WordPress site.
- Run the sync torture drill against a live WordPress site: offline edit, interrupted upload, stale edit conflict, concurrent move/rename/delete, expired cursor full resync, quota failure, token revoke, and reconnect recovery.
- Confirm the Mac diagnostics bundle includes the support correlation ID, selected account, domain registry state, cursor, pending/conflict counts, active enumerators, last sync error, and last onboarding error without leaking tokens or query strings.
- Confirm the release target still matches the current baseline: macOS 26.0+ and Swift tools 6.2.

## GitHub Release

- Confirm the `Floppy Beta Checks` workflow is green.
- Confirm `dist/floppy-release-evidence.json` exists in the workflow artifacts or release issue evidence bundle.
- Attach the plugin ZIP.
- Attach the signed, notarized, stapled Mac DMG.
- Link this wiki from the release notes.
- State known beta limits plainly.
- Include the support correlation ID from the final WordPress debug bundle and Mac diagnostics bundle in the internal release issue.
- Attach or link the 10k CI load report, the 100k beta load report, sync torture notes, private-storage probe results, export/restore notes, and Mac disconnect/revoke notes.
