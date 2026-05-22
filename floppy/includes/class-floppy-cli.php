<?php
/**
 * WP-CLI commands for Floppy repair/export operations.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Floppy WP-CLI command namespace.
 */
final class Floppy_CLI {
	/**
	 * Register commands.
	 */
	public static function init(): void {
		WP_CLI::add_command( 'floppy', __CLASS__ );
	}

	/**
	 * Show production health checks.
	 *
	 * ## EXAMPLES
	 *
	 *     wp floppy health
	 */
	public function health(): void {
		$summary = Floppy_Compatibility::summary();
		foreach ( $summary['checks'] as $key => $check ) {
			WP_CLI::line( sprintf( '%s: %s %s', $key, ! empty( $check['ok'] ) ? 'pass' : 'fail', $check['message'] ?? '' ) );
		}

		if ( empty( $summary['ok'] ) ) {
			WP_CLI::warning( 'Floppy has failing production checks.' );
			return;
		}

		WP_CLI::success( 'Floppy production checks passed.' );
	}

	/**
	 * Reinstall/repair database schema.
	 *
	 * ## EXAMPLES
	 *
	 *     wp floppy repair-schema
	 */
	public function repair_schema(): void {
		Floppy_Schema::install();
		WP_CLI::success( 'Floppy schema repaired.' );
	}

	/**
	 * Verify private blob references.
	 *
	 * ## OPTIONS
	 *
	 * [--limit=<limit>]
	 * : Number of rows to inspect.
	 *
	 * ## EXAMPLES
	 *
	 *     wp floppy verify-blobs --limit=5000
	 */
	public function verify_blobs( array $args, array $assoc_args ): void {
		global $wpdb;

		$limit = isset( $assoc_args['limit'] ) ? absint( $assoc_args['limit'] ) : 1000;
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT id, name, storage_key FROM ' . Floppy_Schema::table( 'files' ) . " WHERE status != 'deleted' ORDER BY id ASC LIMIT %d",
				$limit
			),
			ARRAY_A
		);

		$missing = 0;
		foreach ( $rows as $row ) {
			if ( ! is_readable( Floppy_Storage::path_for_key( $row['storage_key'] ) ) ) {
				++$missing;
				WP_CLI::warning( sprintf( 'Missing blob for file #%d: %s', (int) $row['id'], $row['name'] ) );
			}
		}

		if ( $missing ) {
			WP_CLI::warning( sprintf( '%d missing blobs found.', $missing ) );
			return;
		}

		WP_CLI::success( sprintf( 'Verified %d blobs.', count( $rows ) ) );
	}

	/**
	 * Export a metadata manifest as JSON.
	 *
	 * ## OPTIONS
	 *
	 * --path=<path>
	 * : Output path for the JSON manifest.
	 *
	 * [--user=<id>]
	 * : Limit export to one owner id.
	 *
	 * ## EXAMPLES
	 *
	 *     wp floppy export-manifest --path=/tmp/floppy-manifest.json
	 */
	public function export_manifest( array $args, array $assoc_args ): void {
		global $wpdb;

		if ( empty( $assoc_args['path'] ) ) {
			WP_CLI::error( '--path is required.' );
		}

		$path = (string) $assoc_args['path'];
		$user_id = isset( $assoc_args['user'] ) ? absint( $assoc_args['user'] ) : 0;
		$where = $user_id ? $wpdb->prepare( 'WHERE owner_id = %d', $user_id ) : '';

		$files = $wpdb->get_results( 'SELECT * FROM ' . Floppy_Schema::table( 'files' ) . " $where ORDER BY id ASC", ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$folders = $wpdb->get_results( 'SELECT * FROM ' . Floppy_Schema::table( 'folders' ) . " $where ORDER BY id ASC", ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$manifest = array(
			'generated_at_gmt' => current_time( 'mysql', true ),
			'site_url'         => home_url(),
			'version'          => FLOPPY_VERSION,
			'files'            => $files,
			'folders'          => $folders,
		);

		if ( false === file_put_contents( $path, wp_json_encode( $manifest, JSON_PRETTY_PRINT ) ) ) { // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_file_put_contents
			WP_CLI::error( 'Could not write manifest.' );
		}

		WP_CLI::success( 'Manifest exported to ' . $path );
	}
}
