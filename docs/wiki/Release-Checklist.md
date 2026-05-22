# Release Checklist

## WordPress Plugin

- Run `composer validate --strict`.
- Run `composer audit:composer`.
- Confirm `floppy/floppy.php` exists in the release ZIP.
- Run `composer lint:all` for PHP syntax, PHP compatibility, and WordPress API checks.
- Run Composer PHPUnit integration tests against the WordPress test suite and MySQL.
- Validate `.distignore` release ZIP shape so Composer, PHPUnit, GitHub, and test artifacts stay out of the plugin ZIP.
- Run WordPress Plugin Check before WordPress.org submission.
- Verify activation, deactivation, reinstall, and uninstall behavior.
- Verify HTTPS, REST API, upload limits, cron health, private storage, and DB table/index diagnostics.
- Download a repair dry run and debug bundle from the admin screen and confirm they do not leak `storage_key` or private paths.
- Load-test 10k and 100k metadata rows before public beta tagging.

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

## GitHub Release

- Confirm the `Floppy Beta Checks` workflow is green.
- Attach the plugin ZIP.
- Attach the Mac build artifact only when signing/notarization status is explicit.
- Link this wiki from the release notes.
- State known beta limits plainly.
