<?php
/**
 * Device token authentication.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Authenticates browser-approved macOS devices.
 */
final class Floppy_Auth {
	/**
	 * Register auth hooks.
	 */
	public static function init(): void {
		add_filter( 'determine_current_user', array( __CLASS__, 'authenticate_bearer_token' ), 20 );
	}

	/**
	 * Authenticate a Floppy bearer token.
	 *
	 * @param int|false $user_id Current user id.
	 * @return int|false
	 */
	public static function authenticate_bearer_token( $user_id ) {
		if ( $user_id ) {
			return $user_id;
		}

		if ( ! self::is_floppy_rest_request() ) {
			return $user_id;
		}

		$token = self::get_bearer_token();
		if ( '' === $token || 0 !== strpos( $token, 'flp_' ) ) {
			return $user_id;
		}

		if ( ! self::is_secure_request() ) {
			Floppy_Audit::log( 'device_token.insecure_rejected', 'device', 0, __( 'Device token rejected over a non-HTTPS request.', 'floppy' ) );
			return $user_id;
		}

		global $wpdb;
		$row = $wpdb->get_row(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'devices' ) . ' WHERE token_hash = %s AND status = %s LIMIT 1',
				self::hash_token( $token ),
				'active'
			),
			ARRAY_A
		);

		if ( empty( $row ) ) {
			Floppy_Audit::log( 'device_token.failed', 'device', 0, __( 'Invalid or revoked device token.', 'floppy' ) );
			return $user_id;
		}

		$GLOBALS['floppy_device_id'] = (int) $row['id'];
		$GLOBALS['floppy_device_uuid'] = (string) $row['device_uuid'];
		$GLOBALS['floppy_device_scope'] = (string) $row['scope'];
		$GLOBALS['floppy_device_user_id'] = (int) $row['user_id'];

		$wpdb->update(
			Floppy_Schema::table( 'devices' ),
			array( 'last_seen_at_gmt' => current_time( 'mysql', true ) ),
			array( 'id' => (int) $row['id'] ),
			array( '%s' ),
			array( '%d' )
		);

		return (int) $row['user_id'];
	}

	/**
	 * Create a scoped device token. The raw token is returned once.
	 */
	public static function create_device( int $user_id, string $device_name, string $scope = 'files:read,files:write,sync' ) {
		global $wpdb;

		$rate = Floppy_Rate_Limiter::check( 'device-authorize', 10, HOUR_IN_SECONDS, 'user:' . $user_id );
		if ( is_wp_error( $rate ) ) {
			return $rate;
		}

		$token = 'flp_' . wp_generate_password( 64, false, false );
		$uuid  = wp_generate_uuid4();
		$name  = sanitize_text_field( $device_name );
		if ( '' === $name ) {
			$name = __( 'Mac', 'floppy' );
		}

		$inserted = $wpdb->insert(
			Floppy_Schema::table( 'devices' ),
			array(
				'device_uuid'     => $uuid,
				'user_id'         => $user_id,
				'device_name'     => $name,
				'token_hash'      => self::hash_token( $token ),
				'scope'           => sanitize_text_field( $scope ),
				'status'          => 'active',
				'approved_at_gmt' => current_time( 'mysql', true ),
			),
			array( '%s', '%d', '%s', '%s', '%s', '%s', '%s' )
		);

		if ( ! $inserted ) {
			return new WP_Error( 'floppy_device_create_failed', __( 'Could not create a device token.', 'floppy' ), array( 'status' => 500 ) );
		}

		Floppy_Audit::log( 'device.approved', 'device', (int) $wpdb->insert_id, sprintf( 'Approved device %s.', $name ), array( 'device_uuid' => $uuid ), $user_id );

		return array(
			'device_uuid' => $uuid,
			'token'       => $token,
			'scope'       => $scope,
		);
	}

	/**
	 * Create a one-time browser approval code instead of putting a token in a custom URL.
	 */
	public static function create_device_exchange_code( int $user_id, string $device_name, string $state ): string {
		$code = 'flc_' . wp_generate_password( 48, false, false );
		set_transient(
			self::exchange_transient_key( $code ),
			array(
				'user_id'     => $user_id,
				'device_name' => sanitize_text_field( $device_name ),
				'state'       => sanitize_text_field( $state ),
				'created_at'  => time(),
			),
			10 * MINUTE_IN_SECONDS
		);

		Floppy_Audit::log( 'device.exchange_code.created', 'device', 0, __( 'Created a one-time device exchange code.', 'floppy' ), array(), $user_id );
		return $code;
	}

	/**
	 * Exchange a short-lived code for a newly created device token.
	 */
	public static function exchange_device_code( string $code, string $state ) {
		$key = self::exchange_transient_key( $code );
		$payload = get_transient( $key );
		delete_transient( $key );

		if ( ! is_array( $payload ) || empty( $payload['user_id'] ) ) {
			Floppy_Audit::log( 'device.exchange_code.failed', 'device', 0, __( 'Invalid or expired device exchange code.', 'floppy' ) );
			return new WP_Error( 'floppy_device_exchange_invalid', __( 'The Floppy device approval code expired or was already used.', 'floppy' ), array( 'status' => 410 ) );
		}

		if ( ! hash_equals( (string) ( $payload['state'] ?? '' ), $state ) ) {
			Floppy_Audit::log( 'device.exchange_code.state_failed', 'device', 0, __( 'Device exchange state did not match.', 'floppy' ), array(), (int) $payload['user_id'] );
			return new WP_Error( 'floppy_device_exchange_state', __( 'The Floppy device approval state did not match.', 'floppy' ), array( 'status' => 403 ) );
		}

		$device = self::create_device( (int) $payload['user_id'], (string) ( $payload['device_name'] ?? __( 'Mac', 'floppy' ) ) );
		if ( is_wp_error( $device ) ) {
			return $device;
		}

		Floppy_Audit::log( 'device.exchange_code.used', 'device', 0, __( 'Exchanged a one-time device approval code.', 'floppy' ), array( 'device_uuid' => $device['device_uuid'] ), (int) $payload['user_id'] );
		return $device;
	}

	/**
	 * Revoke a device owned by the current user or an administrator.
	 */
	public static function revoke_device( string $device_uuid, int $actor_id ) {
		global $wpdb;

		$row = $wpdb->get_row(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'devices' ) . ' WHERE device_uuid = %s LIMIT 1',
				$device_uuid
			),
			ARRAY_A
		);

		if ( ! $row ) {
			return new WP_Error( 'floppy_device_not_found', __( 'Device not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		if ( (int) $row['user_id'] !== $actor_id && ! user_can( $actor_id, 'manage_options' ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot revoke this device.', 'floppy' ), array( 'status' => 403 ) );
		}

		$wpdb->update(
			Floppy_Schema::table( 'devices' ),
			array(
				'status'         => 'revoked',
				'revoked_at_gmt' => current_time( 'mysql', true ),
			),
			array( 'id' => (int) $row['id'] ),
			array( '%s', '%s' ),
			array( '%d' )
		);

		Floppy_Audit::log( 'device.revoked', 'device', (int) $row['id'], __( 'Device token revoked.', 'floppy' ), array( 'device_uuid' => $device_uuid ), $actor_id );

		return true;
	}

	/**
	 * List devices visible to a user.
	 */
	public static function list_devices( int $user_id ): array {
		global $wpdb;

		$where = user_can( $user_id, 'manage_options' ) ? '1=1' : $wpdb->prepare( 'user_id = %d', $user_id );

		return $wpdb->get_results(
			'SELECT id, device_uuid, user_id, device_name, scope, status, last_cursor, last_error, approved_at_gmt, last_seen_at_gmt, last_sync_at_gmt, revoked_at_gmt FROM ' . Floppy_Schema::table( 'devices' ) . " WHERE $where ORDER BY approved_at_gmt DESC LIMIT 200", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
			ARRAY_A
		);
	}

	/**
	 * Whether the current REST request authenticated via a Floppy device token.
	 */
	public static function is_device_auth(): bool {
		return ! empty( $GLOBALS['floppy_device_id'] );
	}

	/**
	 * Check the current device token scope.
	 */
	public static function current_device_can( string $scope ): bool {
		if ( ! self::is_device_auth() ) {
			return true;
		}

		$scopes = array_map( 'trim', explode( ',', (string) ( $GLOBALS['floppy_device_scope'] ?? '' ) ) );
		return in_array( $scope, $scopes, true );
	}

	/**
	 * Device tokens are accepted only on Floppy REST routes.
	 */
	private static function is_floppy_rest_request(): bool {
		$route = isset( $_GET['rest_route'] ) ? (string) wp_unslash( $_GET['rest_route'] ) : ''; // phpcs:ignore WordPress.Security.NonceVerification.Recommended,WordPress.Security.ValidatedSanitizedInput.InputNotSanitized
		if ( 0 === strpos( $route, '/floppy/v1' ) ) {
			return true;
		}

		$uri = isset( $_SERVER['REQUEST_URI'] ) ? (string) wp_unslash( $_SERVER['REQUEST_URI'] ) : ''; // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized
		return false !== strpos( $uri, '/' . rest_get_url_prefix() . '/floppy/v1' );
	}

	/**
	 * Require HTTPS for bearer tokens.
	 */
	private static function is_secure_request(): bool {
		return is_ssl() || self::is_loopback_request();
	}

	/**
	 * Allow local Studio smoke tests to use device tokens over loopback HTTP.
	 */
	private static function is_loopback_request(): bool {
		$host = isset( $_SERVER['HTTP_HOST'] ) ? strtolower( (string) wp_unslash( $_SERVER['HTTP_HOST'] ) ) : ''; // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized
		$host = preg_replace( '/:\\d+$/', '', $host );
		if ( in_array( $host, array( 'localhost', '127.0.0.1', '::1', '[::1]' ), true ) ) {
			return true;
		}

		$remote_addr = isset( $_SERVER['REMOTE_ADDR'] ) ? (string) wp_unslash( $_SERVER['REMOTE_ADDR'] ) : ''; // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized
		return in_array( $remote_addr, array( '127.0.0.1', '::1' ), true );
	}

	/**
	 * Hash a raw device token.
	 */
	public static function hash_token( string $token ): string {
		return hash_hmac( 'sha256', $token, wp_salt( 'auth' ) );
	}

	/**
	 * Transient key for a one-time exchange code.
	 */
	private static function exchange_transient_key( string $code ): string {
		return 'floppy_exchange_' . hash_hmac( 'sha256', $code, wp_salt( 'auth' ) );
	}

	/**
	 * Extract bearer token from request headers.
	 */
	private static function get_bearer_token(): string {
		$header = '';
		if ( isset( $_SERVER['HTTP_AUTHORIZATION'] ) ) {
			$header = (string) wp_unslash( $_SERVER['HTTP_AUTHORIZATION'] ); // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized
		} elseif ( isset( $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ) ) {
			$header = (string) wp_unslash( $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ); // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized
		}

		if ( preg_match( '/Bearer\s+(.+)/i', $header, $matches ) ) {
			return trim( $matches[1] );
		}

		return '';
	}
}
