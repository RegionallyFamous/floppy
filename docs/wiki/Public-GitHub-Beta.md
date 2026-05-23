# Public GitHub Beta

The first public beta is GitHub-first. Users install the WordPress plugin from a GitHub ZIP and connect the Mac app to their own WordPress site.

Floppy does not use a hosted file, telemetry, diagnostics, or sync service. GitHub is the distribution channel; the user's WordPress site and Mac remain the product's data boundary.

## Current Baseline

- WordPress plugin target: WordPress 7.0+ and PHP 8.3+.
- macOS app target: macOS 26.0+ with Swift tools 6.2.
- The Mac app is signing-ready; public distribution requires the Developer ID, hardened runtime, notarization, stapling, and Gatekeeper release lane.
- Desktop Mode support is tested through an executable public-API harness, not string matching.
- The required CI gate runs a 10k load budget on every push; the 100k load budget is a manual release gate before beta tags; 1M metadata rows remain stress evidence before public announcements.

## Beta Goals

- Private-by-default WordPress storage for personal and team files.
- Finder-native sync through the macOS File Provider extension.
- Stable UUID item identifiers for Mac and sync clients.
- Cursor-based sync events with clear full-resync recovery.
- Export tooling so users can leave without lock-in.
- Diagnostics good enough for early adopters and support.

## Distribution

- WordPress plugin: GitHub release ZIP containing `floppy/floppy.php`.
- Mac app: signing-ready local build for beta testers, with notarized distribution as the next release lane.
- Root README: marketing only.
- Technical docs: this wiki.

## Acceptance Checks

- Plugin activates on HTTPS WordPress sites with REST API enabled.
- Direct private-file access probes fail.
- The 10k load budget runner passes in CI.
- The 100k load budget runner passes before tagging the beta.
- Upload sessions enforce chunk caps, file size limits, MIME validation, dangerous extension checks, and quota errors.
- Replacement sessions handle large Finder edits without whole-file in-memory uploads.
- Stale Finder edits create local conflict copies instead of silently overwriting.
- Sync expired cursors return HTTP `410` and tell clients to re-enumerate.
- Finder item IDs use Floppy UUIDs, with legacy numeric lookup only as a compatibility fallback.
- Export jobs run asynchronously and expose status/download URLs without leaking private storage keys.
- Export/restore preserves metadata, blobs, checksums, tombstones, and attachment links.
- The sync torture drill passes for offline edits, interrupted uploads, concurrent move/rename/delete, stale conflicts, quota failure, token revoke, and reconnect recovery.
- Mac disconnect/revoke produces a clear repair/auth state and reconnects without orphaning the File Provider domain.
- WordPress debug bundles and Mac diagnostics bundles share a support correlation ID and remain redacted.
- The Desktop Mode Release Evidence panel can download a redacted evidence JSON sidecar, and CI creates `dist/floppy-release-evidence.json`.
- The Desktop Mode hook audit passes with public `wp.desktop`, `wp.desktop.HOOKS`, and `wp.hooks` integration only.
- Strict WordPress Plugin Check passes against the built GitHub release ZIP contents.
- Composer dependency freshness passes through the safe compatibility lane. PHPUnit remains on the WordPress-compatible 9.6 line until the WordPress test harness no longer depends on APIs removed in newer PHPUnit majors.
- Swift build/tests pass on the current macOS runner, and Xcode doctor verifies the local release setup before shipping Mac artifacts.

## Required Beta Evidence

Keep these artifacts on the internal release issue for every public beta:

- `10k` CI load report and `100k` pre-tag load report.
- Private-storage probe results for the target host.
- Sync torture notes, including conflict-copy and expired-cursor results.
- Export/restore notes with checksum verification.
- Mac diagnostics bundle and WordPress debug bundle with matching
  `support_correlation_id`.
- Disconnect/revoke notes from a live WordPress site.
- Desktop Mode hook-audit report and release evidence sidecar.
