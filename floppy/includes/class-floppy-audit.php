<?php
/**
 * Audit log helpers.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Writes append-only audit events.
 */
final class Floppy_Audit {
	/**
	 * Insert an audit event.
	 */
	public static function log( string $action, string $target_type = '', int $target_id = 0, string $message = '', array $meta = array(), int $actor_id = 0, int $device_id = 0 ): void {
		global $wpdb;

		$actor_id = $actor_id ?: get_current_user_id();
		$device_id = $device_id ?: (int) ( $GLOBALS['floppy_device_id'] ?? 0 );

		$wpdb->insert(
			Floppy_Schema::table( 'audit_log' ),
			array(
				'actor_id'        => $actor_id,
				'device_id'       => $device_id,
				'action'          => sanitize_key( $action ),
				'target_type'     => sanitize_key( $target_type ),
				'target_id'       => $target_id,
				'ip_hash'         => self::hash_server_value( 'REMOTE_ADDR' ),
				'user_agent_hash' => self::hash_server_value( 'HTTP_USER_AGENT' ),
				'message'         => self::redact_message( $message ),
				'meta_json'       => wp_json_encode( $meta ),
				'created_at_gmt'  => current_time( 'mysql', true ),
			),
			array( '%d', '%d', '%s', '%s', '%d', '%s', '%s', '%s', '%s', '%s' )
		);
	}

	/**
	 * Hash sensitive server values so logs stay support-safe.
	 */
	private static function hash_server_value( string $key ): string {
		$value = isset( $_SERVER[ $key ] ) ? (string) wp_unslash( $_SERVER[ $key ] ) : ''; // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized
		if ( '' === $value ) {
			return '';
		}

		return hash_hmac( 'sha256', $value, wp_salt( 'auth' ) );
	}

	/**
	 * Redact potentially private names in audit messages by default.
	 */
	private static function redact_message( string $message ): string {
		if ( '' === $message ) {
			return '';
		}

		if ( Floppy_Settings::get_value( 'audit_raw_messages', false ) ) {
			return $message;
		}

		return 'redacted:' . hash_hmac( 'sha256', $message, wp_salt( 'auth' ) );
	}
}
