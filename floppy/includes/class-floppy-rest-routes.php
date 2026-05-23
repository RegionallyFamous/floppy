<?php
/**
 * REST route map.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Registers Floppy REST endpoints without mixing route wiring into handlers.
 */
final class Floppy_Rest_Routes {
	/**
	 * Register every Floppy REST route.
	 *
	 * @param string $namespace  REST namespace.
	 * @param string $controller Endpoint controller class.
	 */
	public static function register( string $namespace, string $controller ): void {
		self::register_system_routes( $namespace, $controller );
		self::register_file_routes( $namespace, $controller );
		self::register_media_routes( $namespace, $controller );
		self::register_sync_routes( $namespace, $controller );
		self::register_device_routes( $namespace, $controller );
		self::register_export_routes( $namespace, $controller );
	}

	/**
	 * Discovery, health, maintenance, and recovery routes.
	 */
	private static function register_system_routes( string $namespace, string $controller ): void {
		self::route( $namespace, '/discovery', WP_REST_Server::READABLE, $controller, 'discovery', '__return_true' );
		self::route( $namespace, '/health', WP_REST_Server::READABLE, $controller, 'health', array( 'Floppy_Rest_Access', 'require_admin' ) );
		self::route( $namespace, '/maintenance/deep-health', WP_REST_Server::READABLE, $controller, 'deep_health', array( 'Floppy_Rest_Access', 'require_admin' ) );
		self::route( $namespace, '/maintenance/repair', WP_REST_Server::READABLE . ',' . WP_REST_Server::CREATABLE, $controller, 'maintenance_repair', array( 'Floppy_Rest_Access', 'require_admin' ) );
		self::route( $namespace, '/maintenance/doctor-jobs', WP_REST_Server::READABLE . ',' . WP_REST_Server::CREATABLE, $controller, 'maintenance_doctor_jobs', array( 'Floppy_Rest_Access', 'require_admin' ) );
		self::route( $namespace, '/maintenance/doctor-jobs/(?P<uuid>[a-f0-9-]+)', WP_REST_Server::READABLE, $controller, 'maintenance_doctor_job_status', array( 'Floppy_Rest_Access', 'require_admin' ) );
		self::route( $namespace, '/debug-bundle', WP_REST_Server::READABLE, $controller, 'debug_bundle', array( 'Floppy_Rest_Access', 'require_admin' ) );
		self::route( $namespace, '/release-evidence', WP_REST_Server::READABLE, $controller, 'release_evidence', array( 'Floppy_Rest_Access', 'require_admin' ) );
		self::route(
			$namespace,
			'/recovery',
			WP_REST_Server::READABLE,
			$controller,
			'recovery_center',
			array( 'Floppy_Rest_Access', 'require_read' ),
			array(
				'limit' => array(
					'type'              => 'integer',
					'default'           => 50,
					'minimum'           => 1,
					'maximum'           => 100,
					'sanitize_callback' => 'absint',
				),
			)
		);
	}

