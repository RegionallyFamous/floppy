# Public GitHub Beta

The first public beta is GitHub-first. Users install the WordPress plugin from a GitHub ZIP and connect the Mac app to their own WordPress site.

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
- Upload sessions enforce chunk caps, file size limits, MIME validation, dangerous extension checks, and quota errors.
- Replacement sessions handle large Finder edits without whole-file in-memory uploads.
- Stale Finder edits create local conflict copies instead of silently overwriting.
- Sync expired cursors return HTTP `410` and tell clients to re-enumerate.
- Finder item IDs use Floppy UUIDs, with legacy numeric lookup only as a compatibility fallback.
- Export jobs run asynchronously and expose status/download URLs without leaking private storage keys.
