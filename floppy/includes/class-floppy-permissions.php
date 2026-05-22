<?php
/**
 * Permission checks.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Capability checks for files, folders, and shares.
 */
final class Floppy_Permissions {
	public const CAP_READ = 'floppy_read_files';
	public const CAP_WRITE = 'floppy_write_files';
	public const CAP_MANAGE = 'floppy_manage_files';

	/**
	 * Add Floppy-specific capabilities to roles that already own comparable media capabilities.
	 */
	public static function install_capabilities(): void {
		foreach ( wp_roles()->roles as $role_name => $role_data ) {
			$role = get_role( $role_name );
			if ( ! $role ) {
				continue;
			}

			$caps = (array) ( $role_data['capabilities'] ?? array() );
			if ( ! empty( $caps['manage_options'] ) ) {
				$role->add_cap( self::CAP_READ );
				$role->add_cap( self::CAP_WRITE );
				$role->add_cap( self::CAP_MANAGE );
				continue;
			}

			if ( ! empty( $caps['upload_files'] ) ) {
				$role->add_cap( self::CAP_READ );
				$role->add_cap( self::CAP_WRITE );
			}
		}

		update_option( 'floppy_capabilities_version', FLOPPY_VERSION, false );
	}

	/**
	 * Check read access.
	 */
	public static function can_read( string $target_type, int $target_id, int $user_id = 0 ): bool {
		return self::can( $target_type, $target_id, 'read', $user_id );
	}

	/**
	 * Check write access.
	 */
	public static function can_write( string $target_type, int $target_id, int $user_id = 0 ): bool {
		return self::can( $target_type, $target_id, 'write', $user_id );
	}

	/**
	 * Check a capability.
	 */
	public static function can( string $target_type, int $target_id, string $capability, int $user_id = 0 ): bool {
		$user_id = $user_id ?: get_current_user_id();
		if ( ! $user_id ) {
			return false;
		}

		if ( user_can( $user_id, 'manage_options' ) ) {
			return true;
		}

		if ( ! user_can( $user_id, self::cap_for( $capability ) ) ) {
			return false;
		}

		$row = self::get_target_row( $target_type, $target_id );
		if ( ! $row || 'deleted' === ( $row['status'] ?? '' ) ) {
			return false;
		}

		if ( (int) $row['owner_id'] === $user_id ) {
			return true;
		}

		if ( self::has_direct_grant( $target_type, $target_id, $capability, $user_id ) ) {
			return true;
		}

		$parent_id = (int) ( $row['parent_id'] ?? 0 );
		if ( $parent_id > 0 ) {
			foreach ( self::folder_ancestor_ids( $parent_id ) as $ancestor_id ) {
				if ( self::has_direct_grant( 'folder', $ancestor_id, $capability, $user_id ) ) {
					return true;
				}
			}
		}

		return false;
	}

	/**
	 * Return whether a user has Floppy's site-level read/write/manage capability.
	 */
	public static function user_can_site( int $user_id, string $capability ): bool {
		if ( user_can( $user_id, 'manage_options' ) ) {
			return true;
		}

		return user_can( $user_id, self::cap_for( $capability ) );
	}

	/**
	 * Fetch file or folder row.
	 */
	public static function get_target_row( string $target_type, int $target_id ): ?array {
		global $wpdb;

		$table = 'folder' === $target_type ? Floppy_Schema::table( 'folders' ) : Floppy_Schema::table( 'files' );
		$row = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM $table WHERE id = %d LIMIT 1", $target_id ), ARRAY_A ); // phpcs:ignore WordPress.DB.PreparedSQL.InterpolatedNotPrepared

		return $row ?: null;
	}

