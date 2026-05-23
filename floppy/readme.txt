=== Floppy ===
Contributors: floppycontributors
Tags: media, files, private storage, desktop mode, sync
Requires at least: 7.0
Tested up to: 7.0
Requires PHP: 8.3
Stable tag: 0.1.1
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Private, WordPress-owned file storage for Desktop Mode and Finder-native Mac sync.

== Description ==

Floppy brings "Freedom for your files" to WordPress. It turns a WordPress site into a private file drive where storage, permissions, metadata, device approvals, audit logs, diagnostics, and exports remain under the site owner's control.

Floppy is private by default. It keeps WordPress users as the identity source, stores file records as Media Library attachments for interoperability, and uses indexed custom tables for filesystem state, permissions, sync cursors, tombstones, audit logs, devices, upload sessions, versions, conflicts, and background jobs.

For Desktop Mode, Floppy registers a native window, launcher, command scripts, settings scripts, title-bar scripts, file-opener scripts, badges, and drag/drop integration using public Desktop Mode APIs.

For macOS, Floppy exposes REST endpoints designed for a signed File Provider client. Device authorization uses browser approval and scoped device tokens. No external cloud service is required: GitHub can distribute Floppy, but file data and sync state belong to the user's WordPress site and Mac.

== Privacy ==

Floppy stores file metadata, private blob references, device records, audit logs, and sync events in your WordPress database. Private file bytes are stored in a protected uploads path by default. Files, previews, and downloads are served through authenticated endpoints instead of public media URLs.

The macOS client design stores the approved device token in Keychain and communicates only with the WordPress site you approve.

== Installation ==

1. Confirm the site runs WordPress 7.0+ and PHP 8.3+.
2. Upload the `floppy` folder to `/wp-content/plugins/`.
3. Activate Floppy.
4. Open Floppy in wp-admin and run the health checks.
5. Install Desktop Mode for the native desktop window experience.

== Production Notes ==

Before using Floppy for production private files, confirm the health screen passes private storage probing, REST availability, HTTPS, upload limits, database table checks, and background job checks.

== Changelog ==

= 0.1.0 =
* Initial production-shaped scaffold.
