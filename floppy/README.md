# Floppy

Floppy is a private-by-default WordPress file service designed for Desktop Mode and Finder-native macOS sync.

This repository currently contains a production-shaped WordPress plugin scaffold:

- Custom indexed tables for filesystem state, ACLs, sync events, devices, upload sessions, tombstones, audit logs, and jobs.
- Protected local upload storage with direct-access probes and sharded blob paths.
- REST namespace `/floppy/v1` for discovery, files, folders, uploads, resumable upload sessions, downloads, sharing, devices, sync changes, health, and export jobs.
- Browser-approved device tokens for macOS clients.
- Desktop Mode native window registration, launcher/script hooks, drag/drop integration, command/settings/titlebar/file-opener scripts, badges, and notifications.
- Admin diagnostics and WP-CLI repair/export helpers.
- Load fixture tooling for 10k, 100k, and 1M metadata scenarios.

## Development Checks

```bash
find floppy -name '*.php' -print0 | xargs -0 -n1 php -l
php floppy/tests/load/generate-fixture.php describe --scenario=100k
php floppy/tests/load/generate-fixture.php seed --scenario=10k --format=jsonl --output=/tmp/floppy-10k.jsonl
```

## WP-CLI

```bash
wp floppy health
wp floppy repair-schema
wp floppy verify-blobs --limit=5000
wp floppy export-manifest --path=/tmp/floppy-manifest.json
```

## macOS Client

The WordPress plugin exposes the server-side contract for a macOS File Provider app. See `docs/macos-file-provider.md` for the client architecture and sync mapping.
