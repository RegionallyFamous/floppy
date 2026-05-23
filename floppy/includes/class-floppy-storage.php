<?php
/**
 * Private storage adapter.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Local protected-upload storage adapter.
 */
final class Floppy_Storage {
	/**
	 * Private storage directory name inside uploads.
	 */
	private const PRIVATE_DIR = 'floppy-private';

	/**
	 * Register storage privacy hooks.
	 */
	public static function init(): void {
		add_filter( 'wp_get_attachment_url', array( __CLASS__, 'filter_private_attachment_url' ), 10, 2 );
		add_filter( 'rest_prepare_attachment', array( __CLASS__, 'filter_private_attachment_rest_response' ), 10, 3 );
	}

	/**
	 * Get private root path and URL.
	 */
	public static function root(): array {
		$uploads = wp_upload_dir( null, false );

		return array(
			'path'  => trailingslashit( $uploads['basedir'] ) . self::PRIVATE_DIR,
			'url'   => trailingslashit( $uploads['baseurl'] ) . self::PRIVATE_DIR,
			'error' => $uploads['error'] ?? '',
		);
	}

	/**
	 * Ensure private root exists and is protected where the host supports it.
	 */
	public static function ensure_private_root(): array {
		$root = self::root();
		if ( ! empty( $root['error'] ) ) {
			return array( 'ok' => false, 'message' => $root['error'] );
		}

		if ( ! wp_mkdir_p( $root['path'] ) ) {
			return array( 'ok' => false, 'message' => __( 'Could not create Floppy private upload directory.', 'floppy' ) );
		}

		$files = array(
			'.htaccess' => "Require all denied\nDeny from all\n",
			'web.config' => "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<configuration><system.webServer><authorization><deny users=\"*\" /></authorization></system.webServer></configuration>\n",
			'index.php' => "<?php\n// Silence is golden.\n",
		);

		foreach ( $files as $name => $contents ) {
			$path = trailingslashit( $root['path'] ) . $name;
			if ( ! file_exists( $path ) ) {
				file_put_contents( $path, $contents ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_file_put_contents
			}
		}

		return array( 'ok' => true, 'message' => __( 'Private storage is writable.', 'floppy' ) );
	}

	/**
	 * Probe whether private files are directly reachable.
	 */
	public static function direct_access_probe(): array {
		$root = self::ensure_private_root();
		if ( empty( $root['ok'] ) ) {
			update_option( 'floppy_private_probe', $root, false );
			return $root;
		}

		$storage = self::root();
		$name    = 'probe-' . wp_generate_uuid4() . '.txt';
		$path    = trailingslashit( $storage['path'] ) . $name;
		$url     = trailingslashit( $storage['url'] ) . $name;
		$body    = 'floppy-private-probe-' . wp_generate_password( 16, false );

		file_put_contents( $path, $body ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_file_put_contents
		$response = wp_remote_get( $url, array( 'timeout' => 4 ) );
		@unlink( $path ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged

		if ( is_wp_error( $response ) ) {
			$result = array( 'ok' => true, 'message' => __( 'Private files were not directly reachable during probe.', 'floppy' ) );
			update_option( 'floppy_private_probe', $result, false );
			return $result;
		}

		$code = (int) wp_remote_retrieve_response_code( $response );
		$seen = wp_remote_retrieve_body( $response );
		$ok   = 200 !== $code || $seen !== $body;
		if ( ! $ok && self::allows_unprotected_storage_for_local_development() ) {
			$result = array(
				'ok'      => true,
				'status'  => 'warn',
				'code'    => $code,
				'label'   => __( 'Local development storage', 'floppy' ),
				'message' => __( 'Private storage is directly reachable, but this loopback site is allowed for local Studio testing only. Production sites must block direct access to wp-content/uploads/floppy-private/.', 'floppy' ),
			);
			update_option( 'floppy_private_probe', $result, false );

			return $result;
		}

		$result = array(
			'ok'      => $ok,
			'status'  => $ok ? 'pass' : 'fail',
			'code'    => $code,
			'label'   => $ok ? __( 'Private storage probe passed.', 'floppy' ) : __( 'Private storage directly reachable', 'floppy' ),
			'message' => $ok
				? __( 'Private storage probe passed.', 'floppy' )
				: __( 'Private storage is directly reachable. Floppy private mode must not be used until the server blocks this path.', 'floppy' ),
		);
		update_option( 'floppy_private_probe', $result, false );

		return $result;
	}

	/**
	 * Return cached private storage status with local-development allowances applied.
	 */
	public static function private_storage_status(): array {
		$probe = get_option( 'floppy_private_probe' );
		if ( ! is_array( $probe ) ) {
			return self::direct_access_probe();
		}

		if ( empty( $probe['ok'] ) && self::allows_unprotected_storage_for_local_development() ) {
			return array(
				'ok'      => true,
				'status'  => 'warn',
				'code'    => isset( $probe['code'] ) ? (int) $probe['code'] : 0,
				'label'   => __( 'Local development storage', 'floppy' ),
				'message' => __( 'Private storage is directly reachable, but this loopback site is allowed for local Studio testing only. Production sites must block direct access to wp-content/uploads/floppy-private/.', 'floppy' ),
			);
		}

		if ( empty( $probe['status'] ) ) {
			$probe['status'] = empty( $probe['ok'] ) ? 'fail' : 'pass';
		}

		return $probe;
	}

	/**
	 * Return support-safe host guidance for private-storage protection.
	 */
	public static function private_storage_probe_matrix(): array {
		$probe = self::private_storage_status();
		$server = self::server_family();

		return array(
			'probe'             => $probe,
			'server_family'     => $server,
			'protected_path'    => 'wp-content/uploads/' . self::PRIVATE_DIR . '/',
			'local_development' => self::allows_unprotected_storage_for_local_development(),
			'recommended_fixes' => self::private_storage_fixes_for_server( $server ),
		);
	}

	/**
	 * Return a WP_Error when private storage is not enforceable.
	 */
	public static function require_private_mode() {
		$probe = self::private_storage_status();

		if ( empty( $probe['ok'] ) ) {
			return new WP_Error(
				'floppy_private_storage_unprotected',
				__( 'Floppy private storage is directly reachable. Uploads are disabled until the server blocks direct access.', 'floppy' ),
				array( 'status' => 503 )
			);
		}

		return true;
	}

	/**
	 * Check whether this site is a loopback development site.
	 */
	public static function is_loopback_site(): bool {
		$host = strtolower( (string) wp_parse_url( home_url(), PHP_URL_HOST ) );
		if ( in_array( $host, array( 'localhost', '127.0.0.1', '::1' ), true ) ) {
			return true;
		}

		return filter_var( $host, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4 | FILTER_FLAG_IPV6 | FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE ) === false
			&& filter_var( $host, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4 | FILTER_FLAG_IPV6 ) !== false
			&& in_array( inet_pton( $host ), array( inet_pton( '127.0.0.1' ), inet_pton( '::1' ) ), true );
	}

	/**
	 * Allow direct storage only for explicit local development contexts.
	 */
	private static function allows_unprotected_storage_for_local_development(): bool {
		$allowed = self::is_loopback_site();

		if ( defined( 'FLOPPY_ALLOW_UNPROTECTED_LOCAL_STORAGE' ) ) {
			$allowed = (bool) FLOPPY_ALLOW_UNPROTECTED_LOCAL_STORAGE;
		}

		return (bool) apply_filters( 'floppy_allow_unprotected_local_storage', $allowed );
	}

	/**
	 * Detect broad server family for diagnostics.
	 */
	private static function server_family(): string {
		$software = isset( $_SERVER['SERVER_SOFTWARE'] ) ? strtolower( sanitize_text_field( wp_unslash( $_SERVER['SERVER_SOFTWARE'] ) ) ) : ''; // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized
		$host = strtolower( (string) wp_parse_url( home_url(), PHP_URL_HOST ) );

		if ( false !== strpos( $host, 'localhost' ) || self::is_loopback_site() ) {
			return 'studio_or_loopback';
		}
		if ( false !== strpos( $software, 'nginx' ) ) {
			return 'nginx';
		}
		if ( false !== strpos( $software, 'apache' ) || false !== strpos( $software, 'litespeed' ) ) {
			return 'apache';
		}
		if ( false !== strpos( $software, 'iis' ) ) {
			return 'iis';
		}

		return 'unknown';
	}

	/**
	 * Return concise direct-access remediation steps without exposing local paths.
	 */
	private static function private_storage_fixes_for_server( string $server ): array {
		$common = array(
			__( 'Keep all file, preview, and thumbnail access behind authenticated Floppy REST endpoints.', 'floppy' ),
			__( 'Re-run the Floppy private-storage probe after changing host rules.', 'floppy' ),
		);

		if ( 'nginx' === $server ) {
			array_unshift( $common, __( 'Add a location block that denies access to /wp-content/uploads/floppy-private/.', 'floppy' ) );
			return $common;
		}
		if ( 'apache' === $server ) {
			array_unshift( $common, __( 'Ensure .htaccess files are honored and deny all access under wp-content/uploads/floppy-private/.', 'floppy' ) );
			return $common;
		}
		if ( 'iis' === $server ) {
			array_unshift( $common, __( 'Ensure web.config denies anonymous access under wp-content/uploads/floppy-private/.', 'floppy' ) );
			return $common;
		}
		if ( 'studio_or_loopback' === $server ) {
			array_unshift( $common, __( 'Loopback development may warn instead of fail; production sites must block the private upload path.', 'floppy' ) );
			return $common;
		}

		array_unshift( $common, __( 'Configure your web server to deny direct HTTP access to /wp-content/uploads/floppy-private/.', 'floppy' ) );
		return $common;
	}

	/**
	 * Store an uploaded file and return private storage metadata.
	 */
	public static function store_upload( array $file ): array {
		$private_mode = self::require_private_mode();
		if ( is_wp_error( $private_mode ) ) {
			return array( 'error' => $private_mode );
		}

		if ( ! empty( $file['error'] ) ) {
			return array( 'error' => new WP_Error( 'floppy_upload_error', __( 'Upload failed before Floppy received the file.', 'floppy' ), array( 'status' => 400 ) ) );
		}

		$tmp_name = $file['tmp_name'] ?? '';
		$name     = self::normalize_filename( (string) ( $file['name'] ?? 'file' ) );
		if ( '' === $tmp_name || ! is_uploaded_file( $tmp_name ) ) {
			return array( 'error' => new WP_Error( 'floppy_invalid_upload', __( 'No valid uploaded file was provided.', 'floppy' ), array( 'status' => 400 ) ) );
		}

		$size = (int) ( $file['size'] ?? filesize( $tmp_name ) );
		$max  = (int) Floppy_Settings::get_value( 'max_file_size', wp_max_upload_size() );
		if ( $size > $max ) {
			return array( 'error' => new WP_Error( 'floppy_upload_too_large', __( 'The file is larger than the Floppy upload limit.', 'floppy' ), array( 'status' => 413 ) ) );
		}

		if ( self::has_dangerous_extension( $name ) ) {
			return array( 'error' => new WP_Error( 'floppy_dangerous_file_type', __( 'This file type is not allowed in private storage.', 'floppy' ), array( 'status' => 415 ) ) );
		}

		$type = wp_check_filetype_and_ext( $tmp_name, $name );
		if ( empty( $type['type'] ) ) {
			return array( 'error' => new WP_Error( 'floppy_unknown_mime', __( 'Floppy could not verify the file type.', 'floppy' ), array( 'status' => 415 ) ) );
		}

		$uuid = wp_generate_uuid4();
		$hash = hash_file( 'sha256', $tmp_name );
		$ext  = pathinfo( $name, PATHINFO_EXTENSION );
		$key  = self::storage_key( $uuid, $ext );
		$path = self::path_for_key( $key );

		if ( ! wp_mkdir_p( dirname( $path ) ) ) {
			return array( 'error' => new WP_Error( 'floppy_storage_unwritable', __( 'Floppy could not create a private storage shard.', 'floppy' ), array( 'status' => 500 ) ) );
		}

		if ( ! move_uploaded_file( $tmp_name, $path ) ) {
			return array( 'error' => new WP_Error( 'floppy_storage_move_failed', __( 'Floppy could not move the file into private storage.', 'floppy' ), array( 'status' => 500 ) ) );
		}

		@chmod( $path, 0640 ); // phpcs:ignore WordPress.PHP.NoSilencedErrors.Discouraged

		return array(
			'uuid'         => $uuid,
			'name'         => $name,
			'path'         => $path,
			'storage_key'  => $key,
			'content_hash' => $hash,
			'size_bytes'   => $size,
			'mime_type'    => $type['type'],
		);
	}

	/**
	 * Build a sharded storage key.
	 */
	public static function storage_key( string $uuid, string $ext = '' ): string {
		$hash = hash( 'sha256', $uuid );
		$file = $uuid . ( $ext ? '.' . strtolower( $ext ) : '' );

		return substr( $hash, 0, 2 ) . '/' . substr( $hash, 2, 2 ) . '/' . $file;
	}

	/**
	 * Resolve a private storage key to a local path.
	 */
	public static function path_for_key( string $key ): string {
		$root = self::root();
		$key  = ltrim( str_replace( array( '..', '\\' ), '', $key ), '/' );

		return trailingslashit( $root['path'] ) . $key;
	}

	/**
	 * Normalize an uploaded filename.
	 */
	public static function normalize_filename( string $filename ): string {
		$filename = sanitize_file_name( wp_basename( $filename ) );
		if ( '' === $filename || '.' === $filename ) {
			return 'file';
		}

		return $filename;
	}

	/**
	 * Normalize for collision checks.
	 */
	public static function normalize_lookup_name( string $filename ): string {
		return strtolower( self::normalize_filename( $filename ) );
	}

	/**
	 * Reject executable/server-interpreted extensions.
	 */
	public static function has_dangerous_extension( string $filename ): bool {
		$dangerous = array( 'php', 'php3', 'php4', 'php5', 'phtml', 'phar', 'cgi', 'pl', 'asp', 'aspx', 'jsp', 'sh', 'bash', 'zsh' );
		$ext = strtolower( pathinfo( $filename, PATHINFO_EXTENSION ) );

		return in_array( $ext, $dangerous, true );
	}

	/**
	 * Replace private attachment URLs with authenticated Floppy URLs.
	 *
	 * @param string|false $url Attachment URL.
	 * @param int          $attachment_id Attachment id.
	 * @return string|false
	 */
	public static function filter_private_attachment_url( $url, int $attachment_id ) {
		if ( '1' !== get_post_meta( $attachment_id, '_floppy_private', true ) ) {
			return $url;
		}

		global $wpdb;
		$file_id = (int) $wpdb->get_var(
			$wpdb->prepare(
				'SELECT id FROM ' . Floppy_Schema::table( 'files' ) . ' WHERE attachment_id = %d LIMIT 1',
				$attachment_id
			)
		);

		if ( $file_id && Floppy_Permissions::can_read( 'file', $file_id ) ) {
			return rest_url( Floppy_Rest::NAMESPACE . '/files/' . $file_id . '/download' );
		}

		return '';
	}

	/**
	 * Remove raw media URLs from REST responses for private attachments.
	 */
	public static function filter_private_attachment_rest_response( WP_REST_Response $response, WP_Post $post, WP_REST_Request $request ): WP_REST_Response {
		if ( '1' !== get_post_meta( $post->ID, '_floppy_private', true ) ) {
			return $response;
		}

		$data = $response->get_data();
		$data['source_url'] = '';
		unset( $data['media_details']['sizes'] );
		$response->set_data( $data );

		return $response;
	}
}
