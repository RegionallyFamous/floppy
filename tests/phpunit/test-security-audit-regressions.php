<?php
/**
 * Security audit regression tests.
 *
 * @package Floppy
 */

/**
 * @covers Floppy_Auth
 * @covers Floppy_Admin
 * @covers Floppy_Rest
 * @covers Floppy_Storage
 */
final class Floppy_Security_Audit_Regressions_Test extends WP_UnitTestCase {
	/**
	 * Original server globals.
	 *
	 * @var array
	 */
	private $server_backup = array();

	/**
	 * Original query globals.
	 *
	 * @var array
	 */
	private $get_backup = array();

	/**
	 * Current test user id.
	 *
	 * @var int
	 */
	private $user_id = 0;

	public function set_up(): void {
		parent::set_up();

		$this->server_backup = $_SERVER;
		$this->get_backup = $_GET;

		Floppy_Schema::install();
		Floppy_Permissions::install_capabilities();
		update_option( 'floppy_private_probe', array( 'ok' => true, 'status' => 'pass', 'message' => 'test' ), false );
		update_option( 'floppy_settings', array( 'max_file_size' => 20 * MB_IN_BYTES, 'user_quota_bytes' => 20 * MB_IN_BYTES ), false );
		update_option(
			'floppy_compatibility',
			array(
				'desktop_mode'    => array( 'ok' => true, 'status' => 'pass', 'label' => 'Desktop Mode', 'message' => '' ),
				'https'          => array( 'ok' => true, 'status' => 'pass', 'label' => 'HTTPS', 'message' => '' ),
				'private_storage' => array( 'ok' => true, 'status' => 'pass', 'label' => 'Private storage', 'message' => '' ),
			),
			false
		);

		$this->truncate_floppy_tables();
		$this->user_id = self::factory()->user->create( array( 'role' => 'author' ) );
		wp_set_current_user( $this->user_id );
	}

	public function tear_down(): void {
		$_SERVER = $this->server_backup;
		$_GET = $this->get_backup;
		$this->reset_device_globals();
		wp_set_current_user( 0 );
		parent::tear_down();
	}

	public function test_device_token_does_not_authenticate_core_rest_route_when_query_mentions_floppy_namespace(): void {
		$token = $this->insert_device_token( $this->user_id );
		wp_set_current_user( 0 );
		$_GET = array();
		$_SERVER['HTTPS'] = 'on';
		$_SERVER['REQUEST_URI'] = '/wp-json/wp/v2/users?x=/wp-json/floppy/v1/files';
		$_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . $token;

		$this->assertFalse( Floppy_Auth::authenticate_bearer_token( false ) );
		$this->assertFalse( Floppy_Auth::is_device_auth() );
	}

	public function test_device_token_authenticates_exact_floppy_rest_route(): void {
		$token = $this->insert_device_token( $this->user_id );
		wp_set_current_user( 0 );
		$_GET = array();
		$_SERVER['HTTPS'] = 'on';
		$_SERVER['REQUEST_URI'] = '/wp-json/floppy/v1/files';
		$_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . $token;

		$this->assertSame( $this->user_id, Floppy_Auth::authenticate_bearer_token( false ) );
		$this->assertTrue( Floppy_Auth::is_device_auth() );
	}

	public function test_device_token_ignores_full_url_smuggled_in_rest_route_query_arg(): void {
		$token = $this->insert_device_token( $this->user_id );
		wp_set_current_user( 0 );
		$_GET = array( 'rest_route' => 'https://example.test/floppy/v1/files' );
		$_SERVER['HTTPS'] = 'on';
		$_SERVER['REQUEST_URI'] = '/wp-json/wp/v2/users?rest_route=https%3A%2F%2Fexample.test%2Ffloppy%2Fv1%2Ffiles';
		$_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . $token;

		$this->assertFalse( Floppy_Auth::authenticate_bearer_token( false ) );
		$this->assertFalse( Floppy_Auth::is_device_auth() );
	}

	public function test_device_token_rejects_plain_http_with_spoofed_loopback_host(): void {
		$token = $this->insert_device_token( $this->user_id );
		wp_set_current_user( 0 );
		$_GET = array();
		unset( $_SERVER['HTTPS'] );
		$_SERVER['SERVER_PORT'] = '80';
		$_SERVER['HTTP_HOST'] = 'localhost';
		$_SERVER['REMOTE_ADDR'] = '198.51.100.20';
		$_SERVER['REQUEST_URI'] = '/wp-json/floppy/v1/files';
		$_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . $token;

		$this->assertFalse( Floppy_Auth::authenticate_bearer_token( false ) );
		$this->assertFalse( Floppy_Auth::is_device_auth() );
	}

	public function test_admin_approval_success_does_not_render_unsafe_open_url(): void {
		require_once ABSPATH . 'wp-admin/includes/template.php';
		wp_set_current_user( self::factory()->user->create( array( 'role' => 'administrator' ) ) );
		$_GET = array(
			'page'            => 'floppy',
			'floppy-approved' => '1',
			'open'            => 'javascript%3Aalert%281%29',
		);

		ob_start();
		Floppy_Admin::render_page();
		$html = ob_get_clean();

		$this->assertStringNotContainsString( 'href="javascript:', $html );
	}

