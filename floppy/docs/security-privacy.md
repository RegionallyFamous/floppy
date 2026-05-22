# Floppy Security and Privacy Model

Floppy is a private-by-default file service for WordPress. The baseline promise is simple: uploading a file to Floppy must not publish it, attach it to the media library, expose it through a public URL, or make it visible to another WordPress user unless the owner explicitly grants access.

This document defines the security and privacy controls required for the WordPress plugin, Desktop Mode app, REST API, and macOS Finder sync client.

## Security Principles

- Private by default: every item starts owner-only.
- Least privilege: route, item, device, and storage permissions are checked separately.
- Stable authorization: item access follows explicit grants and inherited folder grants, not path guesses.
- No public storage paths: private bytes are served only through authenticated application code.
- Revocable devices: macOS sync tokens can be revoked without changing the user's WordPress password.
- Explicit sharing: shared links and public access are disabled unless a site owner enables them.
- Auditability: security-sensitive events are logged with IDs and actors.
- Data minimization: clients store only the metadata, tokens, and cached content they need to function.

## Threat Model

Floppy must defend against:

- Anonymous users guessing download URLs.
- Authenticated users reading or modifying files they do not own.
- CSRF against wp-admin or Desktop Mode file operations.
- XSS or unsafe output leaking filenames, share links, or tokens.
- Path traversal through filenames, ZIP extraction, or move operations.
- MIME confusion and unsafe inline rendering.
- Stolen macOS device tokens.
- Stale sync clients overwriting newer content.
- Accidental publication through WordPress media, attachment pages, sitemaps, feeds, or search indexing.
- Logs, analytics, crash reports, or debug tooling capturing private filenames or tokens.

Floppy cannot fully defend against a compromised WordPress administrator, compromised server filesystem, malicious privileged plugin, or malware running as the macOS user. The product should be honest about those limits.

## WordPress Authorization Model

### Capabilities

Define Floppy-specific capabilities and map them to roles on activation:

- `floppy_read_own_files`: browse and download owned files.
- `floppy_write_own_files`: create, rename, move, upload, trash, and restore owned files.
- `floppy_share_own_files`: grant access to owned files.
- `floppy_read_shared_files`: browse and download files shared with the user.
- `floppy_write_shared_files`: modify files shared with write permission.
- `floppy_manage_devices`: view and revoke the user's own sync devices.
- `floppy_manage_service`: administer quotas, retention, storage, and global settings.

Do not use broad capabilities such as `upload_files` or `manage_options` as item-level authorization. They can gate admin screens, but every file operation still needs Floppy grant checks.

### Item Grants

Effective access is the union of:

- Owner access.
- Direct grants on the item.
- Inherited grants from parent folders.
- Administrative override, only for users with `floppy_manage_service`, and only in audited admin tools.

Grant checks must answer:

- Can this principal see the item exists?
- Can this principal read metadata?
- Can this principal download content?
- Can this principal create children?
- Can this principal modify metadata?
- Can this principal replace content?
- Can this principal trash or permanently delete?
- Can this principal share or revoke shares?

If a user lacks visibility, return the same outward behavior as a missing item. Avoid revealing private item IDs through error messages.

## REST API Requirements

Every route in `/wp-json/floppy/v1` must register a `permission_callback`. Public routes should not exist in the default product. If a future public-share feature is added, isolate it under a separate namespace or route group with separate rate limits and link-token checks.

For each request:

1. Authenticate the caller.
2. Validate the route schema.
3. Resolve the item by ID without trusting client-supplied paths.
4. Run item-level permission checks.
5. Enforce quota, storage, and policy limits.
6. Perform the operation.
7. Return only fields the caller is allowed to see.

Desktop Mode requests:

- Use WordPress cookie authentication and `X-WP-Nonce` for REST calls.
- Rely on WordPress' REST nonce handling for CSRF protection.
- Also check capabilities and item grants. A valid nonce is not authorization.

macOS requests:

- Require HTTPS.
- Use device-scoped bearer tokens or a similarly scoped credential.
- Store only a hash of the token server-side.
- Bind the token to `user_id`, `site_id`, `device_id`, scopes, issue time, last-used time, and revocation time.
- Rotate tokens on reauth and allow user-initiated revocation from WordPress.

Application Passwords can be used as a bootstrap path for early prototypes or power users, but the production macOS client should prefer Floppy-scoped device tokens so sync access can be limited and revoked independently.

## Input Validation

