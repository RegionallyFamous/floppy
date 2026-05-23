# Floppy Load Fixtures And Query Budgets

This directory owns CLI-oriented scale fixtures for Floppy metadata. The goal is
to exercise private-by-default file metadata, Desktop Mode app state, and macOS
Finder sync identifiers without requiring a full WordPress bootstrap by default.

## Generator

`generate-fixture.php` is a self-contained PHP CLI script. It can describe a
scenario or stream deterministic seed data to stdout or a file.

```sh
php floppy/tests/load/generate-fixture.php --mode=describe --scenario=10k
php floppy/tests/load/generate-fixture.php --mode=describe --scenario=100k --format=json
php floppy/tests/load/generate-fixture.php --mode=seed --scenario=10k --format=jsonl --output=/tmp/floppy-10k.jsonl
php floppy/tests/load/generate-fixture.php --mode=seed --scenario=100k --format=csv --output=/tmp/floppy-100k.csv
php floppy/tests/load/generate-fixture.php --mode=seed --scenario=1m --format=sql --table=wp_floppy_files --output=/tmp/floppy-1m.sql
```

Supported scenarios:

| Scenario | Records | Intended use |
| --- | ---: | --- |
| `10k` | 10,000 | Local smoke test and development profiling. |
| `100k` | 100,000 | Branch acceptance for indexes, pagination, and sync deltas. |
| `1m` | 1,000,000 | Release-scale metadata gate and import rehearsal. |

The generator never loads WordPress unless a future test harness wraps it. SQL
output is a schema-neutral scaffold using the current expected metadata shape;
adjust `--table` or import mapping when the production schema is finalized.

## Fixture Shape

Each row represents one private file metadata record:

- Stable file id, site id, owner id, private visibility, path, filename, type,
  size, checksum, and version.
- Desktop Mode and Finder sync identifiers.
- Sync states distributed across `synced`, `remote-pending`, `local-only`, and
  `conflict`.
- Created, updated, last-synced, and occasional soft-deleted timestamps.

The data is deterministic for a given `--seed`, so failures can be reproduced
with the exact same command.

## Query Budget Runner

`run-query-budget.php` is the real acceptance harness for this directory. It
streams the deterministic JSONL fixture into SQLite, creates Floppy-like indexes,
runs representative metadata hot paths, records query plans, and exits non-zero
when budgets or index-use expectations fail.

```sh
php floppy/tests/load/run-query-budget.php --scenario=10k
php floppy/tests/load/run-query-budget.php --scenario=100k --format=json
php floppy/tests/load/run-query-budget.php --scenario=1m --iterations=5 --keep-db --db=/tmp/floppy-load.sqlite
```

The runner covers:

- Owner folder listing with stable cursor-style ordering.
- Exact path lookup for materialization and download checks.
- Prefix filename search for large-folder search behavior.
- Sync-delta enumeration for Desktop Mode and Finder clients.
- Conflict listing for diagnostics.
- Quota rollup and repair dry-run count queries for maintenance paths.

Reports include scenario, record count, seed, import duration, query p95, query
plans, peak memory, and budget failures. JSON output is intended for CI artifacts
and release notes; text output is easier for local profiling.

## Acceptance Targets

These targets are initial budgets for Floppy load work. They should be tightened
after real schema and production hardware baselines exist.

| Scenario | Required gate | Import target | Metadata/API target | Sync target |
| --- | --- | --- | --- | --- |
| `10k` | Every branch and PR. | Import in under 20 seconds with peak memory under 192 MB. | Hot list/search/path queries p95 under 150 ms with indexed plans. | Sync-delta query p95 under 1 second. |
| `100k` | Required before public beta tagging. | Import in under 60 seconds with peak memory under 256 MB. | Hot list/search/path queries p95 under 250 ms with indexed plans. | Sync-delta query p95 under 3 seconds. |
| `1m` | Release rehearsal and stress-path review. | Import in under 10 minutes with peak memory under 512 MB. | Hot owner/path/sync-state queries p95 under 500 ms and no full-table scan on hot paths. | Sync-delta query p95 under 10 seconds and conflict listing under 2 seconds. |

Minimum pass criteria:

- Metadata remains private by default in every fixture row.
- Fixture generation works from PHP CLI without WordPress, Composer, or network
  access.
- Large scenarios stream records instead of building large in-memory arrays.
- Import runs can be repeated with the same seed and produce the same row ids.
- Test results report scenario, record count, seed, import duration, query p95,
  peak memory, and database/index notes.
- Hot-path query plans must use an index; full table scans fail the budget.

## Release Workflow

Use `10k` in CI as the fast regression guard. Run `100k` locally or in a release
job before cutting a public beta. Run `1m` before major schema/index changes and
attach the JSON report to the release issue.

The SQLite harness is not a substitute for WordPress/MySQL integration tests. It
is the first gate: if these query shapes regress here, the branch is not ready
for the heavier WordPress REST, sync torture, export/restore, and Mac revoke
drills.
