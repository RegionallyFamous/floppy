<?php
/**
 * Schema repair integration tests.
 *
 * @package Floppy
 */

/**
 * @covers Floppy_Schema
 */
final class Floppy_Schema_Repair_Test extends WP_UnitTestCase {
	/**
	 * Current test user id.
	 *
	 * @var int
	 */
	private $user_id = 0;

	public function set_up(): void {
		parent::set_up();

		Floppy_Schema::install();
		update_option( 'floppy_private_probe', array( 'ok' => true, 'message' => 'test' ), false );
		$this->truncate_floppy_tables();
		$this->user_id = self::factory()->user->create( array( 'role' => 'administrator' ) );
	}

	public function test_repair_dry_run_reports_missing_and_orphaned_name_reservations(): void {
		global $wpdb;

		$file = $this->insert_private_file( 'repair me' );
		$wpdb->insert(
			Floppy_Schema::table( 'item_names' ),
			array(
				'parent_id'       => 0,
				'normalized_name' => 'ghost.txt',
				'target_type'     => 'file',
				'target_id'       => 999999,
				'status'          => 'reserved',
				'created_at_gmt'  => current_time( 'mysql', true ),
				'updated_at_gmt'  => current_time( 'mysql', true ),
			),
			array( '%d', '%s', '%s', '%d', '%s', '%s', '%s' )
		);

		$report = Floppy_Schema::repair( false );

		$this->assertFalse( $report['apply'] );
		$this->assertGreaterThanOrEqual( 1, $report['item_names']['missing'] );
		$this->assertGreaterThanOrEqual( 1, $report['orphaned_name_reservations']['orphaned'] );
		$this->assertStringNotContainsString( $file['storage_key'], wp_json_encode( $report ) );
	}

	public function test_repair_apply_backfills_item_name_reservations(): void {
		global $wpdb;

		$file = $this->insert_private_file( 'repair me' );
		$report = Floppy_Schema::repair( true );
		$reservation = $wpdb->get_var(
			$wpdb->prepare(
				'SELECT id FROM ' . Floppy_Schema::table( 'item_names' ) . ' WHERE target_type = %s AND target_id = %d',
				'file',
				$file['id']
			)
		);

		$this->assertTrue( $report['apply'] );
		$this->assertNotEmpty( $reservation );
	}

