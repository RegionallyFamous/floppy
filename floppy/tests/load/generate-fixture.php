#!/usr/bin/env php
<?php
/**
 * Generate deterministic Floppy metadata load fixtures without loading WordPress.
 *
 * This is intentionally a plain PHP CLI so scale scenarios can run in CI,
 * containers, or a developer shell before the plugin/database bootstrap exists.
 */

declare(strict_types=1);

const FLOPPY_LOAD_SCENARIOS = [
    '10k' => 10000,
    '100k' => 100000,
    '1m' => 1000000,
];

const FLOPPY_LOAD_EXTENSIONS = [
    ['pdf', 'application/pdf', 128000, 4200000],
    ['jpg', 'image/jpeg', 82000, 6400000],
    ['png', 'image/png', 64000, 5200000],
    ['txt', 'text/plain', 1200, 90000],
    ['md', 'text/markdown', 900, 180000],
    ['docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 22000, 2100000],
    ['xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 24000, 2600000],
    ['mov', 'video/quicktime', 1800000, 180000000],
];

const FLOPPY_LOAD_COLLECTIONS = [
    'inbox',
    'clients',
    'desktop',
    'screenshots',
    'receipts',
    'archive',
    'projects',
    'shared-private',
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

    $scenario = strtolower((string) ($options['scenario'] ?? '10k'));
    $count = isset($options['count']) ? parse_positive_int((string) $options['count'], 'count') : null;

    if ($count === null) {
        if (!isset(FLOPPY_LOAD_SCENARIOS[$scenario])) {
            fail('Unknown scenario "' . $scenario . '". Use one of: ' . implode(', ', array_keys(FLOPPY_LOAD_SCENARIOS)) . '.');
        }
        $count = FLOPPY_LOAD_SCENARIOS[$scenario];
    }

    $mode = strtolower((string) ($options['mode'] ?? 'describe'));
    $format = strtolower((string) ($options['format'] ?? ($mode === 'describe' ? 'text' : 'jsonl')));
    $seed = parse_positive_int((string) ($options['seed'] ?? '8675309'), 'seed');
    $ownerCount = parse_positive_int((string) ($options['owners'] ?? default_owner_count($count)), 'owners');
    $siteCount = parse_positive_int((string) ($options['sites'] ?? default_site_count($count)), 'sites');
    $batchSize = parse_positive_int((string) ($options['batch-size'] ?? '1000'), 'batch-size');
    $table = (string) ($options['table'] ?? 'wp_floppy_files');
    $outputPath = isset($options['output']) ? (string) $options['output'] : null;

    if (!in_array($mode, ['describe', 'seed'], true)) {
        fail('Invalid --mode. Use describe or seed.');
    }

    if ($mode === 'describe') {
        if (!in_array($format, ['text', 'json'], true)) {
            fail('Describe mode supports --format=text or --format=json.');
        }
        write_describe($count, $scenario, $seed, $ownerCount, $siteCount, $batchSize, $format, $outputPath);
        return;
    }

    if (!in_array($format, ['jsonl', 'csv', 'sql'], true)) {
        fail('Seed mode supports --format=jsonl, --format=csv, or --format=sql.');
    }

    write_seed($count, $seed, $ownerCount, $siteCount, $batchSize, $format, $outputPath, $table);
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
        $value = $parts[1] ?? '1';

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
Floppy load fixture generator

Usage:
  php floppy/tests/load/generate-fixture.php --mode=describe --scenario=100k
  php floppy/tests/load/generate-fixture.php --mode=seed --scenario=10k --format=jsonl --output=/tmp/floppy-10k.jsonl
  php floppy/tests/load/generate-fixture.php --mode=seed --scenario=1m --format=sql --table=wp_floppy_files --output=/tmp/floppy-1m.sql

Options:
  --mode=describe|seed     Describe the scenario or emit fixture rows. Default: describe.
  --scenario=10k|100k|1m   Named metadata scale scenario. Default: 10k.
  --count=N                Override the named scenario record count.
  --format=text|json       Formats for describe mode. Default: text.
  --format=jsonl|csv|sql   Formats for seed mode. Default: jsonl.
  --output=PATH            Write to PATH instead of stdout.
  --seed=N                 Deterministic fixture seed. Default: 8675309.
  --owners=N               Number of owner/user ids to distribute over.
  --sites=N                Number of site ids to distribute over.
  --batch-size=N           SQL insert rows per batch. Default: 1000.
  --table=NAME             SQL table name. Default: wp_floppy_files.

The generator does not load WordPress or require plugin bootstrap. SQL output is a
schema-neutral scaffold for direct database load testing and may need column names
adjusted once the production metadata schema settles.

HELP;
}

function write_describe(
    int $count,
    string $scenario,
    int $seed,
    int $ownerCount,
    int $siteCount,
    int $batchSize,
    string $format,
    ?string $outputPath
): void {
    $scenarioLabel = normalized_scenario($scenario, $count);
    $fixtureSelector = fixture_selector($scenario, $count);
    $manifest = [
        'plugin' => 'floppy',
        'fixture' => 'metadata-load',
        'scenario' => $scenarioLabel,
        'records' => $count,
        'seed' => $seed,
        'owners' => $ownerCount,
        'sites' => $siteCount,
        'private_by_default' => true,
        'wordpress_bootstrap_required' => false,
        'supported_seed_formats' => ['jsonl', 'csv', 'sql'],
        'sql_batch_size' => $batchSize,
        'record_shape' => [
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
        ],
        'distributions' => [
            'visibility' => '100% private',
            'deleted_at' => 'about 1.9% soft deleted',
            'sync_state' => 'local-only, synced, remote-pending, conflict',
            'paths' => 'owner/site/year/month collection fanout',
        ],
        'example_commands' => [
            'describe' => 'php floppy/tests/load/generate-fixture.php --mode=describe ' . $fixtureSelector,
            'jsonl' => 'php floppy/tests/load/generate-fixture.php --mode=seed ' . $fixtureSelector . ' --format=jsonl --output=/tmp/floppy-' . $scenarioLabel . '.jsonl',
            'sql' => 'php floppy/tests/load/generate-fixture.php --mode=seed ' . $fixtureSelector . ' --format=sql --output=/tmp/floppy-' . $scenarioLabel . '.sql',
        ],
    ];

    $handle = open_output($outputPath);

    if ($format === 'json') {
        fwrite($handle, json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
        close_output($handle, $outputPath);
        return;
    }

    fwrite($handle, 'Floppy metadata load fixture' . PHP_EOL);
    fwrite($handle, 'Scenario: ' . $scenarioLabel . ' (' . number_format($count) . ' records)' . PHP_EOL);
    fwrite($handle, 'WordPress bootstrap required: no' . PHP_EOL);
    fwrite($handle, 'Private by default: yes' . PHP_EOL);
    fwrite($handle, 'Owners: ' . number_format($ownerCount) . PHP_EOL);
    fwrite($handle, 'Sites: ' . number_format($siteCount) . PHP_EOL);
    fwrite($handle, 'Seed: ' . $seed . PHP_EOL);
    fwrite($handle, 'SQL batch size: ' . number_format($batchSize) . PHP_EOL);
    fwrite($handle, PHP_EOL . 'Record shape:' . PHP_EOL);

    foreach ($manifest['record_shape'] as $column) {
        fwrite($handle, '  - ' . $column . PHP_EOL);
    }

    fwrite($handle, PHP_EOL . 'Seed examples:' . PHP_EOL);
    foreach ($manifest['example_commands'] as $label => $command) {
        fwrite($handle, '  ' . $label . ': ' . $command . PHP_EOL);
    }

    close_output($handle, $outputPath);
}

function write_seed(
    int $count,
    int $seed,
    int $ownerCount,
    int $siteCount,
    int $batchSize,
    string $format,
    ?string $outputPath,
    string $table
): void {
    $startedAt = microtime(true);
    $handle = open_output($outputPath);

    if ($format === 'csv') {
        write_csv_row($handle, fixture_columns());
    } elseif ($format === 'sql') {
        fwrite($handle, "-- Floppy metadata load fixture generated without WordPress bootstrap." . PHP_EOL);
        fwrite($handle, "-- Generated at " . gmdate('c') . "; rows: " . $count . PHP_EOL . PHP_EOL);
    }

    $batch = [];

    foreach (generate_records($count, $seed, $ownerCount, $siteCount) as $record) {
        if ($format === 'jsonl') {
            fwrite($handle, json_encode($record, JSON_UNESCAPED_SLASHES) . PHP_EOL);
            continue;
        }

        if ($format === 'csv') {
            write_csv_row($handle, array_values($record));
            continue;
        }

        $batch[] = sql_tuple($record);
        if (count($batch) >= $batchSize) {
            write_sql_batch($handle, $table, $batch);
            $batch = [];
        }
    }

    if ($format === 'sql' && $batch !== []) {
        write_sql_batch($handle, $table, $batch);
    }

    close_output($handle, $outputPath);

    $elapsed = microtime(true) - $startedAt;
    fwrite(STDERR, 'Generated ' . number_format($count) . ' Floppy metadata rows in ' . number_format($elapsed, 3) . 's' . PHP_EOL);
}

/**
 * @param resource $handle
 * @param array<int, int|string|null> $row
 */
function write_csv_row($handle, array $row): void
{
    fputcsv($handle, $row, ',', '"', '\\');
}

/**
 * @return Generator<int, array<string, int|string|null>>
 */
function generate_records(int $count, int $seed, int $ownerCount, int $siteCount): Generator
{
    $baseTimestamp = strtotime('2025-01-01T00:00:00Z');
    if ($baseTimestamp === false) {
        fail('Unable to build base timestamp.');
    }

    for ($id = 1; $id <= $count; $id++) {
        $extensionSpec = FLOPPY_LOAD_EXTENSIONS[stable_bucket($seed, $id, 17, count(FLOPPY_LOAD_EXTENSIONS))];
        [$extension, $mimeType, $minSize, $maxSize] = $extensionSpec;

        $ownerId = stable_bucket($seed, $id, 23, $ownerCount) + 1;
        $siteId = stable_bucket($seed, $id, 29, $siteCount) + 1;
        $collection = FLOPPY_LOAD_COLLECTIONS[stable_bucket($seed, $id, 31, count(FLOPPY_LOAD_COLLECTIONS))];
        $sizeBytes = $minSize + stable_bucket($seed, $id, 37, $maxSize - $minSize + 1);
        $version = stable_bucket($seed, $id, 41, 7) + 1;
        $created = $baseTimestamp + stable_bucket($seed, $id, 43, 31536000);
        $updated = $created + stable_bucket($seed, $id, 47, 7776000);
        $lastSynced = $updated + stable_bucket($seed, $id, 53, 604800);
        $deleted = stable_bucket($seed, $id, 59, 53) === 0 ? $updated + stable_bucket($seed, $id, 61, 1209600) : null;
        $filename = sprintf('floppy-%06d-%s.%s', $id, substr(stable_hash($seed, $id, 'name'), 0, 8), $extension);
        $year = gmdate('Y', $created);
        $month = gmdate('m', $created);

        yield [
            'id' => $id,
            'file_id' => 'flp_' . substr(stable_hash($seed, $id, 'file'), 0, 20),
            'site_id' => $siteId,
            'owner_id' => $ownerId,
            'visibility' => 'private',
            'path' => sprintf('/site-%03d/user-%05d/%s/%s/%s/%s', $siteId, $ownerId, $collection, $year, $month, $filename),
            'filename' => $filename,
            'extension' => $extension,
            'mime_type' => $mimeType,
            'size_bytes' => $sizeBytes,
            'checksum_sha256' => stable_hash($seed, $id, 'checksum'),
            'version' => $version,
            'sync_state' => sync_state($seed, $id),
            'desktop_item_id' => 'desk_' . substr(stable_hash($seed, $id, 'desktop'), 0, 16),
            'finder_item_id' => 'finder_' . substr(stable_hash($seed, $id, 'finder'), 0, 16),
            'created_at' => gmdate('Y-m-d H:i:s', $created),
            'updated_at' => gmdate('Y-m-d H:i:s', $updated),
            'last_synced_at' => gmdate('Y-m-d H:i:s', $lastSynced),
            'deleted_at' => $deleted === null ? null : gmdate('Y-m-d H:i:s', $deleted),
        ];
    }
}

function sync_state(int $seed, int $id): string
{
    $bucket = stable_bucket($seed, $id, 67, 100);

    if ($bucket < 72) {
        return 'synced';
    }
    if ($bucket < 86) {
        return 'remote-pending';
    }
    if ($bucket < 97) {
        return 'local-only';
    }

    return 'conflict';
}

function stable_hash(int $seed, int $id, string $salt): string
{
    return hash('sha256', $seed . ':' . $id . ':' . $salt);
}

function stable_bucket(int $seed, int $id, int $salt, int $modulo): int
{
    if ($modulo < 1) {
        fail('Modulo must be greater than zero.');
    }

    $hash = hash('sha256', $seed . ':' . $id . ':' . $salt);
    return intval(substr($hash, 0, 12), 16) % $modulo;
}

/**
 * @return array<int, string>
 */
function fixture_columns(): array
{
    return [
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
}

/**
 * @param resource $handle
 * @param array<int, string> $tuples
 */
function write_sql_batch($handle, string $table, array $tuples): void
{
    fwrite(
        $handle,
        'INSERT INTO `' . str_replace('`', '``', $table) . '` (`' . implode('`, `', fixture_columns()) . '`) VALUES' . PHP_EOL .
        implode(',' . PHP_EOL, $tuples) . ';' . PHP_EOL
    );
}

/**
 * @param array<string, int|string|null> $record
 */
function sql_tuple(array $record): string
{
    $values = array_map(static function ($value): string {
        if ($value === null) {
            return 'NULL';
        }

        if (is_int($value)) {
            return (string) $value;
        }

        return "'" . str_replace(["\\", "'"], ["\\\\", "\\'"], $value) . "'";
    }, array_values($record));

    return '(' . implode(', ', $values) . ')';
}

/**
 * @return resource
 */
function open_output(?string $outputPath)
{
    if ($outputPath === null || $outputPath === '-') {
        return STDOUT;
    }

    $directory = dirname($outputPath);
    if (!is_dir($directory)) {
        fail('Output directory does not exist: ' . $directory);
    }

    $handle = fopen($outputPath, 'wb');
    if ($handle === false) {
        fail('Unable to open output path: ' . $outputPath);
    }

    return $handle;
}

/**
 * @param resource $handle
 */
function close_output($handle, ?string $outputPath): void
{
    if ($outputPath !== null && $outputPath !== '-') {
        fclose($handle);
    }
}

function parse_positive_int(string $value, string $name): int
{
    if (!preg_match('/^[1-9][0-9]*$/', $value)) {
        fail('--' . $name . ' must be a positive integer.');
    }

    return (int) $value;
}

function default_owner_count(int $count): int
{
    if ($count >= 1000000) {
        return 10000;
    }

    if ($count >= 100000) {
        return 2500;
    }

    return 250;
}

function default_site_count(int $count): int
{
    if ($count >= 1000000) {
        return 100;
    }

    if ($count >= 100000) {
        return 25;
    }

    return 5;
}

function normalized_scenario(string $scenario, int $count): string
{
    if (is_named_scenario($scenario, $count)) {
        return $scenario;
    }

    return count_label($count);
}

function fixture_selector(string $scenario, int $count): string
{
    if (is_named_scenario($scenario, $count)) {
        return '--scenario=' . $scenario;
    }

    return '--count=' . $count;
}

function is_named_scenario(string $scenario, int $count): bool
{
    return isset(FLOPPY_LOAD_SCENARIOS[$scenario]) && FLOPPY_LOAD_SCENARIOS[$scenario] === $count;
}

function count_label(int $count): string
{
    foreach (FLOPPY_LOAD_SCENARIOS as $label => $scenarioCount) {
        if ($count === $scenarioCount) {
            return $label;
        }
    }

    return (string) $count;
}

function fail(string $message): void
{
    fwrite(STDERR, 'Error: ' . $message . PHP_EOL);
    exit(1);
}