	/**
	 * File and folder metadata routes.
	 */
	private static function register_file_routes( string $namespace, string $controller ): void {
		self::route( $namespace, '/files', WP_REST_Server::READABLE, $controller, 'list_items', array( 'Floppy_Rest_Access', 'require_read' ), Floppy_Rest_Arguments::collection() );
		self::route( $namespace, '/search', WP_REST_Server::READABLE, $controller, 'search', array( 'Floppy_Rest_Access', 'require_read' ), Floppy_Rest_Arguments::search() );
		self::route( $namespace, '/items/(?P<uuid>[a-f0-9-]+)', WP_REST_Server::READABLE, $controller, 'get_item_by_uuid', array( 'Floppy_Rest_Access', 'require_read' ) );
		self::route( $namespace, '/folders', WP_REST_Server::CREATABLE, $controller, 'create_folder', array( 'Floppy_Rest_Access', 'require_write' ) );

		foreach ( array( 'rename', 'move', 'trash', 'restore' ) as $action ) {
			self::route( $namespace, '/folders/(?P<id>[\d]+)/' . $action, WP_REST_Server::CREATABLE, $controller, 'folder_' . $action, array( 'Floppy_Rest_Access', 'require_write' ), Floppy_Rest_Arguments::id() );
		}

		foreach ( array( 'rename', 'move', 'trash', 'restore', 'replace' ) as $action ) {
			self::route( $namespace, '/files/(?P<id>[\d]+)/' . $action, WP_REST_Server::CREATABLE, $controller, 'file_' . $action, array( 'Floppy_Rest_Access', 'require_write' ), Floppy_Rest_Arguments::id() );
		}

		self::route( $namespace, '/files/(?P<id>[\d]+)', WP_REST_Server::DELETABLE, $controller, 'delete_file', array( 'Floppy_Rest_Access', 'require_write' ), Floppy_Rest_Arguments::id() );
		self::route( $namespace, '/folders/(?P<id>[\d]+)', WP_REST_Server::DELETABLE, $controller, 'delete_folder', array( 'Floppy_Rest_Access', 'require_write' ), Floppy_Rest_Arguments::id() );
		self::routes(
			$namespace,
			'/share',
			array(
				self::endpoint( WP_REST_Server::CREATABLE, $controller, 'share_target', array( 'Floppy_Rest_Access', 'require_write' ) ),
				self::endpoint( WP_REST_Server::DELETABLE, $controller, 'unshare_target', array( 'Floppy_Rest_Access', 'require_write' ) ),
			)
		);
	}

	/**
	 * Upload, download, preview, version, thumbnail, and conflict routes.
	 */
	private static function register_media_routes( string $namespace, string $controller ): void {
		self::route( $namespace, '/upload', WP_REST_Server::CREATABLE, $controller, 'upload_file', array( 'Floppy_Rest_Access', 'require_write' ) );
		self::route( $namespace, '/upload-sessions', WP_REST_Server::CREATABLE, $controller, 'create_upload_session', array( 'Floppy_Rest_Access', 'require_write' ) );
		self::route( $namespace, '/files/(?P<id>[\d]+)/replace-sessions', WP_REST_Server::CREATABLE, $controller, 'create_replace_session', array( 'Floppy_Rest_Access', 'require_write' ), Floppy_Rest_Arguments::id() );
		self::route( $namespace, '/upload-sessions/(?P<uuid>[a-f0-9-]+)/chunk', WP_REST_Server::CREATABLE, $controller, 'append_upload_chunk', array( 'Floppy_Rest_Access', 'require_write' ) );
		self::route( $namespace, '/upload-sessions/(?P<uuid>[a-f0-9-]+)/complete', WP_REST_Server::CREATABLE, $controller, 'complete_upload_session', array( 'Floppy_Rest_Access', 'require_write' ) );
		self::route( $namespace, '/files/(?P<id>[\d]+)/download', WP_REST_Server::READABLE, $controller, 'download_file', array( 'Floppy_Rest_Access', 'require_read' ), Floppy_Rest_Arguments::id() );
		self::route( $namespace, '/files/(?P<id>[\d]+)/preview', WP_REST_Server::READABLE, $controller, 'preview_file', array( 'Floppy_Rest_Access', 'require_read' ), Floppy_Rest_Arguments::id() );
		self::routes(
			$namespace,
			'/files/(?P<id>[\d]+)/thumbnail',
			array(
				self::endpoint( WP_REST_Server::READABLE, $controller, 'thumbnail_file', array( 'Floppy_Rest_Access', 'require_read' ), Floppy_Rest_Arguments::id() ),
				self::endpoint( WP_REST_Server::CREATABLE, $controller, 'enqueue_thumbnail', array( 'Floppy_Rest_Access', 'require_read' ), Floppy_Rest_Arguments::id() ),
			)
		);
		self::route( $namespace, '/files/(?P<id>[\d]+)/versions', WP_REST_Server::READABLE, $controller, 'list_file_versions', array( 'Floppy_Rest_Access', 'require_read' ), Floppy_Rest_Arguments::id() );
		self::route(
			$namespace,
			'/files/(?P<id>[\d]+)/versions/(?P<version_id>[\d]+)/restore',
			WP_REST_Server::CREATABLE,
			$controller,
			'restore_file_version',
			array( 'Floppy_Rest_Access', 'require_write' ),
			self::file_version_args()
		);
		self::route(
			$namespace,
			'/files/(?P<id>[\d]+)/versions/(?P<version_id>[\d]+)/download',
			WP_REST_Server::READABLE,
			$controller,
			'download_file_version',
			array( 'Floppy_Rest_Access', 'require_read' ),
			self::file_version_args()
		);
		self::routes(
			$namespace,
			'/conflicts',
			array(
				self::endpoint( WP_REST_Server::READABLE, $controller, 'list_conflicts', array( 'Floppy_Rest_Access', 'require_read' ) ),
				self::endpoint( WP_REST_Server::CREATABLE, $controller, 'record_conflict', array( 'Floppy_Rest_Access', 'require_write' ) ),
			)
		);
		self::route( $namespace, '/conflicts/(?P<uuid>[a-f0-9-]+)/actions', WP_REST_Server::CREATABLE, $controller, 'conflict_action', array( 'Floppy_Rest_Access', 'require_write' ) );
		self::route( $namespace, '/conflicts/(?P<uuid>[a-f0-9-]+)/resolve', WP_REST_Server::CREATABLE, $controller, 'resolve_conflict', array( 'Floppy_Rest_Access', 'require_write' ) );
	}

