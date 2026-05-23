# Known Limits

These are intentional beta boundaries, not product goals.

- GitHub is the only distribution channel at the start.
- The Mac app is signing-ready, but public notarized builds require a Developer ID release lane.
- Finder conflict copies are local-only; server-synced conflict files are a future phase.
- Windows, mobile apps, and public share links are future phases.
- Formal regulated-data compliance is out of scope for v1.
- End-to-end encryption is not user-facing in this round. Floppy only adds storage metadata seams so a future encryption design can be evaluated without rushing key management.
- The first production target is 100k files per site, with 1M metadata rows used as a stress path.

## Next Improvements

- Server-side conflict file promotion and conflict resolution controls.
- More WordPress REST tests around ACL inheritance, direct-access probes, and share revocation.
- Signed and notarized public Mac beta artifacts with Sparkle update feeds.
- Longer soak tests for 100k-file sites and 1M-row metadata stress fixtures.
