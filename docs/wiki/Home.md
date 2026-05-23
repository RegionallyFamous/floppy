# Floppy Wiki

Floppy is "Freedom for your files": a WordPress-owned file system with a native Mac companion app.

This wiki holds the technical material that should not crowd the public README:

- [Public GitHub Beta](Public-GitHub-Beta.md)
- [WordPress Plugin](WordPress-Plugin.md)
- [macOS App](Mac-App.md)
- [Security And Sync](Security-And-Sync.md)
- [Desktop Mode And Release Evidence](Desktop-Mode-Release-Evidence.md)
- [Release Checklist](Release-Checklist.md)
- [Known Limits](Known-Limits.md)

The root README stays focused on the story: own your data, get rid of the SaaS, and let WordPress set your files free.

## Current Beta Baseline

- Distribution is GitHub-first: plugin ZIPs and Mac artifacts are produced from this repository.
- WordPress target: WordPress 7.0+ and PHP 8.3+.
- Mac target: macOS 26.0+ with Swift tools 6.2 and a signing-ready File Provider extension lane.
- Desktop Mode integration must use public `wp.desktop`, `wp.desktop.HOOKS`, and `wp.hooks` APIs only.
- No hosted data service is part of Floppy. File bytes, metadata, diagnostics, audit logs, device state, and sync state belong to the user's WordPress site and Mac.
- CI gates include Composer validation/audit, safe dependency freshness checks, PHP linting, WordPress PHPUnit/MySQL tests, plugin ZIP shape validation, WordPress Plugin Check, 10k load evidence, executable Desktop Mode hook auditing, Swift build/tests, and Xcode doctor checks.

## How To Read This Wiki

Start with [Public GitHub Beta](Public-GitHub-Beta.md) for the release shape, then use [WordPress Plugin](WordPress-Plugin.md) and [macOS App](Mac-App.md) for implementation details. [Release Checklist](Release-Checklist.md) is the practical go/no-go list for every beta.