	/**
	 * Sync feed routes.
	 */
	private static function register_sync_routes( string $namespace, string $controller ): void {
		self::route( $namespace, '/sync/changes', WP_REST_Server::READABLE, $controller, 'sync_changes', array( 'Floppy_Rest_Access', 'require_sync' ) );
	}

	/**
	 * Device pairing and revoke routes.
	 */
	private static function register_device_routes( string $namespace, string $controller ): void {
		self::route( $namespace, '/devices', WP_REST_Server::READABLE, $controller, 'list_devices', array( 'Floppy_Rest_Access', 'require_browser_session' ) );
		self::route( $namespace, '/devices/authorize', WP_REST_Server::CREATABLE, $controller, 'authorize_device', array( 'Floppy_Rest_Access', 'require_device_authorization' ) );
		self::route( $namespace, '/devices/exchange', WP_REST_Server::CREATABLE, $controller, 'exchange_device_code', '__return_true' );
		self::route( $namespace, '/devices/(?P<uuid>[a-f0-9-]+)/revoke', WP_REST_Server::CREATABLE, $controller, 'revoke_device', array( 'Floppy_Rest_Access', 'require_device_revoke' ) );
	}

	/**
	 * Export job routes.
	 */
	private static function register_export_routes( string $namespace, string $controller ): void {
		self::route( $namespace, '/exports', WP_REST_Server::CREATABLE, $controller, 'enqueue_export', array( 'Floppy_Rest_Access', 'require_browser_session' ) );
		self::route( $namespace, '/jobs/(?P<uuid>[a-f0-9-]+)', WP_REST_Server::READABLE, $controller, 'job_status', array( 'Floppy_Rest_Access', 'require_browser_session' ) );
		self::route( $namespace, '/exports/(?P<uuid>[a-f0-9-]+)/download', WP_REST_Server::READABLE, $controller, 'download_export', array( 'Floppy_Rest_Access', 'require_browser_session' ) );
	}

	/**
	 * Register one endpoint.
	 */
	private static function route( string $namespace, string $path, string $methods, string $controller, string $callback, $permission_callback, array $args = array() ): void {
		self::routes( $namespace, $path, array( self::endpoint( $methods, $controller, $callback, $permission_callback, $args ) ) );
	}

	/**
	 * Register multiple endpoint definitions under one route.
	 */
	private static function routes( string $namespace, string $path, array $endpoints ): void {
		register_rest_route( $namespace, $path, $endpoints );
	}

	/**
	 * Build a route endpoint definition.
	 */
	private static function endpoint( string $methods, string $controller, string $callback, $permission_callback, array $args = array() ): array {
		return array(
			'methods'             => $methods,
			'callback'            => array( $controller, $callback ),
			'permission_callback' => $permission_callback,
			'args'                => $args,
		);
	}

	/**
	 * Shared version target args.
	 */
	private static function file_version_args(): array {
		return array(
			'id'         => array( 'sanitize_callback' => 'absint' ),
			'version_id' => array( 'sanitize_callback' => 'absint' ),
		);
	}
}
