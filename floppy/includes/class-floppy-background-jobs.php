<?php
/**
 * Background job runner.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Cron-backed job queue for maintenance tasks.
 */
final class Floppy_Background_Jobs {
	public const HOOK = 'floppy_run_background_jobs';
	public const DAILY_HOOK = 'floppy_daily_maintenance';

	/**
	 * Register hooks.
	 */
	public static function init(): void {
		add_action( self::HOOK, array( __CLASS__, 'run_due_jobs' ) );
		add_action( self::DAILY_HOOK, array( __CLASS__, 'daily_maintenance' ) );
	}

	/**
	 * Schedule recurring jobs.
	 */
	public static function schedule(): void {
		if ( ! wp_next_scheduled( self::HOOK ) ) {
			wp_schedule_event( time() + MINUTE_IN_SECONDS, 'hourly', self::HOOK );
		}
		if ( ! wp_next_scheduled( self::DAILY_HOOK ) ) {
			wp_schedule_event( time() + HOUR_IN_SECONDS, 'daily', self::DAILY_HOOK );
		}
	}

	/**
	 * Unschedule jobs.
	 */
	public static function unschedule(): void {
		wp_clear_scheduled_hook( self::HOOK );
		wp_clear_scheduled_hook( self::DAILY_HOOK );
	}

	/**
	 * Enqueue a job.
	 */
	public static function enqueue( string $job_type, array $payload = array(), int $priority = 5, int $delay = 0 ) {
		global $wpdb;
		$uuid = wp_generate_uuid4();

		$inserted = $wpdb->insert(
			Floppy_Schema::table( 'jobs' ),
			array(
				'job_uuid'       => $uuid,
				'job_type'       => sanitize_key( $job_type ),
				'status'         => 'queued',
				'priority'       => max( 0, min( 9, $priority ) ),
				'not_before_gmt' => gmdate( 'Y-m-d H:i:s', time() + $delay ),
				'payload_json'   => wp_json_encode( $payload ),
				'created_at_gmt' => current_time( 'mysql', true ),
				'updated_at_gmt' => current_time( 'mysql', true ),
			),
			array( '%s', '%s', '%s', '%d', '%s', '%s', '%s', '%s' )
		);

		if ( ! $inserted ) {
			return new WP_Error( 'floppy_job_enqueue_failed', __( 'Could not enqueue Floppy background job.', 'floppy' ) );
		}

		return array(
			'id'       => (int) $wpdb->insert_id,
			'job_uuid' => $uuid,
		);
	}

