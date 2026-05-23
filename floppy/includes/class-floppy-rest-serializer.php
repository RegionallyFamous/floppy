<?php
/**
 * REST response serialization.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Converts internal Floppy records into public, redacted REST DTOs.
 */
final class Floppy_Rest_Serializer {
	/**
	 * Resolve a folder id into a public UUID.
	 */
	public static function parent_uuid_for( int $parent_id ): string {
		if ( $parent_id <= 0 ) {
			return '';
		}

		global $wpdb;
		return (string) $wpdb->get_var(
			$wpdb->prepare(
				'SELECT uuid FROM ' . Floppy_Schema::table( 'folders' ) . ' WHERE id = %d LIMIT 1',
				$parent_id
			)
		);
	}

	/**
	 * Serialize job state without leaking private storage keys.
	 */
	public static function job( array $job ): array {
		$result = json_decode( (string) $job['result_json'], true );
		if ( ! is_array( $result ) ) {
			$result = array();
		}
		unset( $result['export_key'] );

		$response = array(
			'job_id'         => (int) $job['id'],
			'job_uuid'       => $job['job_uuid'],
			'job_type'       => $job['job_type'],
			'status'         => $job['status'],
			'attempts'       => (int) $job['attempts'],
			'not_before_gmt' => $job['not_before_gmt'],
			'created_at_gmt' => $job['created_at_gmt'],
			'updated_at_gmt' => $job['updated_at_gmt'],
			'result'         => $result,
		);

		if ( 'export' === $job['job_type'] && 'complete' === $job['status'] ) {
			$response['download_url'] = rest_url( Floppy_Rest::NAMESPACE . '/exports/' . $job['job_uuid'] . '/download' );
		}

		return $response;
	}

	/**
	 * Serialize a retained version without private storage details.
	 */
	public static function version( array $row ): array {
		return array(
			'id'               => (int) $row['id'],
			'version_uuid'     => (string) $row['version_uuid'],
			'file_id'          => (int) $row['file_id'],
			'file_uuid'        => (string) $row['file_uuid'],
			'name'             => (string) $row['name'],
			'mime_type'        => (string) $row['mime_type'],
			'size_bytes'       => (int) $row['size_bytes'],
			'content_hash'     => (string) $row['content_hash'],
			'content_version'  => (string) $row['content_version'],
			'metadata_version' => (string) $row['metadata_version'],
			'reason'           => (string) $row['reason'],
			'created_by'       => (int) $row['created_by'],
			'created_at_gmt'   => (string) $row['created_at_gmt'],
			'download_url'      => rest_url( Floppy_Rest::NAMESPACE . '/files/' . (int) $row['file_id'] . '/versions/' . (int) $row['id'] . '/download' ),
		);
	}

	/**
	 * Serialize a recovery-center file/folder row.
	 */
	public static function recovery_item( array $row ): array {
		$item = 'folder' === (string) $row['kind'] ? self::folder( $row ) : self::file( $row );
		if ( 'active' !== (string) ( $row['status'] ?? '' ) ) {
			unset( $item['download_url'] );
		}

		return $item;
	}

	/**
	 * Serialize recovery activity without message/meta payloads.
	 */
	public static function recovery_activity( array $row ): array {
		return array(
			'action'         => (string) $row['action'],
			'target_type'    => (string) $row['target_type'],
			'target_id'      => (int) $row['target_id'],
			'created_at_gmt' => (string) $row['created_at_gmt'],
		);
	}

	/**
	 * Serialize a conflict lifecycle record without local paths or blobs.
	 */
	public static function conflict( array $row ): array {
		$file = null;
		$file_id = (int) $row['file_id'];
		if ( $file_id && Floppy_Permissions::can_read( 'file', $file_id ) ) {
			$file_row = Floppy_Permissions::get_target_row( 'file', $file_id );
			$file = $file_row ? self::file( $file_row ) : null;
		}

		return array(
			'id'                     => (int) $row['id'],
			'conflict_uuid'          => (string) $row['conflict_uuid'],
			'state'                  => (string) $row['status'],
			'file_id'                => $file_id,
			'file_uuid'              => (string) $row['file_uuid'],
			'local_item_uuid'        => '',
			'parent_id'              => (int) $row['parent_id'],
			'status'                 => (string) $row['status'],
			'reason'                 => (string) $row['reason'],
			'local_name'             => (string) $row['local_name'],
			'server_content_version' => (string) $row['server_content_version'],
			'local_content_hash'     => (string) $row['local_content_hash'],
			'local_size_bytes'       => (int) $row['local_size_bytes'],
			'client_created_at_gmt'  => (string) $row['client_created_at_gmt'],
			'resolved_at_gmt'        => (string) $row['resolved_at_gmt'],
			'created_at_gmt'         => (string) $row['created_at_gmt'],
			'updated_at_gmt'         => (string) $row['updated_at_gmt'],
			'item'                   => $file,
			'server_file'            => $file,
		);
	}

	/**
	 * Serialize folder row.
	 */
	public static function folder( array $row ): array {
		return array(
			'kind'             => 'folder',
			'id'               => (int) $row['id'],
			'uuid'             => $row['uuid'],
			'owner_id'         => (int) $row['owner_id'],
			'parent_id'        => (int) $row['parent_id'],
			'parent_uuid'      => self::parent_uuid_for( (int) $row['parent_id'] ),
			'name'             => $row['name'],
			'metadata_version' => $row['metadata_version'],
			'status'           => $row['status'],
			'created_at_gmt'   => $row['created_at_gmt'],
			'updated_at_gmt'   => $row['updated_at_gmt'],
		);
	}

	/**
	 * Serialize file row.
	 */
	public static function file( array $row ): array {
		return array(
			'kind'             => 'file',
			'id'               => (int) $row['id'],
			'uuid'             => $row['uuid'],
			'attachment_id'    => (int) $row['attachment_id'],
			'owner_id'         => (int) $row['owner_id'],
			'parent_id'        => (int) $row['parent_id'],
			'parent_uuid'      => self::parent_uuid_for( (int) $row['parent_id'] ),
			'name'             => $row['name'],
			'mime_type'        => $row['mime_type'],
			'size_bytes'       => (int) $row['size_bytes'],
			'content_hash'     => $row['content_hash'],
			'content_version'  => $row['content_version'],
			'metadata_version' => $row['metadata_version'],
			'status'           => $row['status'],
			'visibility'       => $row['visibility'],
			'download_url'     => rest_url( Floppy_Rest::NAMESPACE . '/files/' . (int) $row['id'] . '/download' ),
			'created_at_gmt'   => $row['created_at_gmt'],
			'updated_at_gmt'   => $row['updated_at_gmt'],
		);
	}
}
