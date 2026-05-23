<?php
/**
 * REST request argument schemas.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Small, reusable REST argument definitions.
 */
final class Floppy_Rest_Arguments {
	/**
	 * File/folder collection query args.
	 */
	public static function collection(): array {
		return array(
			'parent_id' => array(
				'type'              => 'integer',
				'default'           => 0,
				'minimum'           => 0,
				'sanitize_callback' => 'absint',
			),
			'after_id'  => array(
				'type'              => 'integer',
				'default'           => 0,
				'minimum'           => 0,
				'sanitize_callback' => 'absint',
			),
			'cursor'    => array(
				'type'              => 'string',
				'default'           => '',
				'pattern'           => '^(folder|file):[0-9]+$|^$',
				'sanitize_callback' => 'sanitize_text_field',
			),
			'shared'    => array(
				'type'              => 'boolean',
				'default'           => false,
				'sanitize_callback' => 'rest_sanitize_boolean',
			),
			'limit'     => array(
				'type'              => 'integer',
				'default'           => 50,
				'minimum'           => 1,
				'maximum'           => 100,
				'sanitize_callback' => 'absint',
			),
		);
	}

	/**
	 * Search query args.
	 */
	public static function search(): array {
		return array(
			'q'        => array(
				'type'              => 'string',
				'required'          => false,
				'default'           => '',
				'sanitize_callback' => 'sanitize_text_field',
			),
			'limit'    => array(
				'type'              => 'integer',
				'default'           => 50,
				'minimum'           => 1,
				'maximum'           => 100,
				'sanitize_callback' => 'absint',
			),
			'after_id' => array(
				'type'              => 'integer',
				'default'           => 0,
				'minimum'           => 0,
				'sanitize_callback' => 'absint',
			),
		);
	}

	/**
	 * Standard numeric target id arg.
	 */
	public static function id(): array {
		return array( 'id' => array( 'sanitize_callback' => 'absint' ) );
	}
}
