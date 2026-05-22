# WordPress Plugin

The WordPress plugin is the authoritative storage and permissions system for Floppy.

## Storage Model

- Private blobs live under the Floppy private storage root.
- Blob paths are sharded by opaque UUID-derived keys to avoid huge filesystem directories.
- Media Library attachments are retained for WordPress interoperability.
- Custom Floppy tables are used for hot file-system queries, sync state, device tokens, jobs, audit logs, upload sessions, and tombstones.

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
- Sync clients should treat `410 floppy_sync_anchor_expired` as a required full re-enumeration.
- Export creation returns `202` with a `job_uuid`, `status_url`, and eventual `download_url`.

## Operations

- Large recursive folder trash/delete/restore operations are queued when they exceed the inline operation limit.
- Background jobs claim work atomically and retry transient failures with backoff.
- Export jobs write a manifest into private storage and serve it only through authenticated endpoints.
- Daily maintenance cleans expired upload sessions, probes private storage protection, and compacts sync events only when active device cursors allow it.