	public function test_admin_approval_success_renders_valid_floppy_open_url(): void {
		require_once ABSPATH . 'wp-admin/includes/template.php';
		wp_set_current_user( self::factory()->user->create( array( 'role' => 'administrator' ) ) );
		$_GET = array(
			'page'            => 'floppy',
			'floppy-approved' => '1',
			'open'            => rawurlencode( 'floppy://device-approved?code=flc_test&state=abc' ),
		);

		ob_start();
		Floppy_Admin::render_page();
		$html = ob_get_clean();

		$this->assertStringContainsString( 'href="floppy://device-approved?code=flc_test', $html );
	}

	public function test_search_limit_is_applied_after_user_scoping(): void {
		$other_user_id = self::factory()->user->create( array( 'role' => 'author' ) );
		$other = $this->insert_private_file( $other_user_id, 'needle-other.txt', '2026-01-01 00:00:02' );
		$owned = $this->insert_private_file( $this->user_id, 'needle-owned.txt', '2026-01-01 00:00:01' );
		$request = new WP_REST_Request( 'GET', '/floppy/v1/search' );
		$request->set_param( 'q', 'needle' );
		$request->set_param( 'limit', 1 );

		$response = Floppy_Rest::search( $request );
		$data = $response->get_data();

		$this->assertSame( $owned['id'], $data['items'][0]['id'] );
		$this->assertNotSame( $other['id'], $data['items'][0]['id'] );
	}

	public function test_sync_changes_caps_large_limit(): void {
		for ( $i = 0; $i < 501; ++$i ) {
			Floppy_Sync::append_event( 'file.updated', 'file', $i + 1, array( 'name' => 'file-' . $i ), $this->user_id );
		}

		$request = new WP_REST_Request( 'GET', '/floppy/v1/sync/changes' );
		$request->set_param( 'cursor', 0 );
		$request->set_param( 'limit', 10000000 );
		$response = Floppy_Rest::sync_changes( $request );
		$data = $response->get_data();

		$this->assertCount( 500, $data['events'] );
		$this->assertTrue( $data['has_more'] );
	}

	public function test_public_discovery_omits_version_and_limits(): void {
		wp_set_current_user( 0 );

		$data = Floppy_Rest::discovery()->get_data();

		$this->assertArrayNotHasKey( 'version', $data );
		$this->assertArrayNotHasKey( 'limits', $data );
	}

	public function test_dangerous_extension_blocks_php_version_suffixes(): void {
		$this->assertTrue( Floppy_Storage::has_dangerous_extension( 'shell.php7' ) );
		$this->assertTrue( Floppy_Storage::has_dangerous_extension( 'shell.php8' ) );
	}

	private function insert_device_token( int $user_id ): string {
		global $wpdb;

		$token = 'flp_' . wp_generate_password( 64, false, false );
		$wpdb->insert(
			Floppy_Schema::table( 'devices' ),
			array(
				'device_uuid'     => wp_generate_uuid4(),
				'user_id'         => $user_id,
				'device_name'     => 'Test Mac',
				'token_hash'      => Floppy_Auth::hash_token( $token ),
				'scope'           => 'files:read,files:write,sync',
				'status'          => 'active',
				'approved_at_gmt' => current_time( 'mysql', true ),
			),
			array( '%s', '%d', '%s', '%s', '%s', '%s', '%s' )
		);

		return $token;
	}

	private function insert_private_file( int $owner_id, string $name, string $updated_at_gmt ): array {
		global $wpdb;

		$uuid = wp_generate_uuid4();
		$row = array(
			'uuid'             => $uuid,
			'attachment_id'    => 0,
			'owner_id'         => $owner_id,
			'parent_id'        => 0,
			'name'             => $name,
			'normalized_name'  => Floppy_Storage::normalize_lookup_name( $name ),
			'mime_type'        => 'text/plain',
			'size_bytes'       => 0,
			'content_hash'     => '',
			'storage_key'      => '',
			'content_version'  => wp_generate_uuid4(),
			'metadata_version' => wp_generate_uuid4(),
			'status'           => 'active',
			'visibility'       => 'private',
			'created_at_gmt'   => $updated_at_gmt,
			'updated_at_gmt'   => $updated_at_gmt,
		);
		$wpdb->insert(
			Floppy_Schema::table( 'files' ),
			$row,
			array( '%s', '%d', '%d', '%d', '%s', '%s', '%s', '%d', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s' )
		);
		$row['id'] = (int) $wpdb->insert_id;

		return $row;
	}

	private function truncate_floppy_tables(): void {
		global $wpdb;

		foreach ( array( 'jobs', 'audit_log', 'tombstones', 'upload_sessions', 'devices', 'sync_events', 'acl_grants', 'item_names', 'folders', 'files' ) as $table ) {
			$wpdb->query( 'DELETE FROM ' . Floppy_Schema::table( $table ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		}
	}

	private function reset_device_globals(): void {
		unset(
			$GLOBALS['floppy_device_id'],
			$GLOBALS['floppy_device_uuid'],
			$GLOBALS['floppy_device_scope'],
			$GLOBALS['floppy_device_user_id']
		);
	}
}
