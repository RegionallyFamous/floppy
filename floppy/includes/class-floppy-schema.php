<?php
/**
 * Database schema and table helpers.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Manages Floppy custom tables.
 */
final class Floppy_Schema {
	/**
	 * Maximum rows each repair pass should inspect or mutate in one request.
	 */
	private const REPAIR_BATCH_LIMIT = 1000;

	/**
	 * Return fully qualified table name.
	 */
	public static function table( string $name ): string {
		global $wpdb;

		return $wpdb->prefix . 'floppy_' . $name;
	}

	/**
	 * Install or upgrade Floppy schema.
	 */
	public static function install(): void {
		global $wpdb;

		require_once ABSPATH . 'wp-admin/includes/upgrade.php';

		$charset = $wpdb->get_charset_collate();

		$sql = array();

		$sql[] = 'CREATE TABLE ' . self::table( 'files' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			uuid char(36) NOT NULL,
			attachment_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			owner_id bigint(20) unsigned NOT NULL,
			parent_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			name varchar(255) NOT NULL,
			normalized_name varchar(255) NOT NULL,
			mime_type varchar(127) NOT NULL DEFAULT '',
			size_bytes bigint(20) unsigned DEFAULT 0 NOT NULL,
			content_hash char(64) NOT NULL DEFAULT '',
			storage_key varchar(255) NOT NULL DEFAULT '',
			storage_adapter varchar(32) NOT NULL DEFAULT 'local',
			blob_format varchar(32) NOT NULL DEFAULT 'plain',
			hash_algorithm varchar(32) NOT NULL DEFAULT 'sha256',
			encryption_state varchar(32) NOT NULL DEFAULT 'none',
			key_id varchar(191) NOT NULL DEFAULT '',
			nonce varchar(191) NOT NULL DEFAULT '',
			content_version char(36) NOT NULL,
			metadata_version char(36) NOT NULL,
			status varchar(20) NOT NULL DEFAULT 'active',
			visibility varchar(20) NOT NULL DEFAULT 'private',
			conflict_of bigint(20) unsigned DEFAULT 0 NOT NULL,
			created_at_gmt datetime NOT NULL,
			updated_at_gmt datetime NOT NULL,
			deleted_at_gmt datetime DEFAULT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY uuid (uuid),
			KEY owner_parent_name (owner_id,parent_id,normalized_name(120)),
			KEY parent_name (parent_id,normalized_name(120)),
			KEY parent_status_id (parent_id,status,id),
			KEY owner_parent_status_id (owner_id,parent_id,status,id),
			KEY owner_normalized_status_id (owner_id,normalized_name(120),status,id),
			KEY normalized_status_id (normalized_name(120),status,id),
			KEY owner_status_updated_id (owner_id,status,updated_at_gmt,id),
			KEY updated_id (updated_at_gmt,id),
			KEY attachment_id (attachment_id),
			KEY content_hash (content_hash),
			KEY conflict_of (conflict_of)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'folders' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			uuid char(36) NOT NULL,
			owner_id bigint(20) unsigned NOT NULL,
			parent_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			name varchar(255) NOT NULL,
			normalized_name varchar(255) NOT NULL,
			metadata_version char(36) NOT NULL,
			status varchar(20) NOT NULL DEFAULT 'active',
			created_at_gmt datetime NOT NULL,
			updated_at_gmt datetime NOT NULL,
			deleted_at_gmt datetime DEFAULT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY uuid (uuid),
			KEY owner_parent_name (owner_id,parent_id,normalized_name(120)),
			KEY parent_name (parent_id,normalized_name(120)),
			KEY parent_status_id (parent_id,status,id),
			KEY owner_parent_status_id (owner_id,parent_id,status,id),
			KEY owner_normalized_status_id (owner_id,normalized_name(120),status,id),
			KEY normalized_status_id (normalized_name(120),status,id),
			KEY owner_status_updated_id (owner_id,status,updated_at_gmt,id),
			KEY updated_id (updated_at_gmt,id)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'item_names' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			parent_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			normalized_name varchar(255) NOT NULL,
			target_type varchar(20) NOT NULL,
			target_id bigint(20) unsigned NOT NULL,
			status varchar(20) NOT NULL DEFAULT 'active',
			created_at_gmt datetime NOT NULL,
			updated_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY live_name (parent_id,normalized_name(120),status),
			UNIQUE KEY target_lookup (target_type,target_id),
			KEY parent_lookup (parent_id,status)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'acl_grants' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			target_type varchar(20) NOT NULL,
			target_id bigint(20) unsigned NOT NULL,
			principal_type varchar(20) NOT NULL,
			principal_ref varchar(191) NOT NULL,
			capability varchar(20) NOT NULL DEFAULT 'read',
			state varchar(20) NOT NULL DEFAULT 'accepted',
			created_by bigint(20) unsigned NOT NULL,
			created_at_gmt datetime NOT NULL,
			updated_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY target_principal (target_type,target_id,principal_type,principal_ref),
			KEY principal_lookup (principal_type,principal_ref,state),
			KEY target_lookup (target_type,target_id,state)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'sync_events' ) . " (
			seq bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			event_uuid char(36) NOT NULL,
			actor_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			target_type varchar(20) NOT NULL,
			target_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			event_type varchar(64) NOT NULL,
			parent_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			metadata_version char(36) NOT NULL DEFAULT '',
			content_version char(36) NOT NULL DEFAULT '',
			payload_json longtext,
			created_at_gmt datetime NOT NULL,
			PRIMARY KEY  (seq),
			UNIQUE KEY event_uuid (event_uuid),
			KEY target_lookup (target_type,target_id,seq),
			KEY actor_seq (actor_id,seq),
			KEY parent_seq (parent_id,seq)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'sync_audience' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			seq bigint(20) unsigned NOT NULL,
			event_uuid char(36) NOT NULL,
			principal_type varchar(20) NOT NULL,
			principal_ref varchar(191) NOT NULL,
			created_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY event_principal (seq,principal_type,principal_ref),
			KEY principal_seq (principal_type,principal_ref,seq),
			KEY seq_lookup (seq)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'devices' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			device_uuid char(36) NOT NULL,
			user_id bigint(20) unsigned NOT NULL,
			device_name varchar(191) NOT NULL,
			token_hash char(64) NOT NULL,
			scope varchar(255) NOT NULL DEFAULT 'files:read,files:write,sync',
			status varchar(20) NOT NULL DEFAULT 'active',
			last_cursor bigint(20) unsigned DEFAULT 0 NOT NULL,
			last_error text,
			approved_at_gmt datetime NOT NULL,
			last_seen_at_gmt datetime DEFAULT NULL,
			last_sync_at_gmt datetime DEFAULT NULL,
			revoked_at_gmt datetime DEFAULT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY device_uuid (device_uuid),
			UNIQUE KEY token_hash (token_hash),
			KEY user_status (user_id,status),
			KEY last_seen (last_seen_at_gmt)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'upload_sessions' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			session_uuid char(36) NOT NULL,
			user_id bigint(20) unsigned NOT NULL,
			parent_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			filename varchar(255) NOT NULL,
			total_size bigint(20) unsigned DEFAULT 0 NOT NULL,
			received_bytes bigint(20) unsigned DEFAULT 0 NOT NULL,
			content_hash char(64) NOT NULL DEFAULT '',
			mime_type varchar(127) NOT NULL DEFAULT '',
			storage_key varchar(255) NOT NULL DEFAULT '',
			operation varchar(20) NOT NULL DEFAULT 'create',
			target_file_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			base_content_version char(36) NOT NULL DEFAULT '',
			reserved_bytes bigint(20) unsigned DEFAULT 0 NOT NULL,
			quota_delta_bytes bigint(20) unsigned DEFAULT 0 NOT NULL,
			reservation_expires_at_gmt datetime DEFAULT NULL,
			status varchar(20) NOT NULL DEFAULT 'open',
			expires_at_gmt datetime NOT NULL,
			created_at_gmt datetime NOT NULL,
			updated_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY session_uuid (session_uuid),
			KEY user_status (user_id,status),
			KEY target_operation (target_file_id,operation,status),
			KEY user_reservations (user_id,status,reservation_expires_at_gmt),
			KEY expires_at (expires_at_gmt)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'usage_counters' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			scope varchar(20) NOT NULL,
			user_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			active_files bigint(20) unsigned DEFAULT 0 NOT NULL,
			active_folders bigint(20) unsigned DEFAULT 0 NOT NULL,
			active_bytes bigint(20) unsigned DEFAULT 0 NOT NULL,
			version_bytes bigint(20) unsigned DEFAULT 0 NOT NULL,
			reserved_bytes bigint(20) unsigned DEFAULT 0 NOT NULL,
			calculated_at_gmt datetime NOT NULL,
			updated_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY scope_user (scope,user_id),
			KEY updated_at (updated_at_gmt)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'rate_limits' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			rate_key char(32) NOT NULL,
			bucket varchar(80) NOT NULL,
			identity_hash char(64) NOT NULL,
			count int(10) unsigned DEFAULT 0 NOT NULL,
			expires_at_gmt datetime NOT NULL,
			created_at_gmt datetime NOT NULL,
			updated_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY rate_key (rate_key),
			KEY expires_at (expires_at_gmt),
			KEY bucket_expires (bucket,expires_at_gmt)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'tombstones' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			target_type varchar(20) NOT NULL,
			target_id bigint(20) unsigned NOT NULL,
			owner_id bigint(20) unsigned NOT NULL,
			sync_seq bigint(20) unsigned DEFAULT 0 NOT NULL,
			reason varchar(64) NOT NULL DEFAULT 'deleted',
			created_at_gmt datetime NOT NULL,
			expires_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY target_lookup (target_type,target_id),
			KEY owner_expires (owner_id,expires_at_gmt),
			KEY sync_seq (sync_seq)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'audit_log' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			actor_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			device_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			action varchar(80) NOT NULL,
			target_type varchar(20) NOT NULL DEFAULT '',
			target_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			ip_hash char(64) NOT NULL DEFAULT '',
			user_agent_hash char(64) NOT NULL DEFAULT '',
			message text,
			meta_json longtext,
			created_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			KEY actor_created (actor_id,created_at_gmt),
			KEY action_created (action,created_at_gmt),
			KEY target_lookup (target_type,target_id,created_at_gmt)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'file_versions' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			version_uuid char(36) NOT NULL,
			file_id bigint(20) unsigned NOT NULL,
			file_uuid char(36) NOT NULL,
			owner_id bigint(20) unsigned NOT NULL,
			name varchar(255) NOT NULL,
			mime_type varchar(127) NOT NULL DEFAULT '',
			size_bytes bigint(20) unsigned DEFAULT 0 NOT NULL,
			content_hash char(64) NOT NULL DEFAULT '',
			storage_key varchar(255) NOT NULL DEFAULT '',
			content_version char(36) NOT NULL,
			metadata_version char(36) NOT NULL DEFAULT '',
			reason varchar(64) NOT NULL DEFAULT 'replace',
			created_by bigint(20) unsigned DEFAULT 0 NOT NULL,
			created_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY version_uuid (version_uuid),
			KEY file_created (file_id,created_at_gmt,id),
			KEY owner_file (owner_id,file_id,id),
			KEY content_hash (content_hash)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'conflicts' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			conflict_uuid char(36) NOT NULL,
			owner_id bigint(20) unsigned NOT NULL,
			file_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			file_uuid char(36) NOT NULL DEFAULT '',
			parent_id bigint(20) unsigned DEFAULT 0 NOT NULL,
			status varchar(20) NOT NULL DEFAULT 'open',
			reason varchar(64) NOT NULL DEFAULT 'stale_content',
			local_name varchar(255) NOT NULL DEFAULT '',
			server_content_version char(36) NOT NULL DEFAULT '',
			local_content_hash char(64) NOT NULL DEFAULT '',
			local_size_bytes bigint(20) unsigned DEFAULT 0 NOT NULL,
			client_created_at_gmt datetime DEFAULT NULL,
			resolved_at_gmt datetime DEFAULT NULL,
			created_at_gmt datetime NOT NULL,
			updated_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY conflict_uuid (conflict_uuid),
			KEY owner_status_id (owner_id,status,id),
			KEY file_status (file_id,status,id),
			KEY parent_status (parent_id,status,id)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'thumbnails' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			file_id bigint(20) unsigned NOT NULL,
			file_uuid char(36) NOT NULL,
			content_version char(36) NOT NULL,
			status varchar(20) NOT NULL DEFAULT 'queued',
			storage_key varchar(255) NOT NULL DEFAULT '',
			mime_type varchar(127) NOT NULL DEFAULT 'image/jpeg',
			width int(10) unsigned DEFAULT 0 NOT NULL,
			height int(10) unsigned DEFAULT 0 NOT NULL,
			size_bytes bigint(20) unsigned DEFAULT 0 NOT NULL,
			source_hash char(64) NOT NULL DEFAULT '',
			error_message text,
			created_at_gmt datetime NOT NULL,
			updated_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY file_version (file_id,content_version),
			KEY file_status (file_id,status),
			KEY status_updated (status,updated_at_gmt)
		) $charset;";

