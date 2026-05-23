<?php
/**
 * REST integration tests for admin maintenance diagnostics.
 *
 * @package Floppy
 */

/**
 * @covers Floppy_Rest
 * @covers Floppy_Diagnostics
 */
final class Floppy_REST_Maintenance_Test extends WP_UnitTestCase {
	/**
	 * Admin user id.
	 *
	 * @var int
	 */
	private $admin_id = 0;

	public function set_up(): void {
		parent::set_up();

		Floppy_Schema::install();
		Floppy_Permissions::install_capabilities();
		update_option( 'floppy_private_probe', array( 'ok' => true, 'status' => 'pass', 'message' => 'test' ), false );
		$this->truncate_floppy_tables();
		$this->admin_id = self::factory()->user->create( array( 'role' => 'administrator' ) );
		wp_set_current_user( $this->admin_id );
	}

	public function tear_down(): void {
		wp_set_current_user( 0 );
		parent::tear_down();
	}

	public function test_health_includes_support_correlation_id(): void {
		$response = Floppy_Rest::health();
		$data = $response->get_data();

		$this->assertArrayHasKey( 'support', $data );
		$this->assertMatchesRegularExpression( '/^floppy-[a-f0-9-]{36}$/', $data['support']['correlation_id'] );
	}

	public function test_admin_debug_bundle_is_redacted_and_has_deep_sections(): void {
		$file = $this->insert_private_file( 'secret contents' );
		$request = new WP_REST_Request( 'GET', '/floppy/v1/debug-bundle' );
		$response = Floppy_Rest::debug_bundle( $request );
		$data = $response->get_data();
		$json = wp_json_encode( $data );

		$this->assertSame( 'floppy-debug-bundle-v2', $data['format'] );
		$this->assertArrayHasKey( 'support', $data );
		$this->assertArrayHasKey( 'private_storage', $data );
		$this->assertArrayHasKey( 'sync', $data );
		$this->assertArrayHasKey( 'storage', $data );
		$this->assertArrayHasKey( 'conflicts', $data );
		$this->assertArrayHasKey( 'versions', $data );
		$this->assertArrayHasKey( 'thumbnails', $data );
		$this->assertArrayHasKey( 'release_evidence', $data );
		$this->assertTrue( $data['privacy']['no_external_services'] );
		$this->assertStringNotContainsString( $file['storage_key'], $json );
		$this->assertStringNotContainsString( Floppy_Storage::path_for_key( $file['storage_key'] ), $json );
	}

	public function test_release_evidence_is_redacted_and_has_beta_gates(): void {
		$file = $this->insert_private_file( 'secret contents' );
		$response = Floppy_Rest::release_evidence();
		$data = $response->get_data();
		$json = wp_json_encode( $data );

		$this->assertSame( 'floppy-beta-evidence-v1', $data['format'] );
		$this->assertTrue( $data['privacy']['no_external_services'] );
		$this->assertSame( 'ci-required', $data['release_gates']['phpunit_wordpress'] );
		$this->assertArrayHasKey( 'developer_id_notarization', $data['release_gates'] );
		$this->assertStringNotContainsString( $file['storage_key'], $json );
		$this->assertStringNotContainsString( Floppy_Storage::path_for_key( $file['storage_key'] ), $json );
	}

	public function test_admin_repair_endpoint_supports_dry_run_and_apply(): void {
		global $wpdb;

		$file = $this->insert_private_file( 'repair me' );
		$wpdb->insert(
			Floppy_Schema::table( 'acl_grants' ),
			array(
				'target_type'    => 'file',
				'target_id'      => 999999,
				'principal_type' => 'user',
				'principal_ref'  => (string) $this->admin_id,
				'capability'     => 'read',
				'state'          => 'accepted',
				'created_by'     => $this->admin_id,
				'created_at_gmt' => current_time( 'mysql', true ),
				'updated_at_gmt' => current_time( 'mysql', true ),
			),
			array( '%s', '%d', '%s', '%s', '%s', '%s', '%d', '%s', '%s' )
		);

		$dry_run = new WP_REST_Request( 'GET', '/floppy/v1/maintenance/repair' );
		$dry_response = Floppy_Rest::maintenance_repair( $dry_run );
		$dry_data = $dry_response->get_data();
		$this->assertFalse( $dry_data['apply'] );
		$this->assertGreaterThanOrEqual( 1, $dry_data['report']['orphaned_acl_grants']['orphaned'] );

		$apply = new WP_REST_Request( 'POST', '/floppy/v1/maintenance/repair' );
		$apply->set_param( 'apply', true );
		$apply_response = Floppy_Rest::maintenance_repair( $apply );
		$apply_data = $apply_response->get_data();
		$remaining = (int) $wpdb->get_var( 'SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'acl_grants' ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared

		$this->assertTrue( $apply_data['apply'] );
		$this->assertSame( 0, $remaining );
		$this->assertStringNotContainsString( $file['storage_key'], wp_json_encode( $apply_data ) );
	}

	public function test_maintenance_requires_admin_browser_session(): void {
		wp_set_current_user( self::factory()->user->create( array( 'role' => 'subscriber' ) ) );

		$result = Floppy_Rest::require_admin();

		$this->assertWPError( $result );
		$this->assertSame( 403, $result->get_error_data()['status'] );
	}

	private function truncate_floppy_tables(): void {
		global $wpdb;

		foreach ( array( 'jobs', 'thumbnails', 'conflicts', 'file_versions', 'audit_log', 'tombstones', 'upload_sessions', 'devices', 'sync_events', 'acl_grants', 'item_names', 'folders', 'files' ) as $table ) {
			$wpdb->query( 'DELETE FROM ' . Floppy_Schema::table( $table ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		}
	}

	private function insert_private_file( string $contents ): array {
		global $wpdb;

		$uuid = wp_generate_uuid4();
		$key = Floppy_Storage::storage_key( $uuid, 'txt' );
		$path = Floppy_Storage::path_for_key( $key );
		wp_mkdir_p( dirname( $path ) );
		file_put_contents( $path, $contents ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_file_put_contents
		$now = current_time( 'mysql', true );
		$row = array(
			'uuid'             => $uuid,
			'attachment_id'    => 0,
			'owner_id'         => $this->admin_id,
			'parent_id'        => 0,
			'name'             => 'maintenance.txt',
			'normalized_name'  => 'maintenance.txt',
			'mime_type'        => 'text/plain',
			'size_bytes'       => strlen( $contents ),
			'content_hash'     => hash( 'sha256', $contents ),
			'storage_key'      => $key,
			'content_version'  => wp_generate_uuid4(),
			'metadata_version' => wp_generate_uuid4(),
			'status'           => 'active',
			'visibility'       => 'private',
			'created_at_gmt'   => $now,
			'updated_at_gmt'   => $now,
		);
		$wpdb->insert(
			Floppy_Schema::table( 'files' ),
			$row,
			array( '%s', '%d', '%d', '%d', '%s', '%s', '%s', '%d', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s' )
		);
		$row['id'] = (int) $wpdb->insert_id;
		return $row;
	}
}
