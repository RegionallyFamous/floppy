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

## Support Correlation IDs

Every support bundle should carry a shared `support_correlation_id` so a user,
site admin, and maintainer can match the Mac diagnostics export with the
WordPress debug bundle without exposing secrets.

Correlation IDs are not authentication credentials. They should be random,
short-lived support labels that appear in:

- WordPress debug bundle metadata.
- Mac diagnostics bundle metadata.
- Recent sync or REST failure summaries.
- Release or support issue notes when a beta build is being investigated.

Do not include tokens, application passwords, private blob paths, `storage_key`,
raw local filesystem paths, or URL query strings in either bundle. Keep enough
origin and account shape to debug the issue, but redact values that could grant
access or reveal private filenames outside the authenticated item DTOs.

## Robustness Drills

Before a public beta tag, run and record:

- Sync torture: offline edits, interrupted uploads, concurrent move/rename/delete,
  stale content conflicts, expired cursor full resync, quota failure, token
  revoke, and reconnect recovery.
- Scale gates: `10k` in CI and `100k` before tagging with the load budget runner.
- Security probes: direct private-storage access, invisible item access,
  revoked-device access, dangerous MIME/extension rejection, and audit logging.
- Exit drills: export/restore with metadata, blobs, checksums, tombstones, and
  attachment links verified.
- Mac revoke drill: disconnect the app, revoke the server device token, confirm
  Finder enters a repair/auth state, then reconnect cleanly.
