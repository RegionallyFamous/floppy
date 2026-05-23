<?php
/**
 * REST access policy.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Capability and device-scope checks for REST routes.
 */
final class Floppy_Rest_Access {
	/**
	 * Require a logged-in user.
	 */
	public static function require_user() {
		return is_user_logged_in() ? true : new WP_Error( 'floppy_rest_forbidden', __( 'Authentication required.', 'floppy' ), array( 'status' => 401 ) );
	}

	/**
	 * Require file read scope.
	 */
	public static function require_read() {
		$scope = self::require_scope( 'files:read' );
		if ( is_wp_error( $scope ) ) {
			return $scope;
		}

		return Floppy_Permissions::user_can_site( get_current_user_id(), 'read' )
			? true
			: new WP_Error( 'floppy_rest_forbidden', __( 'You do not have access to Floppy files.', 'floppy' ), array( 'status' => 403 ) );
	}

	/**
	 * Require file write scope.
	 */
	public static function require_write() {
		$scope = self::require_scope( 'files:write' );
		if ( is_wp_error( $scope ) ) {
			return $scope;
		}

		return Floppy_Permissions::user_can_site( get_current_user_id(), 'write' )
			? true
			: new WP_Error( 'floppy_rest_forbidden', __( 'You cannot write Floppy files.', 'floppy' ), array( 'status' => 403 ) );
	}

	/**
	 * Require sync scope.
	 */
	public static function require_sync() {
		$scope = self::require_scope( 'sync' );
		if ( is_wp_error( $scope ) ) {
			return $scope;
		}

		return Floppy_Permissions::user_can_site( get_current_user_id(), 'read' )
			? true
			: new WP_Error( 'floppy_rest_forbidden', __( 'You do not have access to Floppy sync.', 'floppy' ), array( 'status' => 403 ) );
	}

	/**
	 * Require a browser-authenticated WordPress session, not a device token.
	 */
	public static function require_browser_session() {
		$user = self::require_user();
		if ( is_wp_error( $user ) ) {
			return $user;
		}

		if ( Floppy_Auth::is_device_auth() || self::is_application_password_auth() ) {
			return new WP_Error( 'floppy_browser_session_required', __( 'This action requires a browser-approved WordPress session.', 'floppy' ), array( 'status' => 403 ) );
		}

		return true;
	}

	/**
	 * Require an authenticated WordPress user who is not already using a Floppy device token.
	 */
	public static function require_device_authorization() {
		$user = self::require_user();
		if ( is_wp_error( $user ) ) {
			return $user;
		}

		if ( Floppy_Auth::is_device_auth() ) {
			return new WP_Error( 'floppy_browser_session_required', __( 'Device authorization requires a WordPress session or temporary Application Password.', 'floppy' ), array( 'status' => 403 ) );
		}

		return Floppy_Permissions::user_can_site( get_current_user_id(), 'read' )
			? true
			: new WP_Error( 'floppy_rest_forbidden', __( 'You do not have access to Floppy device authorization.', 'floppy' ), array( 'status' => 403 ) );
	}

	/**
	 * Allow browser sessions to revoke any owned device and device tokens to revoke themselves.
	 */
	public static function require_device_revoke( WP_REST_Request $request ) {
		$user = self::require_user();
		if ( is_wp_error( $user ) ) {
			return $user;
		}

		if ( Floppy_Auth::is_device_auth() ) {
			$current_uuid = (string) ( $GLOBALS['floppy_device_uuid'] ?? '' );
			$requested_uuid = sanitize_text_field( (string) $request['uuid'] );
			return hash_equals( $current_uuid, $requested_uuid )
				? true
				: new WP_Error( 'floppy_forbidden', __( 'Device tokens can only revoke themselves.', 'floppy' ), array( 'status' => 403 ) );
		}

		return true;
	}

	/**
	 * Require admin.
	 */
	public static function require_admin() {
		if ( Floppy_Auth::is_device_auth() || self::is_application_password_auth() ) {
			return new WP_Error( 'floppy_browser_session_required', __( 'Administrator diagnostics require a browser session.', 'floppy' ), array( 'status' => 403 ) );
		}

		return current_user_can( Floppy_Permissions::CAP_MANAGE ) || current_user_can( 'manage_options' )
			? true
			: new WP_Error( 'floppy_rest_forbidden', __( 'Administrator access required.', 'floppy' ), array( 'status' => 403 ) );
	}

	/**
	 * Require a logged-in user and, for device tokens, a matching scope.
	 */
	private static function require_scope( string $scope ) {
		$user = self::require_user();
		if ( is_wp_error( $user ) ) {
			return $user;
		}

		if ( ! Floppy_Auth::current_device_can( $scope ) ) {
			return new WP_Error( 'floppy_scope_forbidden', __( 'The device token does not include the required Floppy scope.', 'floppy' ), array( 'status' => 403 ) );
		}

		return true;
	}

	/**
	 * Whether core authenticated this REST request with an Application Password.
	 */
	private static function is_application_password_auth(): bool {
		return function_exists( 'rest_get_authenticated_app_password' ) && (bool) rest_get_authenticated_app_password();
	}
}
