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
- Finder edits use resumable replacement sessions instead of whole-file multipart uploads.
- The client computes SHA-256, creates an upload or replacement session, sends bounded chunks, and completes the session.
- Downloads are constrained to the connected site/rest origin and reject unsafe redirects.
- The legacy multipart replacement endpoint remains only for compatibility with older clients.

## Finder Signaling

After sync, conflict creation, upload completion, delete, move, and rename, the app signals the File Provider working set plus active folder enumerators from the ledger so Finder can refresh without user action.

## Local Conflict Copies

- Stale Finder writes that receive `409` or `428` keep the user-edited bytes locally.
- The File Provider creates a Finder-visible local item named `Original Name (Floppy conflict YYYY-MM-DD HH.mm.ss).ext`.
- Local conflict item identifiers use `local-conflict-{uuid}` and are stored in SQLite with materialized file paths and original content versions.
- Conflict copies are local-only in this beta; syncing conflict files back to WordPress as server items is a future phase.

## Diagnostics

- Settings can export a redacted JSON diagnostics bundle.
- The bundle includes app version, selected account, redacted site/rest origins, Keychain availability, domain registry, ledger path, cursor, pending/conflict counts, active enumerators, and onboarding status.

## Xcode

The repo includes `FloppyMac/project.yml` for generating a signing-ready Xcode project with the containing app and embedded File Provider extension. See `FloppyMac/docs/xcode-signing-ready.md`.
