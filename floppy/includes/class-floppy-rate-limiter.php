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
		$count    = self::increment_bucket( $bucket, $key, $window );

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
			'backend'      => wp_using_ext_object_cache() ? 'object-cache' : 'database',
			'cache_group'  => self::CACHE_GROUP,
			'persistent_without_object_cache' => true,
			'identity_pii' => 'hashed-only-in-audit-log',
		);
	}

	/**
	 * Increment a bucket with object-cache support when available.
	 */
	private static function increment_bucket( string $bucket, string $key, int $window ): int {
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

		return self::increment_database_bucket( $bucket, $key, $window );
	}

	/**
	 * Increment a persistent DB bucket for hosts without an object cache.
	 */
	private static function increment_database_bucket( string $bucket, string $key, int $window ): int {
		global $wpdb;

		$table = Floppy_Schema::table( 'rate_limits' );
		if ( $wpdb->get_var( $wpdb->prepare( 'SHOW TABLES LIKE %s', $table ) ) !== $table ) {
			return self::increment_transient_bucket( $key, $window );
		}

		$now = current_time( 'mysql', true );
		$expires = gmdate( 'Y-m-d H:i:s', time() + max( 1, $window ) );
		$rate_key = md5( $key );
		$identity_hash = hash( 'sha256', $key );

		$wpdb->query(
			$wpdb->prepare(
				'DELETE FROM ' . $table . ' WHERE expires_at_gmt < %s LIMIT 100',
				$now
			)
		); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared

		$updated = $wpdb->query(
			$wpdb->prepare(
				'INSERT INTO ' . $table . ' (rate_key, bucket, identity_hash, count, expires_at_gmt, created_at_gmt, updated_at_gmt) VALUES (%s, %s, %s, 1, %s, %s, %s) ON DUPLICATE KEY UPDATE count = IF(expires_at_gmt < %s, 1, count + 1), expires_at_gmt = IF(expires_at_gmt < %s, %s, expires_at_gmt), updated_at_gmt = %s',
				$rate_key,
				$bucket,
				$identity_hash,
				$expires,
				$now,
				$now,
				$now,
				$now,
				$expires,
				$now
			)
		); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared

		if ( false === $updated ) {
			return self::increment_transient_bucket( $key, $window );
		}

		return (int) $wpdb->get_var(
			$wpdb->prepare(
				'SELECT count FROM ' . $table . ' WHERE rate_key = %s LIMIT 1',
				$rate_key
			)
		); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
	}

	/**
	 * Increment a transient fallback bucket with an atomic SQL update.
	 */
	private static function increment_transient_bucket( string $key, int $window ): int {
		global $wpdb;

		$count_option = '_transient_' . $key;
		$timeout_option = '_transient_timeout_' . $key;
		$now = time();
		$timeout = (int) get_option( $timeout_option );
		if ( $timeout && $timeout < $now ) {
			delete_option( $count_option );
			delete_option( $timeout_option );
			$timeout = 0;
		}

		if ( ! $timeout ) {
			add_option( $timeout_option, (string) ( $now + $window ), '', false );
		}

		if ( add_option( $count_option, '1', '', false ) ) {
			return 1;
		}

		$updated = $wpdb->query(
			$wpdb->prepare(
				"UPDATE $wpdb->options SET option_value = CAST(option_value AS UNSIGNED) + 1 WHERE option_name = %s", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
				$count_option
			)
		);

		if ( false === $updated || 0 === (int) $updated ) {
			if ( add_option( $count_option, '1', '', false ) ) {
				return 1;
			}

			$count = (int) get_transient( $key ) + 1;
			set_transient( $key, $count, $window );
			return $count;
		}

		return (int) $wpdb->get_var(
			$wpdb->prepare(
				"SELECT option_value FROM $wpdb->options WHERE option_name = %s LIMIT 1", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
				$count_option
			)
		);
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
