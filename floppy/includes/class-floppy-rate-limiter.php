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
	 * Cache group for object-cache-backed buckets.
	 */
	private const CACHE_GROUP = 'floppy_rate_limits';

	/**
	 * Check and increment a rate bucket.
	 */
	public static function check( string $bucket, int $limit, int $window, string $identity = '' ) {
		$identity = $identity ?: self::default_identity();
		$key      = 'floppy_rate_' . md5( $bucket . '|' . $identity );
		$count    = self::increment_bucket( $key, $window );

		if ( $count > $limit ) {
			Floppy_Audit::log( 'rate_limit.exceeded', 'rate_limit', 0, $bucket, array( 'identity' => md5( $identity ) ) );
			return new WP_Error(
				'floppy_rate_limited',
				__( 'Too many requests. Please slow down and try again.', 'floppy' ),
				array(
					'status'      => 429,
					'retry_after' => $window,
				)
			);
		}

		return true;
	}

	/**
	 * Return support-safe limiter diagnostics.
	 */
	public static function diagnostics(): array {
		return array(
			'backend'      => wp_using_ext_object_cache() ? 'object-cache' : 'transient',
			'cache_group'  => self::CACHE_GROUP,
			'identity_pii' => 'hashed-only-in-audit-log',
		);
	}

	/**
	 * Increment a bucket with object-cache support when available.
	 */
	private static function increment_bucket( string $key, int $window ): int {
		if ( wp_using_ext_object_cache() ) {
			$added = wp_cache_add( $key, 0, self::CACHE_GROUP, $window );
			$count = wp_cache_incr( $key, 1, self::CACHE_GROUP );
			if ( false !== $count ) {
				return (int) $count;
			}
			if ( $added ) {
				return 1;
			}
		}

		$count = (int) get_transient( $key ) + 1;
		set_transient( $key, $count, $window );
		return $count;
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
