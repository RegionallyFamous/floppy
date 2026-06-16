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
		Floppy_Rest_Routes::register( self::NAMESPACE, __CLASS__ );
	}

	/**
	 * Public discovery.
	 */
	public static function discovery(): WP_REST_Response {
		$data = array(
			'name'         => 'Floppy',
			'namespace'    => self::NAMESPACE,
			'rest_url'     => esc_url_raw( rest_url( self::NAMESPACE ) ),
			'auth'         => array( 'browser_device_approval', 'device_code_exchange', 'wordpress_session', 'application_password_bootstrap' ),
			'desktop_mode' => function_exists( 'desktop_mode_register_window' ),
			'private'      => true,
		);

		if ( is_user_logged_in() ) {
			$data['version'] = FLOPPY_VERSION;
			$data['limits'] = array(
				'max_file_size'   => (int) Floppy_Settings::get_value( 'max_file_size', wp_max_upload_size() ),
				'max_batch_files' => (int) Floppy_Settings::get_value( 'max_batch_files', 50 ),
				'max_chunk_size'  => self::max_upload_chunk_bytes(),
			);
		}

		return new WP_REST_Response( $data );
	}

	/**
	 * Health endpoint.
	 */
	public static function health(): WP_REST_Response {
		return new WP_REST_Response(
			array_merge(
				Floppy_Compatibility::summary(),
				array( 'support' => Floppy_Diagnostics::support_block() )
			)
		);
	}

	/**
	 * Deep admin-only maintenance health.
	 */
	public static function deep_health(): WP_REST_Response {
		return new WP_REST_Response( Floppy_Diagnostics::deep_health() );
	}

	/**
	 * Admin-only repair dry run or execution.
	 */
	public static function maintenance_repair( WP_REST_Request $request ): WP_REST_Response {
		$apply = WP_REST_Server::CREATABLE === $request->get_method() && rest_sanitize_boolean( $request->get_param( 'apply' ) );
		$report = Floppy_Schema::repair( $apply );

		if ( $apply ) {
			Floppy_Audit::log( 'maintenance.repair_applied', 'maintenance', 0, '', array( 'support_id' => Floppy_Diagnostics::correlation_id() ) );
		}

		return new WP_REST_Response(
			array(
				'format'         => 'floppy-repair-report-v2',
				'support'        => Floppy_Diagnostics::support_block(),
				'apply'          => $apply,
				'report'         => $report,
			)
		);
	}

	/**
	 * Admin-only async doctor job enqueue/list endpoint.
	 */
	public static function maintenance_doctor_jobs( WP_REST_Request $request ) {
		if ( WP_REST_Server::CREATABLE === $request->get_method() ) {
			$apply = rest_sanitize_boolean( $request->get_param( 'apply' ) );
			$job = Floppy_Background_Jobs::enqueue(
				'doctor',
				array(
					'apply'      => $apply,
					'support_id' => Floppy_Diagnostics::correlation_id(),
				),
				2
			);
			if ( is_wp_error( $job ) ) {
				return $job;
			}

			Floppy_Audit::log( $apply ? 'maintenance.doctor_repair_queued' : 'maintenance.doctor_dry_run_queued', 'maintenance', (int) $job['id'], '', array( 'support_id' => Floppy_Diagnostics::correlation_id() ) );
			return new WP_REST_Response(
				array(
					'format'       => 'floppy-doctor-job-v1',
					'support'      => Floppy_Diagnostics::support_block(),
					'job_id'       => (int) $job['id'],
					'job_uuid'     => $job['job_uuid'],
					'status_url'   => rest_url( self::NAMESPACE . '/maintenance/doctor-jobs/' . $job['job_uuid'] ),
				),
				202
			);
		}

		return new WP_REST_Response(
			array(
				'format'  => 'floppy-doctor-jobs-v1',
				'support' => Floppy_Diagnostics::support_block(),
				'jobs'    => array_map( array( 'Floppy_Rest_Serializer', 'job' ), Floppy_Background_Jobs::latest_jobs( 'doctor', 10 ) ),
			)
		);
	}

	/**
	 * Admin-only async doctor job status endpoint.
	 */
	public static function maintenance_doctor_job_status( WP_REST_Request $request ) {
		$job = Floppy_Background_Jobs::get_job( sanitize_text_field( (string) $request['uuid'] ) );
		if ( is_wp_error( $job ) ) {
			return $job;
		}
		if ( 'doctor' !== (string) $job['job_type'] ) {
			return new WP_Error( 'floppy_job_not_found', __( 'Floppy job not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		return new WP_REST_Response(
			array(
				'format'  => 'floppy-doctor-job-v1',
				'support' => Floppy_Diagnostics::support_block(),
				'job'     => Floppy_Rest_Serializer::job( $job ),
			)
		);
	}

	/**
	 * Run a queued deep doctor job.
	 */
	public static function run_doctor_job( array $payload ): array {
		$apply = ! empty( $payload['apply'] );
		$report = Floppy_Schema::repair( $apply );
		$usage = Floppy_Schema::refresh_usage_counters();
		Floppy_Audit::log( $apply ? 'maintenance.doctor_repair_ran' : 'maintenance.doctor_dry_run_ran', 'maintenance', 0, '', array( 'support_id' => sanitize_text_field( (string) ( $payload['support_id'] ?? '' ) ) ) );

		return array(
			'ok'         => true,
			'format'     => 'floppy-doctor-result-v1',
			'apply'      => $apply,
			'report'     => $report,
			'usage'      => $usage,
			'completed_at_gmt' => current_time( 'mysql', true ),
		);
	}

	/**
	 * Admin-only redacted debug bundle.
	 */
	public static function debug_bundle(): WP_REST_Response {
		Floppy_Audit::log( 'maintenance.debug_bundle_downloaded', 'maintenance', 0, '', array( 'support_id' => Floppy_Diagnostics::correlation_id() ) );
		return new WP_REST_Response( Floppy_Diagnostics::debug_bundle() );
	}

	/**
	 * Admin-only public beta evidence summary.
	 */
	public static function release_evidence(): WP_REST_Response {
		Floppy_Audit::log( 'release_evidence.downloaded', 'maintenance', 0 );

		return new WP_REST_Response( Floppy_Diagnostics::release_evidence() );
	}

	/**
	 * Authenticated recovery center for restore, conflict, version, and export state.
	 */
	public static function recovery_center( WP_REST_Request $request ): WP_REST_Response {
		global $wpdb;

		$user_id = get_current_user_id();
		$limit   = max( 1, min( 100, absint( $request->get_param( 'limit' ) ?: 50 ) ) );

		$trash_items = self::query_recovery_items( 'trashed', $limit, $user_id );
		$recent_items = self::query_recent_items( $limit, $user_id );
		$version_rows = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'file_versions' ) . ' WHERE owner_id = %d ORDER BY id DESC LIMIT %d',
				$user_id,
				$limit
			),
			ARRAY_A
		);
		$conflict_rows = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'conflicts' ) . " WHERE owner_id = %d AND status = 'open' ORDER BY id ASC LIMIT %d",
				$user_id,
				$limit
			),
			ARRAY_A
		);
		$activity_rows = self::query_recovery_activity( $limit, $user_id );
		$export_jobs = self::query_current_user_export_jobs( $limit, $user_id );

		$response = array(
			'format'       => 'floppy-recovery-center-v1',
			'support'      => Floppy_Diagnostics::support_block(),
			'scope'        => array(
				'user_id'            => $user_id,
				'visibility'         => 'current-user-owned',
				'public_share_links' => false,
				'private_storage'    => 'mandatory-for-sync',
			),
			'recents'      => array(
				'items' => array_map( array( 'Floppy_Rest_Serializer', 'recovery_item' ), $recent_items ),
			),
			'trash'        => array(
				'items'  => array_map( array( 'Floppy_Rest_Serializer', 'recovery_item' ), $trash_items ),
				'counts' => self::trash_counts_for_user( $user_id ),
			),
			'versions'     => array(
				'items'   => array_map( array( 'Floppy_Rest_Serializer', 'version' ), $version_rows ),
				'summary' => Floppy_Diagnostics::version_recovery_summary(),
			),
			'conflicts'    => array(
				'items'   => array_map( array( 'Floppy_Rest_Serializer', 'conflict' ), $conflict_rows ),
				'summary' => array(
					'open' => count( $conflict_rows ),
				),
			),
			'activity'     => array(
				'events' => array_map( array( 'Floppy_Rest_Serializer', 'recovery_activity' ), $activity_rows ),
			),
			'exports'      => array(
				'latest' => array_map( array( 'Floppy_Rest_Serializer', 'job' ), $export_jobs ),
			),
			'quota'        => array(
				'reservations' => Floppy_Diagnostics::quota_reservation_summary( $user_id ),
			),
			'trust'        => array(
				'no_external_services'        => true,
				'preserve_local_bytes_first'  => true,
				'public_links_in_milestone'   => false,
				'version_restore_available'   => true,
				'trash_restore_available'     => true,
				'conflict_records_available'  => true,
				'export_restore_status_ready' => true,
			),
		);

		return new WP_REST_Response( $response );
	}

	/**
	 * List files and folders under a parent.
	 */
	public static function list_items( WP_REST_Request $request ) {
		global $wpdb;

		$user_id   = get_current_user_id();
		$parent_id = absint( $request->get_param( 'parent_id' ) );
		$after_id  = absint( $request->get_param( 'after_id' ) );
		$cursor    = sanitize_text_field( (string) $request->get_param( 'cursor' ) );
		$shared    = rest_sanitize_boolean( $request->get_param( 'shared' ) );
		$limit     = max( 1, min( 100, absint( $request->get_param( 'limit' ) ?: 50 ) ) );

		if ( $shared ) {
			return self::list_shared_items( $cursor, $after_id, $limit, $user_id );
		}

		if ( $parent_id && ! Floppy_Permissions::can_read( 'folder', $parent_id, $user_id ) ) {
			return self::not_found_or_forbidden( 'folder', $parent_id, 'read' );
		}

		$rows = self::query_children_page( $parent_id, $cursor, $after_id, $limit + 1, $user_id );
		$has_more = count( $rows ) > $limit;
		if ( $has_more ) {
			array_pop( $rows );
		}
		$items = array();
		$next_cursor = '';
		foreach ( $rows as $row ) {
			if ( 'folder' === $row['kind'] && Floppy_Permissions::can_read( 'folder', (int) $row['id'], $user_id ) ) {
				$items[] = Floppy_Rest_Serializer::folder( $row );
				$next_cursor = 'folder:' . (int) $row['id'];
			} elseif ( 'file' === $row['kind'] && Floppy_Permissions::can_read( 'file', (int) $row['id'], $user_id ) ) {
				$items[] = Floppy_Rest_Serializer::file( $row );
				$next_cursor = 'file:' . (int) $row['id'];
			}
		}

		return new WP_REST_Response(
			array(
				'parent_id'   => $parent_id,
				'limit'       => $limit,
				'cursor'      => $cursor,
				'next_cursor' => $next_cursor,
				'has_more'    => $has_more,
				'items'       => $items,
			)
		);
	}

	/**
	 * List directly shared files and folders for the current user.
	 */
	private static function list_shared_items( string $cursor, int $after_id, int $limit, int $user_id ): WP_REST_Response {
		global $wpdb;

		$user = get_userdata( $user_id );
		$roles = $user ? array_values( (array) $user->roles ) : array();
		$cursor_kind = '';
		$cursor_id = $after_id;
		if ( preg_match( '/^(folder|file):(\d+)$/', $cursor, $matches ) ) {
			$cursor_kind = $matches[1];
			$cursor_id = (int) $matches[2];
		}

		$folder_after = 'file' === $cursor_kind ? PHP_INT_MAX : $cursor_id;
		$file_after = 'folder' === $cursor_kind ? 0 : $cursor_id;
		$principals = array( array( 'user', (string) $user_id ) );
		foreach ( $roles as $role ) {
			$principals[] = array( 'role', (string) $role );
		}

		$grant_clauses = array();
		$grant_values = array();
		foreach ( $principals as $principal ) {
			$grant_clauses[] = '(g.principal_type = %s AND g.principal_ref = %s)';
			$grant_values[] = $principal[0];
			$grant_values[] = $principal[1];
		}
		$grant_sql = implode( ' OR ', $grant_clauses );

		$sql = $wpdb->prepare(
			"SELECT 'folder' AS kind, 0 AS kind_order, f.id, f.uuid, 0 AS attachment_id, f.owner_id, f.parent_id, f.name, f.normalized_name, '' AS mime_type, 0 AS size_bytes, '' AS content_hash, '' AS storage_key, '' AS content_version, f.metadata_version, f.status, 'private' AS visibility, f.created_at_gmt, f.updated_at_gmt FROM " . Floppy_Schema::table( 'acl_grants' ) . ' g INNER JOIN ' . Floppy_Schema::table( 'folders' ) . " f ON g.target_type = 'folder' AND g.target_id = f.id WHERE g.state = 'accepted' AND ($grant_sql) AND f.status = 'active' AND f.id > %d
			UNION ALL
			SELECT 'file' AS kind, 1 AS kind_order, f.id, f.uuid, f.attachment_id, f.owner_id, f.parent_id, f.name, f.normalized_name, f.mime_type, f.size_bytes, f.content_hash, f.storage_key, f.content_version, f.metadata_version, f.status, f.visibility, f.created_at_gmt, f.updated_at_gmt FROM " . Floppy_Schema::table( 'acl_grants' ) . ' g INNER JOIN ' . Floppy_Schema::table( 'files' ) . " f ON g.target_type = 'file' AND g.target_id = f.id WHERE g.state = 'accepted' AND ($grant_sql) AND f.status = 'active' AND f.id > %d
			ORDER BY kind_order ASC, id ASC LIMIT %d",
			array_merge( $grant_values, array( $folder_after ), $grant_values, array( $file_after, $limit + 1 ) )
		); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared

		$rows = $wpdb->get_results( $sql, ARRAY_A );
		$has_more = count( $rows ) > $limit;
		if ( $has_more ) {
			array_pop( $rows );
		}

		$items = array();
		$next_cursor = '';
		foreach ( $rows as $row ) {
			if ( 'folder' === $row['kind'] && Floppy_Permissions::can_read( 'folder', (int) $row['id'], $user_id ) ) {
				$items[] = Floppy_Rest_Serializer::folder( $row );
				$next_cursor = 'folder:' . (int) $row['id'];
			} elseif ( 'file' === $row['kind'] && Floppy_Permissions::can_read( 'file', (int) $row['id'], $user_id ) ) {
				$items[] = Floppy_Rest_Serializer::file( $row );
				$next_cursor = 'file:' . (int) $row['id'];
			}
		}

		return new WP_REST_Response(
			array(
				'parent_id'   => 0,
				'shared'      => true,
				'limit'       => $limit,
				'cursor'      => $cursor,
				'next_cursor' => $next_cursor,
				'has_more'    => $has_more,
				'items'       => $items,
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
			return self::not_found_or_forbidden( 'folder', $parent_id, 'write' );
		}

		$collision = self::item_name_collision( $parent_id, $name );
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

		$reserved = self::sync_item_name_reservation( 'folder', $row['id'], $row );
		if ( is_wp_error( $reserved ) ) {
			$wpdb->delete( Floppy_Schema::table( 'folders' ), array( 'id' => $row['id'] ), array( '%d' ) );
			return $reserved;
		}

		Floppy_Sync::append_event( 'folder.created', 'folder', $row['id'], $row, $user_id );
		Floppy_Audit::log( 'folder.created', 'folder', $row['id'], $name );
		Floppy_Schema::refresh_usage_counters();

		return new WP_REST_Response( Floppy_Rest_Serializer::folder( $row ), 201 );
	}

	/**
	 * Rename a folder.
	 */
	public static function folder_rename( WP_REST_Request $request ) {
		$id = absint( $request['id'] );
		$name = Floppy_Storage::normalize_filename( (string) $request->get_param( 'name' ) );

		return self::update_folder_metadata( $id, $request, array( 'name' => $name, 'normalized_name' => Floppy_Storage::normalize_lookup_name( $name ) ), 'folder.renamed' );
	}

	/**
	 * Move a folder.
	 */
	public static function folder_move( WP_REST_Request $request ) {
		$id = absint( $request['id'] );
		$parent_id = absint( $request->get_param( 'parent_id' ) );

		if ( $parent_id === $id || self::folder_is_descendant( $parent_id, $id ) ) {
			return new WP_Error( 'floppy_invalid_folder_move', __( 'A folder cannot be moved into itself or one of its descendants.', 'floppy' ), array( 'status' => 409 ) );
		}

		if ( $parent_id && ! Floppy_Permissions::can_write( 'folder', $parent_id ) ) {
			return self::not_found_or_forbidden( 'folder', $parent_id, 'write' );
		}

		return self::update_folder_metadata( $id, $request, array( 'parent_id' => $parent_id ), 'folder.moved' );
	}

	/**
	 * Trash a folder and visible descendants.
	 */
	public static function folder_trash( WP_REST_Request $request ) {
		return self::update_folder_tree_status( absint( $request['id'] ), $request, 'trashed', 'folder.trashed' );
	}

	/**
	 * Restore a folder and descendants.
	 */
	public static function folder_restore( WP_REST_Request $request ) {
		return self::update_folder_tree_status( absint( $request['id'] ), $request, 'active', 'folder.restored' );
	}

	/**
	 * Delete a folder and tombstone descendants.
	 */
	public static function delete_folder( WP_REST_Request $request ) {
		return self::update_folder_tree_status( absint( $request['id'] ), $request, 'deleted', 'folder.deleted' );
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

		$normalized = Floppy_Storage::normalize_lookup_name( $q );
		$like = $wpdb->esc_like( $normalized ) . '%';
		$folder_access = self::search_access_condition( 'folder', $user_id );
		$file_access = self::search_access_condition( 'file', $user_id );
		$folders = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT f.* FROM ' . Floppy_Schema::table( 'folders' ) . " f WHERE f.status = 'active' AND f.normalized_name LIKE %s" . $folder_access['sql'] . ' ORDER BY f.updated_at_gmt DESC, f.id DESC LIMIT %d',
				array_merge( array( $like ), $folder_access['values'], array( $limit ) )
			),
			ARRAY_A
		); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
		$files = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT f.* FROM ' . Floppy_Schema::table( 'files' ) . " f WHERE f.status = 'active' AND f.normalized_name LIKE %s" . $file_access['sql'] . ' ORDER BY f.updated_at_gmt DESC, f.id DESC LIMIT %d',
				array_merge( array( $like ), $file_access['values'], array( $limit ) )
			),
			ARRAY_A
		); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared

		$items = array();
		foreach ( $folders as $row ) {
			if ( Floppy_Permissions::can_read( 'folder', (int) $row['id'], $user_id ) ) {
				$items[] = Floppy_Rest_Serializer::folder( $row );
			}
		}
		foreach ( $files as $row ) {
			if ( Floppy_Permissions::can_read( 'file', (int) $row['id'], $user_id ) ) {
				$items[] = Floppy_Rest_Serializer::file( $row );
			}
		}

		return new WP_REST_Response(
			array(
				'items'      => array_slice( $items, 0, $limit ),
				'query_mode' => 'prefix',
			)
		);
	}

	/**
	 * SQL fragment limiting search candidates to the current user's own or directly shared rows.
	 */
	private static function search_access_condition( string $target_type, int $user_id ): array {
		if ( user_can( $user_id, 'manage_options' ) ) {
			return array( 'sql' => '', 'values' => array() );
		}

		if ( ! $user_id ) {
			return array( 'sql' => ' AND 1 = 0', 'values' => array() );
		}

		$user = get_userdata( $user_id );
		$principals = array( array( 'user', (string) $user_id ) );
		if ( $user ) {
			foreach ( (array) $user->roles as $role ) {
				$principals[] = array( 'role', (string) $role );
			}
		}

		$grant_clauses = array();
		$grant_values = array();
		foreach ( $principals as $principal ) {
			$grant_clauses[] = '(g.principal_type = %s AND g.principal_ref = %s)';
			$grant_values[] = $principal[0];
			$grant_values[] = $principal[1];
		}

		return array(
			'sql'    => ' AND (f.owner_id = %d OR EXISTS (SELECT 1 FROM ' . Floppy_Schema::table( 'acl_grants' ) . " g WHERE g.target_type = %s AND g.target_id = f.id AND g.state = 'accepted' AND g.capability IN ('read','write') AND (" . implode( ' OR ', $grant_clauses ) . ')))',
			'values' => array_merge( array( $user_id, $target_type ), $grant_values ),
		);
	}

	/**
	 * Fetch one visible item by stable UUID.
	 */
	public static function get_item_by_uuid( WP_REST_Request $request ) {
		global $wpdb;

		$uuid = sanitize_text_field( (string) $request['uuid'] );
		$folder = $wpdb->get_row(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'folders' ) . ' WHERE uuid = %s LIMIT 1',
				$uuid
			),
			ARRAY_A
		);
		if ( $folder ) {
			return Floppy_Permissions::can_read( 'folder', (int) $folder['id'] )
				? new WP_REST_Response( Floppy_Rest_Serializer::folder( $folder ) )
				: self::not_found_or_forbidden( 'folder', (int) $folder['id'], 'read' );
		}

		$file = $wpdb->get_row(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'files' ) . ' WHERE uuid = %s LIMIT 1',
				$uuid
			),
			ARRAY_A
		);
		if ( $file ) {
			return Floppy_Permissions::can_read( 'file', (int) $file['id'] )
				? new WP_REST_Response( Floppy_Rest_Serializer::file( $file ) )
				: self::not_found_or_forbidden( 'file', (int) $file['id'], 'read' );
		}

		return new WP_Error( 'floppy_item_not_found', __( 'Floppy item not found.', 'floppy' ), array( 'status' => 404 ) );
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

		if ( ! current_user_can( Floppy_Permissions::CAP_WRITE ) && ! current_user_can( Floppy_Permissions::CAP_MANAGE ) ) {
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

		$max_batch = (int) Floppy_Settings::get_value( 'max_batch_files', 50 );
		if ( count( $files ) > $max_batch ) {
			return new WP_Error( 'floppy_upload_batch_too_large', __( 'This upload batch is larger than the Floppy batch limit.', 'floppy' ), array( 'status' => 413 ) );
		}

		$quota = self::check_quota( $user_id, (int) ( $file['size'] ?? 0 ) );
		if ( is_wp_error( $quota ) ) {
			return $quota;
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

		$collision = self::item_name_collision( $parent_id, $stored['name'] );
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

		$reserved = self::sync_item_name_reservation( 'file', $row['id'], $row );
		if ( is_wp_error( $reserved ) ) {
			$wpdb->delete( Floppy_Schema::table( 'files' ), array( 'id' => $row['id'] ), array( '%d' ) );
			if ( $attachment_id ) {
				wp_delete_attachment( $attachment_id, true );
			}
			@unlink( $stored['path'] ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			return $reserved;
		}

		Floppy_Sync::append_event( 'file.created', 'file', $row['id'], $row, $user_id );
		Floppy_Audit::log( 'file.uploaded', 'file', $row['id'], $stored['name'], array( 'size_bytes' => $stored['size_bytes'] ) );
		Floppy_Schema::refresh_usage_counters();

		return new WP_REST_Response( Floppy_Rest_Serializer::file( $row ), 201 );
	}

	/**
	 * Create a resumable replacement upload session for an existing file.
	 */
	public static function create_replace_session( WP_REST_Request $request ) {
		global $wpdb;

		$user_id = get_current_user_id();
		$rate = Floppy_Rate_Limiter::check( 'upload-session', 300, HOUR_IN_SECONDS, 'user:' . $user_id );
		if ( is_wp_error( $rate ) ) {
			return $rate;
		}

		$private_mode = Floppy_Storage::require_private_mode();
		if ( is_wp_error( $private_mode ) ) {
			return $private_mode;
		}

		$id = absint( $request['id'] );
		if ( ! Floppy_Permissions::can_write( 'file', $id, $user_id ) ) {
			return self::not_found_or_forbidden( 'file', $id, 'write' );
		}

		$row = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $row || 'active' !== $row['status'] ) {
			return new WP_Error( 'floppy_file_not_found', __( 'File not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$known_version = (string) $request->get_param( 'content_version' );
		if ( '' === $known_version ) {
			return new WP_Error( 'floppy_content_version_required', __( 'A content version is required to replace file contents.', 'floppy' ), array( 'status' => 428, 'server' => Floppy_Rest_Serializer::file( $row ) ) );
		}
		if ( $known_version !== $row['content_version'] ) {
			return new WP_Error( 'floppy_conflict', __( 'The file contents changed on the server. Refresh before applying this change.', 'floppy' ), array( 'status' => 409, 'server' => Floppy_Rest_Serializer::file( $row ) ) );
		}

		$total_size_param = $request->get_param( 'total_size' );
		$total_size = is_numeric( $total_size_param ) ? (int) $total_size_param : -1;
		$max = (int) Floppy_Settings::get_value( 'max_file_size', wp_max_upload_size() );
		if ( $total_size < 0 || $total_size > $max ) {
			return new WP_Error( 'floppy_invalid_upload_size', __( 'Invalid upload size.', 'floppy' ), array( 'status' => 413 ) );
		}

		$quota_delta = max( 0, $total_size - (int) $row['size_bytes'] );
		$quota = self::check_quota( $user_id, $quota_delta );
		if ( is_wp_error( $quota ) ) {
			return $quota;
		}

		$content_hash = strtolower( sanitize_text_field( (string) $request->get_param( 'content_hash' ) ) );
		if ( '' !== $content_hash && ! preg_match( '/^[a-f0-9]{64}$/', $content_hash ) ) {
			return new WP_Error( 'floppy_invalid_content_hash', __( 'Upload content_hash must be a SHA-256 hex digest.', 'floppy' ), array( 'status' => 400 ) );
		}

		$uuid = wp_generate_uuid4();
		$storage_key = 'chunks/' . Floppy_Storage::storage_key( $uuid, 'part' );
		$path = Floppy_Storage::path_for_key( $storage_key );
		if ( ! wp_mkdir_p( dirname( $path ) ) || ! touch( $path ) ) {
			return new WP_Error( 'floppy_storage_unwritable', __( 'Floppy could not create an upload chunk file.', 'floppy' ), array( 'status' => 500 ) );
		}
		@chmod( $path, 0640 ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged

		$now = current_time( 'mysql', true );
		$wpdb->insert(
			Floppy_Schema::table( 'upload_sessions' ),
			array(
				'session_uuid'        => $uuid,
				'user_id'             => $user_id,
				'parent_id'           => (int) $row['parent_id'],
				'filename'            => $row['name'],
				'total_size'          => $total_size,
				'received_bytes'      => 0,
				'content_hash'        => $content_hash,
				'mime_type'           => sanitize_mime_type( (string) $request->get_param( 'mime_type' ) ),
				'storage_key'         => $storage_key,
				'operation'           => 'replace',
				'target_file_id'      => $id,
				'base_content_version' => $known_version,
				'reserved_bytes'      => $quota_delta,
				'quota_delta_bytes'   => $quota_delta,
				'reservation_expires_at_gmt' => gmdate( 'Y-m-d H:i:s', time() + DAY_IN_SECONDS ),
				'status'              => 'open',
				'expires_at_gmt'      => gmdate( 'Y-m-d H:i:s', time() + DAY_IN_SECONDS ),
				'created_at_gmt'      => $now,
				'updated_at_gmt'      => $now,
			),
			array( '%s', '%d', '%d', '%s', '%d', '%d', '%s', '%s', '%s', '%s', '%d', '%s', '%d', '%d', '%s', '%s', '%s', '%s', '%s' )
		);

		Floppy_Schema::refresh_usage_counters();

		Floppy_Audit::log( 'upload_session.created', 'file', $id, $row['name'], array( 'operation' => 'replace', 'size_bytes' => $total_size ) );

		return new WP_REST_Response(
			array(
				'session_uuid'   => $uuid,
				'received_bytes' => 0,
				'chunk_size'     => self::max_upload_chunk_bytes(),
				'operation'      => 'replace',
				'target_file_id' => $id,
				'expires_at_gmt' => gmdate( 'Y-m-d H:i:s', time() + DAY_IN_SECONDS ),
			),
			201
		);
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

		if ( ! current_user_can( Floppy_Permissions::CAP_WRITE ) && ! current_user_can( Floppy_Permissions::CAP_MANAGE ) ) {
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
		$total_size_param = $request->get_param( 'total_size' );
		$total_size = is_numeric( $total_size_param ) ? (int) $total_size_param : -1;
		$max = (int) Floppy_Settings::get_value( 'max_file_size', wp_max_upload_size() );
		if ( $total_size < 0 || $total_size > $max ) {
			return new WP_Error( 'floppy_invalid_upload_size', __( 'Invalid upload size.', 'floppy' ), array( 'status' => 413 ) );
		}
		$quota = self::check_quota( $user_id, $total_size );
		if ( is_wp_error( $quota ) ) {
			return $quota;
		}
		if ( Floppy_Storage::has_dangerous_extension( $filename ) ) {
			return new WP_Error( 'floppy_dangerous_file_type', __( 'This file type is not allowed in private storage.', 'floppy' ), array( 'status' => 415 ) );
		}

		$content_hash = strtolower( sanitize_text_field( (string) $request->get_param( 'content_hash' ) ) );
		if ( '' !== $content_hash && ! preg_match( '/^[a-f0-9]{64}$/', $content_hash ) ) {
			return new WP_Error( 'floppy_invalid_content_hash', __( 'Upload content_hash must be a SHA-256 hex digest.', 'floppy' ), array( 'status' => 400 ) );
		}
		$mime_type = sanitize_mime_type( (string) $request->get_param( 'mime_type' ) );

		$uuid = wp_generate_uuid4();
		$storage_key = 'chunks/' . Floppy_Storage::storage_key( $uuid, 'part' );
		$path = Floppy_Storage::path_for_key( $storage_key );
		if ( ! wp_mkdir_p( dirname( $path ) ) ) {
			return new WP_Error( 'floppy_storage_unwritable', __( 'Floppy could not create a chunk storage shard.', 'floppy' ), array( 'status' => 500 ) );
		}
		if ( ! touch( $path ) ) {
			return new WP_Error( 'floppy_storage_unwritable', __( 'Floppy could not create an upload chunk file.', 'floppy' ), array( 'status' => 500 ) );
		}
		@chmod( $path, 0640 ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged

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
				'content_hash'   => $content_hash,
				'mime_type'      => $mime_type,
				'storage_key'    => $storage_key,
				'operation'      => 'create',
				'target_file_id' => 0,
				'base_content_version' => '',
				'reserved_bytes' => $total_size,
				'quota_delta_bytes' => $total_size,
				'reservation_expires_at_gmt' => gmdate( 'Y-m-d H:i:s', time() + DAY_IN_SECONDS ),
				'status'         => 'open',
				'expires_at_gmt' => gmdate( 'Y-m-d H:i:s', time() + DAY_IN_SECONDS ),
				'created_at_gmt' => $now,
				'updated_at_gmt' => $now,
			),
			array( '%s', '%d', '%d', '%s', '%d', '%d', '%s', '%s', '%s', '%s', '%d', '%s', '%d', '%d', '%s', '%s', '%s', '%s', '%s' )
		);

		Floppy_Schema::refresh_usage_counters();

		Floppy_Audit::log( 'upload_session.created', 'upload_session', (int) $wpdb->insert_id, $filename, array( 'size_bytes' => $total_size ) );

		return new WP_REST_Response(
			array(
				'session_uuid'   => $uuid,
				'received_bytes' => 0,
				'chunk_size'     => self::max_upload_chunk_bytes(),
				'operation'      => 'create',
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

		$max_chunk = self::max_upload_chunk_bytes();
		$content_length = isset( $_SERVER['CONTENT_LENGTH'] ) ? absint( wp_unslash( $_SERVER['CONTENT_LENGTH'] ) ) : 0; // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized
		if ( $content_length > $max_chunk ) {
			return new WP_Error( 'floppy_chunk_too_large', __( 'This upload chunk is larger than the Floppy chunk limit.', 'floppy' ), array( 'status' => 413, 'max_chunk_size' => $max_chunk ) );
		}

		$body = file_get_contents( 'php://input' ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_get_contents_file_get_contents
		if ( false === $body || '' === $body ) {
			return new WP_Error( 'floppy_empty_chunk', __( 'Chunk body is empty.', 'floppy' ), array( 'status' => 400 ) );
		}

		$length = strlen( $body );
		if ( $length > $max_chunk ) {
			return new WP_Error( 'floppy_chunk_too_large', __( 'This upload chunk is larger than the Floppy chunk limit.', 'floppy' ), array( 'status' => 413, 'max_chunk_size' => $max_chunk ) );
		}
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

		if ( 'replace' !== (string) ( $session['operation'] ?? 'create' ) && empty( $session['reserved_bytes'] ) ) {
			$quota = self::check_quota( (int) $session['user_id'], (int) $session['total_size'] );
			if ( is_wp_error( $quota ) ) {
				return $quota;
			}
		}

		$final_uuid = wp_generate_uuid4();
		$ext = pathinfo( $session['filename'], PATHINFO_EXTENSION );
		$final_key = Floppy_Storage::storage_key( $final_uuid, $ext );
		$final_path = Floppy_Storage::path_for_key( $final_key );
		if ( ! wp_mkdir_p( dirname( $final_path ) ) || ! rename( $tmp_path, $final_path ) ) {
			return new WP_Error( 'floppy_upload_finalize_failed', __( 'Could not finalize upload.', 'floppy' ), array( 'status' => 500 ) );
		}
		@chmod( $final_path, 0640 ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged

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

		$scan = apply_filters( 'floppy_validate_private_upload', true, $stored, $request );
		if ( is_wp_error( $scan ) ) {
			@unlink( $final_path ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			return $scan;
		}

		if ( 'replace' === (string) ( $session['operation'] ?? 'create' ) ) {
			return self::complete_replace_session( $session, $stored );
		}

		$row = self::create_file_row_from_stored( $stored, (int) $session['user_id'], (int) $session['parent_id'] );
		if ( is_wp_error( $row ) ) {
			@unlink( $final_path ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			return $row;
		}

		$wpdb->update(
			Floppy_Schema::table( 'upload_sessions' ),
			array(
				'status'         => 'complete',
				'reserved_bytes' => 0,
				'updated_at_gmt' => current_time( 'mysql', true ),
			),
			array( 'id' => (int) $session['id'] ),
			array( '%s', '%d', '%s' ),
			array( '%d' )
		);

		Floppy_Schema::refresh_usage_counters();

		return new WP_REST_Response( Floppy_Rest_Serializer::file( $row ), 201 );
	}

	/**
	 * Complete a resumable replacement session using content-version CAS.
	 */
	private static function complete_replace_session( array $session, array $stored ) {
		global $wpdb;

		$id = (int) ( $session['target_file_id'] ?? 0 );
		$user_id = (int) $session['user_id'];
		if ( $id <= 0 || ! Floppy_Permissions::can_write( 'file', $id, $user_id ) ) {
			@unlink( $stored['path'] ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			return new WP_Error( 'floppy_file_not_found', __( 'File not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$row = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $row || 'active' !== $row['status'] ) {
			@unlink( $stored['path'] ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			return new WP_Error( 'floppy_file_not_found', __( 'File not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$known_version = (string) ( $session['base_content_version'] ?? '' );
		if ( '' === $known_version || $known_version !== $row['content_version'] ) {
			@unlink( $stored['path'] ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			$wpdb->update(
				Floppy_Schema::table( 'upload_sessions' ),
				array(
					'status'         => 'failed',
					'updated_at_gmt' => current_time( 'mysql', true ),
				),
				array( 'id' => (int) $session['id'] ),
				array( '%s', '%s' ),
				array( '%d' )
			);
			return new WP_Error( 'floppy_conflict', __( 'The file contents changed while this replacement was uploading.', 'floppy' ), array( 'status' => 409, 'server' => Floppy_Rest_Serializer::file( $row ) ) );
		}

		$quota_delta = max( 0, (int) $stored['size_bytes'] - (int) $row['size_bytes'] );
		if ( empty( $session['reserved_bytes'] ) ) {
			$quota = self::check_quota( $user_id, $quota_delta );
			if ( is_wp_error( $quota ) ) {
				@unlink( $stored['path'] ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
				return $quota;
			}
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
			return new WP_Error( 'floppy_conflict', __( 'The file contents changed while this replacement was uploading.', 'floppy' ), array( 'status' => 409, 'server' => $server ? Floppy_Rest_Serializer::file( $server ) : null ) );
		}

		$version_id = self::record_file_version( $row, $user_id, 'replace_session' );

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
		if ( ! $version_id && $old_path !== $stored['path'] && file_exists( $old_path ) ) {
			@unlink( $old_path ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
		}

		$wpdb->update(
			Floppy_Schema::table( 'upload_sessions' ),
			array(
				'status'         => 'complete',
				'reserved_bytes' => 0,
				'updated_at_gmt' => current_time( 'mysql', true ),
			),
			array( 'id' => (int) $session['id'] ),
			array( '%s', '%d', '%s' ),
			array( '%d' )
		);

		Floppy_Schema::refresh_usage_counters();

		Floppy_Audit::log( 'file.content_updated', 'file', $id, $row['name'], array( 'operation' => 'replace_session', 'size_bytes' => (int) $stored['size_bytes'] ), $user_id );

		return new WP_REST_Response( Floppy_Rest_Serializer::file( $next ) + array( 'last_sync_seq' => $seq ) );
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

		if ( ! current_user_can( Floppy_Permissions::CAP_WRITE ) && ! current_user_can( Floppy_Permissions::CAP_MANAGE ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot upload files.', 'floppy' ), array( 'status' => 403 ) );
		}

		$private_mode = Floppy_Storage::require_private_mode();
		if ( is_wp_error( $private_mode ) ) {
			return $private_mode;
		}

		if ( ! Floppy_Permissions::can_write( 'file', $id, $user_id ) ) {
			return self::not_found_or_forbidden( 'file', $id, 'write' );
		}

		$row = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $row || 'active' !== $row['status'] ) {
			return new WP_Error( 'floppy_file_not_found', __( 'File not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$known_version = (string) $request->get_param( 'content_version' );
		if ( '' === $known_version ) {
			return new WP_Error( 'floppy_content_version_required', __( 'A content version is required to replace file contents.', 'floppy' ), array( 'status' => 428, 'server' => Floppy_Rest_Serializer::file( $row ) ) );
		}

		if ( $known_version !== $row['content_version'] ) {
			return new WP_Error( 'floppy_conflict', __( 'The file contents changed on the server. Refresh before applying this change.', 'floppy' ), array( 'status' => 409, 'server' => Floppy_Rest_Serializer::file( $row ) ) );
		}

		$files = $request->get_file_params();
		$file  = $files['file'] ?? null;
		if ( ! is_array( $file ) ) {
			return new WP_Error( 'floppy_missing_file', __( 'Upload a file using the "file" field.', 'floppy' ), array( 'status' => 400 ) );
		}

		$quota_delta = max( 0, (int) ( $file['size'] ?? 0 ) - (int) $row['size_bytes'] );
		$quota = self::check_quota( $user_id, $quota_delta );
		if ( is_wp_error( $quota ) ) {
			return $quota;
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
			return new WP_Error( 'floppy_conflict', __( 'The file contents changed while this replacement was uploading.', 'floppy' ), array( 'status' => 409, 'server' => $server ? Floppy_Rest_Serializer::file( $server ) : null ) );
		}

		$version_id = self::record_file_version( $row, $user_id, 'multipart_replace' );

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
		if ( ! $version_id && $old_path !== $stored['path'] && file_exists( $old_path ) ) {
			@unlink( $old_path ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
		}

		Floppy_Audit::log( 'file.content_updated', 'file', $id, $row['name'], array( 'size_bytes' => (int) $stored['size_bytes'] ), $user_id );
		Floppy_Schema::refresh_usage_counters();

		return new WP_REST_Response( Floppy_Rest_Serializer::file( $next ) + array( 'last_sync_seq' => $seq ) );
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
			return self::not_found_or_forbidden( 'folder', $parent_id, 'write' );
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
		return Floppy_Rest_Streaming::file( absint( $request['id'] ), false );
	}

	/**
	 * Stream a preview inline.
	 */
	public static function preview_file( WP_REST_Request $request ) {
		return Floppy_Rest_Streaming::file( absint( $request['id'] ), true );
	}

	/**
	 * Download a retained file version through authenticated private storage.
	 */
	public static function download_file_version( WP_REST_Request $request ) {
		return Floppy_Rest_Streaming::version( absint( $request['id'] ), absint( $request['version_id'] ) );
	}

	/**
	 * List retained content versions for a file.
	 */
	public static function list_file_versions( WP_REST_Request $request ): WP_REST_Response {
		global $wpdb;

		$id = absint( $request['id'] );
		if ( ! Floppy_Permissions::can_read( 'file', $id ) ) {
			return self::not_found_or_forbidden( 'file', $id, 'read' );
		}

		$limit = max( 1, min( 100, absint( $request->get_param( 'limit' ) ?: 50 ) ) );
		$after_id = absint( $request->get_param( 'after_id' ) );
		$after_sql = $after_id ? $wpdb->prepare( ' AND id < %d', $after_id ) : '';
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'file_versions' ) . " WHERE file_id = %d $after_sql ORDER BY id DESC LIMIT %d", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
				$id,
				$limit + 1
			),
			ARRAY_A
		);
		$has_more = count( $rows ) > $limit;
		if ( $has_more ) {
			array_pop( $rows );
		}

		$last_row = $rows ? end( $rows ) : null;
		$versions = array_map( array( 'Floppy_Rest_Serializer', 'version' ), $rows );
		return new WP_REST_Response(
			array(
				'versions'    => $versions,
				'has_more'    => $has_more,
				'next_cursor' => $has_more && is_array( $last_row ) ? (int) $last_row['id'] : 0,
			)
		);
	}

	/**
	 * Restore one retained file version.
	 */
	public static function restore_file_version( WP_REST_Request $request ) {
		global $wpdb;

		$id = absint( $request['id'] );
		$version_id = absint( $request['version_id'] );
		$user_id = get_current_user_id();
		if ( ! Floppy_Permissions::can_write( 'file', $id, $user_id ) ) {
			return self::not_found_or_forbidden( 'file', $id, 'write' );
		}

		$row = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $row || 'active' !== $row['status'] ) {
			return new WP_Error( 'floppy_file_not_found', __( 'File not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$known_version = (string) $request->get_param( 'content_version' );
		if ( '' === $known_version ) {
			return new WP_Error( 'floppy_content_version_required', __( 'A content version is required to restore file contents.', 'floppy' ), array( 'status' => 428, 'server' => Floppy_Rest_Serializer::file( $row ) ) );
		}
		if ( $known_version !== $row['content_version'] ) {
			return new WP_Error( 'floppy_conflict', __( 'The file contents changed on the server. Refresh before restoring this version.', 'floppy' ), array( 'status' => 409, 'server' => Floppy_Rest_Serializer::file( $row ) ) );
		}

		$version = $wpdb->get_row(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'file_versions' ) . ' WHERE id = %d AND file_id = %d LIMIT 1',
				$version_id,
				$id
			),
			ARRAY_A
		);
		if ( ! $version ) {
			return new WP_Error( 'floppy_version_not_found', __( 'File version not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$restore_path = Floppy_Storage::path_for_key( (string) $version['storage_key'] );
		if ( ! is_readable( $restore_path ) ) {
			return new WP_Error( 'floppy_version_blob_missing', __( 'The retained version blob is missing from private storage.', 'floppy' ), array( 'status' => 500 ) );
		}

		$next_content_version = wp_generate_uuid4();
		$updated_at = current_time( 'mysql', true );
		$updated = $wpdb->query(
			$wpdb->prepare(
				'UPDATE ' . Floppy_Schema::table( 'files' ) . ' SET mime_type = %s, size_bytes = %d, content_hash = %s, storage_key = %s, content_version = %s, updated_at_gmt = %s WHERE id = %d AND content_version = %s',
				(string) $version['mime_type'],
				(int) $version['size_bytes'],
				(string) $version['content_hash'],
				(string) $version['storage_key'],
				$next_content_version,
				$updated_at,
				$id,
				$known_version
			)
		);
		if ( 1 !== $updated ) {
			$server = Floppy_Permissions::get_target_row( 'file', $id );
			return new WP_Error( 'floppy_conflict', __( 'The file contents changed while this version was being restored.', 'floppy' ), array( 'status' => 409, 'server' => $server ? Floppy_Rest_Serializer::file( $server ) : null ) );
		}

		self::record_file_version( $row, $user_id, 'restore_current', false );

		if ( ! empty( $row['attachment_id'] ) ) {
			wp_update_post(
				array(
					'ID'             => (int) $row['attachment_id'],
					'post_mime_type' => (string) $version['mime_type'],
				)
			);
			update_attached_file( (int) $row['attachment_id'], $restore_path );
			update_post_meta( (int) $row['attachment_id'], '_floppy_storage_key', (string) $version['storage_key'] );
		}

		self::prune_file_versions( $id, array( $version_id ) );
		$next = Floppy_Permissions::get_target_row( 'file', $id );
		$seq = Floppy_Sync::append_event( 'file.version_restored', 'file', $id, $next ?: array(), $user_id );
		$next['last_sync_seq'] = $seq;
		Floppy_Audit::log( 'file.version_restored', 'file', $id, $row['name'], array( 'version_id' => $version_id ), $user_id );
		Floppy_Schema::refresh_usage_counters();

		return new WP_REST_Response( Floppy_Rest_Serializer::file( $next ) + array( 'last_sync_seq' => $seq ) );
	}

	/**
	 * List conflict records visible to the current user.
	 */
	public static function list_conflicts( WP_REST_Request $request ): WP_REST_Response {
		global $wpdb;

		$user_id = get_current_user_id();
		$status = sanitize_key( (string) ( $request->get_param( 'status' ) ?: 'open' ) );
		$limit = max( 1, min( 100, absint( $request->get_param( 'limit' ) ?: 50 ) ) );
		$after_id = absint( $request->get_param( 'after_id' ) ?: $request->get_param( 'cursor' ) );
		$after_sql = $after_id ? $wpdb->prepare( ' AND id > %d', $after_id ) : '';
		$status_sql = 'all' === $status ? '' : $wpdb->prepare( ' AND status = %s', $status );
		$rows = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'conflicts' ) . " WHERE owner_id = %d $status_sql $after_sql ORDER BY id ASC LIMIT %d", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
				$user_id,
				$limit + 1
			),
			ARRAY_A
		);
		$has_more = count( $rows ) > $limit;
		if ( $has_more ) {
			array_pop( $rows );
		}

		$last_row = $rows ? end( $rows ) : null;
		return new WP_REST_Response(
			array(
				'conflicts'   => array_map( array( 'Floppy_Rest_Serializer', 'conflict' ), $rows ),
				'has_more'    => $has_more,
				'next_cursor' => $has_more && is_array( $last_row ) ? (int) $last_row['id'] : 0,
			)
		);
	}

	/**
	 * Record a client-visible conflict without uploading private local bytes.
	 */
	public static function record_conflict( WP_REST_Request $request ) {
		global $wpdb;

		$file_id = absint( $request->get_param( 'file_id' ) );
		$user_id = get_current_user_id();
		if ( $file_id && ! Floppy_Permissions::can_write( 'file', $file_id, $user_id ) ) {
			return self::not_found_or_forbidden( 'file', $file_id, 'write' );
		}

		$file = $file_id ? Floppy_Permissions::get_target_row( 'file', $file_id ) : null;
		$hash = strtolower( sanitize_text_field( (string) $request->get_param( 'local_content_hash' ) ) );
		if ( '' !== $hash && ! preg_match( '/^[a-f0-9]{64}$/', $hash ) ) {
			return new WP_Error( 'floppy_invalid_content_hash', __( 'Conflict local_content_hash must be a SHA-256 hex digest.', 'floppy' ), array( 'status' => 400 ) );
		}

		$now = current_time( 'mysql', true );
		$uuid = wp_generate_uuid4();
		$reason = sanitize_key( (string) ( $request->get_param( 'reason' ) ?: 'stale_content' ) );
		$local_name = Floppy_Storage::normalize_filename( (string) ( $request->get_param( 'local_name' ) ?: ( $file['name'] ?? __( 'Conflict copy', 'floppy' ) ) ) );
		$inserted = $wpdb->insert(
			Floppy_Schema::table( 'conflicts' ),
			array(
				'conflict_uuid'          => $uuid,
				'owner_id'               => $user_id,
				'file_id'                => $file_id,
				'file_uuid'              => $file ? (string) $file['uuid'] : '',
				'parent_id'              => $file ? (int) $file['parent_id'] : absint( $request->get_param( 'parent_id' ) ),
				'status'                 => 'open',
				'reason'                 => $reason,
				'local_name'             => $local_name,
				'server_content_version' => sanitize_text_field( (string) ( $request->get_param( 'server_content_version' ) ?: ( $file['content_version'] ?? '' ) ) ),
				'local_content_hash'     => $hash,
				'local_size_bytes'       => absint( $request->get_param( 'local_size_bytes' ) ),
				'client_created_at_gmt'  => self::sanitize_mysql_datetime( (string) $request->get_param( 'client_created_at_gmt' ) ),
				'created_at_gmt'         => $now,
				'updated_at_gmt'         => $now,
			),
			array( '%s', '%d', '%d', '%s', '%d', '%s', '%s', '%s', '%s', '%s', '%d', '%s', '%s', '%s' )
		);
		if ( ! $inserted ) {
			return new WP_Error( 'floppy_conflict_record_failed', __( 'Could not record the conflict.', 'floppy' ), array( 'status' => 500 ) );
		}

		$row = $wpdb->get_row( $wpdb->prepare( 'SELECT * FROM ' . Floppy_Schema::table( 'conflicts' ) . ' WHERE id = %d', (int) $wpdb->insert_id ), ARRAY_A );
		Floppy_Sync::append_event( 'conflict.created', 'conflict', (int) $row['id'], Floppy_Rest_Serializer::conflict( $row ), $user_id );
		Floppy_Audit::log( 'conflict.created', 'conflict', (int) $row['id'], $local_name, array( 'reason' => $reason, 'file_id' => $file_id ), $user_id );

		return new WP_REST_Response( Floppy_Rest_Serializer::conflict( $row ), 201 );
	}

	/**
	 * Resolve a conflict lifecycle record.
	 */
	public static function resolve_conflict( WP_REST_Request $request ) {
		$result = self::apply_conflict_action(
			sanitize_text_field( (string) $request['uuid'] ),
			sanitize_key( (string) $request->get_param( 'action' ) )
		);

		if ( is_wp_error( $result ) ) {
			return $result;
		}

		return new WP_REST_Response( $result['conflict'] );
	}

	/**
	 * Future-compatible conflict action endpoint used by Mac and Desktop Mode clients.
	 */
	public static function conflict_action( WP_REST_Request $request ) {
		$result = self::apply_conflict_action(
			sanitize_text_field( (string) $request['uuid'] ),
			sanitize_key( (string) $request->get_param( 'action' ) )
		);

		if ( is_wp_error( $result ) ) {
			return $result;
		}

		return new WP_REST_Response( $result );
	}

	/**
	 * Apply a normalized conflict action and return a redacted action response.
	 */
	private static function apply_conflict_action( string $uuid, string $action ) {
		global $wpdb;

		$action = self::normalize_conflict_action( $action );
		$status_map = array(
			'discard' => 'discarded',
			'keep'    => 'kept',
			'resolve' => 'resolved',
			'retry'   => 'open',
		);
		if ( ! isset( $status_map[ $action ] ) ) {
			return new WP_Error( 'floppy_invalid_conflict_action', __( 'Invalid conflict action.', 'floppy' ), array( 'status' => 400 ) );
		}

		$row = $wpdb->get_row(
			$wpdb->prepare( 'SELECT * FROM ' . Floppy_Schema::table( 'conflicts' ) . ' WHERE conflict_uuid = %s LIMIT 1', $uuid ),
			ARRAY_A
		);
		if ( ! $row || (int) $row['owner_id'] !== get_current_user_id() ) {
			return new WP_Error( 'floppy_conflict_not_found', __( 'Conflict not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$next_status = $status_map[ $action ];
		$now = current_time( 'mysql', true );
		$wpdb->update(
			Floppy_Schema::table( 'conflicts' ),
			array(
				'status'          => $next_status,
				'resolved_at_gmt' => 'open' === $next_status ? null : $now,
				'updated_at_gmt'  => $now,
			),
			array( 'id' => (int) $row['id'] ),
			array( '%s', '%s', '%s' ),
			array( '%d' )
		);

		$next = $wpdb->get_row( $wpdb->prepare( 'SELECT * FROM ' . Floppy_Schema::table( 'conflicts' ) . ' WHERE id = %d', (int) $row['id'] ), ARRAY_A );
		$serialized = Floppy_Rest_Serializer::conflict( $next );
		Floppy_Sync::append_event( 'conflict.' . $action, 'conflict', (int) $row['id'], $serialized, get_current_user_id() );
		Floppy_Audit::log( 'conflict.' . $action, 'conflict', (int) $row['id'], (string) $row['local_name'], array( 'status' => $next_status ) );

		return array(
			'conflict'       => $serialized,
			'canonical_item' => $serialized['server_file'],
		);
	}

	/**
	 * Normalize Mac/Desktop conflict action names to server lifecycle verbs.
	 */
	private static function normalize_conflict_action( string $action ): string {
		$aliases = array(
			'mark_resolved'      => 'resolve',
			'discard_local_copy' => 'discard',
			'keep_both'          => 'keep',
			'retry_upload'       => 'retry',
		);

		return $aliases[ $action ] ?? $action;
	}

	/**
	 * Enqueue thumbnail generation.
	 */
	public static function enqueue_thumbnail( WP_REST_Request $request ) {
		$id = absint( $request['id'] );
		if ( ! Floppy_Permissions::can_read( 'file', $id ) ) {
			return self::not_found_or_forbidden( 'file', $id, 'read' );
		}

		$job = Floppy_Background_Jobs::enqueue( 'thumbnail_generate', array( 'file_id' => $id, 'user_id' => get_current_user_id() ), 4 );
		if ( is_wp_error( $job ) ) {
			return $job;
		}

		return new WP_REST_Response(
			array(
				'ok'         => true,
				'job_id'     => (int) $job['id'],
				'job_uuid'   => $job['job_uuid'],
				'status_url' => rest_url( self::NAMESPACE . '/jobs/' . $job['job_uuid'] ),
			),
			202
		);
	}

	/**
	 * Stream an authenticated thumbnail, generating it on demand for small images.
	 */
	public static function thumbnail_file( WP_REST_Request $request ) {
		$id = absint( $request['id'] );
		if ( ! Floppy_Permissions::can_read( 'file', $id ) ) {
			return self::not_found_or_forbidden( 'file', $id, 'read' );
		}

		$rate = Floppy_Rate_Limiter::check( 'preview', 600, HOUR_IN_SECONDS );
		if ( is_wp_error( $rate ) ) {
			return $rate;
		}

		$row = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $row || 'active' !== $row['status'] ) {
			return new WP_Error( 'floppy_file_not_found', __( 'File not found.', 'floppy' ), array( 'status' => 404 ) );
		}
		if ( 0 !== strpos( (string) $row['mime_type'], 'image/' ) ) {
			return new WP_Error( 'floppy_thumbnail_not_available', __( 'Thumbnails are available for image files only.', 'floppy' ), array( 'status' => 415 ) );
		}

		$thumbnail = self::get_ready_thumbnail( $row );
		if ( ! $thumbnail ) {
			$inline_limit = (int) Floppy_Settings::get_value( 'thumbnail_inline_max_size', 20 * MB_IN_BYTES );
			if ( (int) $row['size_bytes'] <= $inline_limit ) {
				$generated = self::generate_thumbnail_for_file( $row );
				if ( is_wp_error( $generated ) ) {
					return $generated;
				}
				$thumbnail = $generated;
			} else {
				$job = self::enqueue_thumbnail( $request );
				$data = $job instanceof WP_REST_Response ? $job->get_data() : array();
				return new WP_REST_Response(
					array(
						'status' => 'queued',
						'job'    => $data,
					),
					202
				);
			}
		}

		self::stream_thumbnail( $thumbnail, $row );
		exit;
	}

	/**
	 * Run a queued thumbnail job.
	 */
	public static function run_thumbnail_job( array $payload ): array {
		$id = absint( $payload['file_id'] ?? 0 );
		if ( $id <= 0 ) {
			return array( 'ok' => false, 'message' => 'Missing file_id.' );
		}

		$row = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $row || 'active' !== $row['status'] ) {
			return array( 'ok' => false, 'message' => 'File not found.' );
		}

		$result = self::generate_thumbnail_for_file( $row );
		if ( is_wp_error( $result ) ) {
			return array(
				'ok'      => false,
				'message' => $result->get_error_message(),
				'code'    => $result->get_error_code(),
			);
		}

		return array(
			'ok'      => true,
			'message' => 'Thumbnail generated.',
			'file_id' => $id,
		);
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
		$limit  = max( 1, min( 500, absint( $request->get_param( 'limit' ) ?: 250 ) ) );
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
	 * Exchange a short-lived browser approval code for a scoped device token.
	 */
	public static function exchange_device_code( WP_REST_Request $request ) {
		if ( ! is_ssl() ) {
			return new WP_Error( 'floppy_https_required', __( 'Device code exchange requires HTTPS.', 'floppy' ), array( 'status' => 403 ) );
		}

		$rate = Floppy_Rate_Limiter::check( 'device-exchange', 20, HOUR_IN_SECONDS );
		if ( is_wp_error( $rate ) ) {
			return $rate;
		}

		$code = sanitize_text_field( (string) $request->get_param( 'code' ) );
		$state = sanitize_text_field( (string) $request->get_param( 'state' ) );
		$exchange = Floppy_Auth::exchange_device_code( $code, $state );
		if ( is_wp_error( $exchange ) ) {
			return $exchange;
		}

		return new WP_REST_Response( $exchange, 201 );
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

		$principal = self::normalize_share_principal( $principal_type, $principal_ref );
		if ( is_wp_error( $principal ) ) {
			return $principal;
		}
		$principal_ref = $principal['principal_ref'];

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

		if ( ! in_array( $target_type, array( 'file', 'folder' ), true ) || ! in_array( $principal_type, array( 'user', 'role' ), true ) ) {
			return new WP_Error( 'floppy_invalid_share', __( 'Invalid share target or principal.', 'floppy' ), array( 'status' => 400 ) );
		}

		if ( ! Floppy_Permissions::can_write( $target_type, $target_id ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot unshare this item.', 'floppy' ), array( 'status' => 403 ) );
		}

		$principal = self::normalize_share_principal( $principal_type, $principal_ref );
		if ( ! is_wp_error( $principal ) ) {
			$principal_ref = $principal['principal_ref'];
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
		$job = Floppy_Background_Jobs::enqueue( 'export', array( 'user_id' => get_current_user_id() ), 5 );
		if ( is_wp_error( $job ) ) {
			return $job;
		}

		Floppy_Audit::log( 'export.enqueued', 'export', (int) $job['id'] );
		return new WP_REST_Response(
			array(
				'ok'           => true,
				'job_id'       => (int) $job['id'],
				'job_uuid'     => $job['job_uuid'],
				'status_url'   => rest_url( self::NAMESPACE . '/jobs/' . $job['job_uuid'] ),
				'download_url' => rest_url( self::NAMESPACE . '/exports/' . $job['job_uuid'] . '/download' ),
			),
			202
		);
	}

	/**
	 * Return status for an owned job.
	 */
	public static function job_status( WP_REST_Request $request ) {
		$job = Floppy_Background_Jobs::get_job( sanitize_text_field( (string) $request['uuid'] ) );
		if ( is_wp_error( $job ) ) {
			return $job;
		}
		if ( ! self::current_user_can_access_job( $job ) ) {
			return new WP_Error( 'floppy_job_not_found', __( 'Floppy job not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		return new WP_REST_Response( Floppy_Rest_Serializer::job( $job ) );
	}

	/**
	 * Download a completed export manifest.
	 */
	public static function download_export( WP_REST_Request $request ) {
		$job = Floppy_Background_Jobs::get_job( sanitize_text_field( (string) $request['uuid'] ) );
		if ( is_wp_error( $job ) ) {
			return $job;
		}
		if ( ! self::current_user_can_access_job( $job ) || 'export' !== $job['job_type'] ) {
			return new WP_Error( 'floppy_export_not_found', __( 'Floppy export not found.', 'floppy' ), array( 'status' => 404 ) );
		}
		if ( 'complete' !== $job['status'] ) {
			return new WP_Error( 'floppy_export_not_ready', __( 'This Floppy export is not ready yet.', 'floppy' ), array( 'status' => 409, 'job' => Floppy_Rest_Serializer::job( $job ) ) );
		}

		$result = json_decode( (string) $job['result_json'], true );
		$export_key = is_array( $result ) ? (string) ( $result['export_key'] ?? '' ) : '';
		$path = $export_key ? Floppy_Storage::path_for_key( $export_key ) : '';
		if ( '' === $path || ! is_readable( $path ) ) {
			return new WP_Error( 'floppy_export_missing', __( 'The export manifest is missing from private storage.', 'floppy' ), array( 'status' => 500 ) );
		}

		Floppy_Audit::log( 'export.downloaded', 'export', (int) $job['id'] );

		nocache_headers();
		header( 'Cache-Control: private, no-store, max-age=0' );
		header( 'X-Content-Type-Options: nosniff' );
		header( 'Content-Type: application/json' );
		header( 'Content-Disposition: attachment; filename="floppy-export-' . str_replace( '"', '', $job['job_uuid'] ) . '.json"' );
		header( 'Content-Length: ' . filesize( $path ) );
		readfile( $path ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_readfile,WordPress.Security.EscapeOutput.OutputNotEscaped
		exit;
	}

	/**
	 * Check whether the current browser user owns a job.
	 */
	private static function current_user_can_access_job( array $job ): bool {
		if ( current_user_can( Floppy_Permissions::CAP_MANAGE ) || current_user_can( 'manage_options' ) ) {
			return true;
		}

		$payload = json_decode( (string) $job['payload_json'], true );
		$owner_id = is_array( $payload ) ? (int) ( $payload['user_id'] ?? 0 ) : 0;
		return $owner_id > 0 && $owner_id === get_current_user_id();
	}

	/**
	 * Resolve shares to canonical user ids or role slugs.
	 */
	private static function normalize_share_principal( string $principal_type, string $principal_ref ) {
		if ( 'user' === $principal_type ) {
			if ( is_numeric( $principal_ref ) ) {
				$user = get_user_by( 'id', (int) $principal_ref );
			} elseif ( is_email( $principal_ref ) ) {
				$user = get_user_by( 'email', $principal_ref );
			} else {
				$user = get_user_by( 'login', $principal_ref );
			}

			if ( ! $user ) {
				return new WP_Error( 'floppy_invalid_share_principal', __( 'Share user was not found.', 'floppy' ), array( 'status' => 404 ) );
			}

			return array(
				'principal_type' => 'user',
				'principal_ref'  => (string) $user->ID,
			);
		}

		$roles = wp_roles();
		if ( ! $roles || ! $roles->is_role( $principal_ref ) ) {
			return new WP_Error( 'floppy_invalid_share_principal', __( 'Share role was not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		return array(
			'principal_type' => 'role',
			'principal_ref'  => $principal_ref,
		);
	}

	/**
	 * Require a logged-in user.
	 */
	public static function require_user() {
		return Floppy_Rest_Access::require_user();
	}

	/**
	 * Require file read scope.
	 */
	public static function require_read() {
		return Floppy_Rest_Access::require_read();
	}

	/**
	 * Require file write scope.
	 */
	public static function require_write() {
		return Floppy_Rest_Access::require_write();
	}

	/**
	 * Require sync scope.
	 */
	public static function require_sync() {
		return Floppy_Rest_Access::require_sync();
	}

	/**
	 * Require a browser-authenticated WordPress session, not a device token.
	 */
	public static function require_browser_session() {
		return Floppy_Rest_Access::require_browser_session();
	}

	/**
	 * Require an authenticated WordPress user who is not already using a Floppy device token.
	 */
	public static function require_device_authorization() {
		return Floppy_Rest_Access::require_device_authorization();
	}

	/**
	 * Allow browser sessions to revoke any owned device and device tokens to revoke themselves.
	 */
	public static function require_device_revoke( WP_REST_Request $request ) {
		return Floppy_Rest_Access::require_device_revoke( $request );
	}

	/**
	 * Require admin.
	 */
	public static function require_admin() {
		return Floppy_Rest_Access::require_admin();
	}

	/**
	 * Query a restore-ready set of owned file/folder rows.
	 */
	private static function query_recovery_items( string $status, int $limit, int $user_id ): array {
		global $wpdb;

		if ( ! in_array( $status, array( 'active', 'trashed', 'deleted' ), true ) ) {
			$status = 'trashed';
		}

		$sql = $wpdb->prepare(
			"SELECT 'folder' AS kind, 0 AS kind_order, id, uuid, 0 AS attachment_id, owner_id, parent_id, name, normalized_name, '' AS mime_type, 0 AS size_bytes, '' AS content_hash, '' AS storage_key, '' AS content_version, metadata_version, status, 'private' AS visibility, created_at_gmt, updated_at_gmt, deleted_at_gmt FROM " . Floppy_Schema::table( 'folders' ) . " WHERE owner_id = %d AND status = %s
			UNION ALL
			SELECT 'file' AS kind, 1 AS kind_order, id, uuid, attachment_id, owner_id, parent_id, name, normalized_name, mime_type, size_bytes, content_hash, storage_key, content_version, metadata_version, status, visibility, created_at_gmt, updated_at_gmt, deleted_at_gmt FROM " . Floppy_Schema::table( 'files' ) . " WHERE owner_id = %d AND status = %s
			ORDER BY deleted_at_gmt DESC, updated_at_gmt DESC, kind_order ASC, id DESC LIMIT %d",
			$user_id,
			$status,
			$user_id,
			$status,
			$limit
		); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared

		return $wpdb->get_results( $sql, ARRAY_A );
	}

	/**
	 * Query recently touched owned active rows for the Recents control-center panel.
	 */
	private static function query_recent_items( int $limit, int $user_id ): array {
		global $wpdb;

		$sql = $wpdb->prepare(
			"SELECT 'folder' AS kind, 0 AS kind_order, id, uuid, 0 AS attachment_id, owner_id, parent_id, name, normalized_name, '' AS mime_type, 0 AS size_bytes, '' AS content_hash, '' AS storage_key, '' AS content_version, metadata_version, status, 'private' AS visibility, created_at_gmt, updated_at_gmt, deleted_at_gmt FROM " . Floppy_Schema::table( 'folders' ) . " WHERE owner_id = %d AND status = 'active'
			UNION ALL
			SELECT 'file' AS kind, 1 AS kind_order, id, uuid, attachment_id, owner_id, parent_id, name, normalized_name, mime_type, size_bytes, content_hash, storage_key, content_version, metadata_version, status, visibility, created_at_gmt, updated_at_gmt, deleted_at_gmt FROM " . Floppy_Schema::table( 'files' ) . " WHERE owner_id = %d AND status = 'active'
			ORDER BY updated_at_gmt DESC, kind_order ASC, id DESC LIMIT %d",
			$user_id,
			$user_id,
			$limit
		); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared

		return $wpdb->get_results( $sql, ARRAY_A );
	}

	/**
	 * Query recovery-related audit events without leaking metadata payloads.
	 */
	private static function query_recovery_activity( int $limit, int $user_id ): array {
		global $wpdb;

		$actions = "'file.trashed','file.restored','folder.trashed','folder.restored','file.version_restored','conflict.created','conflict.retry_upload','conflict.keep_both','conflict.mark_resolved','conflict.discard_local_copy','export.enqueued','export.downloaded'";

		return $wpdb->get_results(
			$wpdb->prepare(
				'SELECT action, target_type, target_id, created_at_gmt FROM ' . Floppy_Schema::table( 'audit_log' ) . " WHERE actor_id = %d AND action IN ($actions) ORDER BY id DESC LIMIT %d", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
				$user_id,
				$limit
			),
			ARRAY_A
		);
	}

	/**
	 * Return export jobs created by the current user only.
	 */
	private static function query_current_user_export_jobs( int $limit, int $user_id ): array {
		global $wpdb;

		$rows = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'jobs' ) . " WHERE job_type = 'export' AND (payload_json LIKE %s OR payload_json LIKE %s) ORDER BY id DESC LIMIT %d",
				'%"user_id":' . $user_id . ',%',
				'%"user_id":' . $user_id . '}%',
				max( 1, min( 100, $limit ) )
			),
			ARRAY_A
		);

		$out = array();
		foreach ( $rows as $row ) {
			$payload = json_decode( (string) ( $row['payload_json'] ?? '' ), true );
			if ( is_array( $payload ) && (int) ( $payload['user_id'] ?? 0 ) === $user_id ) {
				$out[] = $row;
			}
			if ( count( $out ) >= $limit ) {
				break;
			}
		}

		return $out;
	}

	/**
	 * Count owned trash rows by kind.
	 */
	private static function trash_counts_for_user( int $user_id ): array {
		global $wpdb;

		return array(
			'files'   => (int) $wpdb->get_var( $wpdb->prepare( 'SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'files' ) . " WHERE owner_id = %d AND status = 'trashed'", $user_id ) ),
			'folders' => (int) $wpdb->get_var( $wpdb->prepare( 'SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'folders' ) . " WHERE owner_id = %d AND status = 'trashed'", $user_id ) ),
		);
	}

	/**
	 * Query a stable, folder-first children page without PHP sorting.
	 */
	private static function query_children_page( int $parent_id, string $cursor, int $after_id, int $limit, int $user_id ): array {
		global $wpdb;

		$cursor_kind = '';
		$cursor_id = $after_id;
		if ( preg_match( '/^(folder|file):(\d+)$/', $cursor, $matches ) ) {
			$cursor_kind = $matches[1];
			$cursor_id = (int) $matches[2];
		}

		$folder_after = 'file' === $cursor_kind ? PHP_INT_MAX : $cursor_id;
		$file_after = 'folder' === $cursor_kind ? 0 : $cursor_id;
		$folder_owner_sql = $parent_id ? '' : $wpdb->prepare( ' AND owner_id = %d', $user_id );
		$file_owner_sql = $parent_id ? '' : $wpdb->prepare( ' AND owner_id = %d', $user_id );

		$sql = $wpdb->prepare(
			"SELECT 'folder' AS kind, 0 AS kind_order, id, uuid, 0 AS attachment_id, owner_id, parent_id, name, normalized_name, '' AS mime_type, 0 AS size_bytes, '' AS content_hash, '' AS storage_key, '' AS content_version, metadata_version, status, 'private' AS visibility, created_at_gmt, updated_at_gmt FROM " . Floppy_Schema::table( 'folders' ) . " WHERE parent_id = %d AND status = 'active' AND id > %d $folder_owner_sql
			UNION ALL
			SELECT 'file' AS kind, 1 AS kind_order, id, uuid, attachment_id, owner_id, parent_id, name, normalized_name, mime_type, size_bytes, content_hash, storage_key, content_version, metadata_version, status, visibility, created_at_gmt, updated_at_gmt FROM " . Floppy_Schema::table( 'files' ) . " WHERE parent_id = %d AND status = 'active' AND id > %d $file_owner_sql
			ORDER BY kind_order ASC, id ASC LIMIT %d",
			$parent_id,
			$folder_after,
			$parent_id,
			$file_after,
			$limit
		); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared

		return $wpdb->get_results( $sql, ARRAY_A );
	}

	/**
	 * Compare-and-swap metadata update.
	 */
	private static function update_file_metadata( int $id, WP_REST_Request $request, array $updates, string $event_type ) {
		global $wpdb;

		if ( ! Floppy_Permissions::can_write( 'file', $id ) ) {
			return self::not_found_or_forbidden( 'file', $id, 'write' );
		}

		$row = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $row ) {
			return new WP_Error( 'floppy_file_not_found', __( 'File not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$known_version = (string) $request->get_param( 'metadata_version' );
		if ( '' === $known_version ) {
			return new WP_Error( 'floppy_metadata_version_required', __( 'A metadata version is required to change this file.', 'floppy' ), array( 'status' => 428, 'server' => Floppy_Rest_Serializer::file( $row ) ) );
		}
		if ( $known_version !== $row['metadata_version'] ) {
			return new WP_Error( 'floppy_conflict', __( 'The file changed on the server. Refresh before applying this change.', 'floppy' ), array( 'status' => 409, 'server' => Floppy_Rest_Serializer::file( $row ) ) );
		}

		if ( isset( $updates['name'] ) ) {
			$collision = self::item_name_collision( (int) $row['parent_id'], (string) $updates['name'], 'file', $id );
			if ( is_wp_error( $collision ) ) {
				return $collision;
			}
		}

		if ( isset( $updates['parent_id'] ) ) {
			$collision = self::item_name_collision( (int) $updates['parent_id'], (string) $row['name'], 'file', $id );
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

		self::begin_transaction();
		$updated = $wpdb->update( Floppy_Schema::table( 'files' ), $updates, array( 'id' => $id, 'metadata_version' => $known_version ), $formats, array( '%d', '%s' ) );
		if ( 1 !== $updated ) {
			self::rollback_transaction();
			$server = Floppy_Permissions::get_target_row( 'file', $id );
			return new WP_Error( 'floppy_conflict', __( 'The file changed while this request was being applied.', 'floppy' ), array( 'status' => 409, 'server' => $server ? Floppy_Rest_Serializer::file( $server ) : null ) );
		}

		$next = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $next ) {
			self::rollback_transaction();
			return new WP_Error( 'floppy_file_not_found', __( 'File not found after updating metadata.', 'floppy' ), array( 'status' => 404 ) );
		}
		if ( 'deleted' === $next['status'] ) {
			self::release_item_name_reservation( 'file', $id );
		} else {
			$reserved = self::sync_item_name_reservation( 'file', $id, $next );
			if ( is_wp_error( $reserved ) ) {
				self::rollback_transaction();
				return $reserved;
			}
		}

		$seq = Floppy_Sync::append_event( $event_type, 'file', $id, array_merge( $next, $audience ) );
		if ( $seq <= 0 ) {
			self::rollback_transaction();
			return new WP_Error( 'floppy_sync_event_failed', __( 'Could not record the Floppy sync event for this change.', 'floppy' ), array( 'status' => 500 ) );
		}
		$next['last_sync_seq'] = $seq;
		self::commit_transaction();

		Floppy_Audit::log( $event_type, 'file', $id );
		Floppy_Schema::refresh_usage_counters();

		return new WP_REST_Response( Floppy_Rest_Serializer::file( $next ) + array( 'last_sync_seq' => $seq ) );
	}

	/**
	 * Compare-and-swap folder metadata update.
	 */
	private static function update_folder_metadata( int $id, WP_REST_Request $request, array $updates, string $event_type ) {
		global $wpdb;

		if ( ! Floppy_Permissions::can_write( 'folder', $id ) ) {
			return self::not_found_or_forbidden( 'folder', $id, 'write' );
		}

		$row = Floppy_Permissions::get_target_row( 'folder', $id );
		if ( ! $row ) {
			return new WP_Error( 'floppy_folder_not_found', __( 'Folder not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$known_version = (string) $request->get_param( 'metadata_version' );
		if ( '' === $known_version ) {
			return new WP_Error( 'floppy_metadata_version_required', __( 'A metadata version is required to change this folder.', 'floppy' ), array( 'status' => 428, 'server' => Floppy_Rest_Serializer::folder( $row ) ) );
		}
		if ( $known_version !== $row['metadata_version'] ) {
			return new WP_Error( 'floppy_conflict', __( 'The folder changed on the server. Refresh before applying this change.', 'floppy' ), array( 'status' => 409, 'server' => Floppy_Rest_Serializer::folder( $row ) ) );
		}

		if ( isset( $updates['name'] ) ) {
			$collision = self::item_name_collision( (int) $row['parent_id'], (string) $updates['name'], 'folder', $id );
			if ( is_wp_error( $collision ) ) {
				return $collision;
			}
		}

		if ( isset( $updates['parent_id'] ) ) {
			$collision = self::item_name_collision( (int) $updates['parent_id'], (string) $row['name'], 'folder', $id );
			if ( is_wp_error( $collision ) ) {
				return $collision;
			}
		}

		$updates['metadata_version'] = wp_generate_uuid4();
		$updates['updated_at_gmt'] = current_time( 'mysql', true );
		$formats = array();
		foreach ( $updates as $value ) {
			$formats[] = is_int( $value ) ? '%d' : '%s';
		}

		self::begin_transaction();
		$updated = $wpdb->update( Floppy_Schema::table( 'folders' ), $updates, array( 'id' => $id, 'metadata_version' => $known_version ), $formats, array( '%d', '%s' ) );
		if ( 1 !== $updated ) {
			self::rollback_transaction();
			$server = Floppy_Permissions::get_target_row( 'folder', $id );
			return new WP_Error( 'floppy_conflict', __( 'The folder changed while this request was being applied.', 'floppy' ), array( 'status' => 409, 'server' => $server ? Floppy_Rest_Serializer::folder( $server ) : null ) );
		}

		$next = Floppy_Permissions::get_target_row( 'folder', $id );
		if ( ! $next ) {
			self::rollback_transaction();
			return new WP_Error( 'floppy_folder_not_found', __( 'Folder not found after updating metadata.', 'floppy' ), array( 'status' => 404 ) );
		}
		if ( 'deleted' === $next['status'] ) {
			self::release_item_name_reservation( 'folder', $id );
		} else {
			$reserved = self::sync_item_name_reservation( 'folder', $id, $next );
			if ( is_wp_error( $reserved ) ) {
				self::rollback_transaction();
				return $reserved;
			}
		}

		$seq = Floppy_Sync::append_event( $event_type, 'folder', $id, $next ?: array() );
		if ( $seq <= 0 ) {
			self::rollback_transaction();
			return new WP_Error( 'floppy_sync_event_failed', __( 'Could not record the Floppy sync event for this change.', 'floppy' ), array( 'status' => 500 ) );
		}
		$next['last_sync_seq'] = $seq;
		self::commit_transaction();
		Floppy_Audit::log( $event_type, 'folder', $id );
		Floppy_Schema::refresh_usage_counters();

		return new WP_REST_Response( Floppy_Rest_Serializer::folder( $next ) + array( 'last_sync_seq' => $seq ) );
	}

	/**
	 * Recursively update folder tree status and emit sync/tombstone records.
	 */
	private static function update_folder_tree_status( int $id, WP_REST_Request $request, string $status, string $event_type ) {
		global $wpdb;

		if ( ! Floppy_Permissions::can_write( 'folder', $id ) ) {
			return self::not_found_or_forbidden( 'folder', $id, 'write' );
		}

		$row = Floppy_Permissions::get_target_row( 'folder', $id );
		if ( ! $row ) {
			return new WP_Error( 'floppy_folder_not_found', __( 'Folder not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$known_version = (string) $request->get_param( 'metadata_version' );
		if ( '' === $known_version ) {
			return new WP_Error( 'floppy_metadata_version_required', __( 'A metadata version is required to change this folder tree.', 'floppy' ), array( 'status' => 428, 'server' => Floppy_Rest_Serializer::folder( $row ) ) );
		}
		if ( $known_version !== $row['metadata_version'] ) {
			return new WP_Error( 'floppy_conflict', __( 'The folder changed on the server. Refresh before applying this change.', 'floppy' ), array( 'status' => 409, 'server' => Floppy_Rest_Serializer::folder( $row ) ) );
		}

		$tree = self::folder_tree_ids( $id );
		$total_items = count( $tree['folders'] ) + count( $tree['files'] );
		$inline_limit = (int) apply_filters( 'floppy_inline_folder_operation_limit', 500 );
		if ( $total_items > $inline_limit && ! rest_sanitize_boolean( $request->get_param( 'run_inline' ) ) ) {
			$job = Floppy_Background_Jobs::enqueue(
				'folder_tree_status',
				array(
					'user_id'          => get_current_user_id(),
					'folder_id'        => $id,
					'status'           => $status,
					'event_type'       => $event_type,
					'metadata_version' => $known_version,
				),
				3
			);
			if ( is_wp_error( $job ) ) {
				return $job;
			}

			Floppy_Audit::log( $event_type . '.queued', 'folder', $id, '', array( 'folders' => count( $tree['folders'] ), 'files' => count( $tree['files'] ) ) );
			return new WP_REST_Response(
				array(
					'ok'           => true,
					'queued'       => true,
					'job_id'       => (int) $job['id'],
					'job_uuid'     => $job['job_uuid'],
					'status_url'   => rest_url( self::NAMESPACE . '/jobs/' . $job['job_uuid'] ),
					'folders'      => count( $tree['folders'] ),
					'files'        => count( $tree['files'] ),
				),
				202
			);
		}

		return self::apply_folder_tree_status( $id, $status, $event_type, $tree, get_current_user_id() );
	}

	/**
	 * Run a queued recursive folder status update.
	 */
	public static function run_folder_tree_status_job( array $payload ): array {
		$id = absint( $payload['folder_id'] ?? 0 );
		$status = sanitize_key( (string) ( $payload['status'] ?? '' ) );
		$event_type = preg_replace( '/[^a-z0-9_.-]/', '', strtolower( (string) ( $payload['event_type'] ?? '' ) ) );
		$metadata_version = sanitize_text_field( (string) ( $payload['metadata_version'] ?? '' ) );
		if ( $id <= 0 || ! in_array( $status, array( 'active', 'trashed', 'deleted' ), true ) || '' === $event_type || '' === $metadata_version ) {
			return array( 'ok' => false, 'message' => 'Invalid folder tree job payload.' );
		}

		$row = Floppy_Permissions::get_target_row( 'folder', $id );
		if ( ! $row ) {
			return array( 'ok' => false, 'message' => 'Folder not found.' );
		}
		if ( $metadata_version !== $row['metadata_version'] ) {
			return array(
				'ok'      => false,
				'message' => 'Folder changed before queued operation could run.',
			);
		}

		$actor_id = absint( $payload['user_id'] ?? 0 );
		if ( ! Floppy_Permissions::can_write( 'folder', $id, $actor_id ) ) {
			return array(
				'ok'      => false,
				'message' => 'Queued actor can no longer write this folder.',
			);
		}

		$response = self::apply_folder_tree_status( $id, $status, $event_type, self::folder_tree_ids( $id ), $actor_id );
		if ( is_wp_error( $response ) ) {
			return array(
				'ok'      => false,
				'message' => $response->get_error_message(),
				'code'    => $response->get_error_code(),
			);
		}

		$data = $response->get_data();
		return array(
			'ok'            => true,
			'message'       => 'Folder tree updated.',
			'last_sync_seq' => (int) ( $data['last_sync_seq'] ?? 0 ),
			'folders'       => (int) ( $data['folders'] ?? 0 ),
			'files'         => (int) ( $data['files'] ?? 0 ),
		);
	}

	/**
	 * Apply a recursive folder tree status update.
	 */
	private static function apply_folder_tree_status( int $id, string $status, string $event_type, array $tree, int $actor_id = 0 ) {
		global $wpdb;

		$folder_ids = $tree['folders'];
		$file_ids = $tree['files'];
		$deleted_at = 'active' === $status ? null : current_time( 'mysql', true );
		$now = current_time( 'mysql', true );
		$deleted_sql = null === $deleted_at ? 'NULL' : $wpdb->prepare( '%s', $deleted_at );

		if ( $folder_ids ) {
			$wpdb->query(
				$wpdb->prepare(
					'UPDATE ' . Floppy_Schema::table( 'folders' ) . ' SET status = %s, deleted_at_gmt = ' . $deleted_sql . ', metadata_version = UUID(), updated_at_gmt = %s WHERE id IN (' . implode( ',', array_map( 'absint', $folder_ids ) ) . ')',
					$status,
					$now
				)
			);
		}

		if ( $file_ids ) {
			$wpdb->query(
				$wpdb->prepare(
					'UPDATE ' . Floppy_Schema::table( 'files' ) . ' SET status = %s, deleted_at_gmt = ' . $deleted_sql . ', metadata_version = UUID(), updated_at_gmt = %s WHERE id IN (' . implode( ',', array_map( 'absint', $file_ids ) ) . ')',
					$status,
					$now
				)
			);
		}

		$last_seq = 0;
		foreach ( $folder_ids as $folder_id ) {
			$updated = Floppy_Permissions::get_target_row( 'folder', (int) $folder_id );
			$payload = array_merge( $updated ?: array(), Floppy_Permissions::audience_for( 'folder', (int) $folder_id ) );
			$last_seq = Floppy_Sync::append_event( $event_type, 'folder', (int) $folder_id, $payload, $actor_id );
			if ( 'deleted' === $status && $updated ) {
				self::release_item_name_reservation( 'folder', (int) $folder_id );
				Floppy_Sync::tombstone( 'folder', (int) $folder_id, (int) $updated['owner_id'], $last_seq );
			} elseif ( $updated ) {
				self::sync_item_name_reservation( 'folder', (int) $folder_id, $updated );
			}
		}

		foreach ( $file_ids as $file_id ) {
			$updated = Floppy_Permissions::get_target_row( 'file', (int) $file_id );
			$file_event = str_replace( 'folder.', 'file.', $event_type );
			$payload = array_merge( $updated ?: array(), Floppy_Permissions::audience_for( 'file', (int) $file_id ) );
			$last_seq = Floppy_Sync::append_event( $file_event, 'file', (int) $file_id, $payload, $actor_id );
			if ( 'deleted' === $status && $updated ) {
				self::release_item_name_reservation( 'file', (int) $file_id );
				Floppy_Sync::tombstone( 'file', (int) $file_id, (int) $updated['owner_id'], $last_seq );
			} elseif ( $updated ) {
				self::sync_item_name_reservation( 'file', (int) $file_id, $updated );
			}
		}

		$next = Floppy_Permissions::get_target_row( 'folder', $id );
		Floppy_Audit::log( $event_type, 'folder', $id, '', array( 'folders' => count( $folder_ids ), 'files' => count( $file_ids ) ), $actor_id );
		Floppy_Schema::refresh_usage_counters();

		return new WP_REST_Response(
			Floppy_Rest_Serializer::folder( $next ) + array(
				'last_sync_seq' => $last_seq,
				'folders'       => count( $folder_ids ),
				'files'         => count( $file_ids ),
			)
		);
	}

	/**
	 * Prevent duplicate file/folder names inside a parent.
	 */
	private static function item_name_collision( int $parent_id, string $name, string $ignore_type = '', int $ignore_id = 0 ) {
		global $wpdb;

		$normalized = Floppy_Storage::normalize_lookup_name( $name );
		$reservations = Floppy_Schema::table( 'item_names' );
		if ( self::table_exists( $reservations ) ) {
			$reserved = $wpdb->get_row(
				$wpdb->prepare(
					"SELECT target_type, target_id FROM $reservations WHERE parent_id = %d AND normalized_name = %s AND status = 'reserved' LIMIT 1", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
					$parent_id,
					$normalized
				),
				ARRAY_A
			);
			if ( $reserved && ( $ignore_type !== $reserved['target_type'] || $ignore_id !== (int) $reserved['target_id'] ) ) {
				return new WP_Error( 'floppy_name_collision', __( 'An item with that name already exists in this folder.', 'floppy' ), array( 'status' => 409 ) );
			}
		}

		foreach ( array( 'folders' => 'folder', 'files' => 'file' ) as $table_name => $kind ) {
			$table = Floppy_Schema::table( $table_name );
			$ignore_sql = ( $ignore_id && $ignore_type === $kind ) ? $wpdb->prepare( ' AND id != %d', $ignore_id ) : '';
			$sql = $wpdb->prepare(
				"SELECT id FROM $table WHERE parent_id = %d AND normalized_name = %s AND status != 'deleted' $ignore_sql LIMIT 1", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
				$parent_id,
				$normalized
			);

			if ( $wpdb->get_var( $sql ) ) {
				return new WP_Error( 'floppy_name_collision', __( 'An item with that name already exists in this folder.', 'floppy' ), array( 'status' => 409 ) );
			}
		}

		return true;
	}

	/**
	 * Keep the cross-table sibling-name reservation in sync.
	 */
	private static function sync_item_name_reservation( string $target_type, int $target_id, array $row ) {
		global $wpdb;

		if ( 'deleted' === (string) ( $row['status'] ?? '' ) ) {
			self::release_item_name_reservation( $target_type, $target_id );
			return true;
		}

		$table = Floppy_Schema::table( 'item_names' );
		if ( ! self::table_exists( $table ) ) {
			return true;
		}

		$normalized = Floppy_Storage::normalize_lookup_name( (string) $row['name'] );
		$parent_id = (int) $row['parent_id'];
		$conflict = self::item_name_collision( $parent_id, (string) $row['name'], $target_type, $target_id );
		if ( is_wp_error( $conflict ) ) {
			return $conflict;
		}

		$existing = $wpdb->get_row(
			$wpdb->prepare(
				"SELECT id FROM $table WHERE target_type = %s AND target_id = %d LIMIT 1", // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
				$target_type,
				$target_id
			),
			ARRAY_A
		);
		$now = current_time( 'mysql', true );

		if ( $existing ) {
			$updated = $wpdb->update(
				$table,
				array(
					'parent_id'        => $parent_id,
					'normalized_name'  => $normalized,
					'status'           => 'reserved',
					'updated_at_gmt'   => $now,
				),
				array( 'id' => (int) $existing['id'] ),
				array( '%d', '%s', '%s', '%s' ),
				array( '%d' )
			);
			return false !== $updated ? true : new WP_Error( 'floppy_name_reservation_failed', __( 'Could not reserve this Floppy item name.', 'floppy' ), array( 'status' => 409 ) );
		}

		$inserted = $wpdb->insert(
			$table,
			array(
				'parent_id'        => $parent_id,
				'normalized_name'  => $normalized,
				'target_type'      => $target_type,
				'target_id'        => $target_id,
				'status'           => 'reserved',
				'created_at_gmt'   => $now,
				'updated_at_gmt'   => $now,
			),
			array( '%d', '%s', '%s', '%d', '%s', '%s', '%s' )
		);

		return $inserted ? true : new WP_Error( 'floppy_name_collision', __( 'An item with that name already exists in this folder.', 'floppy' ), array( 'status' => 409 ) );
	}

	/**
	 * Release a sibling-name reservation.
	 */
	private static function release_item_name_reservation( string $target_type, int $target_id ): void {
		global $wpdb;

		$table = Floppy_Schema::table( 'item_names' );
		if ( ! self::table_exists( $table ) ) {
			return;
		}

		$wpdb->delete(
			$table,
			array(
				'target_type' => $target_type,
				'target_id'   => $target_id,
			),
			array( '%s', '%d' )
		);
	}

	/**
	 * Check table existence before beta migrations have run on upgraded sites.
	 */
	private static function table_exists( string $table ): bool {
		global $wpdb;

		return $wpdb->get_var( $wpdb->prepare( 'SHOW TABLES LIKE %s', $table ) ) === $table;
	}

	/**
	 * Begin a best-effort SQL transaction for metadata/write-path coherence.
	 */
	private static function begin_transaction(): void {
		global $wpdb;

		$wpdb->query( 'START TRANSACTION' );
	}

	/**
	 * Commit a best-effort SQL transaction.
	 */
	private static function commit_transaction(): void {
		global $wpdb;

		$wpdb->query( 'COMMIT' );
	}

	/**
	 * Roll back a best-effort SQL transaction.
	 */
	private static function rollback_transaction(): void {
		global $wpdb;

		$wpdb->query( 'ROLLBACK' );
	}

	/**
	 * Return a folder tree as folder ids and file ids.
	 */
	private static function folder_tree_ids( int $root_folder_id ): array {
		global $wpdb;

		$folders = array( $root_folder_id );
		$files = array();
		$queue = array( $root_folder_id );
		$seen = array( $root_folder_id => true );

		while ( $queue ) {
			$batch = array_splice( $queue, 0, 100 );
			$in = implode( ',', array_map( 'absint', $batch ) );
			$child_folders = $wpdb->get_col( "SELECT id FROM " . Floppy_Schema::table( 'folders' ) . " WHERE parent_id IN ($in) AND status != 'deleted'" ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
			$child_files = $wpdb->get_col( "SELECT id FROM " . Floppy_Schema::table( 'files' ) . " WHERE parent_id IN ($in) AND status != 'deleted'" ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared

			foreach ( $child_folders as $folder_id ) {
				$folder_id = (int) $folder_id;
				if ( empty( $seen[ $folder_id ] ) ) {
					$seen[ $folder_id ] = true;
					$folders[] = $folder_id;
					$queue[] = $folder_id;
				}
			}

			foreach ( $child_files as $file_id ) {
				$files[] = (int) $file_id;
			}
		}

		return array(
			'folders' => $folders,
			'files'   => array_values( array_unique( $files ) ),
		);
	}

	/**
	 * Check whether one folder sits inside another folder.
	 */
	private static function folder_is_descendant( int $candidate_folder_id, int $ancestor_folder_id ): bool {
		if ( $candidate_folder_id <= 0 ) {
			return false;
		}

		global $wpdb;
		$seen = array();
		while ( $candidate_folder_id > 0 && empty( $seen[ $candidate_folder_id ] ) ) {
			if ( $candidate_folder_id === $ancestor_folder_id ) {
				return true;
			}
			$seen[ $candidate_folder_id ] = true;
			$candidate_folder_id = (int) $wpdb->get_var(
				$wpdb->prepare(
					'SELECT parent_id FROM ' . Floppy_Schema::table( 'folders' ) . ' WHERE id = %d LIMIT 1',
					$candidate_folder_id
				)
			);
		}

		return false;
	}

	/**
	 * Enforce per-user and site storage quotas.
	 */
	private static function check_quota( int $user_id, int $incoming_bytes ) {
		if ( $incoming_bytes <= 0 || current_user_can( Floppy_Permissions::CAP_MANAGE ) ) {
			return true;
		}

		global $wpdb;
		$user_quota = (int) Floppy_Settings::get_value( 'user_quota_bytes', 0 );
		$site_quota = (int) Floppy_Settings::get_value( 'site_quota_bytes', 0 );
		$counters = self::quota_counter_snapshot();

		if ( $user_quota > 0 ) {
			$user_used = isset( $counters['users'][ $user_id ] )
				? (int) $counters['users'][ $user_id ]['active_bytes'] + (int) $counters['users'][ $user_id ]['reserved_bytes']
				: (int) $wpdb->get_var(
					$wpdb->prepare(
						'SELECT COALESCE(SUM(size_bytes),0) FROM ' . Floppy_Schema::table( 'files' ) . " WHERE owner_id = %d AND status != 'deleted'",
						$user_id
					)
				);
			if ( ! isset( $counters['users'][ $user_id ] ) ) {
				$user_used += self::open_reserved_bytes( $user_id );
			}
			if ( $user_used + $incoming_bytes > $user_quota ) {
				return new WP_Error( 'floppy_user_quota_exceeded', __( 'This upload would exceed your Floppy storage quota.', 'floppy' ), array( 'status' => 507, 'used' => $user_used, 'quota' => $user_quota ) );
			}
		}

		if ( $site_quota > 0 ) {
			$site_used = isset( $counters['site'] )
				? (int) $counters['site']['active_bytes'] + (int) $counters['site']['reserved_bytes']
				: (int) $wpdb->get_var( 'SELECT COALESCE(SUM(size_bytes),0) FROM ' . Floppy_Schema::table( 'files' ) . " WHERE status != 'deleted'" ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
			if ( ! isset( $counters['site'] ) ) {
				$site_used += self::open_reserved_bytes( 0 );
			}
			if ( $site_used + $incoming_bytes > $site_quota ) {
				return new WP_Error( 'floppy_site_quota_exceeded', __( 'This upload would exceed the site Floppy storage quota.', 'floppy' ), array( 'status' => 507, 'used' => $site_used, 'quota' => $site_quota ) );
			}
		}

		return true;
	}

	/**
	 * Load quota counters when schema migrations have created them.
	 */
	private static function quota_counter_snapshot(): array {
		global $wpdb;

		$table = Floppy_Schema::table( 'usage_counters' );
		if ( ! self::table_exists( $table ) ) {
			return array();
		}

		$rows = $wpdb->get_results( "SELECT scope, user_id, active_bytes, reserved_bytes FROM $table", ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
		$out = array( 'users' => array() );
		foreach ( $rows as $row ) {
			$data = array(
				'active_bytes'   => (int) $row['active_bytes'],
				'reserved_bytes' => (int) $row['reserved_bytes'],
			);
			if ( 'site' === $row['scope'] ) {
				$out['site'] = $data;
			} elseif ( 'user' === $row['scope'] ) {
				$out['users'][ (int) $row['user_id'] ] = $data;
			}
		}

		return $out;
	}

	/**
	 * Sum open upload reservations as a fallback for upgraded sites.
	 */
	private static function open_reserved_bytes( int $user_id = 0 ): int {
		global $wpdb;

		$where = '';
		$args = array( current_time( 'mysql', true ) );
		if ( $user_id > 0 ) {
			$where = ' AND user_id = %d';
			$args[] = $user_id;
		}

		return (int) $wpdb->get_var(
			$wpdb->prepare(
				'SELECT COALESCE(SUM(reserved_bytes),0) FROM ' . Floppy_Schema::table( 'upload_sessions' ) . " WHERE status = 'open' AND expires_at_gmt >= %s $where",
				$args
			)
		); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared
	}

	/**
	 * Hide invisible item ids while still returning 403 for visible-but-not-writable items.
	 */
	private static function not_found_or_forbidden( string $target_type, int $target_id, string $capability ) {
		if ( 'write' === $capability && Floppy_Permissions::can_read( $target_type, $target_id ) ) {
			return new WP_Error( 'floppy_forbidden', __( 'You cannot modify this Floppy item.', 'floppy' ), array( 'status' => 403 ) );
		}

		return new WP_Error( 'floppy_item_not_found', __( 'Floppy item not found.', 'floppy' ), array( 'status' => 404 ) );
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

		$collision = self::item_name_collision( $parent_id, $stored['name'] );
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
		$reserved = self::sync_item_name_reservation( 'file', $row['id'], $row );
		if ( is_wp_error( $reserved ) ) {
			$wpdb->delete( Floppy_Schema::table( 'files' ), array( 'id' => $row['id'] ), array( '%d' ) );
			if ( $attachment_id ) {
				wp_delete_attachment( $attachment_id, true );
			}
			return $reserved;
		}

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
	 * Maximum bytes accepted per resumable upload chunk.
	 */
	private static function max_upload_chunk_bytes(): int {
		return (int) apply_filters( 'floppy_max_upload_chunk_bytes', 8 * MB_IN_BYTES );
	}

	/**
	 * Sanitize an optional MySQL GMT datetime.
	 */
	private static function sanitize_mysql_datetime( string $value ): ?string {
		$value = trim( $value );
		if ( '' === $value ) {
			return null;
		}

		$timestamp = strtotime( $value . ( false === strpos( $value, 'GMT' ) ? ' GMT' : '' ) );
		if ( false === $timestamp ) {
			return null;
		}

		return gmdate( 'Y-m-d H:i:s', $timestamp );
	}

	/**
	 * Store the current content state as a retained version.
	 */
	private static function record_file_version( array $row, int $actor_id, string $reason = 'replace', bool $prune = true ) {
		global $wpdb;

		if ( empty( $row['id'] ) || empty( $row['storage_key'] ) ) {
			return false;
		}

		$retention_limit = (int) Floppy_Settings::get_value( 'version_retention_limit', 10 );
		if ( $retention_limit <= 0 ) {
			return false;
		}

		$now = current_time( 'mysql', true );
		$inserted = $wpdb->insert(
			Floppy_Schema::table( 'file_versions' ),
			array(
				'version_uuid'     => wp_generate_uuid4(),
				'file_id'          => (int) $row['id'],
				'file_uuid'        => (string) $row['uuid'],
				'owner_id'         => (int) $row['owner_id'],
				'name'             => (string) $row['name'],
				'mime_type'        => (string) $row['mime_type'],
				'size_bytes'       => (int) $row['size_bytes'],
				'content_hash'     => (string) $row['content_hash'],
				'storage_key'      => (string) $row['storage_key'],
				'content_version'  => (string) $row['content_version'],
				'metadata_version' => (string) $row['metadata_version'],
				'reason'           => sanitize_key( $reason ),
				'created_by'       => $actor_id,
				'created_at_gmt'   => $now,
			),
			array( '%s', '%d', '%s', '%d', '%s', '%s', '%d', '%s', '%s', '%s', '%s', '%s', '%d', '%s' )
		);
		if ( ! $inserted ) {
			return false;
		}

		$version_id = (int) $wpdb->insert_id;
		if ( $prune ) {
			self::prune_file_versions( (int) $row['id'] );
		}

		return $version_id;
	}

	/**
	 * Keep retained file versions inside the configured per-file limit.
	 *
	 * @param array<int> $keep_ids Version row ids that must not be pruned.
	 */
	private static function prune_file_versions( int $file_id, array $keep_ids = array() ): void {
		global $wpdb;

		$retention_limit = (int) Floppy_Settings::get_value( 'version_retention_limit', 10 );
		if ( $retention_limit <= 0 ) {
			return;
		}

		$rows = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT id, storage_key FROM ' . Floppy_Schema::table( 'file_versions' ) . ' WHERE file_id = %d ORDER BY id DESC',
				$file_id
			),
			ARRAY_A
		);
		$seen = 0;
		foreach ( $rows as $row ) {
			$id = (int) $row['id'];
			if ( in_array( $id, $keep_ids, true ) ) {
				continue;
			}

			++$seen;
			if ( $seen <= $retention_limit ) {
				continue;
			}

			$storage_key = (string) $row['storage_key'];
			$wpdb->delete( Floppy_Schema::table( 'file_versions' ), array( 'id' => $id ), array( '%d' ) );
			if ( ! self::storage_key_is_referenced( $storage_key ) ) {
				@unlink( Floppy_Storage::path_for_key( $storage_key ) ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			}
		}
	}

	/**
	 * Check if a private blob key is still referenced by active metadata.
	 */
	private static function storage_key_is_referenced( string $storage_key ): bool {
		if ( '' === $storage_key ) {
			return false;
		}

		global $wpdb;
		$count = (int) $wpdb->get_var(
			$wpdb->prepare(
				'SELECT (
					(SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'files' ) . ' WHERE storage_key = %s) +
					(SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'file_versions' ) . ' WHERE storage_key = %s) +
					(SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'upload_sessions' ) . ' WHERE storage_key = %s) +
					(SELECT COUNT(*) FROM ' . Floppy_Schema::table( 'thumbnails' ) . ' WHERE storage_key = %s)
				)',
				$storage_key,
				$storage_key,
				$storage_key,
				$storage_key
			)
		);

		return $count > 0;
	}

	/**
	 * Return an existing ready thumbnail for a file row.
	 */
	private static function get_ready_thumbnail( array $row ) {
		global $wpdb;

		$thumb = $wpdb->get_row(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'thumbnails' ) . " WHERE file_id = %d AND content_version = %s AND status = 'ready' LIMIT 1",
				(int) $row['id'],
				(string) $row['content_version']
			),
			ARRAY_A
		);
		if ( ! $thumb || empty( $thumb['storage_key'] ) || ! is_readable( Floppy_Storage::path_for_key( (string) $thumb['storage_key'] ) ) ) {
			return false;
		}

		return $thumb;
	}

	/**
	 * Generate a private thumbnail for an image file.
	 */
	private static function generate_thumbnail_for_file( array $row ) {
		global $wpdb;

		if ( 0 !== strpos( (string) $row['mime_type'], 'image/' ) ) {
			return new WP_Error( 'floppy_thumbnail_not_available', __( 'Thumbnails are available for image files only.', 'floppy' ), array( 'status' => 415 ) );
		}

		$source_path = Floppy_Storage::path_for_key( (string) $row['storage_key'] );
		if ( ! is_readable( $source_path ) ) {
			return new WP_Error( 'floppy_blob_missing', __( 'The private blob is missing from storage.', 'floppy' ), array( 'status' => 500 ) );
		}

		require_once ABSPATH . 'wp-admin/includes/image.php';

		$editor = wp_get_image_editor( $source_path );
		if ( is_wp_error( $editor ) ) {
			self::upsert_thumbnail_state( $row, 'failed', '', 0, 0, 0, $editor->get_error_message() );
			return $editor;
		}

		$max_edge = (int) Floppy_Settings::get_value( 'thumbnail_max_edge', 512 );
		$editor->resize( $max_edge, $max_edge, false );
		if ( method_exists( $editor, 'set_quality' ) ) {
			$editor->set_quality( 82 );
		}

		$thumb_uuid = wp_generate_uuid4();
		$thumb_key = 'thumbnails/' . Floppy_Storage::storage_key( $thumb_uuid, 'jpg' );
		$thumb_path = Floppy_Storage::path_for_key( $thumb_key );
		if ( ! wp_mkdir_p( dirname( $thumb_path ) ) ) {
			return new WP_Error( 'floppy_thumbnail_storage_failed', __( 'Could not create thumbnail storage.', 'floppy' ), array( 'status' => 500 ) );
		}

		$saved = $editor->save( $thumb_path, 'image/jpeg' );
		if ( is_wp_error( $saved ) ) {
			self::upsert_thumbnail_state( $row, 'failed', '', 0, 0, 0, $saved->get_error_message() );
			return $saved;
		}
		@chmod( $thumb_path, 0640 ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged

		$size = getimagesize( $thumb_path );
		$thumb = self::upsert_thumbnail_state(
			$row,
			'ready',
			$thumb_key,
			is_array( $size ) ? (int) $size[0] : 0,
			is_array( $size ) ? (int) $size[1] : 0,
			(int) filesize( $thumb_path ),
			''
		);
		Floppy_Audit::log( 'thumbnail.generated', 'file', (int) $row['id'], (string) $row['name'] );

		return $thumb;
	}

	/**
	 * Insert or update thumbnail metadata.
	 */
	private static function upsert_thumbnail_state( array $row, string $status, string $storage_key, int $width, int $height, int $size_bytes, string $error_message ) {
		global $wpdb;

		$existing = $wpdb->get_row(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'thumbnails' ) . ' WHERE file_id = %d AND content_version = %s LIMIT 1',
				(int) $row['id'],
				(string) $row['content_version']
			),
			ARRAY_A
		);
		$now = current_time( 'mysql', true );
		$data = array(
			'file_id'         => (int) $row['id'],
			'file_uuid'       => (string) $row['uuid'],
			'content_version' => (string) $row['content_version'],
			'status'          => $status,
			'storage_key'     => $storage_key,
			'mime_type'       => 'image/jpeg',
			'width'           => $width,
			'height'          => $height,
			'size_bytes'      => $size_bytes,
			'source_hash'     => (string) $row['content_hash'],
			'error_message'   => $error_message,
			'updated_at_gmt'  => $now,
		);

		if ( $existing ) {
			$wpdb->update(
				Floppy_Schema::table( 'thumbnails' ),
				$data,
				array( 'id' => (int) $existing['id'] ),
				array( '%d', '%s', '%s', '%s', '%s', '%s', '%d', '%d', '%d', '%s', '%s', '%s' ),
				array( '%d' )
			);
			if ( ! empty( $existing['storage_key'] ) && $existing['storage_key'] !== $storage_key && ! self::storage_key_is_referenced( (string) $existing['storage_key'] ) ) {
				@unlink( Floppy_Storage::path_for_key( (string) $existing['storage_key'] ) ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			}
		} else {
			$data['created_at_gmt'] = $now;
			$wpdb->insert(
				Floppy_Schema::table( 'thumbnails' ),
				$data,
				array( '%d', '%s', '%s', '%s', '%s', '%s', '%d', '%d', '%d', '%s', '%s', '%s', '%s' )
			);
		}

		return $wpdb->get_row(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'thumbnails' ) . ' WHERE file_id = %d AND content_version = %s LIMIT 1',
				(int) $row['id'],
				(string) $row['content_version']
			),
			ARRAY_A
		);
	}

	/**
	 * Stream a generated thumbnail.
	 */
	private static function stream_thumbnail( array $thumbnail, array $file ): void {
		$path = Floppy_Storage::path_for_key( (string) $thumbnail['storage_key'] );
		if ( ! is_readable( $path ) ) {
			status_header( 500 );
			return;
		}

		Floppy_Audit::log( 'thumbnail.viewed', 'file', (int) $file['id'], (string) $file['name'] );

		nocache_headers();
		header( 'Cache-Control: private, no-store, max-age=0' );
		header( 'X-Content-Type-Options: nosniff' );
		header( 'Content-Type: image/jpeg' );
		header( 'Content-Disposition: inline; filename="' . str_replace( '"', '', (string) $file['name'] ) . '.jpg"' );
		header( 'Content-Length: ' . filesize( $path ) );
		readfile( $path ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_readfile,WordPress.Security.EscapeOutput.OutputNotEscaped
	}

	/**
	 * Resolve a parent folder id to its stable UUID.
	 */
	public static function parent_uuid_for( int $parent_id ): string {
		return Floppy_Rest_Serializer::parent_uuid_for( $parent_id );
	}
}
