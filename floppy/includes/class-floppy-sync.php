<?php
/**
 * Sync event feed.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Append-only sync event helpers.
 */
final class Floppy_Sync {
	/**
	 * Append a sync event.
	 */
	public static function append_event( string $event_type, string $target_type, int $target_id, array $payload = array(), int $actor_id = 0 ): int {
		global $wpdb;

		$actor_id = $actor_id ?: get_current_user_id();
		$payload  = self::normalize_payload( $payload );

		$wpdb->insert(
			Floppy_Schema::table( 'sync_events' ),
			array(
				'event_uuid'       => wp_generate_uuid4(),
				'actor_id'         => $actor_id,
				'target_type'      => sanitize_key( $target_type ),
				'target_id'        => $target_id,
				'event_type'       => self::sanitize_event_type( $event_type ),
				'parent_id'        => (int) ( $payload['parent_id'] ?? 0 ),
				'metadata_version' => (string) ( $payload['metadata_version'] ?? '' ),
				'content_version'  => (string) ( $payload['content_version'] ?? '' ),
				'payload_json'     => wp_json_encode( $payload ),
				'created_at_gmt'   => current_time( 'mysql', true ),
			),
			array( '%s', '%d', '%s', '%d', '%s', '%d', '%s', '%s', '%s', '%s' )
		);

		return (int) $wpdb->insert_id;
	}

