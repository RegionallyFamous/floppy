# macOS App

The Mac app connects a WordPress site to Finder.

## Identity

- File Provider item identifiers are UUID based: `floppy:item:{uuid}`.
- `parent_uuid` is preferred for parent identity.
- Numeric identifiers are retained only as a compatibility fallback for older plugin responses and local ledger hydration.
- File Provider domains are tied to the Floppy device UUID so they survive token rotation.

## Ledger

- The app uses SQLite, not a JSON ledger.
- Each File Provider domain gets its own App Group ledger.
- Connected accounts are seeded into both the app ledger and the domain ledger before domain registration.
- The ledger stores accounts, items, materialized files, pending operations, conflicts, active enumerators, and sync anchors.

## Transfers

- New Finder file creates use resumable upload sessions.
- The client computes SHA-256, creates an upload session, sends bounded chunks, and completes the session.
- Downloads are constrained to the connected site/rest origin and reject unsafe redirects.
- Content replacement still uses the legacy multipart endpoint in this beta and should move to resumable replacement before a wider release.

## Finder Signaling

After sync, the app signals the File Provider working set so Finder can refresh without user action.

Future refinement should also signal active folder enumerators from the ledger for lower-latency folder updates.

## Xcode

The repo includes `FloppyMac/project.yml` for generating a signing-ready Xcode project with the containing app and embedded File Provider extension. See `FloppyMac/docs/xcode-signing-ready.md`.
