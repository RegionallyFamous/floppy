# Floppy Load Fixtures

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

## Acceptance Targets

These targets are initial budgets for Floppy load work. They should be tightened
after real schema and production hardware baselines exist.

| Scenario | Generator target | Metadata/API target | Sync target |
| --- | --- | --- | --- |
| `10k` | Describe instantly; seed JSONL in under 5 seconds on a developer laptop. | First page, owner-filtered page, and exact path lookup p95 under 150 ms. | Delta scan for 1,000 changed rows under 1 second. |
| `100k` | Seed JSONL/CSV in under 30 seconds and SQL without memory growth above 128 MB. | Indexed list/search p95 under 250 ms with stable pagination. | Desktop/Finder delta scan for 5,000 changed rows under 3 seconds. |
| `1m` | Stream fixture output without OOM; direct SQL import should remain batchable and resumable. | Indexed owner/path/sync-state queries p95 under 500 ms; no full-table scan on hot paths. | Delta scan for 25,000 changed rows under 10 seconds and conflict listing under 2 seconds. |

Minimum pass criteria:

- Metadata remains private by default in every fixture row.
- Fixture generation works from PHP CLI without WordPress, Composer, or network
  access.
- Large scenarios stream records instead of building large in-memory arrays.
- Import runs can be repeated with the same seed and produce the same row ids.
- Test results report scenario, record count, seed, import duration, query p95,
  peak memory, and database/index notes.

## Next Harness Steps

Once the plugin schema exists, add thin wrappers outside this fixture generator
that import the JSONL/CSV/SQL into the chosen store, run query plans, and record
timings. Keep this file focused on the portable metadata fixture so load tests
can run before WordPress is available.
