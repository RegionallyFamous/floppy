# Known Limits

These are intentional beta boundaries, not product goals.

- GitHub is the only distribution channel at the start.
- The Mac app is signing-ready, but public notarized builds require a Developer ID release lane.
- File replacement still uses multipart upload instead of resumable replacement.
- Windows, mobile apps, and public share links are future phases.
- Formal regulated-data compliance is out of scope for v1.
- The first production target is 100k files per site, with 1M metadata rows used as a stress path.

## Next Improvements

- Resumable replacement sessions for large edited files.
- Full conflict-copy UX in Finder.
- Active-folder File Provider signaling.
- More WordPress REST tests around ACLs, CAS conflicts, and direct-access probes.
- A beta CI workflow for ZIP validation, PHP lint, Swift tests, and package checks.
