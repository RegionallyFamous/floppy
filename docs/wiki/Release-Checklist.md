# Release Checklist

## WordPress Plugin

- Run `composer validate --strict`.
- Run `composer audit:composer`.
- Confirm `floppy/floppy.php` exists in the release ZIP.
- Run `composer lint:all` for PHP syntax, PHP compatibility, and WordPress API checks.
- Run Composer PHPUnit integration tests against the WordPress test suite and MySQL.
- Run `php floppy/tests/load/run-query-budget.php --scenario=10k --format=json` and keep the JSON report with the release notes.
- Validate `.distignore` release ZIP shape so Composer, PHPUnit, GitHub, and test artifacts stay out of the plugin ZIP.
- Run WordPress Plugin Check before WordPress.org submission.
- Verify activation, deactivation, reinstall, and uninstall behavior.
- Verify HTTPS, REST API, upload limits, cron health, private storage, and DB table/index diagnostics.
- Download a repair dry run and debug bundle from the admin screen and confirm they do not leak `storage_key` or private paths.
- Run the 100k load budget before public beta tagging and fail the tag if hot-path query plans full-scan metadata tables.
- Run the private-storage probe matrix for Studio, Apache, Nginx, and the target host. Production/LAN sites must block direct access before release.
- Run an export/restore drill and confirm restored metadata, blobs, checksums, tombstones, and attachment links match the source site.

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
- Test disconnect/revoke behavior against a live WordPress site.
- Run the sync torture drill against a live WordPress site: offline edit, interrupted upload, stale edit conflict, concurrent move/rename/delete, expired cursor full resync, quota failure, token revoke, and reconnect recovery.
- Confirm the Mac diagnostics bundle includes the support correlation ID, selected account, domain registry state, cursor, pending/conflict counts, active enumerators, last sync error, and last onboarding error without leaking tokens or query strings.

## GitHub Release

- Confirm the `Floppy Beta Checks` workflow is green.
- Attach the plugin ZIP.
- Attach the Mac build artifact only when signing/notarization status is explicit.
- Link this wiki from the release notes.
- State known beta limits plainly.
- Include the support correlation ID from the final WordPress debug bundle and Mac diagnostics bundle in the internal release issue.
- Attach or link the 10k CI load report, the 100k beta load report, sync torture notes, private-storage probe results, export/restore notes, and Mac disconnect/revoke notes.