	public function test_repair_reports_blob_integrity_without_private_paths(): void {
		$file = $this->insert_private_file( 'repair me' );
		@unlink( Floppy_Storage::path_for_key( $file['storage_key'] ) ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged

		$report = Floppy_Schema::repair( false );
		$json = wp_json_encode( $report );

		$this->assertGreaterThanOrEqual( 1, $report['blob_integrity']['missing'] );
		$this->assertStringNotContainsString( $file['storage_key'], $json );
		$this->assertStringNotContainsString( Floppy_Storage::path_for_key( $file['storage_key'] ), $json );
	}

	public function test_repair_apply_creates_missing_tombstones_and_removes_orphaned_acl_grants(): void {
		global $wpdb;

		$file = $this->insert_private_file( 'repair me' );
		$wpdb->update(
			Floppy_Schema::table( 'files' ),
			array( 'status' => 'deleted', 'deleted_at_gmt' => current_time( 'mysql', true ) ),
			array( 'id' => $file['id'] ),
			array( '%s', '%s' ),
			array( '%d' )
		);
		$wpdb->insert(
			Floppy_Schema::table( 'acl_grants' ),
			array(
				'target_type'    => 'file',
				'target_id'      => 999999,
				'principal_type' => 'user',
				'principal_ref'  => (string) $this->user_id,
				'capability'     => 'read',
				'state'          => 'accepted',
				'created_by'     => $this->user_id,
				'created_at_gmt' => current_time( 'mysql', true ),
				'updated_at_gmt' => current_time( 'mysql', true ),
			),
			array( '%s', '%d', '%s', '%s', '%s', '%s', '%d', '%s', '%s' )
		);

		$dry_run = Floppy_Schema::repair( false );
		$applied = Floppy_Schema::repair( true );
		$tombstone = (int) $wpdb->get_var(
			$wpdb->prepare(
				'SELECT id FROM ' . Floppy_Schema::table( 'tombstones' ) . ' WHERE target_type = %s AND target_id = %d',
				'file',
				$file['id']
			)
		);
		$acl_count = (int) $wpdb->get_var( 'SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'acl_grants' ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared

		$this->assertGreaterThanOrEqual( 1, $dry_run['missing_tombstones']['missing'] );
		$this->assertGreaterThanOrEqual( 1, $dry_run['orphaned_acl_grants']['orphaned'] );
		$this->assertTrue( $applied['apply'] );
		$this->assertGreaterThan( 0, $tombstone );
		$this->assertSame( 0, $acl_count );
	}

	public function test_repair_reports_stale_versions_conflicts_and_thumbnails(): void {
		global $wpdb;

		$now = current_time( 'mysql', true );
		$wpdb->insert(
			Floppy_Schema::table( 'file_versions' ),
			array(
				'version_uuid'     => wp_generate_uuid4(),
				'file_id'          => 999999,
				'file_uuid'        => wp_generate_uuid4(),
				'owner_id'         => $this->user_id,
				'name'             => 'stale.txt',
				'mime_type'        => 'text/plain',
				'size_bytes'       => 5,
				'content_hash'     => hash( 'sha256', 'stale' ),
				'storage_key'      => '',
				'content_version'  => wp_generate_uuid4(),
				'metadata_version' => wp_generate_uuid4(),
				'reason'           => 'test',
				'created_by'       => $this->user_id,
				'created_at_gmt'   => $now,
			),
			array( '%s', '%d', '%s', '%d', '%s', '%s', '%d', '%s', '%s', '%s', '%s', '%s', '%d', '%s' )
		);
		$wpdb->insert(
			Floppy_Schema::table( 'conflicts' ),
			array(
				'conflict_uuid'         => wp_generate_uuid4(),
				'owner_id'              => $this->user_id,
				'file_id'               => 999999,
				'status'                => 'open',
				'reason'                => 'stale_content',
				'local_name'            => 'stale.txt',
				'local_size_bytes'      => 5,
				'created_at_gmt'        => $now,
				'updated_at_gmt'        => $now,
			),
			array( '%s', '%d', '%d', '%s', '%s', '%s', '%d', '%s', '%s' )
		);
		$wpdb->insert(
			Floppy_Schema::table( 'thumbnails' ),
			array(
				'file_id'         => 999999,
				'file_uuid'       => wp_generate_uuid4(),
				'content_version' => wp_generate_uuid4(),
				'status'          => 'ready',
				'storage_key'     => '',
				'created_at_gmt'  => $now,
				'updated_at_gmt'  => $now,
			),
			array( '%d', '%s', '%s', '%s', '%s', '%s', '%s' )
		);

		$dry_run = Floppy_Schema::repair( false );
		$applied = Floppy_Schema::repair( true );

		$this->assertGreaterThanOrEqual( 1, $dry_run['stale_versions']['stale'] );
		$this->assertGreaterThanOrEqual( 1, $dry_run['stale_conflicts']['stale'] );
		$this->assertGreaterThanOrEqual( 1, $dry_run['stale_thumbnails']['stale'] );
		$this->assertSame( 0, (int) $wpdb->get_var( 'SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'file_versions' ) ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$this->assertSame( 1, (int) $wpdb->get_var( "SELECT COUNT(*) FROM " . Floppy_Schema::table( 'conflicts' ) . " WHERE status = 'stale'" ) ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$this->assertSame( 0, (int) $wpdb->get_var( 'SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'thumbnails' ) ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$this->assertTrue( $applied['apply'] );
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
			'name'             => 'repair.txt',
			'normalized_name'  => 'repair.txt',
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