	/**
	 * Fetch one job by UUID for status/download endpoints.
	 */
	public static function get_job( string $job_uuid ) {
		global $wpdb;

		$job = $wpdb->get_row(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'jobs' ) . ' WHERE job_uuid = %s LIMIT 1',
				$job_uuid
			),
			ARRAY_A
		);

		return $job ?: new WP_Error( 'floppy_job_not_found', __( 'Floppy job not found.', 'floppy' ), array( 'status' => 404 ) );
	}

	/**
	 * Run due jobs.
	 */
	public static function run_due_jobs(): void {
		global $wpdb;

		$jobs = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'jobs' ) . " WHERE status IN ('queued','running') AND (status = 'queued' OR locked_at_gmt < %s) AND not_before_gmt <= %s ORDER BY priority ASC, id ASC LIMIT 10",
				gmdate( 'Y-m-d H:i:s', time() - 15 * MINUTE_IN_SECONDS ),
				current_time( 'mysql', true )
			),
			ARRAY_A
		);

		foreach ( $jobs as $job ) {
			$claimed = self::claim_job( $job );
			if ( $claimed ) {
				self::run_job( $claimed );
			}
		}
	}

	/**
	 * Daily maintenance.
	 */
	public static function daily_maintenance(): void {
		self::cleanup_expired_upload_sessions();
		self::compact_sync_events();
		Floppy_Storage::direct_access_probe();
		update_option( 'floppy_compatibility', Floppy_Compatibility::run_checks(), false );
	}

	/**
	 * Process one job.
	 */
	private static function claim_job( array $job ) {
		global $wpdb;

		$updated = $wpdb->query(
			$wpdb->prepare(
				'UPDATE ' . Floppy_Schema::table( 'jobs' ) . " SET status = 'running', locked_at_gmt = %s, attempts = attempts + 1, updated_at_gmt = %s WHERE id = %d AND (status = 'queued' OR (status = 'running' AND locked_at_gmt < %s))",
				current_time( 'mysql', true ),
				current_time( 'mysql', true ),
				(int) $job['id'],
				gmdate( 'Y-m-d H:i:s', time() - 15 * MINUTE_IN_SECONDS )
			)
		);

		if ( 1 !== $updated ) {
			return false;
		}

		return $wpdb->get_row(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'jobs' ) . ' WHERE id = %d LIMIT 1',
				(int) $job['id']
			),
			ARRAY_A
		);
	}

	/**
	 * Process one claimed job.
	 */
	private static function run_job( array $job ): void {
		global $wpdb;

		$result = array( 'ok' => true, 'message' => 'noop' );
		if ( 'storage_probe' === $job['job_type'] ) {
			$result = Floppy_Storage::direct_access_probe();
		} elseif ( 'export' === $job['job_type'] ) {
			$result = self::run_export_job( $job );
		} elseif ( 'folder_tree_status' === $job['job_type'] ) {
			$payload = json_decode( (string) $job['payload_json'], true );
			$result = is_array( $payload ) ? Floppy_Rest::run_folder_tree_status_job( $payload ) : array( 'ok' => false, 'message' => 'Invalid folder job payload.' );
		} elseif ( 'thumbnail_generate' === $job['job_type'] ) {
			$payload = json_decode( (string) $job['payload_json'], true );
			$result = is_array( $payload ) ? Floppy_Rest::run_thumbnail_job( $payload ) : array( 'ok' => false, 'message' => 'Invalid thumbnail job payload.' );
		}

		$status = empty( $result['ok'] ) ? ( (int) $job['attempts'] >= 3 ? 'failed' : 'queued' ) : 'complete';
		$delay = empty( $result['ok'] ) && 'queued' === $status ? 10 * MINUTE_IN_SECONDS : 0;
		$wpdb->update(
			Floppy_Schema::table( 'jobs' ),
			array(
				'status'         => $status,
				'locked_at_gmt'  => null,
				'not_before_gmt' => gmdate( 'Y-m-d H:i:s', time() + $delay ),
				'result_json'    => wp_json_encode( $result ),
				'updated_at_gmt' => current_time( 'mysql', true ),
			),
			array( 'id' => (int) $job['id'] ),
			array( '%s', '%s', '%s', '%s', '%s' ),
			array( '%d' )
		);
	}

	/**
	 * Build a metadata export manifest for the requesting user.
	 */
	private static function run_export_job( array $job ): array {
		global $wpdb;

		$payload = json_decode( (string) $job['payload_json'], true );
		$user_id = (int) ( is_array( $payload ) ? ( $payload['user_id'] ?? 0 ) : 0 );
		if ( $user_id <= 0 ) {
			return array( 'ok' => false, 'message' => 'Export job is missing user_id.' );
		}

		$files = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT id, uuid, parent_id, name, mime_type, size_bytes, content_hash, content_version, metadata_version, status, created_at_gmt, updated_at_gmt FROM ' . Floppy_Schema::table( 'files' ) . " WHERE owner_id = %d AND status != 'deleted' ORDER BY id ASC",
				$user_id
			),
			ARRAY_A
		);
		$folders = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT id, uuid, parent_id, name, metadata_version, status, created_at_gmt, updated_at_gmt FROM ' . Floppy_Schema::table( 'folders' ) . " WHERE owner_id = %d AND status != 'deleted' ORDER BY id ASC",
				$user_id
			),
			ARRAY_A
		);
		foreach ( $folders as &$folder ) {
			$folder['parent_uuid'] = Floppy_Rest::parent_uuid_for( (int) $folder['parent_id'] );
		}
		unset( $folder );
		foreach ( $files as &$file ) {
			$file['parent_uuid'] = Floppy_Rest::parent_uuid_for( (int) $file['parent_id'] );
			$file['download_url'] = rest_url( Floppy_Rest::NAMESPACE . '/files/' . (int) $file['id'] . '/download' );
		}
		unset( $file );

		$root = Floppy_Storage::ensure_private_root();
		if ( empty( $root['ok'] ) ) {
			return $root;
		}

		$storage = Floppy_Storage::root();
		$export_key = 'exports/' . $job['job_uuid'] . '.json';
		$export_path = Floppy_Storage::path_for_key( $export_key );
		if ( ! wp_mkdir_p( dirname( $export_path ) ) ) {
			return array( 'ok' => false, 'message' => 'Could not create export directory.' );
		}

		$manifest = array(
			'format'         => 'floppy-export-manifest-v1',
			'created_at_gmt' => current_time( 'mysql', true ),
			'user_id'        => $user_id,
			'folders'        => $folders,
			'files'          => $files,
		);
		file_put_contents( $export_path, wp_json_encode( $manifest, JSON_PRETTY_PRINT ) ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_file_put_contents
		@chmod( $export_path, 0640 ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged

		return array(
			'ok'         => true,
			'message'    => 'Export manifest created.',
			'export_key' => $export_key,
			'files'      => count( $files ),
			'folders'    => count( $folders ),
		);
	}

	/**
	 * Remove expired upload session rows.
	 */
	private static function cleanup_expired_upload_sessions(): void {
		global $wpdb;

		$expired = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT id, storage_key FROM ' . Floppy_Schema::table( 'upload_sessions' ) . " WHERE status IN ('open','failed') AND expires_at_gmt < %s LIMIT 500",
				current_time( 'mysql', true )
			),
			ARRAY_A
		);

		foreach ( $expired as $session ) {
			if ( ! empty( $session['storage_key'] ) ) {
				@unlink( Floppy_Storage::path_for_key( $session['storage_key'] ) ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged
			}
		}

		$wpdb->query(
			$wpdb->prepare(
				'DELETE FROM ' . Floppy_Schema::table( 'upload_sessions' ) . " WHERE status IN ('open','failed') AND expires_at_gmt < %s",
				current_time( 'mysql', true )
			)
		);
	}

	/**
	 * Compact event feed past the retention window.
	 */
	private static function compact_sync_events(): void {
		global $wpdb;

		$days = (int) Floppy_Settings::get_value( 'sync_retention_days', 45 );
		$cutoff = gmdate( 'Y-m-d H:i:s', time() - ( DAY_IN_SECONDS * $days ) );
		$oldest_active_cursor = (int) $wpdb->get_var( "SELECT MIN(last_cursor) FROM " . Floppy_Schema::table( 'devices' ) . " WHERE status = 'active' AND last_seen_at_gmt IS NOT NULL" ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared

		if ( $oldest_active_cursor > 0 ) {
			$wpdb->query(
				$wpdb->prepare(
					'DELETE FROM ' . Floppy_Schema::table( 'sync_events' ) . ' WHERE created_at_gmt < %s AND seq < %d',
					$cutoff,
					$oldest_active_cursor
				)
			);
		}
	}
}
