<?php
/**
 * REST integration tests for resumable replacement sessions.
 *
 * @package Floppy
 */

/**
 * @covers Floppy_Rest
 */
final class Floppy_REST_Replacement_Sessions_Test extends WP_UnitTestCase {
	/**
	 * Current test user id.
	 *
	 * @var int
	 */
	private $user_id = 0;

	public function set_up(): void {
		parent::set_up();

		Floppy_Schema::install();
		Floppy_Permissions::install_capabilities();
		update_option( 'floppy_private_probe', array( 'ok' => true, 'message' => 'test' ), false );
		update_option( 'floppy_settings', array( 'max_file_size' => 20 * MB_IN_BYTES, 'user_quota_bytes' => 20 * MB_IN_BYTES ), false );

		$this->truncate_floppy_tables();
		$this->user_id = self::factory()->user->create( array( 'role' => 'administrator' ) );
		wp_set_current_user( $this->user_id );
	}

	public function tear_down(): void {
		wp_set_current_user( 0 );
		remove_all_filters( 'floppy_validate_private_upload' );
		parent::tear_down();
	}

	public function test_create_replace_session_returns_operation_dto(): void {
		$file = $this->insert_private_file( 'hello' );
		$request = new WP_REST_Request( 'POST', '/floppy/v1/files/' . $file['id'] . '/replace-sessions' );
		$request->set_param( 'id', $file['id'] );
		$request->set_param( 'content_version', $file['content_version'] );
		$request->set_param( 'total_size', 7 );
		$request->set_param( 'content_hash', hash( 'sha256', 'updated' ) );
		$request->set_param( 'mime_type', 'text/plain' );

		$response = Floppy_Rest::create_replace_session( $request );

		$this->assertInstanceOf( WP_REST_Response::class, $response );
		$this->assertSame( 201, $response->get_status() );
		$this->assertSame( 'replace', $response->get_data()['operation'] );
		$this->assertSame( $file['id'], $response->get_data()['target_file_id'] );
	}

	public function test_create_replace_session_rejects_stale_content_version(): void {
		$file = $this->insert_private_file( 'hello' );
		$request = new WP_REST_Request( 'POST', '/floppy/v1/files/' . $file['id'] . '/replace-sessions' );
		$request->set_param( 'id', $file['id'] );
		$request->set_param( 'content_version', 'stale-version' );
		$request->set_param( 'total_size', 7 );

		$response = Floppy_Rest::create_replace_session( $request );

		$this->assertWPError( $response );
		$this->assertSame( 409, $response->get_error_data()['status'] );
		$this->assertArrayNotHasKey( 'storage_key', $response->get_error_data()['server'] );
	}

	public function test_complete_replace_session_updates_file_and_removes_old_blob(): void {
		$file = $this->insert_private_file( 'hello' );
		$old_path = Floppy_Storage::path_for_key( $file['storage_key'] );
		$session = $this->create_replace_session_row( $file, 'updated' );

		$request = new WP_REST_Request( 'POST', '/floppy/v1/upload-sessions/' . $session['session_uuid'] . '/complete' );
		$request->set_param( 'uuid', $session['session_uuid'] );
		$response = Floppy_Rest::complete_upload_session( $request );

		$this->assertInstanceOf( WP_REST_Response::class, $response );
		$data = $response->get_data();
		$this->assertSame( 'file', $data['kind'] );
		$this->assertSame( 7, $data['size_bytes'] );
		$this->assertArrayNotHasKey( 'storage_key', $data );
		$this->assertFileDoesNotExist( $old_path );
		$this->assertSame( 'updated', file_get_contents( Floppy_Storage::path_for_key( $this->current_storage_key( $file['id'] ) ) ) );
	}

	public function test_complete_replace_session_respects_malware_scan_hook(): void {
		$file = $this->insert_private_file( 'hello' );
		$session = $this->create_replace_session_row( $file, 'blocked' );
		add_filter(
			'floppy_validate_private_upload',
			static function () {
				return new WP_Error( 'floppy_test_blocked', 'Blocked by test scanner.', array( 'status' => 415 ) );
			}
		);

		$request = new WP_REST_Request( 'POST', '/floppy/v1/upload-sessions/' . $session['session_uuid'] . '/complete' );
		$request->set_param( 'uuid', $session['session_uuid'] );
		$response = Floppy_Rest::complete_upload_session( $request );

		$this->assertWPError( $response );
		$this->assertSame( 'floppy_test_blocked', $response->get_error_code() );
		$this->assertSame( $file['storage_key'], $this->current_storage_key( $file['id'] ) );
	}

	public function test_sync_payload_sanitizes_private_storage_fields(): void {
		$file = $this->insert_private_file( 'hello' );
		Floppy_Sync::append_event(
			'file.updated',
			'file',
			$file['id'],
			$file,
			$this->user_id
		);

		$changes = Floppy_Sync::get_changes( 0, 10, $this->user_id );

		$this->assertIsArray( $changes );
		$this->assertCount( 1, $changes['events'] );
		$payload = $changes['events'][0]['payload'];
		$this->assertSame( 'file', $payload['kind'] );
		$this->assertArrayNotHasKey( 'storage_key', $payload );
		$this->assertArrayNotHasKey( 'path', $payload );
		$this->assertArrayHasKey( 'download_url', $payload );
	}

	private function truncate_floppy_tables(): void {
		global $wpdb;

		foreach ( array( 'jobs', 'audit_log', 'tombstones', 'upload_sessions', 'devices', 'sync_events', 'acl_grants', 'item_names', 'folders', 'files' ) as $table ) {
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
			'owner_id'         => $this->user_id,
			'parent_id'        => 0,
			'name'             => 'hello.txt',
			'normalized_name'  => 'hello.txt',
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

	private function create_replace_session_row( array $file, string $contents ): array {
		global $wpdb;

		$uuid = wp_generate_uuid4();
		$key = 'chunks/' . Floppy_Storage::storage_key( $uuid, 'part' );
		$path = Floppy_Storage::path_for_key( $key );
		wp_mkdir_p( dirname( $path ) );
		file_put_contents( $path, $contents ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_file_put_contents
		$now = current_time( 'mysql', true );
		$row = array(
			'session_uuid'         => $uuid,
			'user_id'              => $this->user_id,
			'parent_id'            => 0,
			'filename'             => 'hello.txt',
			'total_size'           => strlen( $contents ),
			'received_bytes'       => strlen( $contents ),
			'content_hash'         => hash( 'sha256', $contents ),
			'mime_type'            => 'text/plain',
			'storage_key'          => $key,
			'operation'            => 'replace',
			'target_file_id'       => $file['id'],
			'base_content_version' => $file['content_version'],
			'status'               => 'open',
			'expires_at_gmt'       => gmdate( 'Y-m-d H:i:s', time() + DAY_IN_SECONDS ),
			'created_at_gmt'       => $now,
			'updated_at_gmt'       => $now,
		);
		$wpdb->insert(
			Floppy_Schema::table( 'upload_sessions' ),
			$row,
			array( '%s', '%d', '%d', '%s', '%d', '%d', '%s', '%s', '%s', '%s', '%d', '%s', '%s', '%s', '%s', '%s' )
		);
		$row['id'] = (int) $wpdb->insert_id;
		return $row;
	}

	private function current_storage_key( int $file_id ): string {
		global $wpdb;

		return (string) $wpdb->get_var(
			$wpdb->prepare(
				'SELECT storage_key FROM ' . Floppy_Schema::table( 'files' ) . ' WHERE id = %d',
				$file_id
			)
		);
	}
}