### Filenames

Normalize and validate all names server-side:

- Reject empty names, `.` and `..`.
- Reject path separators, null bytes, control characters, and reserved names.
- Enforce byte and character length limits.
- Normalize Unicode consistently before checking sibling uniqueness.
- Preserve display case but compare using a normalized key.
- Generate deterministic conflict names instead of overwriting siblings.

Never concatenate a user filename into a filesystem path. Resolve by `item_id` and server-owned `storage_key`.

### Metadata

- Validate all REST parameters with route `args`.
- Sanitize strings before storage.
- Escape output late in admin and Desktop Mode UI.
- Treat MIME type from the client as advisory. Detect content type server-side.
- Strip or block active content previews unless explicitly supported and sandboxed.

### Uploads

- Enforce per-file, per-user, per-site, and per-request size limits.
- Require content length or chunk sizes where possible.
- Verify chunk order, chunk size, final byte count, and final hash.
- Store incomplete uploads in a non-public temporary area.
- Expire abandoned uploads.
- Use idempotency keys for create and commit operations.
- Provide hooks for malware scanning before commit.

## Private Storage Controls

Preferred storage is outside the web root. If that is not available, store under a Floppy-private directory with defense-in-depth deny rules:

- Apache: deny direct access with `.htaccess` where supported.
- Nginx: document required `location` deny configuration.
- Object storage: use private buckets/objects and server-side authorization before signed delivery.

The application must not rely on obscurity of filenames, directories, UUIDs, or object keys. Download access always goes through Floppy authorization.

Download responses:

- Require authentication and item read permission.
- Set `Content-Disposition` safely.
- Set `X-Content-Type-Options: nosniff`.
- Use conservative inline rendering. Default to attachment for risky types.
- Support byte ranges only after authorization.
- Avoid caching private responses in shared caches. Use `Cache-Control: private`.

## Sharing Model

Sharing is off by default at the site level unless explicitly enabled.

When enabled:

- Owner-only files remain the default.
- Shares are explicit grants to WordPress users, roles, groups, or future external link principals.
- Link sharing, if added, must require high-entropy tokens, optional expiration, optional password, download limits, and audit events.
- Write sharing must be a separate permission from read sharing.
- Revocation must prevent future metadata and content access immediately.
- Revocation should notify active sync clients through the change feed so local capabilities update.

Inherited folder grants should be visible in the UI so owners understand who can access a child item.

## macOS Client Security

The macOS app and File Provider extension should be sandboxed.

Required entitlements and storage boundaries:

- App Group for the app and extension to share a metadata ledger and small coordination files.
- Keychain access group for device tokens.
- No Full Disk Access requirement.
- No broad user-selected file bookmarks except explicit import/export operations.
- No iCloud Keychain sync for Floppy device tokens unless the user explicitly opts in and the threat model is updated.

Local data:

- Device token lives in Keychain, not UserDefaults, SQLite, logs, or crash reports.
- SQLite ledger stores item IDs, versions, parent IDs, capabilities, and minimal metadata.
- Finder/File Provider may cache downloaded file content on disk. The UI must make this clear.
- Debug logs redact hostnames, usernames, filenames, and local paths by default.
- Sign out revokes the server token and removes the File Provider domain. The user chooses whether to remove downloaded local data or preserve it.

Device revocation:

- Revoked token returns `401`.
- macOS app stops sync, removes credentials, and asks the user to sign in again.
- Server records revocation actor and time.
- Change feed and pending upload endpoints reject revoked devices.

## Desktop Mode App Security

Desktop Mode is the WordPress-native control surface, not a privileged bypass.

Requirements:

- Register and open windows through public Desktop Mode APIs.
- Use Floppy REST endpoints for file data.
- Send REST nonces with cookie-authenticated writes.
- Check capabilities and grants server-side for every action.
- Use public `wp.desktop.HOOKS` and `wp.hooks` for file drops, badges, and lifecycle events.
- Never read private Desktop Mode localStorage keys.
- Never scrape host window DOM for authorization or state.
- Never place private file bytes in browser localStorage or IndexedDB.

Drag and drop uploads in Desktop Mode must follow the same upload validation, quota, and conflict rules as macOS uploads.

## Privacy Model

### Data Floppy Stores

Server:

- File and folder names.
- File sizes, MIME/content types, hashes, versions, and timestamps.
- Owner, grants, and device records.
- Private file bytes.
- Audit events for security-sensitive actions.

macOS:

