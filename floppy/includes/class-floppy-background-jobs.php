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

		$inserted = $wpdb->insert(
			Floppy_Schema::table( 'jobs' ),
			array(
				'job_uuid'       => wp_generate_uuid4(),
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

		return (int) $wpdb->insert_id;
	}

	/**
	 * Run due jobs.
	 */
	public static function run_due_jobs(): void {
		global $wpdb;

		$jobs = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'jobs' ) . " WHERE status = 'queued' AND not_before_gmt <= %s ORDER BY priority ASC, id ASC LIMIT 10",
				current_time( 'mysql', true )
			),
			ARRAY_A
		);

		foreach ( $jobs as $job ) {
			self::run_job( $job );
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
	private static function run_job( array $job ): void {
		global $wpdb;

		$wpdb->update(
			Floppy_Schema::table( 'jobs' ),
			array(
				'status'        => 'running',
				'locked_at_gmt' => current_time( 'mysql', true ),
				'attempts'      => (int) $job['attempts'] + 1,
				'updated_at_gmt' => current_time( 'mysql', true ),
			),
			array( 'id' => (int) $job['id'] ),
			array( '%s', '%s', '%d', '%s' ),
			array( '%d' )
		);

		$result = array( 'ok' => true, 'message' => 'noop' );
		if ( 'storage_probe' === $job['job_type'] ) {
			$result = Floppy_Storage::direct_access_probe();
		}

		$wpdb->update(
			Floppy_Schema::table( 'jobs' ),
			array(
				'status'        => empty( $result['ok'] ) ? 'failed' : 'complete',
				'result_json'   => wp_json_encode( $result ),
				'updated_at_gmt' => current_time( 'mysql', true ),
			),
			array( 'id' => (int) $job['id'] ),
			array( '%s', '%s', '%s' ),
			array( '%d' )
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

		$wpdb->query(
			$wpdb->prepare(
				'DELETE FROM ' . Floppy_Schema::table( 'sync_events' ) . ' WHERE created_at_gmt < %s',
				$cutoff
			)
		);
	}
}
