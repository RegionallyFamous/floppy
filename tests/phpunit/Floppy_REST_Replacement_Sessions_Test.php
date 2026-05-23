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

	public function test_complete_replace_session_updates_file_and_retains_version(): void {
		global $wpdb;

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
		$this->assertFileExists( $old_path );
		$this->assertSame( 1, (int) $wpdb->get_var( 'SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'file_versions' ) ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$this->assertSame( 'updated', file_get_contents( Floppy_Storage::path_for_key( $this->current_storage_key( $file['id'] ) ) ) );
	}

	public function test_list_and_restore_retained_version(): void {
		$file = $this->insert_private_file( 'hello' );
		$session = $this->create_replace_session_row( $file, 'updated' );

		$complete = new WP_REST_Request( 'POST', '/floppy/v1/upload-sessions/' . $session['session_uuid'] . '/complete' );
		$complete->set_param( 'uuid', $session['session_uuid'] );
		$complete_response = Floppy_Rest::complete_upload_session( $complete );
		$current = $complete_response->get_data();

		$list = new WP_REST_Request( 'GET', '/floppy/v1/files/' . $file['id'] . '/versions' );
		$list->set_param( 'id', $file['id'] );
		$list_response = Floppy_Rest::list_file_versions( $list );
		$versions = $list_response->get_data()['versions'];

		$this->assertCount( 1, $versions );
		$this->assertSame( 'hello', file_get_contents( Floppy_Storage::path_for_key( $file['storage_key'] ) ) );
		$this->assertArrayNotHasKey( 'storage_key', $versions[0] );
		$this->assertArrayHasKey( 'download_url', $versions[0] );
		$this->assertStringContainsString( '/versions/' . $versions[0]['id'] . '/download', $versions[0]['download_url'] );

		$restore = new WP_REST_Request( 'POST', '/floppy/v1/files/' . $file['id'] . '/versions/' . $versions[0]['id'] . '/restore' );
		$restore->set_param( 'id', $file['id'] );
		$restore->set_param( 'version_id', $versions[0]['id'] );
		$restore->set_param( 'content_version', $current['content_version'] );
		$restore_response = Floppy_Rest::restore_file_version( $restore );
		$restored = $restore_response->get_data();

		$this->assertSame( 5, $restored['size_bytes'] );
		$this->assertSame( 'hello', file_get_contents( Floppy_Storage::path_for_key( $this->current_storage_key( $file['id'] ) ) ) );
		$this->assertArrayNotHasKey( 'storage_key', $restored );
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

	public function test_conflict_lifecycle_is_redacted(): void {
		$file = $this->insert_private_file( 'hello' );
		$request = new WP_REST_Request( 'POST', '/floppy/v1/conflicts' );
		$request->set_param( 'file_id', $file['id'] );
		$request->set_param( 'reason', 'stale_content' );
		$request->set_param( 'local_name', 'hello (Floppy conflict).txt' );
		$request->set_param( 'server_content_version', $file['content_version'] );
		$request->set_param( 'local_content_hash', hash( 'sha256', 'local edit' ) );
		$request->set_param( 'local_size_bytes', 10 );

		$response = Floppy_Rest::record_conflict( $request );
		$data = $response->get_data();
		$json = wp_json_encode( $data );

		$this->assertSame( 201, $response->get_status() );
		$this->assertSame( 'open', $data['status'] );
		$this->assertStringNotContainsString( $file['storage_key'], $json );
		$this->assertStringNotContainsString( Floppy_Storage::path_for_key( $file['storage_key'] ), $json );

		$list = new WP_REST_Request( 'GET', '/floppy/v1/conflicts' );
		$list_response = Floppy_Rest::list_conflicts( $list );
		$this->assertCount( 1, $list_response->get_data()['conflicts'] );

		$resolve = new WP_REST_Request( 'POST', '/floppy/v1/conflicts/' . $data['conflict_uuid'] . '/resolve' );
		$resolve->set_param( 'uuid', $data['conflict_uuid'] );
		$resolve->set_param( 'action', 'resolve' );
		$resolved = Floppy_Rest::resolve_conflict( $resolve )->get_data();
		$this->assertSame( 'resolved', $resolved['status'] );
	}

	public function test_conflict_actions_endpoint_accepts_mac_action_names(): void {
		$file = $this->insert_private_file( 'hello' );
		$request = new WP_REST_Request( 'POST', '/floppy/v1/conflicts' );
		$request->set_param( 'file_id', $file['id'] );
		$request->set_param( 'reason', 'stale_content' );
		$request->set_param( 'local_name', 'hello (Floppy conflict).txt' );
		$request->set_param( 'local_content_hash', hash( 'sha256', 'local edit' ) );

		$created = Floppy_Rest::record_conflict( $request )->get_data();
		$action = new WP_REST_Request( 'POST', '/floppy/v1/conflicts/' . $created['conflict_uuid'] . '/actions' );
		$action->set_param( 'uuid', $created['conflict_uuid'] );
		$action->set_param( 'action', 'mark_resolved' );
		$response = Floppy_Rest::conflict_action( $action );
		$data = $response->get_data();
		$json = wp_json_encode( $data );

		$this->assertArrayHasKey( 'conflict', $data );
		$this->assertSame( 'resolved', $data['conflict']['status'] );
		$this->assertSame( 'resolved', $data['conflict']['state'] );
		$this->assertArrayHasKey( 'canonical_item', $data );
		$this->assertStringNotContainsString( $file['storage_key'], $json );
	}

	public function test_recovery_center_surfaces_restore_state_without_private_storage_leaks(): void {
		global $wpdb;

		$file = $this->insert_private_file( 'hello' );
		$active = $this->insert_private_file( 'recent' );
		$session = $this->create_replace_session_row( $file, 'updated' );
		$complete = new WP_REST_Request( 'POST', '/floppy/v1/upload-sessions/' . $session['session_uuid'] . '/complete' );
		$complete->set_param( 'uuid', $session['session_uuid'] );
		Floppy_Rest::complete_upload_session( $complete );

		$conflict = new WP_REST_Request( 'POST', '/floppy/v1/conflicts' );
		$conflict->set_param( 'file_id', $file['id'] );
		$conflict->set_param( 'reason', 'stale_content' );
		$conflict->set_param( 'local_name', 'hello (Floppy conflict).txt' );
		$conflict->set_param( 'local_content_hash', hash( 'sha256', 'local edit' ) );
		Floppy_Rest::record_conflict( $conflict );
		Floppy_Rest::enqueue_export();

		$wpdb->update(
			Floppy_Schema::table( 'files' ),
			array(
				'status'         => 'trashed',
				'deleted_at_gmt' => current_time( 'mysql', true ),
				'updated_at_gmt' => current_time( 'mysql', true ),
			),
			array( 'id' => $file['id'] ),
			array( '%s', '%s', '%s' ),
			array( '%d' )
		);

		$request = new WP_REST_Request( 'GET', '/floppy/v1/recovery' );
		$response = Floppy_Rest::recovery_center( $request );
		$data = $response->get_data();
		$json = wp_json_encode( $data );

		$this->assertSame( 'floppy-recovery-center-v1', $data['format'] );
		$this->assertFalse( $data['scope']['public_share_links'] );
		$this->assertTrue( $data['trust']['trash_restore_available'] );
		$this->assertSame( 1, $data['trash']['counts']['files'] );
		$this->assertSame( 'hello.txt', $data['trash']['items'][0]['name'] );
		$this->assertSame( $active['id'], $data['recents']['items'][0]['id'] );
		$this->assertNotEmpty( $data['versions']['items'] );
		$this->assertNotEmpty( $data['conflicts']['items'] );
		$this->assertNotEmpty( $data['exports']['latest'] );
		$this->assertStringNotContainsString( 'storage_key', $json );
		$this->assertStringNotContainsString( $file['storage_key'], $json );
		$this->assertStringNotContainsString( Floppy_Storage::path_for_key( $file['storage_key'] ), $json );
		$this->assertStringNotContainsString( 'export_key', $json );
	}

	public function test_unshare_normalizes_user_principal_like_share(): void {
		global $wpdb;

		$file = $this->insert_private_file( 'hello' );
		$grantee_id = self::factory()->user->create(
			array(
				'role'       => 'subscriber',
				'user_login' => 'floppy_grantee',
				'user_email' => 'floppy-grantee@example.test',
			)
		);

		$share = new WP_REST_Request( 'POST', '/floppy/v1/share' );
		$share->set_param( 'target_type', 'file' );
		$share->set_param( 'target_id', $file['id'] );
		$share->set_param( 'principal_type', 'user' );
		$share->set_param( 'principal_ref', 'floppy_grantee' );
		$share->set_param( 'capability', 'read' );
		$share_response = Floppy_Rest::share_target( $share );

		$this->assertInstanceOf( WP_REST_Response::class, $share_response );
		$this->assertSame( 1, (int) $wpdb->get_var( $wpdb->prepare( 'SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'acl_grants' ) . ' WHERE target_type = %s AND target_id = %d AND principal_ref = %s', 'file', $file['id'], (string) $grantee_id ) ) );

		$unshare = new WP_REST_Request( 'DELETE', '/floppy/v1/share' );
		$unshare->set_param( 'target_type', 'file' );
		$unshare->set_param( 'target_id', $file['id'] );
		$unshare->set_param( 'principal_type', 'user' );
		$unshare->set_param( 'principal_ref', 'floppy-grantee@example.test' );
		$unshare_response = Floppy_Rest::unshare_target( $unshare );

		$this->assertInstanceOf( WP_REST_Response::class, $unshare_response );
		$this->assertSame( 0, (int) $wpdb->get_var( $wpdb->prepare( 'SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'acl_grants' ) . ' WHERE target_type = %s AND target_id = %d', 'file', $file['id'] ) ) );
	}

	public function test_queued_folder_tree_status_rechecks_actor_permission(): void {
		global $wpdb;

		$actor_id = self::factory()->user->create( array( 'role' => 'author' ) );
		$folder = $this->insert_private_folder( $actor_id );
		$author = get_role( 'author' );

		$this->assertNotNull( $author );
		$this->assertTrue( Floppy_Permissions::can_write( 'folder', $folder['id'], $actor_id ) );

		try {
			$author->remove_cap( Floppy_Permissions::CAP_WRITE );
			$result = Floppy_Rest::run_folder_tree_status_job(
				array(
					'user_id'          => $actor_id,
					'folder_id'        => $folder['id'],
					'status'           => 'trashed',
					'event_type'       => 'folder.trashed',
					'metadata_version' => $folder['metadata_version'],
				)
			);
		} finally {
			$author->add_cap( Floppy_Permissions::CAP_WRITE );
		}

		$status = (string) $wpdb->get_var(
			$wpdb->prepare(
				'SELECT status FROM ' . Floppy_Schema::table( 'folders' ) . ' WHERE id = %d',
				$folder['id']
			)
		);

		$this->assertFalse( $result['ok'] );
		$this->assertSame( 'Queued actor can no longer write this folder.', $result['message'] );
		$this->assertSame( 'active', $status );
	}

	public function test_thumbnail_for_non_image_is_rejected_privately(): void {
		$file = $this->insert_private_file( 'hello' );
		$request = new WP_REST_Request( 'GET', '/floppy/v1/files/' . $file['id'] . '/thumbnail' );
		$request->set_param( 'id', $file['id'] );

		$response = Floppy_Rest::thumbnail_file( $request );

		$this->assertWPError( $response );
		$this->assertSame( 415, $response->get_error_data()['status'] );
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

	private function insert_private_folder( int $owner_id ): array {
		global $wpdb;

		$now = current_time( 'mysql', true );
		$row = array(
			'uuid'             => wp_generate_uuid4(),
			'owner_id'         => $owner_id,
			'parent_id'        => 0,
			'name'             => 'Private Folder',
			'normalized_name'  => 'private folder',
			'metadata_version' => wp_generate_uuid4(),
			'status'           => 'active',
			'created_at_gmt'   => $now,
			'updated_at_gmt'   => $now,
		);
		$wpdb->insert(
			Floppy_Schema::table( 'folders' ),
			$row,
			array( '%s', '%d', '%d', '%s', '%s', '%s', '%s', '%s', '%s' )
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
