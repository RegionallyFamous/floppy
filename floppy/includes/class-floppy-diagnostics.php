<?php
/**
 * Redacted diagnostics and support bundle helpers.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Builds support-safe health and diagnostics payloads.
 */
final class Floppy_Diagnostics {
	/**
	 * Per-request support correlation id.
	 *
	 * @var string
	 */
	private static $correlation_id = '';

	/**
	 * Return a support correlation id shared across responses in this request.
	 */
	public static function correlation_id(): string {
		if ( self::$correlation_id ) {
			return self::$correlation_id;
		}

		$incoming = isset( $_SERVER['HTTP_X_FLOPPY_SUPPORT_ID'] ) ? sanitize_text_field( wp_unslash( $_SERVER['HTTP_X_FLOPPY_SUPPORT_ID'] ) ) : ''; // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized
		if ( preg_match( '/^floppy-(?:[a-f0-9]{16}|[a-f0-9-]{36})$/', $incoming ) ) {
			self::$correlation_id = $incoming;
		} else {
			self::$correlation_id = 'floppy-' . wp_generate_uuid4();
		}

		return self::$correlation_id;
	}

	/**
	 * Build a compact support identity block.
	 */
	public static function support_block(): array {
		return array(
			'correlation_id' => self::correlation_id(),
			'generated_at'   => current_time( 'mysql', true ),
		);
	}

	/**
	 * Build admin-only deep health diagnostics.
	 */
	public static function deep_health(): array {
		return array(
			'format'         => 'floppy-deep-health-v1',
			'support'        => self::support_block(),
			'compatibility'  => Floppy_Compatibility::summary(),
			'private_storage' => Floppy_Storage::private_storage_probe_matrix(),
			'schema'         => array(
				'missing' => Floppy_Schema::validate(),
				'repair'  => Floppy_Schema::repair( false ),
			),
			'sync'           => self::sync_summary(),
			'storage'        => self::storage_summary(),
			'queues'         => self::job_summary(),
			'conflicts'      => self::conflict_summary(),
			'versions'       => self::version_summary(),
			'thumbnails'     => self::thumbnail_summary(),
			'release_evidence' => self::release_evidence_summary(),
			'rate_limits'    => Floppy_Rate_Limiter::diagnostics(),
		);
	}

