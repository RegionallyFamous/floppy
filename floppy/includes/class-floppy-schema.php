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
			KEY normalized_status_id (normalized_name(120),status,id),
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
			KEY normalized_status_id (normalized_name(120),status,id),
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
			status varchar(20) NOT NULL DEFAULT 'open',
			expires_at_gmt datetime NOT NULL,
			created_at_gmt datetime NOT NULL,
			updated_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY session_uuid (session_uuid),
			KEY user_status (user_id,status),
			KEY target_operation (target_file_id,operation,status),
			KEY expires_at (expires_at_gmt)
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
		foreach ( array( 'files', 'folders', 'item_names', 'acl_grants', 'sync_events', 'devices', 'upload_sessions', 'tombstones', 'audit_log', 'jobs' ) as $name ) {
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
			'files'           => array( 'uuid', 'parent_status_id', 'normalized_status_id', 'updated_id', 'content_hash' ),
			'folders'         => array( 'uuid', 'parent_status_id', 'normalized_status_id', 'updated_id' ),
			'item_names'      => array( 'live_name', 'target_lookup', 'parent_lookup' ),
			'acl_grants'      => array( 'target_principal', 'principal_lookup', 'target_lookup' ),
			'sync_events'     => array( 'event_uuid', 'target_lookup', 'actor_seq', 'parent_seq' ),
			'devices'         => array( 'device_uuid', 'token_hash', 'user_status', 'last_seen' ),
			'upload_sessions' => array( 'session_uuid', 'user_status', 'target_operation', 'expires_at' ),
			'tombstones'      => array( 'target_lookup', 'owner_expires', 'sync_seq' ),
			'audit_log'       => array( 'actor_created', 'action_created', 'target_lookup' ),
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
			'attachment_links'          => self::repair_attachment_links( $apply ),
			'missing_tombstones'        => self::repair_missing_tombstones( $apply ),
			'blob_integrity'            => self::inspect_blob_integrity(),
			'sync_event_continuity'     => self::inspect_sync_event_continuity(),
			'quota_usage'               => self::inspect_quota_usage(),
			'orphaned_blobs'            => self::inspect_orphaned_blobs(),
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

		foreach ( array( 'folders' => 'folder', 'files' => 'file' ) as $source => $target_type ) {
			$rows = $wpdb->get_results(
				'SELECT id, parent_id, normalized_name FROM ' . self::table( $source ) . " WHERE status != 'deleted'",
				ARRAY_A
			); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			foreach ( $rows as $row ) {
				$exists = $wpdb->get_var(
					$wpdb->prepare(
						"SELECT id FROM $table WHERE target_type = %s AND target_id = %d LIMIT 1", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
						$target_type,
						(int) $row['id']
					)
				);
				if ( $exists ) {
					continue;
				}

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
			'missing'   => $created,
			'conflicts' => $conflicts,
		);
	}

	/**
	 * Remove reservations whose target row no longer exists or is deleted.
	 */
	private static function repair_orphaned_name_reservations( bool $apply ): array {
		global $wpdb;

		$table = self::table( 'item_names' );
		$rows = $wpdb->get_results( "SELECT id, target_type, target_id FROM $table", ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$orphans = 0;
		foreach ( $rows as $row ) {
			$source = 'folder' === $row['target_type'] ? self::table( 'folders' ) : self::table( 'files' );
			$target = $wpdb->get_var(
				$wpdb->prepare(
					"SELECT id FROM $source WHERE id = %d AND status != 'deleted' LIMIT 1", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
					(int) $row['target_id']
				)
			);
			if ( $target ) {
				continue;
			}

			++$orphans;
			if ( $apply ) {
				$wpdb->delete( $table, array( 'id' => (int) $row['id'] ), array( '%d' ) );
			}
		}

		return array( 'orphaned' => $orphans );
	}

	/**
	 * Remove ACL grants whose target no longer exists or is deleted.
	 */
	private static function repair_orphaned_acl_grants( bool $apply ): array {
		global $wpdb;

		$table = self::table( 'acl_grants' );
		$rows = $wpdb->get_results( "SELECT id, target_type, target_id FROM $table LIMIT 2000", ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$orphans = 0;
		foreach ( $rows as $row ) {
			$source = 'folder' === $row['target_type'] ? self::table( 'folders' ) : self::table( 'files' );
			$target = $wpdb->get_var(
				$wpdb->prepare(
					"SELECT id FROM $source WHERE id = %d AND status != 'deleted' LIMIT 1", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
					(int) $row['target_id']
				)
			);
			if ( $target ) {
				continue;
			}

			++$orphans;
			if ( $apply ) {
				$wpdb->delete( $table, array( 'id' => (int) $row['id'] ), array( '%d' ) );
			}
		}

		return array(
			'orphaned'     => $orphans,
			'scan_limited' => count( $rows ) >= 2000,
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
	 * Count unreferenced private blobs without returning private paths.
	 */
	private static function inspect_orphaned_blobs(): array {
		global $wpdb;

		$root = Floppy_Storage::root();
		if ( empty( $root['path'] ) || ! is_dir( $root['path'] ) ) {
			return array( 'candidates' => 0, 'scanned' => 0, 'scan_limited' => false );
		}

		$known = array_fill_keys(
			array_filter(
				array_merge(
					$wpdb->get_col( 'SELECT storage_key FROM ' . self::table( 'files' ) . " WHERE storage_key != ''" ), // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
					$wpdb->get_col( 'SELECT storage_key FROM ' . self::table( 'upload_sessions' ) . " WHERE storage_key != ''" ) // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
				)
			),
			true
		);
		$candidates = 0;
		$scanned = 0;
		$limit = 1000;
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
			if ( empty( $known[ $key ] ) && 0 !== strpos( $key, 'exports/' ) ) {
				++$candidates;
			}
			if ( $scanned >= $limit ) {
				break;
			}
		}

		return array(
			'candidates'   => $candidates,
			'scanned'      => $scanned,
			'scan_limited' => $scanned >= $limit,
		);
	}
}
