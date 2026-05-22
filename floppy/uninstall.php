<?php
/**
 * Uninstall handler for Floppy.
 *
 * By default Floppy preserves private files and metadata on uninstall to avoid
 * accidental data loss. Administrators can opt into full cleanup by defining
 * FLOPPY_DELETE_DATA_ON_UNINSTALL as true before uninstalling.
 *
 * @package Floppy
 */

defined( 'WP_UNINSTALL_PLUGIN' ) || exit;

if ( ! defined( 'FLOPPY_DELETE_DATA_ON_UNINSTALL' ) || ! FLOPPY_DELETE_DATA_ON_UNINSTALL ) {
	return;
}

global $wpdb;

$plugin_dir = plugin_dir_path( __FILE__ );
require_once $plugin_dir . 'includes/class-floppy-storage.php';

$files_table = $wpdb->prefix . 'floppy_files';
$sessions_table = $wpdb->prefix . 'floppy_upload_sessions';

$table_exists = $wpdb->get_var( $wpdb->prepare( 'SHOW TABLES LIKE %s', $files_table ) );
if ( $table_exists === $files_table ) {
	$files = $wpdb->get_results( "SELECT attachment_id, storage_key FROM {$files_table}", ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
	foreach ( $files as $file ) {
		if ( ! empty( $file['storage_key'] ) ) {
			@unlink( Floppy_Storage::path_for_key( $file['storage_key'] ) ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
		}
		if ( ! empty( $file['attachment_id'] ) ) {
			wp_delete_attachment( (int) $file['attachment_id'], true );
		}
	}
}

$sessions_exists = $wpdb->get_var( $wpdb->prepare( 'SHOW TABLES LIKE %s', $sessions_table ) );
if ( $sessions_exists === $sessions_table ) {
	$sessions = $wpdb->get_results( "SELECT storage_key FROM {$sessions_table}", ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
	foreach ( $sessions as $session ) {
		if ( ! empty( $session['storage_key'] ) ) {
			@unlink( Floppy_Storage::path_for_key( $session['storage_key'] ) ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
		}
	}
}

$tables = array(
	'floppy_files',
	'floppy_folders',
	'floppy_acl_grants',
	'floppy_sync_events',
	'floppy_devices',
	'floppy_upload_sessions',
	'floppy_tombstones',
	'floppy_audit_log',
	'floppy_jobs',
);

foreach ( $tables as $table ) {
	$wpdb->query( "DROP TABLE IF EXISTS {$wpdb->prefix}{$table}" ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
}

delete_option( 'floppy_db_version' );
delete_option( 'floppy_settings' );
delete_option( 'floppy_compatibility' );
delete_option( 'floppy_private_probe' );
