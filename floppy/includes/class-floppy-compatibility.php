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
		$checks['desktop_mode'] = function_exists( 'desktop_mode_register_window' )
			? self::check( true, 'Desktop Mode integration', '' )
			: self::warning( 'Desktop Mode not detected', 'Desktop Mode is optional. Install it only if you want the browser-native Floppy desktop surface inside WordPress.' );
		$checks['https'] = self::https_check();
		$checks['rest'] = self::check( (bool) rest_url( 'floppy/v1/discovery' ), 'REST API', 'The REST API must be reachable.' );
		$checks['upload_limit'] = self::check( wp_max_upload_size() >= MB_IN_BYTES, size_format( wp_max_upload_size() ), 'Upload limit should be at least 1 MB.' );
		$checks['cron'] = self::check( ! ( defined( 'DISABLE_WP_CRON' ) && DISABLE_WP_CRON ), 'WP-Cron', 'WP-Cron is disabled; configure a real cron runner for Floppy maintenance.' );
		$checks['tables'] = self::check( empty( Floppy_Schema::validate() ), 'Database tables', 'One or more Floppy database tables are missing.' );
		$checks['db_engine'] = self::check( self::database_supports_indexes( $wpdb ), 'Database engine', 'Floppy needs a MySQL-compatible engine with indexed InnoDB-style tables.' );
		$checks['capabilities'] = self::check( self::capabilities_installed(), 'Floppy capabilities', 'Floppy-specific capabilities need to be installed for site users.' );
		$checks['quota_policy'] = self::check( (int) Floppy_Settings::get_value( 'user_quota_bytes', 0 ) > 0, 'Quota policy', 'Configure a non-zero per-user quota before broad team use.' );

		$probe = Floppy_Storage::private_storage_status();
		$checks['private_storage'] = self::from_probe( $probe );

		return $checks;
	}

	/**
	 * Summarize check status.
	 */
	public static function summary(): array {
		$checks = get_option( 'floppy_compatibility', array() );
		if ( ! is_array( $checks ) || empty( $checks ) || self::checks_need_refresh( $checks ) ) {
			$checks = self::run_checks();
			update_option( 'floppy_compatibility', $checks, false );
		}

		$failures = array_filter(
			$checks,
			static function ( $check ) {
				return self::check_status( $check ) === 'fail';
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
	private static function check( bool $ok, string $label, string $message, string $status = '' ): array {
		$status = $status ?: ( $ok ? 'pass' : 'fail' );

		return array(
			'ok'      => $ok,
			'status'  => $status,
			'label'   => $label,
			'message' => $ok ? '' : $message,
		);
	}

	/**
	 * Format a warning check.
	 */
	private static function warning( string $label, string $message ): array {
		return array(
			'ok'      => true,
			'status'  => 'warn',
			'label'   => $label,
			'message' => $message,
		);
	}

	/**
	 * Build HTTPS check with localhost development support.
	 */
	private static function https_check(): array {
		if ( is_ssl() || wp_parse_url( home_url(), PHP_URL_SCHEME ) === 'https' ) {
			return self::check( true, 'HTTPS', '' );
		}

		if ( Floppy_Storage::is_loopback_site() ) {
			return self::warning( 'Local HTTP development site', 'Loopback HTTP is allowed for Studio/local smoke tests only. Use HTTPS before syncing private files on a real site.' );
		}

		return self::check( false, 'HTTPS', 'HTTPS is required for private file sync outside local loopback development.' );
	}

	/**
	 * Convert private storage probe into a check.
	 */
	private static function from_probe( array $probe ): array {
		$status = isset( $probe['status'] ) ? (string) $probe['status'] : ( empty( $probe['ok'] ) ? 'fail' : 'pass' );

		if ( 'warn' === $status ) {
			return self::warning( $probe['label'] ?? 'Private storage warning', $probe['message'] ?? 'Private storage needs review.' );
		}

		return self::check( ! empty( $probe['ok'] ), $probe['label'] ?? ( $probe['message'] ?? 'Private storage' ), $probe['message'] ?? 'Private storage direct-access probe failed.', $status );
	}

	/**
	 * Read check status with backward compatibility for older stored checks.
	 */
	public static function check_status( array $check ): string {
		if ( ! empty( $check['status'] ) ) {
			return (string) $check['status'];
		}

		return empty( $check['ok'] ) ? 'fail' : 'pass';
	}

	/**
	 * Detect legacy cached health payloads that predate warning support.
	 */
	private static function checks_need_refresh( array $checks ): bool {
		$required = array( 'desktop_mode', 'https', 'private_storage' );
		foreach ( $required as $key ) {
			if ( empty( $checks[ $key ] ) || ! is_array( $checks[ $key ] ) || empty( $checks[ $key ]['status'] ) ) {
				return true;
			}
		}

		return false;
	}

	/**
	 * Check DB engine roughly.
	 */
	private static function database_supports_indexes( wpdb $wpdb ): bool {
		$engine = $wpdb->get_var( "SHOW TABLE STATUS LIKE '{$wpdb->posts}'" ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared

		return null !== $engine;
	}

	/**
	 * Check that at least one role owns the Floppy read capability.
	 */
	private static function capabilities_installed(): bool {
		foreach ( wp_roles()->roles as $role_name => $role_data ) {
			$role = get_role( $role_name );
			if ( $role && $role->has_cap( Floppy_Permissions::CAP_READ ) ) {
				return true;
			}
		}

		return false;
	}
}
