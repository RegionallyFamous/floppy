#!/usr/bin/env php
<?php
/**
 * Import deterministic Floppy load fixtures into SQLite and run query budgets.
 *
 * This harness intentionally avoids WordPress bootstrap. It gives CI and local
 * release checks a fast way to catch metadata-query regressions before the
 * heavier WordPress/MySQL and File Provider end-to-end suites run.
 */

declare(strict_types=1);

const FLOPPY_LOAD_BUDGETS = [
    '10k' => [
        'records' => 10000,
        'import_seconds' => 20.0,
        'query_p95_ms' => 150.0,
        'sync_delta_ms' => 1000.0,
        'memory_mb' => 192.0,
    ],
    '100k' => [
        'records' => 100000,
        'import_seconds' => 60.0,
        'query_p95_ms' => 250.0,
        'sync_delta_ms' => 3000.0,
        'memory_mb' => 256.0,
    ],
    '1m' => [
        'records' => 1000000,
        'import_seconds' => 600.0,
        'query_p95_ms' => 500.0,
        'sync_delta_ms' => 10000.0,
        'memory_mb' => 512.0,
    ],
];

const FLOPPY_LOAD_COLUMNS = [
    'id',
    'file_id',
    'site_id',
    'owner_id',
    'visibility',
    'path',
    'filename',
    'extension',
    'mime_type',
    'size_bytes',
    'checksum_sha256',
    'version',
    'sync_state',
    'desktop_item_id',
    'finder_item_id',
    'created_at',
    'updated_at',
    'last_synced_at',
    'deleted_at',
];

main($argv);

/**
 * @param array<int, string> $argv
 */
