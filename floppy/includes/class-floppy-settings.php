<?php
/**
 * Settings and limits.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Provides conservative defaults with filterable limits.
 */
final class Floppy_Settings {
	/**
	 * Get plugin settings.
	 */
	public static function get(): array {
		$defaults = array(
			'max_file_size'          => min( wp_max_upload_size(), 512 * MB_IN_BYTES ),
			'max_batch_files'        => 50,
			'user_quota_bytes'       => 20 * GB_IN_BYTES,
			'site_quota_bytes'       => 0,
			'sync_retention_days'    => 45,
			'tombstone_retention_days' => 90,
			'allowed_mimes'          => array_keys( get_allowed_mime_types() ),
			'enable_desktop_mode'    => true,
		);

		$settings = get_option( 'floppy_settings', array() );
		if ( ! is_array( $settings ) ) {
			$settings = array();
		}

		/**
		 * Filter Floppy settings.
		 *
		 * @param array $settings Resolved settings.
		 */
		return apply_filters( 'floppy_settings', wp_parse_args( $settings, $defaults ) );
	}

	/**
	 * Get a single setting.
	 *
	 * @param mixed $default Default value.
	 */
	public static function get_value( string $key, $default = null ) {
		$settings = self::get();

		return array_key_exists( $key, $settings ) ? $settings[ $key ] : $default;
	}
}