	/**
	 * Build a redacted support/debug bundle.
	 */
	public static function debug_bundle(): array {
		global $wpdb;

		$settings = Floppy_Settings::get();
		$audit_counts = $wpdb->get_results( 'SELECT action, COUNT(*) AS total FROM ' . Floppy_Schema::table( 'audit_log' ) . ' GROUP BY action ORDER BY total DESC LIMIT 25', ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared

		return array(
			'format'         => 'floppy-debug-bundle-v2',
			'support'        => self::support_block(),
			'plugin'         => array(
				'version'    => FLOPPY_VERSION,
				'db_version' => FLOPPY_DB_VERSION,
				'namespace'  => Floppy_Rest::NAMESPACE,
			),
			'privacy'        => array(
				'no_external_services' => true,
				'statement'            => __( 'Floppy does not send file data, diagnostics, telemetry, crash logs, or sync metadata to any hosted service.', 'floppy' ),
			),
			'site'           => array(
				'home_url'    => self::redact_url( home_url( '/' ) ),
				'rest_url'    => self::redact_url( rest_url( Floppy_Rest::NAMESPACE ) ),
				'is_ssl'      => is_ssl(),
				'multisite'   => is_multisite(),
				'php_version' => PHP_VERSION,
				'wp_version'  => get_bloginfo( 'version' ),
			),
			'compatibility'  => Floppy_Compatibility::summary(),
			'private_storage' => Floppy_Storage::private_storage_probe_matrix(),
			'schema'         => array(
				'missing' => Floppy_Schema::validate(),
				'repair'  => Floppy_Schema::repair( false ),
			),
			'desktop_mode'   => array(
				'detected' => function_exists( 'desktop_mode_register_window' ),
				'enabled'  => ! empty( $settings['enable_desktop_mode'] ),
			),
			'quotas'         => array(
				'max_file_size'            => (int) ( $settings['max_file_size'] ?? wp_max_upload_size() ),
				'max_batch_files'          => (int) ( $settings['max_batch_files'] ?? 50 ),
				'user_quota_bytes'         => (int) ( $settings['user_quota_bytes'] ?? 0 ),
				'site_quota_bytes'         => (int) ( $settings['site_quota_bytes'] ?? 0 ),
				'sync_retention_days'      => (int) ( $settings['sync_retention_days'] ?? 45 ),
				'tombstone_retention_days' => (int) ( $settings['tombstone_retention_days'] ?? 90 ),
				'version_retention_limit'  => (int) ( $settings['version_retention_limit'] ?? 10 ),
			),
			'devices'        => self::device_summary(),
			'jobs'           => self::job_summary(),
			'sync'           => self::sync_summary(),
			'storage'        => self::storage_summary(),
			'conflicts'      => self::conflict_summary(),
			'versions'       => self::version_summary(),
			'thumbnails'     => self::thumbnail_summary(),
			'release_evidence' => self::release_evidence_summary(),
			'audit_actions'  => self::keyed_counts( $audit_counts, 'action' ),
		);
	}

	/**
	 * Build the admin-only beta evidence payload.
	 */
	public static function release_evidence(): array {
		return array(
			'format'            => 'floppy-beta-evidence-v1',
			'support'           => self::support_block(),
			'plugin'            => array(
				'version'    => FLOPPY_VERSION,
				'db_version' => FLOPPY_DB_VERSION,
				'namespace'  => Floppy_Rest::NAMESPACE,
			),
			'privacy'           => array(
				'no_external_services' => true,
				'distribution_only'    => 'github',
				'statement'            => __( 'Floppy does not send file data, diagnostics, telemetry, crash logs, or sync metadata to any hosted service. GitHub is used only for release distribution.', 'floppy' ),
			),
			'compatibility'     => Floppy_Compatibility::summary(),
			'schema'            => array(
				'missing' => Floppy_Schema::validate(),
				'repair'  => Floppy_Schema::repair( false ),
			),
			'conflicts'         => self::conflict_summary(),
			'versions'          => self::version_summary(),
			'thumbnails'        => self::thumbnail_summary(),
			'release_gates'     => array(
				'php_lint'                  => 'ci-required',
				'phpcs'                     => 'ci-required',
				'phpunit_wordpress'         => 'ci-required',
				'plugin_zip_shape'          => 'ci-required',
				'swift_build_tests'         => 'ci-required',
				'xcode_doctor'              => 'ci-required',
				'desktop_mode_hook_audit'   => 'ci-required',
				'developer_id_notarization' => 'manual-required',
				'load_100k'                 => 'manual-required',
				'load_1m_stress'            => 'manual-required',
				'redaction_checks'          => 'ci-required',
			),
		);
	}

	/**
	 * Redact credentials/query fragments while preserving the origin/path.
	 */
	public static function redact_url( string $url ): string {
		$parts = wp_parse_url( $url );
		if ( ! is_array( $parts ) || empty( $parts['host'] ) ) {
			return '';
		}

		$scheme = isset( $parts['scheme'] ) ? $parts['scheme'] : 'https';
		$port = isset( $parts['port'] ) ? ':' . (int) $parts['port'] : '';
		$path = isset( $parts['path'] ) ? $parts['path'] : '';

		return $scheme . '://' . $parts['host'] . $port . $path;
	}

	/**
	 * Summarize device state without tokens.
	 */
	private static function device_summary(): array {
		global $wpdb;

		$device_counts = $wpdb->get_results( 'SELECT status, COUNT(*) AS total FROM ' . Floppy_Schema::table( 'devices' ) . ' GROUP BY status', ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$last_seen = $wpdb->get_var( 'SELECT MAX(last_seen_at_gmt) FROM ' . Floppy_Schema::table( 'devices' ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$last_sync = $wpdb->get_var( 'SELECT MAX(last_sync_at_gmt) FROM ' . Floppy_Schema::table( 'devices' ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared

		return array(
			'by_status'      => self::keyed_counts( $device_counts, 'status' ),
			'last_seen_gmt'  => $last_seen ?: '',
			'last_sync_gmt'  => $last_sync ?: '',
		);
	}

	/**
	 * Summarize queue state.
	 */
	private static function job_summary(): array {
		global $wpdb;

		$job_counts = $wpdb->get_results( 'SELECT status, COUNT(*) AS total FROM ' . Floppy_Schema::table( 'jobs' ) . ' GROUP BY status', ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$stale_running = (int) $wpdb->get_var(
			$wpdb->prepare(
				'SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'jobs' ) . " WHERE status = 'running' AND locked_at_gmt < %s",
				gmdate( 'Y-m-d H:i:s', time() - 15 * MINUTE_IN_SECONDS )
			)
		);

		return array(
			'by_status'     => self::keyed_counts( $job_counts, 'status' ),
			'stale_running' => $stale_running,
		);
	}

	/**
	 * Summarize sync-event continuity.
	 */
	private static function sync_summary(): array {
		global $wpdb;

		$row = $wpdb->get_row(
			'SELECT MIN(seq) AS min_seq, MAX(seq) AS max_seq, COUNT(*) AS total FROM ' . Floppy_Schema::table( 'sync_events' ),
			ARRAY_A
		); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$min = (int) ( $row['min_seq'] ?? 0 );
		$max = (int) ( $row['max_seq'] ?? 0 );
		$total = (int) ( $row['total'] ?? 0 );

		return array(
			'min_seq' => $min,
			'max_seq' => $max,
			'total'   => $total,
			'gaps'    => $min && $max ? max( 0, ( $max - $min + 1 ) - $total ) : 0,
		);
	}

	/**
	 * Summarize private file metadata without paths.
	 */
	private static function storage_summary(): array {
		global $wpdb;

		$file_counts = $wpdb->get_results( 'SELECT status, COUNT(*) AS total, COALESCE(SUM(size_bytes),0) AS bytes FROM ' . Floppy_Schema::table( 'files' ) . ' GROUP BY status', ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$folder_counts = $wpdb->get_results( 'SELECT status, COUNT(*) AS total FROM ' . Floppy_Schema::table( 'folders' ) . ' GROUP BY status', ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$bytes = array();
		foreach ( $file_counts as $row ) {
			$bytes[ (string) $row['status'] ] = (int) $row['bytes'];
		}

		return array(
			'files_by_status'   => self::keyed_counts( $file_counts, 'status' ),
			'folders_by_status' => self::keyed_counts( $folder_counts, 'status' ),
			'file_bytes'        => $bytes,
		);
	}

	/**
	 * Summarize server-side conflicts.
	 */
	private static function conflict_summary(): array {
		return array(
			'by_status' => self::count_rows_by_status( Floppy_Schema::table( 'conflicts' ) ),
		);
	}

	/**
	 * Summarize retained versions and quota impact.
	 */
	private static function version_summary(): array {
		global $wpdb;

		return array(
			'total'           => (int) $wpdb->get_var( 'SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'file_versions' ) ), // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			'bytes'           => (int) $wpdb->get_var( 'SELECT COALESCE(SUM(size_bytes),0) FROM ' . Floppy_Schema::table( 'file_versions' ) ), // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			'retention_limit' => (int) Floppy_Settings::get_value( 'version_retention_limit', 10 ),
		);
	}

	/**
	 * Summarize private thumbnail/cache state.
	 */
	private static function thumbnail_summary(): array {
		return array(
			'by_status' => self::count_rows_by_status( Floppy_Schema::table( 'thumbnails' ) ),
		);
	}

	/**
	 * Include a compact beta-readiness view inside support bundles.
	 */
	private static function release_evidence_summary(): array {
		$missing_schema = Floppy_Schema::validate();

		return array(
			'format'               => 'floppy-beta-evidence-summary-v1',
			'schema_ready'         => empty( $missing_schema ),
			'missing_schema_items' => count( $missing_schema ),
			'no_external_services' => true,
			'required_manual_gates' => array( 'developer_id_notarization', 'load_100k', 'load_1m_stress' ),
		);
	}

	/**
	 * Count rows by status in a redacted support-safe table.
	 */
	private static function count_rows_by_status( string $table ): array {
		global $wpdb;

		$rows = $wpdb->get_results( "SELECT status, COUNT(*) AS total FROM $table GROUP BY status", ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		return self::keyed_counts( $rows, 'status' );
	}

	/**
	 * Convert grouped count rows into a plain object.
	 */
	private static function keyed_counts( array $rows, string $key ): array {
		$out = array();
		foreach ( $rows as $row ) {
			$out[ (string) $row[ $key ] ] = (int) $row['total'];
		}
		return $out;
	}
}
