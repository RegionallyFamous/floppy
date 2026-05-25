<?php
/**
 * Plugin Name: Floppy
 * Plugin URI: https://github.com/RegionallyFamous/floppy
 * Description: Private, WordPress-owned file storage for Desktop Mode and Finder-native sync.
 * Version: 0.1.1
 * Requires at least: 7.0
 * Requires PHP: 8.3
 * Requires Plugins: desktop-mode
 * Author: Floppy Contributors
 * License: GPL-2.0-or-later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: floppy
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

define( 'FLOPPY_VERSION', '0.1.1' );
define( 'FLOPPY_DB_VERSION', '2026052302' );
define( 'FLOPPY_FILE', __FILE__ );
define( 'FLOPPY_DIR', plugin_dir_path( __FILE__ ) );
define( 'FLOPPY_URL', plugin_dir_url( __FILE__ ) );

require_once FLOPPY_DIR . 'includes/class-floppy-plugin.php';

register_activation_hook( __FILE__, array( 'Floppy_Plugin', 'activate' ) );
register_deactivation_hook( __FILE__, array( 'Floppy_Plugin', 'deactivate' ) );

add_action(
	'plugins_loaded',
	static function () {
		Floppy_Plugin::instance()->init();
	}
);
