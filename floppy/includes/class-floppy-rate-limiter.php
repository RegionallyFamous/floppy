<?php
/**
 * Lightweight transient-backed rate limiting.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Rate limiter for REST-sensitive paths.
 */
final class Floppy_Rate_Limiter {
	/**
	 * Check and increment a rate bucket.
	 */
	public static function check( string $bucket, int $limit, int $window, string $identity = '' ) {
		$identity = $identity ?: self::default_identity();
		$key      = 'floppy_rate_' . md5( $bucket . '|' . $identity );
		$count    = (int) get_transient( $key );

		if ( $count >= $limit ) {
			Floppy_Audit::log( 'rate_limit.exceeded', 'rate_limit', 0, $bucket, array( 'identity' => md5( $identity ) ) );
			return new WP_Error( 'floppy_rate_limited', __( 'Too many requests. Please slow down and try again.', 'floppy' ), array( 'status' => 429 ) );
		}

		set_transient( $key, $count + 1, $window );
		return true;
	}

	/**
	 * Build a non-secret default identity.
	 */
	private static function default_identity(): string {
		$user_id = get_current_user_id();
		$ip      = isset( $_SERVER['REMOTE_ADDR'] ) ? (string) wp_unslash( $_SERVER['REMOTE_ADDR'] ) : 'unknown'; // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized

		return $user_id ? 'user:' . $user_id : 'ip:' . $ip;
	}
}
