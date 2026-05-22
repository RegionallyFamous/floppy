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
- Delete and trash events preserve tombstones so delayed clients can catch up within the retention window.

## Conflict Policy

Floppy should never silently overwrite user work.

The current server rejects stale metadata/content writes. The Mac beta should turn those rejections into clear Finder conflict copies and diagnostics before the next wider release.