	/**
	 * Snapshot users/roles that should see a destructive or revocation event.
	 */
	public static function audience_for( string $target_type, int $target_id ): array {
		global $wpdb;

		$row = self::get_target_row( $target_type, $target_id );
		$user_ids = array();
		$roles = array();

		if ( $row ) {
			$user_ids[] = (int) $row['owner_id'];
		}

		$grant_targets = array( array( $target_type, $target_id ) );
		$parent_id = (int) ( $row['parent_id'] ?? 0 );
		if ( $parent_id > 0 ) {
			foreach ( self::folder_ancestor_ids( $parent_id ) as $ancestor_id ) {
				$grant_targets[] = array( 'folder', $ancestor_id );
			}
		}

		$grants = array();
		foreach ( $grant_targets as $grant_target ) {
			$grants = array_merge(
				$grants,
				$wpdb->get_results(
					$wpdb->prepare(
						'SELECT principal_type, principal_ref FROM ' . Floppy_Schema::table( 'acl_grants' ) . " WHERE target_type = %s AND target_id = %d AND state = 'accepted'",
						$grant_target[0],
						$grant_target[1]
					),
					ARRAY_A
				)
			);
		}

		foreach ( $grants as $grant ) {
			if ( 'user' === $grant['principal_type'] ) {
				$user_ids[] = (int) $grant['principal_ref'];
			} elseif ( 'role' === $grant['principal_type'] ) {
				$roles[] = (string) $grant['principal_ref'];
			}
		}

		return array(
			'audience_user_ids' => array_values( array_unique( array_filter( $user_ids ) ) ),
			'audience_roles'    => array_values( array_unique( array_filter( $roles ) ) ),
		);
	}

	/**
	 * Map a Floppy item capability to its site-level WordPress capability.
	 */
	private static function cap_for( string $capability ): string {
		if ( 'manage' === $capability ) {
			return self::CAP_MANAGE;
		}

		return 'write' === $capability ? self::CAP_WRITE : self::CAP_READ;
	}

	/**
	 * Return a folder and all its ancestors, nearest first.
	 *
	 * @return array<int, int>
	 */
	private static function folder_ancestor_ids( int $folder_id ): array {
		global $wpdb;

		$ids = array();
		$seen = array();
		while ( $folder_id > 0 && empty( $seen[ $folder_id ] ) ) {
			$ids[] = $folder_id;
			$seen[ $folder_id ] = true;
			$folder_id = (int) $wpdb->get_var(
				$wpdb->prepare(
					'SELECT parent_id FROM ' . Floppy_Schema::table( 'folders' ) . ' WHERE id = %d LIMIT 1',
					$folder_id
				)
			);
		}

		return $ids;
	}

	/**
	 * Check direct ACL grants for users or roles.
	 */
	private static function has_direct_grant( string $target_type, int $target_id, string $capability, int $user_id ): bool {
		global $wpdb;

		$user = get_userdata( $user_id );
		if ( ! $user ) {
			return false;
		}

		$allowed_caps = 'write' === $capability ? array( 'write' ) : array( 'read', 'write' );
		$placeholders = implode( ',', array_fill( 0, count( $allowed_caps ), '%s' ) );

		$user_grant = $wpdb->get_var(
			$wpdb->prepare(
				'SELECT id FROM ' . Floppy_Schema::table( 'acl_grants' ) . " WHERE target_type = %s AND target_id = %d AND principal_type = 'user' AND principal_ref = %s AND state = 'accepted' AND capability IN ($placeholders) LIMIT 1",
				array_merge( array( $target_type, $target_id, (string) $user_id ), $allowed_caps )
			)
		);

		if ( $user_grant ) {
			return true;
		}

		foreach ( (array) $user->roles as $role ) {
			$role_grant = $wpdb->get_var(
				$wpdb->prepare(
					'SELECT id FROM ' . Floppy_Schema::table( 'acl_grants' ) . " WHERE target_type = %s AND target_id = %d AND principal_type = 'role' AND principal_ref = %s AND state = 'accepted' AND capability IN ($placeholders) LIMIT 1",
					array_merge( array( $target_type, $target_id, $role ), $allowed_caps )
				)
			);

			if ( $role_grant ) {
				return true;
			}
		}

		return false;
	}
}