function main(array $argv): void
{
    $options = parse_options($argv);

    if (isset($options['help'])) {
        print_help();
        exit(0);
    }

    assert_sqlite_available();

    $scenario = strtolower((string) ($options['scenario'] ?? '10k'));
    $count = isset($options['count']) ? parse_positive_int((string) $options['count'], 'count') : null;
    $seed = parse_positive_int((string) ($options['seed'] ?? '8675309'), 'seed');
    $iterations = parse_positive_int((string) ($options['iterations'] ?? '9'), 'iterations');
    $format = strtolower((string) ($options['format'] ?? 'text'));
    $keepDb = isset($options['keep-db']);
    $failOnBudget = !isset($options['allow-budget-failures']);

    if ($count === null) {
        if (!isset(FLOPPY_LOAD_BUDGETS[$scenario])) {
            fail('Unknown scenario "' . $scenario . '". Use one of: ' . implode(', ', array_keys(FLOPPY_LOAD_BUDGETS)) . '.');
        }
        $count = FLOPPY_LOAD_BUDGETS[$scenario]['records'];
    }

    if (!in_array($format, ['text', 'json'], true)) {
        fail('--format must be text or json.');
    }

    $scenarioLabel = normalized_scenario($scenario, $count);
    $budget = budget_for($scenarioLabel, $count);
    $databasePath = (string) ($options['db'] ?? tempnam(sys_get_temp_dir(), 'floppy-load-'));
    if ($databasePath === '') {
        fail('Unable to create a temporary SQLite database path.');
    }

    $startedAt = microtime(true);
    $pdo = open_database($databasePath);
    create_schema($pdo);

    $import = import_fixture($pdo, $scenario, $count, $seed);
    create_indexes($pdo);
    $queries = run_queries($pdo, $iterations);
    $elapsed = microtime(true) - $startedAt;
    $peakMemoryMb = memory_get_peak_usage(true) / 1048576;

    $failures = evaluate_budget($import, $queries, $budget, $peakMemoryMb);
    $report = [
        'plugin' => 'floppy',
        'harness' => 'metadata-query-budget',
        'scenario' => $scenarioLabel,
        'records' => $count,
        'seed' => $seed,
        'iterations' => $iterations,
        'database' => $keepDb ? $databasePath : 'temporary',
        'import' => $import,
        'queries' => $queries,
        'budgets' => $budget,
        'peak_memory_mb' => round($peakMemoryMb, 2),
        'elapsed_seconds' => round($elapsed, 3),
        'failures' => $failures,
    ];

    if ($format === 'json') {
        fwrite(STDOUT, json_encode($report, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
    } else {
        write_text_report($report);
    }

    $pdo = null;
    if (!$keepDb && is_file($databasePath)) {
        unlink($databasePath);
    }

    if ($failOnBudget && $failures !== []) {
        exit(1);
    }
}

/**
 * @param array<int, string> $argv
 * @return array<string, string|bool>
 */
function parse_options(array $argv): array
{
    $options = [];

    foreach (array_slice($argv, 1) as $arg) {
        if ($arg === '--help' || $arg === '-h') {
            $options['help'] = true;
            continue;
        }

        if (substr($arg, 0, 2) !== '--') {
            fail('Unexpected argument "' . $arg . '". Use --help for usage.');
        }

        $parts = explode('=', substr($arg, 2), 2);
        $key = $parts[0];
        $value = $parts[1] ?? true;

        if ($key === '') {
            fail('Empty option name. Use --help for usage.');
        }

        $options[$key] = $value;
    }

    return $options;
}

function print_help(): void
{
    echo <<<HELP
Floppy metadata query budget runner

Usage:
  php floppy/tests/load/run-query-budget.php --scenario=10k
  php floppy/tests/load/run-query-budget.php --scenario=100k --format=json
  php floppy/tests/load/run-query-budget.php --count=25000 --iterations=5 --keep-db --db=/tmp/floppy-load.sqlite

Options:
  --scenario=10k|100k|1m      Named metadata scale scenario. Default: 10k.
  --count=N                   Override the named scenario record count.
  --seed=N                    Deterministic fixture seed. Default: 8675309.
  --iterations=N              Query timing iterations. Default: 9.
  --format=text|json          Output format. Default: text.
  --db=PATH                   SQLite database path. Defaults to a temporary file.
  --keep-db                   Keep the SQLite database after the run.
  --allow-budget-failures     Report failures without a non-zero exit.

The runner streams generate-fixture.php JSONL into SQLite, creates hot-path
indexes, runs representative list/search/sync/quota/repair queries, reports
query plans, and fails when budgets or indexed-query expectations regress.

HELP;
}

function assert_sqlite_available(): void
{
    if (!class_exists(PDO::class)) {
        fail('PDO is not available.');
    }

    if (!in_array('sqlite', PDO::getAvailableDrivers(), true)) {
        fail('PDO SQLite is not available. Install/enable pdo_sqlite before running the load harness.');
    }
}

function open_database(string $databasePath): PDO
{
    $pdo = new PDO('sqlite:' . $databasePath, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $pdo->exec('PRAGMA journal_mode = OFF');
    $pdo->exec('PRAGMA synchronous = OFF');
    $pdo->exec('PRAGMA temp_store = MEMORY');
    $pdo->exec('PRAGMA cache_size = -200000');

    return $pdo;
}

function create_schema(PDO $pdo): void
{
    $pdo->exec('DROP TABLE IF EXISTS floppy_files');
    $pdo->exec(
        'CREATE TABLE floppy_files (
            id INTEGER PRIMARY KEY,
            file_id TEXT NOT NULL,
            site_id INTEGER NOT NULL,
            owner_id INTEGER NOT NULL,
            visibility TEXT NOT NULL,
            path TEXT NOT NULL,
            filename TEXT NOT NULL,
            extension TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            checksum_sha256 TEXT NOT NULL,
            version INTEGER NOT NULL,
            sync_state TEXT NOT NULL,
            desktop_item_id TEXT NOT NULL,
            finder_item_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            last_synced_at TEXT NOT NULL,
            deleted_at TEXT NULL
        )'
    );
}

function create_indexes(PDO $pdo): void
{
    $pdo->exec('CREATE UNIQUE INDEX idx_floppy_files_file_id ON floppy_files (file_id)');
    $pdo->exec('CREATE INDEX idx_floppy_files_owner_listing ON floppy_files (owner_id, deleted_at, updated_at, id)');
    $pdo->exec('CREATE INDEX idx_floppy_files_owner_path ON floppy_files (owner_id, path)');
    $pdo->exec('CREATE INDEX idx_floppy_files_owner_filename ON floppy_files (owner_id, filename)');
    $pdo->exec('CREATE INDEX idx_floppy_files_site_sync ON floppy_files (site_id, sync_state, updated_at, id)');
    $pdo->exec('CREATE INDEX idx_floppy_files_conflicts ON floppy_files (sync_state, updated_at, id)');
    $pdo->exec('CREATE INDEX idx_floppy_files_deleted ON floppy_files (deleted_at, id)');
}

/**
 * @return array<string, float|int|string>
 */
function import_fixture(PDO $pdo, string $scenario, int $count, int $seed): array
{
    $startedAt = microtime(true);
    $command = [
        PHP_BINARY,
        __DIR__ . '/generate-fixture.php',
        '--mode=seed',
        fixture_selector($scenario, $count),
        '--format=jsonl',
        '--seed=' . $seed,
        '--output=-',
    ];
    $descriptorSpec = [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ];

    $process = proc_open($command, $descriptorSpec, $pipes, dirname(__DIR__, 3));
    if (!is_resource($process)) {
        fail('Unable to start fixture generator.');
    }

    fclose($pipes[0]);

    $insert = $pdo->prepare(
        'INSERT INTO floppy_files (`' . implode('`, `', FLOPPY_LOAD_COLUMNS) . '`) VALUES (:' .
        implode(', :', FLOPPY_LOAD_COLUMNS) . ')'
    );

    $rowCount = 0;
    $sampleOwnerId = null;
    $samplePath = null;
    $pdo->beginTransaction();

    while (($line = fgets($pipes[1])) !== false) {
        $line = trim($line);
        if ($line === '') {
            continue;
        }

        $row = json_decode($line, true);
        if (!is_array($row)) {
            fail('Fixture generator emitted invalid JSONL at row ' . ($rowCount + 1) . '.');
        }

        foreach (FLOPPY_LOAD_COLUMNS as $column) {
            $insert->bindValue(':' . $column, $row[$column] ?? null);
        }
        $insert->execute();

        $rowCount++;
        if ($sampleOwnerId === null) {
            $sampleOwnerId = (int) $row['owner_id'];
            $samplePath = (string) $row['path'];
        }

        if ($rowCount % 5000 === 0) {
            $pdo->commit();
            $pdo->beginTransaction();
        }
    }

    $pdo->commit();

    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    $exitCode = proc_close($process);

    if ($exitCode !== 0) {
        fail('Fixture generator failed with exit code ' . $exitCode . ': ' . trim((string) $stderr));
    }

    if ($rowCount !== $count) {
        fail('Imported ' . $rowCount . ' rows, expected ' . $count . '.');
    }

    return [
        'rows' => $rowCount,
        'seconds' => round(microtime(true) - $startedAt, 3),
        'sample_owner_id' => $sampleOwnerId ?? 1,
        'sample_path' => $samplePath ?? '',
    ];
}

/**
 * @return array<string, array<string, mixed>>
 */
function run_queries(PDO $pdo, int $iterations): array
{
    $sample = $pdo->query('SELECT owner_id, site_id, path, filename FROM floppy_files ORDER BY id LIMIT 1')->fetch();
    if (!is_array($sample)) {
        fail('No rows available for query budget run.');
    }

    $latestUpdated = (string) $pdo->query('SELECT updated_at FROM floppy_files ORDER BY updated_at DESC LIMIT 1 OFFSET 100')->fetchColumn();
    if ($latestUpdated === '') {
        $latestUpdated = '1970-01-01 00:00:00';
    }

    $queries = [
        'owner_first_page' => [
            'hot_path' => true,
            'sync_path' => false,
            'sql' => 'SELECT file_id, filename, size_bytes, updated_at FROM floppy_files WHERE owner_id = :owner_id AND deleted_at IS NULL ORDER BY updated_at DESC, id DESC LIMIT 101',
            'params' => [':owner_id' => (int) $sample['owner_id']],
        ],
        'exact_path_lookup' => [
            'hot_path' => true,
            'sync_path' => false,
            'sql' => 'SELECT file_id, version, checksum_sha256 FROM floppy_files WHERE owner_id = :owner_id AND path = :path LIMIT 1',
            'params' => [':owner_id' => (int) $sample['owner_id'], ':path' => (string) $sample['path']],
        ],
        'prefix_search' => [
            'hot_path' => true,
            'sync_path' => false,
            'sql' => 'SELECT file_id, filename FROM floppy_files WHERE owner_id = :owner_id AND filename >= :prefix AND filename < :next_prefix ORDER BY filename ASC LIMIT 50',
            'params' => [':owner_id' => (int) $sample['owner_id'], ':prefix' => 'floppy-000', ':next_prefix' => 'floppy-001'],
        ],
        'sync_delta' => [
            'hot_path' => true,
            'sync_path' => true,
            'sql' => 'SELECT file_id, sync_state, updated_at FROM floppy_files WHERE site_id = :site_id AND sync_state IN ("remote-pending", "local-only", "conflict") AND updated_at <= :updated_at ORDER BY updated_at ASC, id ASC LIMIT 5000',
            'params' => [':site_id' => (int) $sample['site_id'], ':updated_at' => $latestUpdated],
        ],
        'conflict_listing' => [
            'hot_path' => true,
            'sync_path' => false,
            'sql' => 'SELECT file_id, owner_id, updated_at FROM floppy_files WHERE sync_state = "conflict" ORDER BY updated_at DESC, id DESC LIMIT 100',
            'params' => [],
        ],
        'quota_rollup' => [
            'hot_path' => false,
            'sync_path' => false,
            'sql' => 'SELECT owner_id, SUM(size_bytes) AS used_bytes FROM floppy_files WHERE deleted_at IS NULL GROUP BY owner_id ORDER BY owner_id ASC LIMIT 100',
            'params' => [],
        ],
        'repair_dry_run_counts' => [
            'hot_path' => false,
            'sync_path' => false,
            'sql' => 'SELECT COUNT(*) AS soft_deleted FROM floppy_files WHERE deleted_at IS NOT NULL',
            'params' => [],
        ],
    ];

    $results = [];
    foreach ($queries as $name => $query) {
        $results[$name] = measure_query($pdo, $name, $query['sql'], $query['params'], (bool) $query['hot_path'], (bool) $query['sync_path'], $iterations);
    }

    return $results;
}

/**
 * @param array<string, int|string> $params
 * @return array<string, mixed>
 */
function measure_query(PDO $pdo, string $name, string $sql, array $params, bool $hotPath, bool $syncPath, int $iterations): array
{
    $statement = $pdo->prepare($sql);
    $durations = [];
    $rowCount = 0;

    for ($i = 0; $i < $iterations; $i++) {
        $startedAt = hrtime(true);
        foreach ($params as $key => $value) {
            $statement->bindValue($key, $value);
        }
        $statement->execute();
        $rows = $statement->fetchAll();
        $statement->closeCursor();
        $durations[] = (hrtime(true) - $startedAt) / 1000000;
        $rowCount = count($rows);
    }

    sort($durations);
    $p95Index = max(0, (int) ceil(count($durations) * 0.95) - 1);
    $plan = explain_query($pdo, $sql, $params);

    return [
        'name' => $name,
        'rows' => $rowCount,
        'p95_ms' => round($durations[$p95Index], 3),
        'min_ms' => round($durations[0], 3),
        'max_ms' => round($durations[count($durations) - 1], 3),
        'hot_path' => $hotPath,
        'sync_path' => $syncPath,
        'uses_index' => plan_uses_index($plan),
        'plan' => $plan,
    ];
}

/**
 * @param array<string, int|string> $params
 * @return array<int, string>
 */
function explain_query(PDO $pdo, string $sql, array $params): array
{
    $statement = $pdo->prepare('EXPLAIN QUERY PLAN ' . $sql);
    foreach ($params as $key => $value) {
        $statement->bindValue($key, $value);
    }
    $statement->execute();
    $rows = $statement->fetchAll();
    $statement->closeCursor();

    return array_map(static function (array $row): string {
        return (string) ($row['detail'] ?? implode(' ', $row));
    }, $rows);
}

/**
 * @param array<int, string> $plan
 */
function plan_uses_index(array $plan): bool
{
    foreach ($plan as $line) {
        if (stripos($line, 'floppy_files') === false) {
            continue;
        }

        if (preg_match('/SCAN\s+floppy_files/i', $line) && stripos($line, 'USING') === false) {
            return false;
        }
    }

    return true;
}

/**
 * @param array<string, float|int|string> $import
 * @param array<string, array<string, mixed>> $queries
 * @param array<string, float|int> $budget
 * @return array<int, string>
 */
function evaluate_budget(array $import, array $queries, array $budget, float $peakMemoryMb): array
{
    $failures = [];

    if ((float) $import['seconds'] > (float) $budget['import_seconds']) {
        $failures[] = 'Import took ' . $import['seconds'] . 's, budget is ' . $budget['import_seconds'] . 's.';
    }

    if ($peakMemoryMb > (float) $budget['memory_mb']) {
        $failures[] = 'Peak memory was ' . round($peakMemoryMb, 2) . ' MB, budget is ' . $budget['memory_mb'] . ' MB.';
    }

    foreach ($queries as $name => $query) {
        $p95 = (float) $query['p95_ms'];
        if ((bool) $query['hot_path'] && !(bool) $query['uses_index']) {
            $failures[] = $name . ' did not use an index on the hot path.';
        }

        $budgetMs = (bool) $query['sync_path'] ? (float) $budget['sync_delta_ms'] : (float) $budget['query_p95_ms'];
        if ((bool) $query['hot_path'] && $p95 > $budgetMs) {
            $failures[] = $name . ' p95 was ' . $p95 . ' ms, budget is ' . $budgetMs . ' ms.';
        }
    }

    return $failures;
}

/**
 * @param array<string, mixed> $report
 */
function write_text_report(array $report): void
{
    fwrite(STDOUT, 'Floppy metadata query budget' . PHP_EOL);
    fwrite(STDOUT, 'Scenario: ' . $report['scenario'] . ' (' . number_format((int) $report['records']) . ' rows)' . PHP_EOL);
    fwrite(STDOUT, 'Seed: ' . $report['seed'] . PHP_EOL);
    fwrite(STDOUT, 'Import: ' . $report['import']['seconds'] . 's' . PHP_EOL);
    fwrite(STDOUT, 'Peak memory: ' . $report['peak_memory_mb'] . ' MB' . PHP_EOL);
    fwrite(STDOUT, PHP_EOL . 'Queries:' . PHP_EOL);

    foreach ($report['queries'] as $query) {
        fwrite(
            STDOUT,
            sprintf(
                '- %s: p95 %.3f ms, rows %d, indexed %s%s',
                $query['name'],
                $query['p95_ms'],
                $query['rows'],
                $query['uses_index'] ? 'yes' : 'no',
                PHP_EOL
            )
        );
    }

    if ($report['failures'] === []) {
        fwrite(STDOUT, PHP_EOL . 'Budget: pass' . PHP_EOL);
        return;
    }

    fwrite(STDOUT, PHP_EOL . 'Budget: fail' . PHP_EOL);
    foreach ($report['failures'] as $failure) {
        fwrite(STDOUT, '- ' . $failure . PHP_EOL);
    }
}

/**
 * @return array<string, float|int>
 */
function budget_for(string $scenarioLabel, int $count): array
{
    if (isset(FLOPPY_LOAD_BUDGETS[$scenarioLabel])) {
        return FLOPPY_LOAD_BUDGETS[$scenarioLabel];
    }

    return [
        'records' => $count,
        'import_seconds' => max(20.0, $count / 1000),
        'query_p95_ms' => 250.0,
        'sync_delta_ms' => 3000.0,
        'memory_mb' => 256.0,
    ];
}

function normalized_scenario(string $scenario, int $count): string
{
    if (isset(FLOPPY_LOAD_BUDGETS[$scenario]) && FLOPPY_LOAD_BUDGETS[$scenario]['records'] === $count) {
        return $scenario;
    }

    return (string) $count;
}

function fixture_selector(string $scenario, int $count): string
{
    if (isset(FLOPPY_LOAD_BUDGETS[$scenario]) && FLOPPY_LOAD_BUDGETS[$scenario]['records'] === $count) {
        return '--scenario=' . $scenario;
    }

    return '--count=' . $count;
}

function parse_positive_int(string $value, string $name): int
{
    if (!preg_match('/^[1-9][0-9]*$/', $value)) {
        fail('--' . $name . ' must be a positive integer.');
    }

    return (int) $value;
}

function fail(string $message): void
{
    fwrite(STDERR, 'Error: ' . $message . PHP_EOL);
    exit(1);
}