- Account base URL and site UUID.
- Device ID and token in Keychain.
- Metadata cache and sync anchors.
- Finder-managed cached file contents for materialized files.
- Pending operation queue for offline changes.

Desktop Mode browser session:

- Uses the logged-in WordPress session.
- Should not persist private file bytes outside normal browser download behavior.

### Data Floppy Should Not Store By Default

- Public URLs for private content.
- Raw bearer tokens.
- WordPress passwords.
- Full local filesystem paths.
- File contents in logs.
- Filenames in analytics.
- Cross-site tracking identifiers.

### Privacy Notices

The product UI and readme should disclose:

- Files are private to the owner unless shared.
- Site administrators with sufficient server access may be able to access stored bytes.
- Finder sync caches downloaded files locally on the user's Mac.
- Removing a sync device stops future sync but may not erase preserved local copies.
- Debug mode can include more detailed metadata and should be used carefully.

## Audit Logging

Audit these events:

- Device registered, token rotated, token revoked.
- File created, downloaded, content replaced, renamed, moved, trashed, restored, permanently deleted.
- Share created, changed, expired, or revoked.
- Permission denied for sensitive operations.
- Conflict created and resolved.
- Admin override access.
- Storage backend errors affecting integrity.

Audit entries should include:

- Timestamp.
- Actor user ID.
- Device ID hash, if present.
- Item ID.
- Action.
- Result.
- Request correlation ID.
- Remote IP hash or truncated IP, depending on site policy.

Do not include file contents, raw tokens, Authorization headers, or unnecessary filenames.

## Retention and Deletion

Default retention:

- Trashed items: configurable, default 30 days.
- Tombstones and change records: configurable, default 90 days.
- Abandoned uploads: default 24 hours.
- Audit logs: configurable, default 180 days.
- Revoked device records: keep metadata without token hash for audit, default 1 year.

User deletion:

- Owner delete moves to trash unless permanent delete is explicitly requested and allowed.
- Permanent delete removes content bytes, active grants, and search/index records.
- Keep tombstones until sync retention expires so connected Macs learn about deletion.

Plugin uninstall:

- Deactivation must not delete files.
- Uninstall must require an explicit destructive setting or confirmation.
- If destructive uninstall is enabled, delete private files, metadata, upload temp files, grants, device tokens, and scheduled jobs.

Privacy export/erase:

- Register WordPress personal data exporter entries for Floppy device records, grants, and item metadata.
- Personal data erasure should either delete owned Floppy data or reassign according to site policy. Do not orphan private files without an owner.

## Operational Hardening

Production sites should enforce:

- HTTPS only for REST and downloads.
- Reasonable rate limits for authentication, downloads, uploads, and share-token routes.
- Storage quotas per user and site.
- Background integrity checks for missing blobs and checksum mismatch.
- Backups that include both metadata tables and private blob storage.
- Restore tests that verify metadata and bytes stay aligned.
- Security headers on download responses.
- Plugin health checks for private directory deny rules.
- WP-Cron or Action Scheduler jobs for upload expiry, trash cleanup, and tombstone pruning.

## Secure Development Checklist

Before release:

- Every REST route has a `permission_callback`.
- Every item operation uses grant checks, not only WordPress role checks.
- Anonymous requests cannot enumerate item IDs, metadata, or bytes.
- Private files are not stored as public media attachments.
- Direct HTTP access to storage paths is denied.
- Uploads validate size, hash, MIME, filename, quota, and permissions.
- Downloads set `nosniff`, safe disposition, and private cache headers.
- Desktop Mode writes include REST nonces.
- macOS tokens are stored only in Keychain.
- Logs redact filenames, local paths, and tokens by default.
- Conflict tests prove stale clients cannot overwrite newer server content.
- Revoking a device blocks metadata, download, upload, and change-feed access.

## References

- WordPress REST API authentication: <https://developer.wordpress.org/rest-api/using-the-rest-api/authentication/>
- WordPress custom REST endpoints and permission callbacks: <https://developer.wordpress.org/rest-api/extending-the-rest-api/adding-custom-endpoints/>
- WordPress nonces: <https://developer.wordpress.org/apis/security/nonces/>
- WordPress escaping guidance: <https://developer.wordpress.org/apis/security/escaping/>
- Apple Keychain access groups: <https://developer.apple.com/documentation/BundleResources/Entitlements/keychain-access-groups>
- Apple App Groups entitlement: <https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.application-groups>
