<?php
/**
 * Plugin metadata tests.
 *
 * @package Floppy
 */

/**
 * @coversNothing
 */
final class Floppy_Plugin_Metadata_Test extends WP_UnitTestCase {
	/**
	 * Floppy declares Desktop Mode as a native WordPress plugin dependency.
	 */
	public function test_plugin_header_requires_desktop_mode(): void {
		require_once ABSPATH . 'wp-admin/includes/plugin.php';

		$data = get_plugin_data( FLOPPY_FILE, false, false );

		$this->assertSame( 'desktop-mode', $data['RequiresPlugins'] ?? '' );
	}

	/**
	 * Floppy treats missing Desktop Mode as a failed readiness check.
	 */
	public function test_compatibility_check_fails_without_desktop_mode(): void {
		if ( function_exists( 'desktop_mode_register_window' ) ) {
			$this->markTestSkipped( 'Desktop Mode is loaded in this test environment.' );
		}

		update_option( 'floppy_private_probe', array( 'ok' => true, 'status' => 'pass', 'message' => 'test' ), false );

		$checks = Floppy_Compatibility::run_checks();

		$this->assertArrayHasKey( 'desktop_mode', $checks );
		$this->assertFalse( $checks['desktop_mode']['ok'] );
		$this->assertSame( 'fail', Floppy_Compatibility::check_status( $checks['desktop_mode'] ) );
		$this->assertSame( 'Desktop Mode required', $checks['desktop_mode']['label'] );
	}
}
