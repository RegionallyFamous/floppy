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
			KEY updated_id (updated_at_gmt,id)
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
			status varchar(20) NOT NULL DEFAULT 'open',
			expires_at_gmt datetime NOT NULL,
			created_at_gmt datetime NOT NULL,
			updated_at_gmt datetime NOT NULL,
			PRIMARY KEY  (id),
			UNIQUE KEY session_uuid (session_uuid),
			KEY user_status (user_id,status),
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
		foreach ( array( 'files', 'folders', 'acl_grants', 'sync_events', 'devices', 'upload_sessions', 'tombstones', 'audit_log', 'jobs' ) as $name ) {
			$table = self::table( $name );
			$found = $wpdb->get_var( $wpdb->prepare( 'SHOW TABLES LIKE %s', $table ) );
			if ( $found !== $table ) {
				$missing[] = $table;
			}
		}

		return $missing;
	}
}
