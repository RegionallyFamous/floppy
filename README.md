# Floppy

<p align="center">
  <img src="floppy/assets/images/floppy-icon-256.png" width="92" alt="Floppy icon">
</p>

<h1 align="center">Freedom for your files.</h1>

<p align="center">
  <strong>A private, WordPress-owned file drive for Mac.</strong><br>
  Dropbox-like sync ambition. WordPress as the control plane. No SaaS lock-in.
</p>

<p align="center">
  <a href="https://github.com/RegionallyFamous/floppy/actions/workflows/beta-checks.yml">
    <img src="https://github.com/RegionallyFamous/floppy/actions/workflows/beta-checks.yml/badge.svg" alt="Floppy Beta Checks">
  </a>
  <a href="docs/wiki/Home.md">
    <img src="https://img.shields.io/badge/docs-technical%20wiki-1f6f43" alt="Technical wiki">
  </a>
  <a href="docs/wiki/Public-GitHub-Beta.md">
    <img src="https://img.shields.io/badge/status-public%20beta%20buildout-0a7cff" alt="Public beta buildout">
  </a>
</p>

<p align="center">
  <a href="docs/wiki/Public-GitHub-Beta.md"><strong>Public Beta</strong></a>
  ·
  <a href="docs/wiki/Mac-App.md"><strong>Mac App</strong></a>
  ·
  <a href="docs/wiki/WordPress-Plugin.md"><strong>WordPress Plugin</strong></a>
  ·
  <a href="docs/wiki/Security-And-Sync.md"><strong>Security And Sync</strong></a>
</p>

---

## Stop renting your file system.

Floppy turns your WordPress site into a private file drive for the open web.

Your files, metadata, permissions, device approvals, audit logs, diagnostics, and exports live in infrastructure you control. The Mac app brings that drive back to the desktop, where real file work belongs: Finder, local folders, drag and drop, previews, conflicts, recovery, and sync that feels native.

This is not another cloud account. It is a path back to ownership.

## The Big Idea

| WordPress-Owned | Mac-Native | No SaaS Lock-In |
| --- | --- | --- |
| Your site is the source of truth for users, roles, files, metadata, versions, devices, audit logs, and exports. | The Mac companion app is built around Finder-native sync through Apple's File Provider direction. | GitHub distributes the software. Your WordPress site and Mac own the data boundary. |

WordPress already gives millions of people a place on the open web that they control. Floppy extends that same promise to private files.

## What Floppy Is Building

Floppy is a Dropbox-like private drive where the control plane belongs to you:

- **Private files on WordPress.** File bytes stay in protected WordPress storage and are served through authenticated endpoints.
- **A native Mac drive.** The Mac app connects your site to a Finder-native file surface.
- **WordPress users and roles.** Permissions build on the identity system site owners already understand.
- **Device approval and revocation.** Macs connect with scoped device tokens that can be revoked from WordPress.
- **Versioning, trash, conflicts, and recovery.** The product is designed around never silently overwriting user work.
- **Export without drama.** Ownership only counts if you can leave with your files and metadata.

## Why It Matters

The modern file cloud is convenient, but the bargain is strange:

- Pay forever for access to your own work.
- Store private files in someone else's control plane.
- Accept their pricing, policies, sharing model, and exit path.
- Hope the service still fits next year.

Floppy points the other way: familiar file sync, but owned by the site you control.

## The Promise

| Promise | What it means |
| --- | --- |
| **Freedom from SaaS lock-in** | Keep files in a system you can inspect, back up, migrate, and host yourself. |
| **Private by default** | Floppy is for personal and team files first, not public media galleries. |
| **Native where it counts** | Finder is the file surface. WordPress is the command center. |
| **Trust backed by evidence** | CI checks plugin shape, Desktop Mode hooks, WordPress tests, Swift builds, Xcode readiness, and load budgets. |
| **No hosted data service** | No Floppy cloud is required for file data, diagnostics, telemetry, metadata, or sync state. |
| **A real exit door** | Export and restore are product requirements, not afterthoughts. |

## Current Beta Shape

Floppy is early, ambitious public-beta software focused on one milestone first:

**Mac plus WordPress as a serious private drive replacement.**

The current build includes:

- a WordPress plugin for private storage, REST APIs, permissions, diagnostics, jobs, versions, conflicts, trash, and export/recovery tooling
- a Desktop Mode control center for My Drive, Recents, Trash, Versions, Conflicts, Shared, Sync, Devices, Diagnostics, Jobs, Evidence, and Settings
- a native macOS companion app moving toward signed and notarized File Provider distribution
- release gates for Composer validation/audit, dependency freshness, PHP lint, WordPress PHPUnit/MySQL tests, plugin ZIP shape, strict WordPress Plugin Check, Desktop Mode executable hook audit, Swift build/tests, Xcode doctor, and query-budget evidence

The goal is not a toy demo. The goal is boring reliability for private files under bad networks, stale clients, broken hosts, token revokes, quota failures, large libraries, and support/debug situations.

## Who It Is For

Floppy is for people and teams who want the convenience of a cloud drive without giving away the control plane:

- WordPress power users who want a private file drive under their own domain
- agencies and studios managing client files
- small teams already built around WordPress users and roles
- families and independent creators who want a private archive
- open-web people who are tired of renting their file cabinet

## What It Is Not Yet

Floppy is deliberately focused. The current milestone does not include Windows, mobile apps, public share links, hosted telemetry, hosted diagnostics, hosted scanning, full regulated-compliance claims, or user-facing end-to-end encryption.

First, the Mac drive has to be excellent.

## Technical Wiki

This README is the front door. The engineering details live in the wiki:

| Area | Read this |
| --- | --- |
| Public beta shape | [Public GitHub Beta](docs/wiki/Public-GitHub-Beta.md) |
| WordPress storage and APIs | [WordPress Plugin](docs/wiki/WordPress-Plugin.md) |
| macOS and File Provider direction | [Mac App](docs/wiki/Mac-App.md) |
| Security, privacy, and sync correctness | [Security And Sync](docs/wiki/Security-And-Sync.md) |
| Desktop Mode public API integration | [Desktop Mode And Release Evidence](docs/wiki/Desktop-Mode-Release-Evidence.md) |
| Release gates | [Release Checklist](docs/wiki/Release-Checklist.md) |
| Known beta boundaries | [Known Limits](docs/wiki/Known-Limits.md) |

## North Star

**Own your data. Get rid of the SaaS. Let WordPress set your files free.**