		$sql[] = 'CREATE TABLE ' . self::table( 'jobs' ) . " (
			id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
			job_uuid char(36) NOT NULL,
			job_type varchar(80) NOT NULL,
			status varchar(20) NOT NULL DEFAULT 'queued',
			priority tinyint(3) unsigned DEFAULT 5 NOT NULL,
			attempts int(10) unsigned DEFAULT 0 NOT NULL,
			not_before_gmt datetime NOT NULL,
			locked_at_gmt datetime DEFAULT NULL,
			payload_json longtext,
			result_json longtext,
			created_at_gmt datetime NOT NULL,
			updated_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY job_uuid (job_uuid),
			KEY queue_lookup (status,not_before_gmt,priority,id),
			KEY job_type_status (job_type,status)
		) $charset;";

		foreach ( $sql as $statement ) {
			dbDelta( $statement );
		}

		self::repair( true );

		update_option( 'floppy_db_version', FLOPPY_DB_VERSION, false );
	}

	/**
	 * Return missing expected tables/index hints for diagnostics.
	 *
	 * @return array<int, string>
	 */
	public static function validate(): array {
		global $wpdb;

		$missing = array();
		foreach ( array( 'files', 'folders', 'item_names', 'acl_grants', 'sync_events', 'sync_audience', 'devices', 'upload_sessions', 'usage_counters', 'rate_limits', 'tombstones', 'audit_log', 'file_versions', 'conflicts', 'thumbnails', 'jobs' ) as $name ) {
			$table = self::table( $name );
			$found = $wpdb->get_var( $wpdb->prepare( 'SHOW TABLES LIKE %s', $table ) );
			if ( $found !== $table ) {
				$missing[] = $table;
				continue;
			}

			foreach ( self::expected_indexes( $name ) as $index ) {
				$found_index = $wpdb->get_var(
					$wpdb->prepare(
						'SHOW INDEX FROM ' . $table . ' WHERE Key_name = %s',
						$index
					)
				); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
				if ( ! $found_index ) {
					$missing[] = $table . '.' . $index;
				}
			}
		}

		return $missing;
	}

	/**
	 * Important indexes expected by production hot paths.
	 *
	 * @return array<int, string>
	 */
	private static function expected_indexes( string $name ): array {
		$indexes = array(
			'files'           => array( 'uuid', 'parent_status_id', 'owner_parent_status_id', 'owner_normalized_status_id', 'owner_status_updated_id', 'normalized_status_id', 'updated_id', 'content_hash' ),
			'folders'         => array( 'uuid', 'parent_status_id', 'owner_parent_status_id', 'owner_normalized_status_id', 'owner_status_updated_id', 'normalized_status_id', 'updated_id' ),
			'item_names'      => array( 'live_name', 'target_lookup', 'parent_lookup' ),
			'acl_grants'      => array( 'target_principal', 'principal_lookup', 'target_lookup' ),
			'sync_events'     => array( 'event_uuid', 'target_lookup', 'actor_seq', 'parent_seq' ),
			'sync_audience'   => array( 'event_principal', 'principal_seq', 'seq_lookup' ),
			'devices'         => array( 'device_uuid', 'token_hash', 'user_status', 'last_seen' ),
			'upload_sessions' => array( 'session_uuid', 'user_status', 'target_operation', 'user_reservations', 'expires_at' ),
			'usage_counters'  => array( 'scope_user', 'updated_at' ),
			'rate_limits'     => array( 'rate_key', 'expires_at', 'bucket_expires' ),
			'tombstones'      => array( 'target_lookup', 'owner_expires', 'sync_seq' ),
			'audit_log'       => array( 'actor_created', 'action_created', 'target_lookup' ),
			'file_versions'   => array( 'version_uuid', 'file_created', 'owner_file', 'content_hash' ),
			'conflicts'       => array( 'conflict_uuid', 'owner_status_id', 'file_status', 'parent_status' ),
			'thumbnails'      => array( 'file_version', 'file_status', 'status_updated' ),
			'jobs'            => array( 'job_uuid', 'queue_lookup', 'job_type_status' ),
		);

		return $indexes[ $name ] ?? array();
	}

	/**
	 * Run additive data repairs and return a redacted report.
	 */
	public static function repair( bool $apply = false ): array {
		return array(
			'apply'                     => $apply,
			'item_names'                => self::repair_item_name_reservations( $apply ),
			'orphaned_name_reservations' => self::repair_orphaned_name_reservations( $apply ),
			'orphaned_acl_grants'       => self::repair_orphaned_acl_grants( $apply ),
			'stale_upload_sessions'     => self::repair_stale_upload_sessions( $apply ),
			'stale_versions'            => self::repair_stale_versions( $apply ),
			'stale_conflicts'           => self::repair_stale_conflicts( $apply ),
			'stale_thumbnails'          => self::repair_stale_thumbnails( $apply ),
			'attachment_links'          => self::repair_attachment_links( $apply ),
			'missing_tombstones'        => self::repair_missing_tombstones( $apply ),
			'usage_counters'            => self::repair_usage_counters( $apply ),
			'storage_keys'              => self::inspect_storage_keys(),
			'blob_integrity'            => self::inspect_blob_integrity(),
			'sync_event_continuity'     => self::inspect_sync_event_continuity(),
			'orphaned_sync_audience'    => self::repair_orphaned_sync_audience( $apply ),
			'sync_audience'             => self::inspect_sync_audience(),
			'quota_usage'               => self::inspect_quota_usage(),
			'orphaned_blobs'            => self::inspect_orphaned_blobs(),
		);
	}

	/**
	 * Return support-safe usage counter health.
	 */
	public static function usage_counter_summary(): array {
		global $wpdb;

		if ( ! self::table_exists( self::table( 'usage_counters' ) ) ) {
			return array(
				'available' => false,
				'status'    => 'missing_table',
			);
		}

		$site = $wpdb->get_row(
			$wpdb->prepare(
				'SELECT active_files, active_folders, active_bytes, version_bytes, reserved_bytes, calculated_at_gmt FROM ' . self::table( 'usage_counters' ) . ' WHERE scope = %s AND user_id = 0 LIMIT 1',
				'site'
			),
			ARRAY_A
		);

		$user_rows = (int) $wpdb->get_var(
			$wpdb->prepare(
				'SELECT COUNT(*) FROM ' . self::table( 'usage_counters' ) . ' WHERE scope = %s',
				'user'
			)
		);

		return array(
			'available'        => true,
			'status'           => $site ? 'ready' : 'needs_backfill',
			'user_rows'        => $user_rows,
			'site'             => $site ? array(
				'active_files'      => (int) $site['active_files'],
				'active_folders'    => (int) $site['active_folders'],
				'active_bytes'      => (int) $site['active_bytes'],
				'version_bytes'     => (int) $site['version_bytes'],
				'reserved_bytes'    => (int) $site['reserved_bytes'],
				'calculated_at_gmt' => (string) $site['calculated_at_gmt'],
			) : null,
		);
	}

	/**
	 * Recalculate usage counters from authoritative metadata.
	 */
	public static function refresh_usage_counters(): array {
		global $wpdb;

		if ( ! self::table_exists( self::table( 'usage_counters' ) ) ) {
			return array( 'ok' => false, 'message' => 'Usage counter table is missing.' );
		}

		$now = current_time( 'mysql', true );
		$files_table = self::table( 'files' );
		$folders_table = self::table( 'folders' );
		$versions_table = self::table( 'file_versions' );
		$sessions_table = self::table( 'upload_sessions' );
		$counters_table = self::table( 'usage_counters' );

		$site = $wpdb->get_row(
			"SELECT
				(SELECT COUNT(*) FROM $files_table WHERE status != 'deleted') AS active_files,
				(SELECT COUNT(*) FROM $folders_table WHERE status != 'deleted') AS active_folders,
				(SELECT COALESCE(SUM(size_bytes),0) FROM $files_table WHERE status != 'deleted') AS active_bytes,
				(SELECT COALESCE(SUM(size_bytes),0) FROM $versions_table) AS version_bytes,
				(SELECT COALESCE(SUM(reserved_bytes),0) FROM $sessions_table WHERE status = 'open' AND expires_at_gmt >= '$now') AS reserved_bytes",
			ARRAY_A
		); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared

		self::upsert_usage_counter( 'site', 0, $site ?: array() );

		$user_ids = array_map(
			'absint',
			array_unique(
				array_merge(
					$wpdb->get_col( "SELECT DISTINCT owner_id FROM $files_table WHERE owner_id > 0" ), // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
					$wpdb->get_col( "SELECT DISTINCT owner_id FROM $folders_table WHERE owner_id > 0" ), // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
					$wpdb->get_col( "SELECT DISTINCT user_id FROM $sessions_table WHERE user_id > 0" ) // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
				)
			)
		);

		foreach ( $user_ids as $user_id ) {
			$row = $wpdb->get_row(
				$wpdb->prepare(
					"SELECT
						(SELECT COUNT(*) FROM $files_table WHERE owner_id = %d AND status != 'deleted') AS active_files,
						(SELECT COUNT(*) FROM $folders_table WHERE owner_id = %d AND status != 'deleted') AS active_folders,
						(SELECT COALESCE(SUM(size_bytes),0) FROM $files_table WHERE owner_id = %d AND status != 'deleted') AS active_bytes,
						(SELECT COALESCE(SUM(size_bytes),0) FROM $versions_table WHERE owner_id = %d) AS version_bytes,
						(SELECT COALESCE(SUM(reserved_bytes),0) FROM $sessions_table WHERE user_id = %d AND status = 'open' AND expires_at_gmt >= %s) AS reserved_bytes",
					$user_id,
					$user_id,
					$user_id,
					$user_id,
					$user_id,
					$now
				),
				ARRAY_A
			); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
			self::upsert_usage_counter( 'user', $user_id, $row ?: array() );
		}

		$wpdb->query(
			$wpdb->prepare(
				"DELETE FROM $counters_table WHERE scope = %s AND user_id > 0 AND user_id NOT IN (" . implode( ',', array_map( 'absint', $user_ids ?: array( 0 ) ) ) . ')',
				'user'
			)
		); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared

		return array(
			'ok'          => true,
			'user_rows'   => count( $user_ids ),
			'updated_at'  => $now,
			'site_active_bytes' => (int) ( $site['active_bytes'] ?? 0 ),
		);
	}

	/**
	 * Upsert one usage counter row.
	 */
	private static function upsert_usage_counter( string $scope, int $user_id, array $row ): void {
		global $wpdb;

		$now = current_time( 'mysql', true );
		$wpdb->replace(
			self::table( 'usage_counters' ),
			array(
				'scope'             => $scope,
				'user_id'           => $user_id,
				'active_files'      => (int) ( $row['active_files'] ?? 0 ),
				'active_folders'    => (int) ( $row['active_folders'] ?? 0 ),
				'active_bytes'      => (int) ( $row['active_bytes'] ?? 0 ),
				'version_bytes'     => (int) ( $row['version_bytes'] ?? 0 ),
				'reserved_bytes'    => (int) ( $row['reserved_bytes'] ?? 0 ),
				'calculated_at_gmt' => $now,
				'updated_at_gmt'    => $now,
			),
			array( '%s', '%d', '%d', '%d', '%d', '%d', '%d', '%s', '%s' )
		);
	}

	/**
	 * Rebuild quota usage counters when needed.
	 */
	private static function repair_usage_counters( bool $apply ): array {
		if ( ! self::table_exists( self::table( 'usage_counters' ) ) ) {
			return array( 'status' => 'missing_table' );
		}

		$summary = self::usage_counter_summary();
		if ( $apply || 'needs_backfill' === ( $summary['status'] ?? '' ) ) {
			return array_merge( array( 'status' => 'recalculated' ), self::refresh_usage_counters() );
		}

		return $summary;
	}

	/**
	 * Inspect stored keys for path traversal or unsupported adapter metadata.
	 */
	private static function inspect_storage_keys(): array {
		global $wpdb;

		$checks = array(
			array( 'files', 'storage_key' ),
			array( 'file_versions', 'storage_key' ),
			array( 'upload_sessions', 'storage_key' ),
			array( 'thumbnails', 'storage_key' ),
		);
		$invalid = 0;
		$scanned = 0;
		foreach ( $checks as $check ) {
			$rows = $wpdb->get_col( 'SELECT ' . $check[1] . ' FROM ' . self::table( $check[0] ) . " WHERE " . $check[1] . " != '' LIMIT 1000" ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			foreach ( $rows as $key ) {
				++$scanned;
				if ( ! Floppy_Storage::storage_key_is_valid( (string) $key ) ) {
					++$invalid;
				}
			}
		}

		return array(
			'scanned'      => $scanned,
			'invalid'      => $invalid,
			'scan_limited' => $scanned >= 4000,
		);
	}

	/**
	 * Backfill missing sibling-name reservations.
	 */
	private static function repair_item_name_reservations( bool $apply ): array {
		global $wpdb;

		$table = self::table( 'item_names' );
		$now = current_time( 'mysql', true );
		$created = 0;
		$conflicts = 0;
		$scan_limited = false;

		foreach ( array( 'folders' => 'folder', 'files' => 'file' ) as $source => $target_type ) {
			$source_table = self::table( $source );
			$rows = $wpdb->get_results(
				$wpdb->prepare(
					"SELECT s.id, s.parent_id, s.normalized_name FROM $source_table s LEFT JOIN $table n ON n.target_type = %s AND n.target_id = s.id WHERE s.status != 'deleted' AND n.id IS NULL LIMIT %d", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
					$target_type,
					self::REPAIR_BATCH_LIMIT + 1
				),
				ARRAY_A
			);
			if ( count( $rows ) > self::REPAIR_BATCH_LIMIT ) {
				array_pop( $rows );
				$scan_limited = true;
			}

			foreach ( $rows as $row ) {
				if ( $apply ) {
					$inserted = $wpdb->insert(
						$table,
						array(
							'parent_id'       => (int) $row['parent_id'],
							'normalized_name' => (string) $row['normalized_name'],
							'target_type'     => $target_type,
							'target_id'       => (int) $row['id'],
							'status'          => 'reserved',
							'created_at_gmt'  => $now,
							'updated_at_gmt'  => $now,
						),
						array( '%d', '%s', '%s', '%d', '%s', '%s', '%s' )
					);
					if ( $inserted ) {
						++$created;
					} else {
						++$conflicts;
					}
				} else {
					++$created;
				}
			}
		}

		return array(
			'missing'      => $created,
			'conflicts'    => $conflicts,
			'scan_limited' => $scan_limited,
		);
	}

	/**
	 * Remove reservations whose target row no longer exists or is deleted.
	 */
	private static function repair_orphaned_name_reservations( bool $apply ): array {
		global $wpdb;

		$table = self::table( 'item_names' );
		$rows = array();
		foreach ( array( 'folder' => 'folders', 'file' => 'files' ) as $target_type => $source ) {
			$source_table = self::table( $source );
			$remaining = ( self::REPAIR_BATCH_LIMIT + 1 ) - count( $rows );
			if ( $remaining <= 0 ) {
				break;
			}

			$rows = array_merge(
				$rows,
				$wpdb->get_results(
					$wpdb->prepare(
						"SELECT n.id FROM $table n LEFT JOIN $source_table s ON n.target_id = s.id AND s.status != 'deleted' WHERE n.target_type = %s AND s.id IS NULL LIMIT %d", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
						$target_type,
						$remaining
					),
					ARRAY_A
				)
			);
		}

		$remaining = ( self::REPAIR_BATCH_LIMIT + 1 ) - count( $rows );
		if ( $remaining > 0 ) {
			$rows = array_merge(
				$rows,
				$wpdb->get_results(
					$wpdb->prepare(
						"SELECT id FROM $table WHERE target_type NOT IN ('folder','file') LIMIT %d", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
						$remaining
					),
					ARRAY_A
				)
			);
		}

		$scan_limited = count( $rows ) > self::REPAIR_BATCH_LIMIT;
		if ( $scan_limited ) {
			array_pop( $rows );
		}

		$orphans = 0;
		foreach ( $rows as $row ) {
			++$orphans;
			if ( $apply ) {
				$wpdb->delete( $table, array( 'id' => (int) $row['id'] ), array( '%d' ) );
			}
		}

		return array(
			'orphaned'     => $orphans,
			'scan_limited' => $scan_limited,
		);
	}

	/**
	 * Remove ACL grants whose target no longer exists or is deleted.
	 */
	private static function repair_orphaned_acl_grants( bool $apply ): array {
		global $wpdb;

		$table = self::table( 'acl_grants' );
		$rows = array();
		foreach ( array( 'folder' => 'folders', 'file' => 'files' ) as $target_type => $source ) {
			$source_table = self::table( $source );
			$remaining = ( self::REPAIR_BATCH_LIMIT + 1 ) - count( $rows );
			if ( $remaining <= 0 ) {
				break;
			}

			$rows = array_merge(
				$rows,
				$wpdb->get_results(
					$wpdb->prepare(
						"SELECT g.id FROM $table g LEFT JOIN $source_table s ON g.target_id = s.id AND s.status != 'deleted' WHERE g.target_type = %s AND s.id IS NULL LIMIT %d", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
						$target_type,
						$remaining
					),
					ARRAY_A
				)
			);
		}

		$remaining = ( self::REPAIR_BATCH_LIMIT + 1 ) - count( $rows );
		if ( $remaining > 0 ) {
			$rows = array_merge(
				$rows,
				$wpdb->get_results(
					$wpdb->prepare(
						"SELECT id FROM $table WHERE target_type NOT IN ('folder','file') LIMIT %d", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
						$remaining
					),
					ARRAY_A
				)
			);
		}

		$scan_limited = count( $rows ) > self::REPAIR_BATCH_LIMIT;
		if ( $scan_limited ) {
			array_pop( $rows );
		}

		$orphans = 0;
		foreach ( $rows as $row ) {
			++$orphans;
			if ( $apply ) {
				$wpdb->delete( $table, array( 'id' => (int) $row['id'] ), array( '%d' ) );
			}
		}

		return array(
			'orphaned'     => $orphans,
			'scan_limited' => $scan_limited,
		);
	}

	/**
	 * Clean expired upload-session rows and temporary blobs.
	 */
	private static function repair_stale_upload_sessions( bool $apply ): array {
		global $wpdb;

		$rows = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT id, storage_key FROM ' . self::table( 'upload_sessions' ) . " WHERE status IN ('open','failed') AND expires_at_gmt < %s LIMIT 500",
				current_time( 'mysql', true )
			),
			ARRAY_A
		);
		if ( $apply ) {
			foreach ( $rows as $row ) {
				if ( ! empty( $row['storage_key'] ) ) {
					@unlink( Floppy_Storage::path_for_key( (string) $row['storage_key'] ) ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
				}
				$wpdb->delete( self::table( 'upload_sessions' ), array( 'id' => (int) $row['id'] ), array( '%d' ) );
			}
		}

		return array( 'expired' => count( $rows ) );
	}

	/**
	 * Repair attachment file/meta pointers for private file rows.
	 */
	private static function repair_attachment_links( bool $apply ): array {
		global $wpdb;

		$rows = $wpdb->get_results(
			'SELECT id, attachment_id, storage_key FROM ' . self::table( 'files' ) . " WHERE attachment_id > 0 AND status != 'deleted' LIMIT 1000",
			ARRAY_A
		); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$drift = 0;
		foreach ( $rows as $row ) {
			$attachment_id = (int) $row['attachment_id'];
			$storage_key = (string) $row['storage_key'];
			$meta_key = (string) get_post_meta( $attachment_id, '_floppy_storage_key', true );
			$attached = (string) get_attached_file( $attachment_id );
			$expected = Floppy_Storage::path_for_key( $storage_key );
			if ( $meta_key === $storage_key && $attached === $expected ) {
				continue;
			}

			++$drift;
			if ( $apply ) {
				update_post_meta( $attachment_id, '_floppy_storage_key', $storage_key );
				update_attached_file( $attachment_id, $expected );
			}
		}

		return array( 'drifted' => $drift );
	}

	/**
	 * Create missing tombstones for deleted files/folders.
	 */
	private static function repair_missing_tombstones( bool $apply ): array {
		global $wpdb;

		$missing = 0;
		foreach ( array( 'folders' => 'folder', 'files' => 'file' ) as $source => $target_type ) {
			$rows = $wpdb->get_results(
				'SELECT id, owner_id FROM ' . self::table( $source ) . " WHERE status = 'deleted' LIMIT 1000",
				ARRAY_A
			); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			foreach ( $rows as $row ) {
				$exists = (int) $wpdb->get_var(
					$wpdb->prepare(
						'SELECT id FROM ' . self::table( 'tombstones' ) . ' WHERE target_type = %s AND target_id = %d LIMIT 1',
						$target_type,
						(int) $row['id']
					)
				);
				if ( $exists ) {
					continue;
				}

				++$missing;
				if ( $apply ) {
					$sync_seq = (int) $wpdb->get_var(
						$wpdb->prepare(
							'SELECT MAX(seq) FROM ' . self::table( 'sync_events' ) . ' WHERE target_type = %s AND target_id = %d',
							$target_type,
							(int) $row['id']
						)
					);
					Floppy_Sync::tombstone( $target_type, (int) $row['id'], (int) $row['owner_id'], $sync_seq );
				}
			}
		}

		return array( 'missing' => $missing );
	}

	/**
	 * Remove version rows whose file no longer exists.
	 */
	private static function repair_stale_versions( bool $apply ): array {
		global $wpdb;

		$table = self::table( 'file_versions' );
		$rows = $wpdb->get_results(
			"SELECT v.id, v.storage_key FROM $table v LEFT JOIN " . self::table( 'files' ) . ' f ON f.id = v.file_id WHERE f.id IS NULL LIMIT 500',
			ARRAY_A
		); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		if ( $apply ) {
			foreach ( $rows as $row ) {
				self::delete_unreferenced_blob( (string) $row['storage_key'] );
				$wpdb->delete( $table, array( 'id' => (int) $row['id'] ), array( '%d' ) );
			}
		}

		return array(
			'stale'        => count( $rows ),
			'scan_limited' => count( $rows ) >= 500,
		);
	}

	/**
	 * Close conflict rows whose source file was deleted.
	 */
	private static function repair_stale_conflicts( bool $apply ): array {
		global $wpdb;

		$table = self::table( 'conflicts' );
		$rows = $wpdb->get_results(
			"SELECT c.id FROM $table c LEFT JOIN " . self::table( 'files' ) . " f ON f.id = c.file_id WHERE c.status = 'open' AND c.file_id > 0 AND (f.id IS NULL OR f.status = 'deleted') LIMIT 500",
			ARRAY_A
		); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		if ( $apply && $rows ) {
			$ids = implode( ',', array_map( 'absint', wp_list_pluck( $rows, 'id' ) ) );
			$wpdb->query(
				$wpdb->prepare(
					"UPDATE $table SET status = 'stale', resolved_at_gmt = %s, updated_at_gmt = %s WHERE id IN ($ids)", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
					current_time( 'mysql', true ),
					current_time( 'mysql', true )
				)
			);
		}

		return array(
			'stale'        => count( $rows ),
			'scan_limited' => count( $rows ) >= 500,
		);
	}

	/**
	 * Remove thumbnail rows whose file or content version no longer matches.
	 */
	private static function repair_stale_thumbnails( bool $apply ): array {
		global $wpdb;

		$table = self::table( 'thumbnails' );
		$rows = $wpdb->get_results(
			"SELECT t.id, t.storage_key FROM $table t LEFT JOIN " . self::table( 'files' ) . " f ON f.id = t.file_id WHERE f.id IS NULL OR f.status = 'deleted' OR f.content_version != t.content_version LIMIT 500",
			ARRAY_A
		); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		if ( $apply ) {
			foreach ( $rows as $row ) {
				self::delete_unreferenced_blob( (string) $row['storage_key'] );
				$wpdb->delete( $table, array( 'id' => (int) $row['id'] ), array( '%d' ) );
			}
		}

		return array(
			'stale'        => count( $rows ),
			'scan_limited' => count( $rows ) >= 500,
		);
	}

	/**
	 * Inspect private blob existence, size, and hashes without returning paths.
	 */
	private static function inspect_blob_integrity(): array {
		global $wpdb;

		$rows = $wpdb->get_results(
			'SELECT id, storage_key, size_bytes, content_hash FROM ' . self::table( 'files' ) . " WHERE status != 'deleted' AND storage_key != '' LIMIT 1000",
			ARRAY_A
		); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$missing = 0;
		$size_mismatches = 0;
		$hash_mismatches = 0;
		foreach ( $rows as $row ) {
			$path = Floppy_Storage::path_for_key( (string) $row['storage_key'] );
			if ( ! is_readable( $path ) ) {
				++$missing;
				continue;
			}
			$size = filesize( $path );
			if ( false !== $size && (int) $size !== (int) $row['size_bytes'] ) {
				++$size_mismatches;
			}
			$hash = hash_file( 'sha256', $path );
			if ( is_string( $hash ) && '' !== (string) $row['content_hash'] && $hash !== (string) $row['content_hash'] ) {
				++$hash_mismatches;
			}
		}

		return array(
			'scanned'         => count( $rows ),
			'missing'         => $missing,
			'size_mismatches' => $size_mismatches,
			'hash_mismatches' => $hash_mismatches,
			'scan_limited'    => count( $rows ) >= 1000,
		);
	}

	/**
	 * Inspect sync sequence continuity without reading payloads.
	 */
	private static function inspect_sync_event_continuity(): array {
		global $wpdb;

		$row = $wpdb->get_row( 'SELECT MIN(seq) AS min_seq, MAX(seq) AS max_seq, COUNT(*) AS total FROM ' . self::table( 'sync_events' ), ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$min = (int) ( $row['min_seq'] ?? 0 );
		$max = (int) ( $row['max_seq'] ?? 0 );
		$total = (int) ( $row['total'] ?? 0 );

		return array(
			'min_seq' => $min,
			'max_seq' => $max,
			'total'   => $total,
			'gaps'    => $min && $max ? max( 0, ( $max - $min + 1 ) - $total ) : 0,
		);
	}

	/**
	 * Summarize sync-audience index coverage.
	 */
	private static function inspect_sync_audience(): array {
		global $wpdb;

		if ( ! self::table_exists( self::table( 'sync_audience' ) ) ) {
			return array(
				'available' => false,
				'status'    => 'missing_table',
			);
		}

		$total_events = (int) $wpdb->get_var( 'SELECT COUNT(*) FROM ' . self::table( 'sync_events' ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$audience_rows = (int) $wpdb->get_var( 'SELECT COUNT(*) FROM ' . self::table( 'sync_audience' ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$events_with_audience = (int) $wpdb->get_var( 'SELECT COUNT(DISTINCT seq) FROM ' . self::table( 'sync_audience' ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared

		return array(
			'available'            => true,
			'total_events'         => $total_events,
			'audience_rows'        => $audience_rows,
			'events_with_audience' => $events_with_audience,
			'strategy'             => 'principal-index-with-permission-fallback',
		);
	}

	/**
	 * Remove sync audience rows whose source events were compacted away.
	 */
	private static function repair_orphaned_sync_audience( bool $apply ): array {
		global $wpdb;

		$table = self::table( 'sync_audience' );
		if ( ! self::table_exists( $table ) ) {
			return array( 'status' => 'missing_table' );
		}

		$events = self::table( 'sync_events' );
		if ( ! self::table_exists( $events ) ) {
			return array( 'status' => 'missing_events_table' );
		}

		$rows = $wpdb->get_results(
			"SELECT a.id FROM $table a LEFT JOIN $events e ON e.seq = a.seq WHERE e.seq IS NULL LIMIT 2000",
			ARRAY_A
		); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared

		if ( $apply && $rows ) {
			$ids = implode( ',', array_map( 'absint', wp_list_pluck( $rows, 'id' ) ) );
			$wpdb->query( "DELETE FROM $table WHERE id IN ($ids)" ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		}

		return array(
			'orphaned'     => count( $rows ),
			'scan_limited' => count( $rows ) >= 2000,
		);
	}

	/**
	 * Summarize quota-impacting metadata.
	 */
	private static function inspect_quota_usage(): array {
		global $wpdb;

		return array(
			'active_files'   => (int) $wpdb->get_var( 'SELECT COUNT(*) FROM ' . self::table( 'files' ) . " WHERE status != 'deleted'" ), // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			'active_folders' => (int) $wpdb->get_var( 'SELECT COUNT(*) FROM ' . self::table( 'folders' ) . " WHERE status != 'deleted'" ), // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			'active_bytes'   => (int) $wpdb->get_var( 'SELECT COALESCE(SUM(size_bytes),0) FROM ' . self::table( 'files' ) . " WHERE status != 'deleted'" ), // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			'deleted_bytes'  => (int) $wpdb->get_var( 'SELECT COALESCE(SUM(size_bytes),0) FROM ' . self::table( 'files' ) . " WHERE status = 'deleted'" ), // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		);
	}

	/**
	 * Delete a blob only when no active metadata row still references it.
	 */
	private static function delete_unreferenced_blob( string $storage_key ): void {
		if ( '' === $storage_key ) {
			return;
		}

		global $wpdb;
		$references = (int) $wpdb->get_var(
			$wpdb->prepare(
				'SELECT (
					(SELECT COUNT(*) FROM ' . self::table( 'files' ) . ' WHERE storage_key = %s) +
					(SELECT COUNT(*) FROM ' . self::table( 'file_versions' ) . ' WHERE storage_key = %s) +
					(SELECT COUNT(*) FROM ' . self::table( 'upload_sessions' ) . ' WHERE storage_key = %s) +
					(SELECT COUNT(*) FROM ' . self::table( 'thumbnails' ) . ' WHERE storage_key = %s)
				)',
				$storage_key,
				$storage_key,
				$storage_key,
				$storage_key
			)
		);
		if ( 0 === $references ) {
			@unlink( Floppy_Storage::path_for_key( $storage_key ) ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
		}
	}

	/**
	 * Count unreferenced private blobs without returning private paths.
	 */
	private static function inspect_orphaned_blobs(): array {
		global $wpdb;

		$root = Floppy_Storage::root();
		if ( empty( $root['path'] ) || ! is_dir( $root['path'] ) ) {
			return array( 'candidates' => 0, 'scanned' => 0, 'scan_limited' => false );
		}

		$keys = array();
		$scanned = 0;
		$limit = self::REPAIR_BATCH_LIMIT;
		$root_path = trailingslashit( $root['path'] );
		$iterator = new RecursiveIteratorIterator( new RecursiveDirectoryIterator( $root_path, FilesystemIterator::SKIP_DOTS ) );
		foreach ( $iterator as $file ) {
			if ( ! $file->isFile() ) {
				continue;
			}
			++$scanned;
			$key = ltrim( str_replace( $root_path, '', $file->getPathname() ), '/' );
			if ( in_array( $key, array( '.htaccess', 'web.config', 'index.php' ), true ) ) {
				continue;
			}
			if ( 0 !== strpos( $key, 'exports/' ) ) {
				$keys[] = $key;
			}
			if ( $scanned >= $limit ) {
				break;
			}
		}

		$known = array();
		$keys = array_values( array_unique( $keys ) );
		if ( ! empty( $keys ) ) {
			$placeholders = implode( ',', array_fill( 0, count( $keys ), '%s' ) );
			foreach ( array( 'files', 'file_versions', 'upload_sessions', 'thumbnails' ) as $source ) {
				$known = array_merge(
					$known,
					$wpdb->get_col(
						$wpdb->prepare(
							'SELECT storage_key FROM ' . self::table( $source ) . " WHERE storage_key IN ($placeholders)", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
							$keys
						)
					)
				);
			}
		}

		$known = array_fill_keys( array_filter( $known ), true );
		$candidates = 0;
		foreach ( $keys as $key ) {
			if ( empty( $known[ $key ] ) ) {
				++$candidates;
			}
		}

		return array(
			'candidates'   => $candidates,
			'scanned'      => $scanned,
			'scan_limited' => $scanned >= $limit,
		);
	}

	/**
	 * Check table existence during additive migrations.
	 */
	private static function table_exists( string $table ): bool {
		global $wpdb;

		return $wpdb->get_var( $wpdb->prepare( 'SHOW TABLES LIKE %s', $table ) ) === $table;
	}
}
