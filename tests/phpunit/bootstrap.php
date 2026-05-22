<?php
/**
 * WordPress PHPUnit bootstrap for Floppy.
 *
 * @package Floppy
 */

$_tests_dir = getenv( 'WP_TESTS_DIR' );
if ( ! $_tests_dir ) {
	$_tests_dir = '/tmp/wordpress-tests-lib';
}

require_once $_tests_dir . '/includes/functions.php';

tests_add_filter(
	'muplugins_loaded',
	static function (): void {
		require dirname( __DIR__, 2 ) . '/floppy/floppy.php';
	}
);

require $_tests_dir . '/includes/bootstrap.php';