	/**
	 * Get events after a cursor for a user.
	 */
	public static function get_changes( int $cursor, int $limit, int $user_id ) {
		global $wpdb;

		$limit = max( 1, min( 500, $limit ) );
		$min_cursor = self::oldest_cursor();
		if ( $cursor > 0 && $min_cursor > 0 && $cursor < $min_cursor ) {
			return new WP_Error(
				'floppy_sync_anchor_expired',
				__( 'The sync cursor has expired. A full re-enumeration is required.', 'floppy' ),
				array(
					'status'                => 410,
					'min_cursor'            => $min_cursor,
					'full_resync_required'  => true,
					'client_recovery_hint'  => 'reenumerate',
				)
			);
		}

		$rows = $wpdb->get_results(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'sync_events' ) . ' WHERE seq > %d ORDER BY seq ASC LIMIT %d',
				$cursor,
				$limit + 1
			),
			ARRAY_A
		);

		$has_more = count( $rows ) > $limit;
		if ( $has_more ) {
			array_pop( $rows );
		}

		$events = array();
		foreach ( $rows as $row ) {
			if ( self::event_visible_to_user( $row, $user_id ) ) {
				$events[] = self::serialize_event( $row );
			}
		}

		$next_cursor = $cursor;
		if ( ! empty( $rows ) ) {
			$last = end( $rows );
			$next_cursor = (int) $last['seq'];
		}

		if ( ! empty( $GLOBALS['floppy_device_id'] ) ) {
			$wpdb->update(
				Floppy_Schema::table( 'devices' ),
				array(
					'last_cursor'      => $next_cursor,
					'last_sync_at_gmt' => current_time( 'mysql', true ),
				),
				array( 'id' => (int) $GLOBALS['floppy_device_id'] ),
				array( '%d', '%s' ),
				array( '%d' )
			);
		}

		return array(
			'cursor'      => $cursor,
			'next_cursor' => $next_cursor,
			'has_more'    => $has_more,
			'events'      => $events,
		);
	}

	/**
	 * Create a tombstone for delayed deletes.
	 */
	public static function tombstone( string $target_type, int $target_id, int $owner_id, int $sync_seq, string $reason = 'deleted' ): void {
		global $wpdb;

		$days = (int) Floppy_Settings::get_value( 'tombstone_retention_days', 90 );
		$wpdb->replace(
			Floppy_Schema::table( 'tombstones' ),
			array(
				'target_type'    => sanitize_key( $target_type ),
				'target_id'      => $target_id,
				'owner_id'       => $owner_id,
				'sync_seq'       => $sync_seq,
				'reason'         => sanitize_key( $reason ),
				'created_at_gmt' => current_time( 'mysql', true ),
				'expires_at_gmt' => gmdate( 'Y-m-d H:i:s', time() + ( DAY_IN_SECONDS * $days ) ),
			),
			array( '%s', '%d', '%d', '%d', '%s', '%s', '%s' )
		);
	}

	/**
	 * Return oldest retained event cursor.
	 */
	private static function oldest_cursor(): int {
		global $wpdb;

		return (int) $wpdb->get_var( 'SELECT MIN(seq) FROM ' . Floppy_Schema::table( 'sync_events' ) ); // phpcs:ignore WordPress.DB.PreparedSQL.NotPrepared
	}

	/**
	 * Determine event visibility.
	 */
	private static function event_visible_to_user( array $event, int $user_id ): bool {
		if ( user_can( $user_id, 'manage_options' ) || (int) $event['actor_id'] === $user_id ) {
			return true;
		}

		$payload = json_decode( (string) $event['payload_json'], true );
		if ( is_array( $payload ) && self::payload_audience_includes_user( $payload, $user_id ) ) {
			return true;
		}

		if ( in_array( $event['target_type'], array( 'file', 'folder' ), true ) ) {
			return Floppy_Permissions::can_read( $event['target_type'], (int) $event['target_id'], $user_id );
		}

		return false;
	}

	/**
	 * Check event payload audience snapshots.
	 */
	private static function payload_audience_includes_user( array $payload, int $user_id ): bool {
		$user_ids = array_map( 'intval', (array) ( $payload['audience_user_ids'] ?? array() ) );
		if ( in_array( $user_id, $user_ids, true ) ) {
			return true;
		}

		$user = get_userdata( $user_id );
		if ( ! $user ) {
			return false;
		}

		$roles = (array) ( $payload['audience_roles'] ?? array() );
		foreach ( (array) $user->roles as $role ) {
			if ( in_array( $role, $roles, true ) ) {
				return true;
			}
		}

		$principal_type = (string) ( $payload['principal_type'] ?? '' );
		$principal_ref  = (string) ( $payload['principal_ref'] ?? '' );
		if ( 'user' === $principal_type && (string) $user_id === $principal_ref ) {
			return true;
		}
		if ( 'role' === $principal_type && in_array( $principal_ref, (array) $user->roles, true ) ) {
			return true;
		}

		return false;
	}

	/**
	 * Serialize an event.
	 */
	private static function serialize_event( array $row ): array {
		$payload = json_decode( (string) $row['payload_json'], true );
		if ( ! is_array( $payload ) ) {
			$payload = array();
		}

		return array(
			'seq'              => (int) $row['seq'],
			'event_uuid'       => $row['event_uuid'],
			'event_type'       => $row['event_type'],
			'target_type'      => $row['target_type'],
			'target_id'        => (int) $row['target_id'],
			'parent_id'        => (int) $row['parent_id'],
			'metadata_version' => $row['metadata_version'],
			'content_version'  => $row['content_version'],
			'created_at_gmt'   => $row['created_at_gmt'],
			'payload'          => self::sanitize_payload_for_client( $payload, $row ),
		);
	}

	/**
	 * Keep sync payloads useful to clients without exposing storage internals.
	 */
	private static function sanitize_payload_for_client( array $payload, array $event ): array {
		foreach ( array( 'storage_key', 'path', 'deleted_at_gmt', 'last_sync_seq', 'audience_user_ids', 'audience_roles' ) as $private_key ) {
			unset( $payload[ $private_key ] );
		}

		if ( in_array( $event['target_type'], array( 'file', 'folder' ), true ) && isset( $payload['uuid'], $payload['name'] ) ) {
			$item = array(
				'kind'             => $event['target_type'],
				'id'               => (int) ( $payload['id'] ?? $event['target_id'] ),
				'uuid'             => (string) $payload['uuid'],
				'owner_id'         => (int) ( $payload['owner_id'] ?? 0 ),
				'parent_id'        => (int) ( $payload['parent_id'] ?? 0 ),
				'parent_uuid'      => (string) ( $payload['parent_uuid'] ?? Floppy_Rest::parent_uuid_for( (int) ( $payload['parent_id'] ?? 0 ) ) ),
				'name'             => (string) $payload['name'],
				'metadata_version' => (string) ( $payload['metadata_version'] ?? '' ),
				'status'           => (string) ( $payload['status'] ?? 'active' ),
				'created_at_gmt'   => (string) ( $payload['created_at_gmt'] ?? '' ),
				'updated_at_gmt'   => (string) ( $payload['updated_at_gmt'] ?? '' ),
			);

			if ( 'file' === $event['target_type'] ) {
				$item['attachment_id'] = (int) ( $payload['attachment_id'] ?? 0 );
				$item['mime_type'] = (string) ( $payload['mime_type'] ?? '' );
				$item['size_bytes'] = (int) ( $payload['size_bytes'] ?? 0 );
				$item['content_hash'] = (string) ( $payload['content_hash'] ?? '' );
				$item['content_version'] = (string) ( $payload['content_version'] ?? '' );
				$item['visibility'] = (string) ( $payload['visibility'] ?? 'private' );
				$item['download_url'] = rest_url( Floppy_Rest::NAMESPACE . '/files/' . (int) $item['id'] . '/download' );
			}

			return $item;
		}

		$allowed = array( 'target_type', 'target_id', 'principal_type', 'principal_ref', 'capability', 'uuid', 'parent_uuid', 'reason' );
		return array_intersect_key( $payload, array_fill_keys( $allowed, true ) );
	}

	/**
	 * Normalize payload to a JSON-safe associative array.
	 */
	private static function normalize_payload( array $payload ): array {
		return json_decode( wp_json_encode( $payload ), true ) ?: array();
	}

	/**
	 * Preserve dotted event names while keeping the value machine-safe.
	 */
	private static function sanitize_event_type( string $event_type ): string {
		return preg_replace( '/[^a-z0-9_.-]/', '', strtolower( $event_type ) ) ?: 'event';
	}
}
