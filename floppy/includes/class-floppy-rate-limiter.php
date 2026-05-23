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
			$count = (int) get_transient( $key ) + 1;
			set_transient( $key, $count, $window );
			return $count;
		}

		$now = current_time( 'mysql', true );
		$expires = gmdate( 'Y-m-d H:i:s', time() + max( 1, $window ) );
		$identity_hash = hash( 'sha256', $key );

		$wpdb->query(
			$wpdb->prepare(
				'DELETE FROM ' . $table . ' WHERE expires_at_gmt < %s LIMIT 100',
				$now
			)
		); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared

		$existing = $wpdb->get_row(
			$wpdb->prepare(
				'SELECT id, count, expires_at_gmt FROM ' . $table . ' WHERE rate_key = %s LIMIT 1',
				md5( $key )
			),
			ARRAY_A
		); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared

		if ( $existing && strtotime( $existing['expires_at_gmt'] . ' GMT' ) >= time() ) {
			$count = (int) $existing['count'] + 1;
			$wpdb->update(
				$table,
				array(
					'count'          => $count,
					'updated_at_gmt' => $now,
				),
				array( 'id' => (int) $existing['id'] ),
				array( '%d', '%s' ),
				array( '%d' )
			);
			return $count;
		}

		if ( $existing ) {
			$wpdb->update(
				$table,
				array(
					'count'          => 1,
					'expires_at_gmt' => $expires,
					'updated_at_gmt' => $now,
				),
				array( 'id' => (int) $existing['id'] ),
				array( '%d', '%s', '%s' ),
				array( '%d' )
			);
			return 1;
		}

		$wpdb->insert(
			$table,
			array(
				'rate_key'       => md5( $key ),
				'bucket'         => $bucket,
				'identity_hash'  => $identity_hash,
				'count'          => 1,
				'expires_at_gmt' => $expires,
				'created_at_gmt' => $now,
				'updated_at_gmt' => $now,
			),
			array( '%s', '%s', '%s', '%d', '%s', '%s', '%s' )
		);

		return 1;
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
