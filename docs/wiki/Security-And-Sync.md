# Security And Sync

## Security Defaults

- Storage is private by default.
- Direct-access probes run on activation and scheduled health checks.
- Files, previews, exports, and thumbnails must be served through authenticated endpoints.
- File responses send `X-Content-Type-Options: nosniff`, private no-store cache headers, and byte-range support.
- Dangerous server-executable extensions are blocked.
- Uploads run through MIME validation and the `floppy_validate_private_upload` malware-scan hook.
- Device tokens are scoped per site, user, and device, and are revocable.

## Sync Rules

- Sync events are append-only and cursor based.
- Clients should not rescan everything unless their cursor expires.
- Expired cursors return HTTP `410` with `full_resync_required`.
- Metadata writes use compare-and-swap through `metadata_version`.
- Content replacement uses compare-and-swap through `content_version`.
- Replacement sessions keep large Finder edits resumable and still enforce MIME validation, malware-scan hooks, quota delta checks, and old-blob cleanup on completion.
- Delete and trash events preserve tombstones so delayed clients can catch up within the retention window.

## Conflict Policy

Floppy should never silently overwrite user work.

The server rejects stale metadata/content writes. The Mac beta turns stale Finder content writes into local conflict copies, refreshes the canonical server item, and records conflict counts for diagnostics.

## Diagnostics Privacy

- WordPress debug bundles are admin-only and redact private blob paths, storage keys, tokens, and raw audit metadata.
- Mac diagnostics redact tokens and URL query strings while preserving enough site, ledger, domain, cursor, pending-operation, and conflict state for support.
