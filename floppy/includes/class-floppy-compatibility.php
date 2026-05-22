<?php
/**
 * Compatibility and health checks.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Runs install and production diagnostics.
 */
final class Floppy_Compatibility {
	/**
	 * Maybe refresh checks during admin use.
	 */
	public static function maybe_refresh_checks(): void {
		$last = (int) get_option( 'floppy_compatibility_last_checked', 0 );
		if ( time() - $last < HOUR_IN_SECONDS ) {
			return;
		}

		update_option( 'floppy_compatibility', self::run_checks(), false );
		update_option( 'floppy_compatibility_last_checked', time(), false );
	}

	/**
	 * Run all checks.
	 */
	public static function run_checks(): array {
		global $wpdb;

		$checks = array();

		$checks['php'] = self::check( version_compare( PHP_VERSION, '7.4', '>=' ), sprintf( 'PHP %s', PHP_VERSION ), 'PHP 7.4+ is required.' );
		$checks['wordpress'] = self::check( version_compare( get_bloginfo( 'version' ), '6.0', '>=' ), 'WordPress ' . get_bloginfo( 'version' ), 'WordPress 6.0+ is required.' );
		$checks['desktop_mode'] = self::check( function_exists( 'desktop_mode_register_window' ), 'Desktop Mode integration', 'Desktop Mode is optional but required for the native Floppy desktop app.' );
		$checks['https'] = self::check( is_ssl() || wp_parse_url( home_url(), PHP_URL_SCHEME ) === 'https', 'HTTPS', 'HTTPS is strongly required for private file sync.' );
		$checks['rest'] = self::check( (bool) rest_url( 'floppy/v1/discovery' ), 'REST API', 'The REST API must be reachable.' );
		$checks['upload_limit'] = self::check( wp_max_upload_size() >= MB_IN_BYTES, size_format( wp_max_upload_size() ), 'Upload limit should be at least 1 MB.' );
		$checks['cron'] = self::check( ! ( defined( 'DISABLE_WP_CRON' ) && DISABLE_WP_CRON ), 'WP-Cron', 'WP-Cron is disabled; configure a real cron runner for Floppy maintenance.' );
		$checks['tables'] = self::check( empty( Floppy_Schema::validate() ), 'Database tables', 'One or more Floppy database tables are missing.' );
		$checks['db_engine'] = self::check( self::database_supports_indexes( $wpdb ), 'Database engine', 'Floppy needs a MySQL-compatible engine with indexed InnoDB-style tables.' );

		$probe = get_option( 'floppy_private_probe' );
		if ( ! is_array( $probe ) ) {
			$probe = Floppy_Storage::direct_access_probe();
		}
		$checks['private_storage'] = self::check( ! empty( $probe['ok'] ), $probe['message'] ?? 'Private storage', 'Private storage direct-access probe failed.' );

		return $checks;
	}

	/**
	 * Summarize check status.
	 */
	public static function summary(): array {
		$checks = get_option( 'floppy_compatibility', array() );
		if ( ! is_array( $checks ) || empty( $checks ) ) {
			$checks = self::run_checks();
		}

		$failures = array_filter(
			$checks,
			static function ( $check ) {
				return empty( $check['ok'] );
			}
		);

		return array(
			'ok'       => empty( $failures ),
			'checks'   => $checks,
			'failures' => array_values( $failures ),
		);
	}

	/**
	 * Format a check.
	 */
	private static function check( bool $ok, string $label, string $message ): array {
		return array(
			'ok'      => $ok,
			'label'   => $label,
			'message' => $ok ? '' : $message,
		);
	}

	/**
	 * Check DB engine roughly.
	 */
	private static function database_supports_indexes( wpdb $wpdb ): bool {
		$engine = $wpdb->get_var( "SHOW TABLE STATUS LIKE '{$wpdb->posts}'" ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared

		return null !== $engine;
	}
}
