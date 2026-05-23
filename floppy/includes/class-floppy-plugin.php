<?php
/**
 * Core plugin bootstrap.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

require_once FLOPPY_DIR . 'includes/class-floppy-schema.php';
require_once FLOPPY_DIR . 'includes/class-floppy-storage.php';
require_once FLOPPY_DIR . 'includes/class-floppy-settings.php';
require_once FLOPPY_DIR . 'includes/class-floppy-audit.php';
require_once FLOPPY_DIR . 'includes/class-floppy-rate-limiter.php';
require_once FLOPPY_DIR . 'includes/class-floppy-diagnostics.php';
require_once FLOPPY_DIR . 'includes/class-floppy-auth.php';
require_once FLOPPY_DIR . 'includes/class-floppy-permissions.php';
require_once FLOPPY_DIR . 'includes/class-floppy-sync.php';
require_once FLOPPY_DIR . 'includes/class-floppy-compatibility.php';
require_once FLOPPY_DIR . 'includes/class-floppy-background-jobs.php';
require_once FLOPPY_DIR . 'includes/class-floppy-rest.php';
require_once FLOPPY_DIR . 'includes/class-floppy-desktop-mode.php';
require_once FLOPPY_DIR . 'includes/class-floppy-admin.php';

if ( defined( 'WP_CLI' ) && WP_CLI ) {
	require_once FLOPPY_DIR . 'includes/class-floppy-cli.php';
}

/**
 * Main plugin object.
 */
final class Floppy_Plugin {
	/**
	 * Singleton instance.
	 *
	 * @var Floppy_Plugin|null
	 */
	private static $instance = null;

	/**
	 * Get singleton instance.
	 */
	public static function instance(): Floppy_Plugin {
		if ( null === self::$instance ) {
			self::$instance = new self();
		}

		return self::$instance;
	}

	/**
	 * Activation routine.
	 */
	public static function activate(): void {
		Floppy_Schema::install();
		Floppy_Permissions::install_capabilities();
		Floppy_Storage::ensure_private_root();
		Floppy_Background_Jobs::schedule();
		update_option( 'floppy_compatibility', Floppy_Compatibility::run_checks(), false );
	}

	/**
	 * Deactivation routine.
	 */
	public static function deactivate(): void {
		Floppy_Background_Jobs::unschedule();
	}

	/**
	 * Register plugin hooks.
	 */
	public function init(): void {
		if ( get_option( 'floppy_db_version' ) !== FLOPPY_DB_VERSION ) {
			Floppy_Schema::install();
		}
		if ( get_option( 'floppy_capabilities_version' ) !== FLOPPY_VERSION ) {
			Floppy_Permissions::install_capabilities();
		}

		Floppy_Storage::init();
		Floppy_Auth::init();
		Floppy_Background_Jobs::init();
		Floppy_Rest::init();
		Floppy_Desktop_Mode::init();
		Floppy_Admin::init();

		if ( defined( 'WP_CLI' ) && WP_CLI ) {
			Floppy_CLI::init();
		}

		add_action( 'admin_init', array( 'Floppy_Compatibility', 'maybe_refresh_checks' ) );
	}
}
