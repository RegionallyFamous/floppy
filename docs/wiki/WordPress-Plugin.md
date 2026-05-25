# WordPress Plugin

The WordPress plugin is the authoritative storage and permissions system for Floppy.

## Requirements

- WordPress 7.0+.
- PHP 8.3+.
- Desktop Mode installed and active (`desktop-mode` plugin dependency).
- REST API enabled.
- HTTPS for production private sync and device tokens.
- A database engine capable of the Floppy custom tables and indexes.
- Private storage protection for `wp-content/uploads/floppy-private/`.

Local loopback Studio sites are allowed for smoke tests, but production and LAN-accessible sites must pass private-storage probes before real sync is trusted.

## Storage Model

- Private blobs live under the Floppy private storage root.
- Blob paths are sharded by opaque UUID-derived keys to avoid huge filesystem directories.
- Media Library attachments are retained for WordPress interoperability.
- Custom Floppy tables are used for hot file-system queries, sync state, device tokens, jobs, audit logs, upload sessions, and tombstones.

## Private Storage Protection

Floppy writes private blobs under `wp-content/uploads/floppy-private/` and then serves files only through authenticated REST endpoints. Production servers must block direct HTTP access to that directory.

Apache-compatible hosts usually honor the `.htaccess` file Floppy writes automatically:

```apache
Require all denied
Deny from all
```

Nginx hosts need an explicit server rule:

```nginx
location ^~ /wp-content/uploads/floppy-private/ {
    deny all;
    return 403;
}
```

Local loopback Studio sites may show a warning instead of a hard failure so upload/sync smoke tests can run on `localhost`. That exception must not be used for production or LAN-accessible sites.

## Desktop Mode And HTTPS Checks

- Desktop Mode is a required plugin dependency because Floppy's browser control surface is registered as a Desktop Mode native window and launcher.
- Finder-native sync uses Floppy's REST API, but the WordPress plugin still declares Desktop Mode as a required dependency for the beta package.
- HTTPS is required for production device tokens and private file sync.
- `http://localhost` and loopback IPs are allowed only for local Studio smoke tests.

## Filesystem Tables

- `floppy_files`: file metadata, content versions, storage keys, and attachment links.
- `floppy_folders`: folder metadata and hierarchy.
- `floppy_item_names`: sibling-name reservations across files and folders.
- `floppy_sync_events`: append-only change feed.
- `floppy_tombstones`: delayed deletion replay.
- `floppy_upload_sessions`: resumable upload state.
- `floppy_jobs`: async work queue.

## REST API Notes

- Numeric routes remain for backward compatibility.
- UUID lookup is available through `/floppy/v1/items/{uuid}`.
- File and folder DTOs include `parent_uuid` so Mac clients can avoid numeric parent identity.
- Metadata mutations require `metadata_version` and use compare-and-swap writes.
- Large edited files use `POST /floppy/v1/files/{id}/replace-sessions` with `content_version`, `total_size`, optional `content_hash`, and optional `mime_type`.
- Replacement sessions reuse the chunk and complete routes, complete through `content_version` CAS, emit `file.updated`, update Media Library attachment pointers, and clean up the old private blob.
- Upload-session DTOs include `operation` so clients can distinguish `create` and `replace` flows.
- Retained versions are listed through `/files/{id}/versions`, restored through `/files/{id}/versions/{version_id}/restore`, and downloaded through `/files/{id}/versions/{version_id}/download`; responses include authenticated URLs only and never expose `storage_key`.
- Conflict lifecycle updates support both `/conflicts/{uuid}/actions` with Mac action names and the older `/conflicts/{uuid}/resolve` route with server lifecycle verbs.
- The recovery center lives at `/floppy/v1/recovery`. It returns current-user-owned Recents, Trash, retained versions, open conflicts, recovery activity, export job status, and a trust block. It is authenticated, capability-checked, and redacted: no `storage_key`, private blob path, or export storage key is returned.
- Sync clients should treat `410 floppy_sync_anchor_expired` as a required full re-enumeration.
- Export creation returns `202` with a `job_uuid`, `status_url`, and eventual `download_url`.

## Operations

- Large recursive folder trash/delete/restore operations are queued when they exceed the inline operation limit.
- Background jobs claim work atomically and retry transient failures with backoff.
- Export jobs write a manifest into private storage and serve it only through authenticated endpoints.
- Daily maintenance cleans expired upload sessions, probes private storage protection, and compacts sync events only when active device cursors allow it.

## Maintenance And Debug

- The admin screen can download a repair dry run, run safe additive repairs, and export a redacted debug bundle.
- Repair checks cover missing item-name reservations, orphaned reservations, stale upload sessions, attachment link drift, and orphaned blob counts.
- Debug bundles include compatibility checks, schema validation, repair dry-run output, device/job counts, quota settings, Desktop Mode status, and redacted audit metadata.
- Debug bundles and release evidence include a recovery summary: trash counts, open conflicts, retained-version quota impact, restore/export activity counts, and private-storage probe freshness.
- Maintenance responses never include private blob paths or `storage_key` values.

## CI And Release Gates

- Composer metadata validation, security audit, and safe dependency freshness checks run in CI.
- PHP linting, WordPress compatibility checks, and WordPress PHPUnit/MySQL tests run before release.
- A 10k load-budget smoke run is required on every CI push.
- The 100k load-budget run is required before a public beta tag.
- Plugin ZIP validation must preserve `floppy/floppy.php` and exclude development, test, Composer, and CI artifacts.
