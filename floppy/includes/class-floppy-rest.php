<?php
/**
 * REST API.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * REST endpoints for Floppy clients.
 */
final class Floppy_Rest {
	public const NAMESPACE = 'floppy/v1';

	/**
	 * Register REST routes.
	 */
	public static function init(): void {
		add_action( 'rest_api_init', array( __CLASS__, 'register_routes' ) );
	}

	/**
	 * Register REST API.
	 */
	public static function register_routes(): void {
		register_rest_route(
			self::NAMESPACE,
			'/discovery',
			array(
				'methods'             => WP_REST_Server::READABLE,
				'callback'            => array( __CLASS__, 'discovery' ),
				'permission_callback' => '__return_true',
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/health',
			array(
				'methods'             => WP_REST_Server::READABLE,
				'callback'            => array( __CLASS__, 'health' ),
				'permission_callback' => array( __CLASS__, 'require_admin' ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/files',
			array(
				'methods'             => WP_REST_Server::READABLE,
				'callback'            => array( __CLASS__, 'list_items' ),
				'permission_callback' => array( __CLASS__, 'require_read' ),
				'args'                => self::collection_args(),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/search',
			array(
				'methods'             => WP_REST_Server::READABLE,
				'callback'            => array( __CLASS__, 'search' ),
				'permission_callback' => array( __CLASS__, 'require_read' ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/folders',
			array(
				'methods'             => WP_REST_Server::CREATABLE,
				'callback'            => array( __CLASS__, 'create_folder' ),
				'permission_callback' => array( __CLASS__, 'require_write' ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/upload',
			array(
				'methods'             => WP_REST_Server::CREATABLE,
				'callback'            => array( __CLASS__, 'upload_file' ),
				'permission_callback' => array( __CLASS__, 'require_write' ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/upload-sessions',
			array(
				'methods'             => WP_REST_Server::CREATABLE,
				'callback'            => array( __CLASS__, 'create_upload_session' ),
				'permission_callback' => array( __CLASS__, 'require_write' ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/upload-sessions/(?P<uuid>[a-f0-9-]+)/chunk',
			array(
				'methods'             => WP_REST_Server::CREATABLE,
				'callback'            => array( __CLASS__, 'append_upload_chunk' ),
				'permission_callback' => array( __CLASS__, 'require_write' ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/upload-sessions/(?P<uuid>[a-f0-9-]+)/complete',
			array(
				'methods'             => WP_REST_Server::CREATABLE,
				'callback'            => array( __CLASS__, 'complete_upload_session' ),
				'permission_callback' => array( __CLASS__, 'require_write' ),
			)
		);

		foreach ( array( 'rename', 'move', 'trash', 'restore', 'replace' ) as $action ) {
			register_rest_route(
				self::NAMESPACE,
				'/files/(?P<id>[\d]+)/' . $action,
				array(
					'methods'             => WP_REST_Server::CREATABLE,
					'callback'            => array( __CLASS__, 'file_' . $action ),
					'permission_callback' => array( __CLASS__, 'require_write' ),
					'args'                => array( 'id' => array( 'sanitize_callback' => 'absint' ) ),
				)
			);
		}

		register_rest_route(
			self::NAMESPACE,
			'/files/(?P<id>[\d]+)/download',
			array(
				'methods'             => WP_REST_Server::READABLE,
				'callback'            => array( __CLASS__, 'download_file' ),
				'permission_callback' => array( __CLASS__, 'require_read' ),
				'args'                => array( 'id' => array( 'sanitize_callback' => 'absint' ) ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/files/(?P<id>[\d]+)/preview',
			array(
				'methods'             => WP_REST_Server::READABLE,
				'callback'            => array( __CLASS__, 'preview_file' ),
				'permission_callback' => array( __CLASS__, 'require_read' ),
				'args'                => array( 'id' => array( 'sanitize_callback' => 'absint' ) ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/files/(?P<id>[\d]+)',
			array(
				'methods'             => WP_REST_Server::DELETABLE,
				'callback'            => array( __CLASS__, 'delete_file' ),
				'permission_callback' => array( __CLASS__, 'require_write' ),
				'args'                => array( 'id' => array( 'sanitize_callback' => 'absint' ) ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/sync/changes',
			array(
				'methods'             => WP_REST_Server::READABLE,
				'callback'            => array( __CLASS__, 'sync_changes' ),
				'permission_callback' => array( __CLASS__, 'require_sync' ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/devices',
			array(
				'methods'             => WP_REST_Server::READABLE,
				'callback'            => array( __CLASS__, 'list_devices' ),
				'permission_callback' => array( __CLASS__, 'require_browser_session' ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/devices/authorize',
			array(
				'methods'             => WP_REST_Server::CREATABLE,
				'callback'            => array( __CLASS__, 'authorize_device' ),
				'permission_callback' => array( __CLASS__, 'require_device_authorization' ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/devices/(?P<uuid>[a-f0-9-]+)/revoke',
			array(
				'methods'             => WP_REST_Server::CREATABLE,
				'callback'            => array( __CLASS__, 'revoke_device' ),
				'permission_callback' => array( __CLASS__, 'require_browser_session' ),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/share',
			array(
				array(
					'methods'             => WP_REST_Server::CREATABLE,
					'callback'            => array( __CLASS__, 'share_target' ),
					'permission_callback' => array( __CLASS__, 'require_write' ),
				),
				array(
					'methods'             => WP_REST_Server::DELETABLE,
					'callback'            => array( __CLASS__, 'unshare_target' ),
					'permission_callback' => array( __CLASS__, 'require_write' ),
				),
			)
		);

		register_rest_route(
			self::NAMESPACE,
			'/exports',
			array(
				'methods'             => WP_REST_Server::CREATABLE,
				'callback'            => array( __CLASS__, 'enqueue_export' ),
				'permission_callback' => array( __CLASS__, 'require_browser_session' ),
			)
		);
	}

	/**
	 * Public discovery.
	 */
	public static function discovery(): WP_REST_Response {
		return new WP_REST_Response(
			array(
				'name'         => 'Floppy',
				'version'      => FLOPPY_VERSION,
				'namespace'    => self::NAMESPACE,
				'rest_url'     => esc_url_raw( rest_url( self::NAMESPACE ) ),
				'auth'         => array( 'browser_device_approval', 'wordpress_session' ),
				'desktop_mode' => function_exists( 'desktop_mode_register_window' ),
				'private'      => true,
			)
		);
	}

	/**
	 * Health endpoint.
	 */
	public static function health(): WP_REST_Response {
		return new WP_REST_Response( Floppy_Compatibility::summary() );
	}

	/**
	 * List files and folders under a parent.
	 */
	public static function list_items( WP_REST_Request $request ) {
		global $wpdb;

		$user_id   = get_current_user_id();
		$parent_id = absint( $request->get_param( 'parent_id' ) );
		$after_id  = absint( $request->get_param( 'after_id' ) );
		$limit     = max( 1, min( 100, absint( $request->get_param( 'limit' ) ?: 50 ) ) );

		if ( $parent_id && ! Floppy_Permissions::can_read( 'folder', $parent_id, $user_id ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot read this folder.', 'floppy' ), array( 'status' => 403 ) );
		}

		$folder_rows = self::query_children( Floppy_Schema::table( 'folders' ), $parent_id, $after_id, $limit, $user_id );
		$file_rows   = self::query_children( Floppy_Schema::table( 'files' ), $parent_id, $after_id, $limit, $user_id );

		$items = array();
		foreach ( $folder_rows as $row ) {
			if ( Floppy_Permissions::can_read( 'folder', (int) $row['id'], $user_id ) ) {
				$items[] = self::serialize_folder( $row );
			}
		}
		foreach ( $file_rows as $row ) {
			if ( Floppy_Permissions::can_read( 'file', (int) $row['id'], $user_id ) ) {
				$items[] = self::serialize_file( $row );
			}
		}

		usort(
			$items,
			static function ( $a, $b ) {
				if ( $a['kind'] === $b['kind'] ) {
					return strnatcasecmp( $a['name'], $b['name'] );
				}

				return 'folder' === $a['kind'] ? -1 : 1;
			}
		);

		return new WP_REST_Response(
			array(
				'parent_id' => $parent_id,
				'limit'     => $limit,
				'items'     => $items,
			)
		);
	}

	/**
	 * Create a folder.
	 */
	public static function create_folder( WP_REST_Request $request ) {
		global $wpdb;

		$user_id   = get_current_user_id();
		$parent_id = absint( $request->get_param( 'parent_id' ) );
		$name      = Floppy_Storage::normalize_filename( (string) $request->get_param( 'name' ) );

		if ( $parent_id && ! Floppy_Permissions::can_write( 'folder', $parent_id, $user_id ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot create folders here.', 'floppy' ), array( 'status' => 403 ) );
		}

		$collision = self::name_collision( 'folders', $parent_id, $name );
		if ( is_wp_error( $collision ) ) {
			return $collision;
		}

		$now = current_time( 'mysql', true );
		$row = array(
			'uuid'             => wp_generate_uuid4(),
			'owner_id'         => $user_id,
			'parent_id'        => $parent_id,
			'name'             => $name,
			'normalized_name'  => Floppy_Storage::normalize_lookup_name( $name ),
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

		Floppy_Sync::append_event( 'folder.created', 'folder', $row['id'], $row, $user_id );
		Floppy_Audit::log( 'folder.created', 'folder', $row['id'], $name );

		return new WP_REST_Response( self::serialize_folder( $row ), 201 );
	}

	/**
	 * Search visible files and folders by name.
	 */
	public static function search( WP_REST_Request $request ): WP_REST_Response {
		global $wpdb;

		$user_id = get_current_user_id();
		$q = trim( sanitize_text_field( (string) $request->get_param( 'q' ) ) );
		$limit = max( 1, min( 100, absint( $request->get_param( 'limit' ) ?: 50 ) ) );
		if ( '' === $q ) {
			return new WP_REST_Response( array( 'items' => array() ) );
		}

		$like = '%' . $wpdb->esc_like( Floppy_Storage::normalize_lookup_name( $q ) ) . '%';
		$folders = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'folders' ) . " WHERE status = 'active' AND normalized_name LIKE %s ORDER BY updated_at_gmt DESC, id DESC LIMIT %d",
				$like,
				$limit
			),
			ARRAY_A
		);
		$files = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'files' ) . " WHERE status = 'active' AND normalized_name LIKE %s ORDER BY updated_at_gmt DESC, id DESC LIMIT %d",
				$like,
				$limit
			),
			ARRAY_A
		);

		$items = array();
		foreach ( $folders as $row ) {
			if ( Floppy_Permissions::can_read( 'folder', (int) $row['id'], $user_id ) ) {
				$items[] = self::serialize_folder( $row );
			}
		}
		foreach ( $files as $row ) {
			if ( Floppy_Permissions::can_read( 'file', (int) $row['id'], $user_id ) ) {
				$items[] = self::serialize_file( $row );
			}
		}

		return new WP_REST_Response( array( 'items' => array_slice( $items, 0, $limit ) ) );
	}

	/**
	 * Upload a private file.
	 */
	public static function upload_file( WP_REST_Request $request ) {
		global $wpdb;

		$user_id = get_current_user_id();
		$rate = Floppy_Rate_Limiter::check( 'upload', 120, HOUR_IN_SECONDS, 'user:' . $user_id );
		if ( is_wp_error( $rate ) ) {
			return $rate;
		}

		if ( ! current_user_can( 'upload_files' ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot upload files.', 'floppy' ), array( 'status' => 403 ) );
		}

		$private_mode = Floppy_Storage::require_private_mode();
		if ( is_wp_error( $private_mode ) ) {
			return $private_mode;
		}

		$parent_id = absint( $request->get_param( 'parent_id' ) );
		if ( $parent_id && ! Floppy_Permissions::can_write( 'folder', $parent_id, $user_id ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot upload into this folder.', 'floppy' ), array( 'status' => 403 ) );
		}

		$files = $request->get_file_params();
		$file  = $files['file'] ?? null;
		if ( ! is_array( $file ) ) {
			return new WP_Error( 'floppy_missing_file', __( 'Upload a file using the "file" field.', 'floppy' ), array( 'status' => 400 ) );
		}

		$stored = Floppy_Storage::store_upload( $file );
		if ( isset( $stored['error'] ) && is_wp_error( $stored['error'] ) ) {
			return $stored['error'];
		}

		$scan = apply_filters( 'floppy_validate_private_upload', true, $stored, $request );
		if ( is_wp_error( $scan ) ) {
			@unlink( $stored['path'] ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			return $scan;
		}

		$collision = self::name_collision( 'files', $parent_id, $stored['name'] );
		if ( is_wp_error( $collision ) ) {
			@unlink( $stored['path'] ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			return $collision;
		}

		$attachment_id = self::create_private_attachment( $stored, $user_id );
		if ( is_wp_error( $attachment_id ) ) {
			@unlink( $stored['path'] ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			return $attachment_id;
		}

		$now = current_time( 'mysql', true );
		$row = array(
			'uuid'             => $stored['uuid'],
			'attachment_id'    => $attachment_id,
			'owner_id'         => $user_id,
			'parent_id'        => $parent_id,
			'name'             => $stored['name'],
			'normalized_name'  => Floppy_Storage::normalize_lookup_name( $stored['name'] ),
			'mime_type'        => $stored['mime_type'],
			'size_bytes'       => $stored['size_bytes'],
			'content_hash'     => $stored['content_hash'],
			'storage_key'      => $stored['storage_key'],
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

		Floppy_Sync::append_event( 'file.created', 'file', $row['id'], $row, $user_id );
		Floppy_Audit::log( 'file.uploaded', 'file', $row['id'], $stored['name'], array( 'size_bytes' => $stored['size_bytes'] ) );

		return new WP_REST_Response( self::serialize_file( $row ), 201 );
	}

	/**
	 * Create a resumable upload session.
	 */
	public static function create_upload_session( WP_REST_Request $request ) {
		global $wpdb;

		$user_id = get_current_user_id();
		$rate = Floppy_Rate_Limiter::check( 'upload-session', 300, HOUR_IN_SECONDS, 'user:' . $user_id );
		if ( is_wp_error( $rate ) ) {
			return $rate;
		}

		if ( ! current_user_can( 'upload_files' ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot upload files.', 'floppy' ), array( 'status' => 403 ) );
		}

		$private_mode = Floppy_Storage::require_private_mode();
		if ( is_wp_error( $private_mode ) ) {
			return $private_mode;
		}

		$parent_id = absint( $request->get_param( 'parent_id' ) );
		if ( $parent_id && ! Floppy_Permissions::can_write( 'folder', $parent_id, $user_id ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot upload into this folder.', 'floppy' ), array( 'status' => 403 ) );
		}

		$filename = Floppy_Storage::normalize_filename( (string) $request->get_param( 'filename' ) );
		$total_size = absint( $request->get_param( 'total_size' ) );
		$max = (int) Floppy_Settings::get_value( 'max_file_size', wp_max_upload_size() );
		if ( $total_size <= 0 || $total_size > $max ) {
			return new WP_Error( 'floppy_invalid_upload_size', __( 'Invalid upload size.', 'floppy' ), array( 'status' => 413 ) );
		}
		if ( Floppy_Storage::has_dangerous_extension( $filename ) ) {
			return new WP_Error( 'floppy_dangerous_file_type', __( 'This file type is not allowed in private storage.', 'floppy' ), array( 'status' => 415 ) );
		}

		$uuid = wp_generate_uuid4();
		$storage_key = 'chunks/' . Floppy_Storage::storage_key( $uuid, 'part' );
		$path = Floppy_Storage::path_for_key( $storage_key );
		if ( ! wp_mkdir_p( dirname( $path ) ) ) {
			return new WP_Error( 'floppy_storage_unwritable', __( 'Floppy could not create a chunk storage shard.', 'floppy' ), array( 'status' => 500 ) );
		}
		touch( $path );

		$now = current_time( 'mysql', true );
		$wpdb->insert(
			Floppy_Schema::table( 'upload_sessions' ),
			array(
				'session_uuid'   => $uuid,
				'user_id'        => $user_id,
				'parent_id'      => $parent_id,
				'filename'       => $filename,
				'total_size'     => $total_size,
				'received_bytes' => 0,
				'content_hash'   => sanitize_text_field( (string) $request->get_param( 'content_hash' ) ),
				'mime_type'      => sanitize_text_field( (string) $request->get_param( 'mime_type' ) ),
				'storage_key'    => $storage_key,
				'status'         => 'open',
				'expires_at_gmt' => gmdate( 'Y-m-d H:i:s', time() + DAY_IN_SECONDS ),
				'created_at_gmt' => $now,
				'updated_at_gmt' => $now,
			),
			array( '%s', '%d', '%d', '%s', '%d', '%d', '%s', '%s', '%s', '%s', '%s', '%s', '%s' )
		);

		Floppy_Audit::log( 'upload_session.created', 'upload_session', (int) $wpdb->insert_id, $filename, array( 'size_bytes' => $total_size ) );

		return new WP_REST_Response(
			array(
				'session_uuid'   => $uuid,
				'received_bytes' => 0,
				'expires_at_gmt' => gmdate( 'Y-m-d H:i:s', time() + DAY_IN_SECONDS ),
			),
			201
		);
	}

	/**
	 * Append a chunk to an upload session.
	 */
	public static function append_upload_chunk( WP_REST_Request $request ) {
		global $wpdb;

		$session = self::get_upload_session( sanitize_text_field( (string) $request['uuid'] ) );
		if ( is_wp_error( $session ) ) {
			return $session;
		}

		if ( (int) $session['user_id'] !== get_current_user_id() ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot write to this upload session.', 'floppy' ), array( 'status' => 403 ) );
		}

		$offset = isset( $_SERVER['HTTP_X_FLOPPY_OFFSET'] ) ? absint( wp_unslash( $_SERVER['HTTP_X_FLOPPY_OFFSET'] ) ) : absint( $request->get_param( 'offset' ) ); // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized
		if ( $offset !== (int) $session['received_bytes'] ) {
			return new WP_Error( 'floppy_upload_offset_mismatch', __( 'Upload chunk offset does not match the server cursor.', 'floppy' ), array( 'status' => 409, 'received_bytes' => (int) $session['received_bytes'] ) );
		}

		$body = file_get_contents( 'php://input' ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_get_contents_file_get_contents
		if ( false === $body || '' === $body ) {
			return new WP_Error( 'floppy_empty_chunk', __( 'Chunk body is empty.', 'floppy' ), array( 'status' => 400 ) );
		}

		$length = strlen( $body );
		$received = (int) $session['received_bytes'] + $length;
		if ( $received > (int) $session['total_size'] ) {
			return new WP_Error( 'floppy_upload_overflow', __( 'Upload exceeded the declared size.', 'floppy' ), array( 'status' => 413 ) );
		}

		$path = Floppy_Storage::path_for_key( $session['storage_key'] );
		$handle = fopen( $path, 'c+b' ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_fopen
		if ( ! $handle ) {
			return new WP_Error( 'floppy_chunk_write_failed', __( 'Could not write upload chunk.', 'floppy' ), array( 'status' => 500 ) );
		}

		flock( $handle, LOCK_EX );
		clearstatcache( true, $path );
		if ( filesize( $path ) !== $offset ) {
			flock( $handle, LOCK_UN );
			fclose( $handle );
			return new WP_Error( 'floppy_upload_offset_mismatch', __( 'Upload chunk offset does not match the stored chunk size.', 'floppy' ), array( 'status' => 409, 'received_bytes' => filesize( $path ) ) );
		}

		fseek( $handle, $offset );
		$written = fwrite( $handle, $body ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_fwrite
		if ( $written !== $length ) {
			ftruncate( $handle, $offset );
			flock( $handle, LOCK_UN );
			fclose( $handle );
			return new WP_Error( 'floppy_chunk_write_failed', __( 'Could not write the complete upload chunk.', 'floppy' ), array( 'status' => 500 ) );
		}

		$updated = $wpdb->query(
			$wpdb->prepare(
				'UPDATE ' . Floppy_Schema::table( 'upload_sessions' ) . ' SET received_bytes = %d, updated_at_gmt = %s WHERE id = %d AND received_bytes = %d',
				$received,
				current_time( 'mysql', true ),
				(int) $session['id'],
				$offset
			)
		);

		if ( 1 !== $updated ) {
			ftruncate( $handle, $offset );
			flock( $handle, LOCK_UN );
			fclose( $handle );
			return new WP_Error( 'floppy_upload_offset_mismatch', __( 'Upload session changed while writing this chunk.', 'floppy' ), array( 'status' => 409, 'received_bytes' => (int) $session['received_bytes'] ) );
		}

		fflush( $handle );
		flock( $handle, LOCK_UN );
		fclose( $handle );

		return new WP_REST_Response( array( 'received_bytes' => $received ) );
	}

	/**
	 * Complete a resumable upload session.
	 */
	public static function complete_upload_session( WP_REST_Request $request ) {
		global $wpdb;

		$session = self::get_upload_session( sanitize_text_field( (string) $request['uuid'] ) );
		if ( is_wp_error( $session ) ) {
			return $session;
		}

		if ( (int) $session['user_id'] !== get_current_user_id() ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot complete this upload session.', 'floppy' ), array( 'status' => 403 ) );
		}

		if ( (int) $session['received_bytes'] !== (int) $session['total_size'] ) {
			return new WP_Error( 'floppy_upload_incomplete', __( 'The upload session is not complete.', 'floppy' ), array( 'status' => 409, 'received_bytes' => (int) $session['received_bytes'] ) );
		}

		$tmp_path = Floppy_Storage::path_for_key( $session['storage_key'] );
		$hash = hash_file( 'sha256', $tmp_path );
		if ( ! empty( $session['content_hash'] ) && strtolower( $session['content_hash'] ) !== $hash ) {
			return new WP_Error( 'floppy_upload_hash_mismatch', __( 'Upload hash did not match.', 'floppy' ), array( 'status' => 409 ) );
		}

		$final_uuid = wp_generate_uuid4();
		$ext = pathinfo( $session['filename'], PATHINFO_EXTENSION );
		$final_key = Floppy_Storage::storage_key( $final_uuid, $ext );
		$final_path = Floppy_Storage::path_for_key( $final_key );
		if ( ! wp_mkdir_p( dirname( $final_path ) ) || ! rename( $tmp_path, $final_path ) ) {
			return new WP_Error( 'floppy_upload_finalize_failed', __( 'Could not finalize upload.', 'floppy' ), array( 'status' => 500 ) );
		}

		$type = wp_check_filetype_and_ext( $final_path, $session['filename'] );
		if ( empty( $type['type'] ) ) {
			@unlink( $final_path ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			return new WP_Error( 'floppy_unknown_mime', __( 'Floppy could not verify the file type.', 'floppy' ), array( 'status' => 415 ) );
		}

		$stored = array(
			'uuid'         => $final_uuid,
			'name'         => $session['filename'],
			'path'         => $final_path,
			'storage_key'  => $final_key,
			'content_hash' => $hash,
			'size_bytes'   => (int) $session['total_size'],
			'mime_type'    => $type['type'],
		);

		$row = self::create_file_row_from_stored( $stored, (int) $session['user_id'], (int) $session['parent_id'] );
		if ( is_wp_error( $row ) ) {
			@unlink( $final_path ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			return $row;
		}

		$wpdb->update(
			Floppy_Schema::table( 'upload_sessions' ),
			array(
				'status'         => 'complete',
				'updated_at_gmt' => current_time( 'mysql', true ),
			),
			array( 'id' => (int) $session['id'] ),
			array( '%s', '%s' ),
			array( '%d' )
		);

		return new WP_REST_Response( self::serialize_file( $row ), 201 );
	}

	/**
	 * Replace file contents using a content-version compare-and-swap.
	 */
	public static function file_replace( WP_REST_Request $request ) {
		global $wpdb;

		$id = absint( $request['id'] );
		$user_id = get_current_user_id();
		$rate = Floppy_Rate_Limiter::check( 'upload', 120, HOUR_IN_SECONDS, 'user:' . $user_id );
		if ( is_wp_error( $rate ) ) {
			return $rate;
		}

		if ( ! current_user_can( 'upload_files' ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot upload files.', 'floppy' ), array( 'status' => 403 ) );
		}

		$private_mode = Floppy_Storage::require_private_mode();
		if ( is_wp_error( $private_mode ) ) {
			return $private_mode;
		}

		if ( ! Floppy_Permissions::can_write( 'file', $id, $user_id ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot modify this file.', 'floppy' ), array( 'status' => 403 ) );
		}

		$row = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $row || 'active' !== $row['status'] ) {
			return new WP_Error( 'floppy_file_not_found', __( 'File not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$known_version = (string) $request->get_param( 'content_version' );
		if ( '' === $known_version ) {
			return new WP_Error( 'floppy_content_version_required', __( 'A content version is required to replace file contents.', 'floppy' ), array( 'status' => 428, 'server' => self::serialize_file( $row ) ) );
		}

		if ( $known_version !== $row['content_version'] ) {
			return new WP_Error( 'floppy_conflict', __( 'The file contents changed on the server. Refresh before applying this change.', 'floppy' ), array( 'status' => 409, 'server' => self::serialize_file( $row ) ) );
		}

		$files = $request->get_file_params();
		$file  = $files['file'] ?? null;
		if ( ! is_array( $file ) ) {
			return new WP_Error( 'floppy_missing_file', __( 'Upload a file using the "file" field.', 'floppy' ), array( 'status' => 400 ) );
		}

		$file['name'] = $row['name'];
		$stored = Floppy_Storage::store_upload( $file );
		if ( isset( $stored['error'] ) && is_wp_error( $stored['error'] ) ) {
			return $stored['error'];
		}

		$scan = apply_filters( 'floppy_validate_private_upload', true, $stored, $request );
		if ( is_wp_error( $scan ) ) {
			@unlink( $stored['path'] ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			return $scan;
		}

		$next_content_version = wp_generate_uuid4();
		$updated_at = current_time( 'mysql', true );
		$updated = $wpdb->query(
			$wpdb->prepare(
				'UPDATE ' . Floppy_Schema::table( 'files' ) . ' SET mime_type = %s, size_bytes = %d, content_hash = %s, storage_key = %s, content_version = %s, updated_at_gmt = %s WHERE id = %d AND content_version = %s',
				$stored['mime_type'],
				(int) $stored['size_bytes'],
				$stored['content_hash'],
				$stored['storage_key'],
				$next_content_version,
				$updated_at,
				$id,
				$known_version
			)
		);

		if ( 1 !== $updated ) {
			@unlink( $stored['path'] ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			$server = Floppy_Permissions::get_target_row( 'file', $id );
			return new WP_Error( 'floppy_conflict', __( 'The file contents changed while this replacement was uploading.', 'floppy' ), array( 'status' => 409, 'server' => $server ? self::serialize_file( $server ) : null ) );
		}

		if ( ! empty( $row['attachment_id'] ) ) {
			wp_update_post(
				array(
					'ID'             => (int) $row['attachment_id'],
					'post_mime_type' => $stored['mime_type'],
				)
			);
			update_attached_file( (int) $row['attachment_id'], $stored['path'] );
			update_post_meta( (int) $row['attachment_id'], '_floppy_storage_key', $stored['storage_key'] );
		}

		$next = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $next ) {
			return new WP_Error( 'floppy_file_not_found', __( 'File not found after replacing contents.', 'floppy' ), array( 'status' => 404 ) );
		}

		$seq = Floppy_Sync::append_event( 'file.updated', 'file', $id, $next ?: array(), $user_id );
		$next['last_sync_seq'] = $seq;

		$old_path = Floppy_Storage::path_for_key( $row['storage_key'] );
		if ( $old_path !== $stored['path'] && file_exists( $old_path ) ) {
			@unlink( $old_path ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
		}

		Floppy_Audit::log( 'file.content_updated', 'file', $id, $row['name'], array( 'size_bytes' => (int) $stored['size_bytes'] ), $user_id );

		return new WP_REST_Response( self::serialize_file( $next ) + array( 'last_sync_seq' => $seq ) );
	}

	/**
	 * Rename a file.
	 */
	public static function file_rename( WP_REST_Request $request ) {
		$id = absint( $request['id'] );
		$name = Floppy_Storage::normalize_filename( (string) $request->get_param( 'name' ) );

		return self::update_file_metadata( $id, $request, array( 'name' => $name, 'normalized_name' => Floppy_Storage::normalize_lookup_name( $name ) ), 'file.renamed' );
	}

	/**
	 * Move a file.
	 */
	public static function file_move( WP_REST_Request $request ) {
		$id = absint( $request['id'] );
		$parent_id = absint( $request->get_param( 'parent_id' ) );

		if ( $parent_id && ! Floppy_Permissions::can_write( 'folder', $parent_id ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot move files into this folder.', 'floppy' ), array( 'status' => 403 ) );
		}

		return self::update_file_metadata( $id, $request, array( 'parent_id' => $parent_id ), 'file.moved' );
	}

	/**
	 * Trash a file.
	 */
	public static function file_trash( WP_REST_Request $request ) {
		return self::update_file_metadata( absint( $request['id'] ), $request, array( 'status' => 'trashed', 'deleted_at_gmt' => current_time( 'mysql', true ) ), 'file.trashed' );
	}

	/**
	 * Restore a file.
	 */
	public static function file_restore( WP_REST_Request $request ) {
		return self::update_file_metadata( absint( $request['id'] ), $request, array( 'status' => 'active', 'deleted_at_gmt' => null ), 'file.restored' );
	}

	/**
	 * Tombstone a file.
	 */
	public static function delete_file( WP_REST_Request $request ) {
		$id = absint( $request['id'] );
		$response = self::update_file_metadata( $id, $request, array( 'status' => 'deleted', 'deleted_at_gmt' => current_time( 'mysql', true ) ), 'file.deleted' );
		if ( is_wp_error( $response ) ) {
			return $response;
		}

		$data = $response->get_data();
		Floppy_Sync::tombstone( 'file', $id, (int) $data['owner_id'], (int) $data['last_sync_seq'] );
		return $response;
	}

	/**
	 * Stream a private file.
	 */
	public static function download_file( WP_REST_Request $request ) {
		return self::stream_file( absint( $request['id'] ), false );
	}

	/**
	 * Stream a preview inline.
	 */
	public static function preview_file( WP_REST_Request $request ) {
		return self::stream_file( absint( $request['id'] ), true );
	}

	/**
	 * Stream a private file.
	 */
	private static function stream_file( int $id, bool $inline ) {
		if ( ! Floppy_Permissions::can_read( 'file', $id ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot download this file.', 'floppy' ), array( 'status' => 403 ) );
		}

		$rate = Floppy_Rate_Limiter::check( 'download', 600, HOUR_IN_SECONDS );
		if ( is_wp_error( $rate ) ) {
			return $rate;
		}

		$row = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $row || 'active' !== $row['status'] ) {
			return new WP_Error( 'floppy_file_not_found', __( 'File not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$path = Floppy_Storage::path_for_key( $row['storage_key'] );
		if ( ! is_readable( $path ) ) {
			return new WP_Error( 'floppy_blob_missing', __( 'The private blob is missing from storage.', 'floppy' ), array( 'status' => 500 ) );
		}

		Floppy_Audit::log( 'file.downloaded', 'file', $id, $row['name'] );

		nocache_headers();
		header( 'Content-Type: ' . ( $row['mime_type'] ?: 'application/octet-stream' ) );
		header( 'Content-Length: ' . filesize( $path ) );
		header( 'Content-Disposition: ' . ( $inline ? 'inline' : 'attachment' ) . '; filename="' . str_replace( '"', '', $row['name'] ) . '"' );
		readfile( $path ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_readfile
		exit;
	}

	/**
	 * Cursor-based sync changes.
	 */
	public static function sync_changes( WP_REST_Request $request ) {
		$rate = Floppy_Rate_Limiter::check( 'sync', 1800, HOUR_IN_SECONDS );
		if ( is_wp_error( $rate ) ) {
			return $rate;
		}

		$cursor = absint( $request->get_param( 'cursor' ) );
		$limit  = absint( $request->get_param( 'limit' ) ?: 250 );
		$result = Floppy_Sync::get_changes( $cursor, $limit, get_current_user_id() );
		if ( is_wp_error( $result ) ) {
			return $result;
		}

		return new WP_REST_Response( $result );
	}

	/**
	 * List devices.
	 */
	public static function list_devices(): WP_REST_Response {
		return new WP_REST_Response( array( 'devices' => Floppy_Auth::list_devices( get_current_user_id() ) ) );
	}

	/**
	 * Authorize a device from a browser-approved session.
	 */
	public static function authorize_device( WP_REST_Request $request ) {
		$name = sanitize_text_field( (string) $request->get_param( 'device_name' ) );
		$device = Floppy_Auth::create_device( get_current_user_id(), $name );
		if ( is_wp_error( $device ) ) {
			return $device;
		}

		return new WP_REST_Response( $device, 201 );
	}

	/**
	 * Revoke a device.
	 */
	public static function revoke_device( WP_REST_Request $request ) {
		$result = Floppy_Auth::revoke_device( sanitize_text_field( (string) $request['uuid'] ), get_current_user_id() );
		if ( is_wp_error( $result ) ) {
			return $result;
		}

		return new WP_REST_Response( array( 'ok' => true ) );
	}

	/**
	 * Share a file or folder.
	 */
	public static function share_target( WP_REST_Request $request ) {
		global $wpdb;

		$target_type = sanitize_key( (string) $request->get_param( 'target_type' ) );
		$target_id = absint( $request->get_param( 'target_id' ) );
		$principal_type = sanitize_key( (string) $request->get_param( 'principal_type' ) );
		$principal_ref = sanitize_text_field( (string) $request->get_param( 'principal_ref' ) );
		$capability = 'write' === $request->get_param( 'capability' ) ? 'write' : 'read';

		if ( ! in_array( $target_type, array( 'file', 'folder' ), true ) || ! in_array( $principal_type, array( 'user', 'role' ), true ) ) {
			return new WP_Error( 'floppy_invalid_share', __( 'Invalid share target or principal.', 'floppy' ), array( 'status' => 400 ) );
		}

		if ( ! Floppy_Permissions::can_write( $target_type, $target_id ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot share this item.', 'floppy' ), array( 'status' => 403 ) );
		}

		$now = current_time( 'mysql', true );
		$wpdb->replace(
			Floppy_Schema::table( 'acl_grants' ),
			array(
				'target_type'    => $target_type,
				'target_id'      => $target_id,
				'principal_type' => $principal_type,
				'principal_ref'  => $principal_ref,
				'capability'     => $capability,
				'state'          => 'accepted',
				'created_by'     => get_current_user_id(),
				'created_at_gmt' => $now,
				'updated_at_gmt' => $now,
			),
			array( '%s', '%d', '%s', '%s', '%s', '%s', '%d', '%s', '%s' )
		);

		$payload = array(
			'target_type'    => $target_type,
			'target_id'      => $target_id,
			'principal_type' => $principal_type,
			'principal_ref'  => $principal_ref,
			'capability'     => $capability,
		);
		Floppy_Sync::append_event( 'share.updated', $target_type, $target_id, $payload );
		Floppy_Audit::log( 'share.updated', $target_type, $target_id, '', $payload );

		return new WP_REST_Response( array( 'ok' => true, 'share' => $payload ), 201 );
	}

	/**
	 * Remove a share.
	 */
	public static function unshare_target( WP_REST_Request $request ) {
		global $wpdb;

		$target_type = sanitize_key( (string) $request->get_param( 'target_type' ) );
		$target_id = absint( $request->get_param( 'target_id' ) );
		$principal_type = sanitize_key( (string) $request->get_param( 'principal_type' ) );
		$principal_ref = sanitize_text_field( (string) $request->get_param( 'principal_ref' ) );

		if ( ! Floppy_Permissions::can_write( $target_type, $target_id ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot unshare this item.', 'floppy' ), array( 'status' => 403 ) );
		}

		$wpdb->delete(
			Floppy_Schema::table( 'acl_grants' ),
			array(
				'target_type'    => $target_type,
				'target_id'      => $target_id,
				'principal_type' => $principal_type,
				'principal_ref'  => $principal_ref,
			),
			array( '%s', '%d', '%s', '%s' )
		);

		Floppy_Sync::append_event( 'share.revoked', $target_type, $target_id, compact( 'target_type', 'target_id', 'principal_type', 'principal_ref' ) );
		Floppy_Audit::log( 'share.revoked', $target_type, $target_id );

		return new WP_REST_Response( array( 'ok' => true ) );
	}

	/**
	 * Enqueue an export job.
	 */
	public static function enqueue_export() {
		$job_id = Floppy_Background_Jobs::enqueue( 'export', array( 'user_id' => get_current_user_id() ), 5 );
		if ( is_wp_error( $job_id ) ) {
			return $job_id;
		}

		Floppy_Audit::log( 'export.enqueued', 'export', (int) $job_id );
		return new WP_REST_Response( array( 'ok' => true, 'job_id' => $job_id ), 202 );
	}

	/**
	 * Require a logged-in user.
	 */
	public static function require_user() {
		return is_user_logged_in() ? true : new WP_Error( 'floppy_rest_forbidden', __( 'Authentication required.', 'floppy' ), array( 'status' => 401 ) );
	}

	/**
	 * Require file read scope.
	 */
	public static function require_read() {
		return self::require_scope( 'files:read' );
	}

	/**
	 * Require file write scope.
	 */
	public static function require_write() {
		return self::require_scope( 'files:write' );
	}

	/**
	 * Require sync scope.
	 */
	public static function require_sync() {
		return self::require_scope( 'sync' );
	}

	/**
	 * Require a browser-authenticated WordPress session, not a device token.
	 */
	public static function require_browser_session() {
		$user = self::require_user();
		if ( is_wp_error( $user ) ) {
			return $user;
		}

		if ( Floppy_Auth::is_device_auth() || self::is_application_password_auth() ) {
			return new WP_Error( 'floppy_browser_session_required', __( 'This action requires a browser-approved WordPress session.', 'floppy' ), array( 'status' => 403 ) );
		}

		return true;
	}

	/**
	 * Require an authenticated WordPress user who is not already using a Floppy device token.
	 */
	public static function require_device_authorization() {
		$user = self::require_user();
		if ( is_wp_error( $user ) ) {
			return $user;
		}

		if ( Floppy_Auth::is_device_auth() ) {
			return new WP_Error( 'floppy_browser_session_required', __( 'Device authorization requires a WordPress session or temporary Application Password.', 'floppy' ), array( 'status' => 403 ) );
		}

		return true;
	}

	/**
	 * Require a logged-in user and, for device tokens, a matching scope.
	 */
	private static function require_scope( string $scope ) {
		$user = self::require_user();
		if ( is_wp_error( $user ) ) {
			return $user;
		}

		if ( ! Floppy_Auth::current_device_can( $scope ) ) {
			return new WP_Error( 'floppy_scope_forbidden', __( 'The device token does not include the required Floppy scope.', 'floppy' ), array( 'status' => 403 ) );
		}

		return true;
	}

	/**
	 * Require admin.
	 */
	public static function require_admin() {
		if ( Floppy_Auth::is_device_auth() || self::is_application_password_auth() ) {
			return new WP_Error( 'floppy_browser_session_required', __( 'Administrator diagnostics require a browser session.', 'floppy' ), array( 'status' => 403 ) );
		}

		return current_user_can( 'manage_options' ) ? true : new WP_Error( 'floppy_rest_forbidden', __( 'Administrator access required.', 'floppy' ), array( 'status' => 403 ) );
	}

	/**
	 * Whether core authenticated this REST request with an Application Password.
	 */
	private static function is_application_password_auth(): bool {
		return function_exists( 'rest_get_authenticated_app_password' ) && (bool) rest_get_authenticated_app_password();
	}

	/**
	 * Collection args.
	 */
	private static function collection_args(): array {
		return array(
			'parent_id' => array( 'sanitize_callback' => 'absint', 'default' => 0 ),
			'after_id'  => array( 'sanitize_callback' => 'absint', 'default' => 0 ),
			'limit'     => array( 'sanitize_callback' => 'absint', 'default' => 50 ),
		);
	}

	/**
	 * Query child rows.
	 */
	private static function query_children( string $table, int $parent_id, int $after_id, int $limit, int $user_id ): array {
		global $wpdb;

		$sql = $parent_id
			? $wpdb->prepare( "SELECT * FROM $table WHERE parent_id = %d AND status = 'active' AND id > %d ORDER BY id ASC LIMIT %d", $parent_id, $after_id, $limit ) // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
			: $wpdb->prepare( "SELECT * FROM $table WHERE owner_id = %d AND parent_id = 0 AND status = 'active' AND id > %d ORDER BY id ASC LIMIT %d", $user_id, $after_id, $limit ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared

		return $wpdb->get_results( $sql, ARRAY_A );
	}

	/**
	 * Compare-and-swap metadata update.
	 */
	private static function update_file_metadata( int $id, WP_REST_Request $request, array $updates, string $event_type ) {
		global $wpdb;

		if ( ! Floppy_Permissions::can_write( 'file', $id ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot modify this file.', 'floppy' ), array( 'status' => 403 ) );
		}

		$row = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $row ) {
			return new WP_Error( 'floppy_file_not_found', __( 'File not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$known_version = (string) $request->get_param( 'metadata_version' );
		if ( $known_version && $known_version !== $row['metadata_version'] ) {
			return new WP_Error( 'floppy_conflict', __( 'The file changed on the server. Refresh before applying this change.', 'floppy' ), array( 'status' => 409, 'server' => self::serialize_file( $row ) ) );
		}

		if ( isset( $updates['name'] ) ) {
			$collision = self::name_collision( 'files', (int) $row['parent_id'], (string) $updates['name'], $id );
			if ( is_wp_error( $collision ) ) {
				return $collision;
			}
		}

		if ( isset( $updates['parent_id'] ) ) {
			$collision = self::name_collision( 'files', (int) $updates['parent_id'], (string) $row['name'], $id );
			if ( is_wp_error( $collision ) ) {
				return $collision;
			}
		}

		$audience = in_array( $event_type, array( 'file.deleted', 'file.trashed', 'file.restored' ), true )
			? Floppy_Permissions::audience_for( 'file', $id )
			: array();

		$updates['metadata_version'] = wp_generate_uuid4();
		$updates['updated_at_gmt'] = current_time( 'mysql', true );

		$formats = array();
		foreach ( $updates as $value ) {
			$formats[] = is_int( $value ) ? '%d' : '%s';
		}

		$wpdb->update( Floppy_Schema::table( 'files' ), $updates, array( 'id' => $id ), $formats, array( '%d' ) );
		$next = Floppy_Permissions::get_target_row( 'file', $id );
		$seq = Floppy_Sync::append_event( $event_type, 'file', $id, array_merge( $next, $audience ) );
		$next['last_sync_seq'] = $seq;

		Floppy_Audit::log( $event_type, 'file', $id );

		return new WP_REST_Response( self::serialize_file( $next ) + array( 'last_sync_seq' => $seq ) );
	}

	/**
	 * Prevent duplicate names inside a parent.
	 */
	private static function name_collision( string $table_name, int $parent_id, string $name, int $ignore_id = 0 ) {
		global $wpdb;

		$table = Floppy_Schema::table( $table_name );
		$normalized = Floppy_Storage::normalize_lookup_name( $name );
		$sql = $wpdb->prepare(
			"SELECT id FROM $table WHERE parent_id = %d AND normalized_name = %s AND status != 'deleted' AND id != %d LIMIT 1", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
			$parent_id,
			$normalized,
			$ignore_id
		);

		if ( $wpdb->get_var( $sql ) ) {
			return new WP_Error( 'floppy_name_collision', __( 'An item with that name already exists in this folder.', 'floppy' ), array( 'status' => 409 ) );
		}

		return true;
	}

	/**
	 * Create a Media Library attachment record for interoperability.
	 */
	private static function create_private_attachment( array $stored, int $user_id ) {
		$attachment_id = wp_insert_attachment(
			array(
				'post_author'    => $user_id,
				'post_title'     => preg_replace( '/\.[^.]+$/', '', $stored['name'] ),
				'post_content'   => '',
				'post_status'    => 'inherit',
				'post_mime_type' => $stored['mime_type'],
			),
			$stored['path']
		);

		if ( is_wp_error( $attachment_id ) ) {
			return $attachment_id;
		}

		update_post_meta( $attachment_id, '_floppy_private', '1' );
		update_post_meta( $attachment_id, '_floppy_storage_key', $stored['storage_key'] );
		update_post_meta( $attachment_id, '_floppy_canonical_download', rest_url( self::NAMESPACE . '/files' ) );

		return (int) $attachment_id;
	}

	/**
	 * Create a Floppy file row from an already-stored private blob.
	 */
	private static function create_file_row_from_stored( array $stored, int $user_id, int $parent_id ) {
		global $wpdb;

		$collision = self::name_collision( 'files', $parent_id, $stored['name'] );
		if ( is_wp_error( $collision ) ) {
			return $collision;
		}

		$attachment_id = self::create_private_attachment( $stored, $user_id );
		if ( is_wp_error( $attachment_id ) ) {
			return $attachment_id;
		}

		$now = current_time( 'mysql', true );
		$row = array(
			'uuid'             => $stored['uuid'],
			'attachment_id'    => $attachment_id,
			'owner_id'         => $user_id,
			'parent_id'        => $parent_id,
			'name'             => $stored['name'],
			'normalized_name'  => Floppy_Storage::normalize_lookup_name( $stored['name'] ),
			'mime_type'        => $stored['mime_type'],
			'size_bytes'       => (int) $stored['size_bytes'],
			'content_hash'     => $stored['content_hash'],
			'storage_key'      => $stored['storage_key'],
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
		Floppy_Sync::append_event( 'file.created', 'file', $row['id'], $row, $user_id );
		Floppy_Audit::log( 'file.uploaded', 'file', $row['id'], $stored['name'], array( 'size_bytes' => (int) $stored['size_bytes'] ), $user_id );

		return $row;
	}

	/**
	 * Fetch an upload session.
	 */
	private static function get_upload_session( string $uuid ) {
		global $wpdb;

		$row = $wpdb->get_row(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'upload_sessions' ) . ' WHERE session_uuid = %s LIMIT 1',
				$uuid
			),
			ARRAY_A
		);

		if ( ! $row ) {
			return new WP_Error( 'floppy_upload_session_not_found', __( 'Upload session not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		if ( 'open' !== $row['status'] ) {
			return new WP_Error( 'floppy_upload_session_closed', __( 'Upload session is not open.', 'floppy' ), array( 'status' => 409 ) );
		}

		if ( strtotime( $row['expires_at_gmt'] . ' GMT' ) < time() ) {
			return new WP_Error( 'floppy_upload_session_expired', __( 'Upload session expired.', 'floppy' ), array( 'status' => 410 ) );
		}

		return $row;
	}

	/**
	 * Serialize folder row.
	 */
	private static function serialize_folder( array $row ): array {
		return array(
			'kind'             => 'folder',
			'id'               => (int) $row['id'],
			'uuid'             => $row['uuid'],
			'owner_id'         => (int) $row['owner_id'],
			'parent_id'        => (int) $row['parent_id'],
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
	private static function serialize_file( array $row ): array {
		return array(
			'kind'             => 'file',
			'id'               => (int) $row['id'],
			'uuid'             => $row['uuid'],
			'attachment_id'    => (int) $row['attachment_id'],
			'owner_id'         => (int) $row['owner_id'],
			'parent_id'        => (int) $row['parent_id'],
			'name'             => $row['name'],
			'mime_type'        => $row['mime_type'],
			'size_bytes'       => (int) $row['size_bytes'],
			'content_hash'     => $row['content_hash'],
			'content_version'  => $row['content_version'],
			'metadata_version' => $row['metadata_version'],
			'status'           => $row['status'],
			'visibility'       => $row['visibility'],
			'download_url'     => rest_url( self::NAMESPACE . '/files/' . (int) $row['id'] . '/download' ),
			'created_at_gmt'   => $row['created_at_gmt'],
			'updated_at_gmt'   => $row['updated_at_gmt'],
		);
	}
}
