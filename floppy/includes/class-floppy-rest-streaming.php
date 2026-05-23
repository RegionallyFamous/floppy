<?php
/**
 * Authenticated private file streaming.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Streams files and versions through capability-checked REST endpoints.
 */
final class Floppy_Rest_Streaming {
	/**
	 * Stream a private file.
	 */
	public static function file( int $id, bool $inline ) {
		if ( ! Floppy_Permissions::can_read( 'file', $id ) ) {
			return self::not_found_or_forbidden( 'file', $id, 'read' );
		}

		$rate = Floppy_Rate_Limiter::check( 'download', 600, HOUR_IN_SECONDS );
		if ( is_wp_error( $rate ) ) {
			return $rate;
		}

		$row = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $row || 'active' !== $row['status'] ) {
			return new WP_Error( 'floppy_file_not_found', __( 'File not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		if ( $inline && ! self::mime_can_preview_inline( (string) $row['mime_type'] ) ) {
			return new WP_Error( 'floppy_preview_not_available', __( 'Inline preview is not available for this file type.', 'floppy' ), array( 'status' => 415 ) );
		}

		$path = Floppy_Storage::path_for_key( $row['storage_key'] );
		if ( ! is_readable( $path ) ) {
			return new WP_Error( 'floppy_blob_missing', __( 'The private blob is missing from storage.', 'floppy' ), array( 'status' => 500 ) );
		}

		Floppy_Audit::log( 'file.downloaded', 'file', $id, $row['name'] );
		self::send_headers( $row['mime_type'], $row['name'], $inline );
		self::path_with_range_support( $path );
		exit;
	}

	/**
	 * Stream a retained version without exposing private storage keys.
	 */
	public static function version( int $id, int $version_id ) {
		global $wpdb;

		if ( ! Floppy_Permissions::can_read( 'file', $id ) ) {
			return self::not_found_or_forbidden( 'file', $id, 'read' );
		}

		$rate = Floppy_Rate_Limiter::check( 'download', 600, HOUR_IN_SECONDS );
		if ( is_wp_error( $rate ) ) {
			return $rate;
		}

		$file = Floppy_Permissions::get_target_row( 'file', $id );
		if ( ! $file || 'active' !== $file['status'] ) {
			return new WP_Error( 'floppy_file_not_found', __( 'File not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$version = $wpdb->get_row(
			$wpdb->prepare(
				'SELECT * FROM ' . Floppy_Schema::table( 'file_versions' ) . ' WHERE id = %d AND file_id = %d LIMIT 1',
				$version_id,
				$id
			),
			ARRAY_A
		);
		if ( ! $version ) {
			return new WP_Error( 'floppy_version_not_found', __( 'File version not found.', 'floppy' ), array( 'status' => 404 ) );
		}

		$path = Floppy_Storage::path_for_key( (string) $version['storage_key'] );
		if ( ! is_readable( $path ) ) {
			return new WP_Error( 'floppy_version_blob_missing', __( 'The retained version blob is missing from private storage.', 'floppy' ), array( 'status' => 500 ) );
		}

		Floppy_Audit::log( 'file.version_downloaded', 'file', $id, (string) $version['name'], array( 'version_id' => $version_id ) );
		self::send_headers( (string) $version['mime_type'], (string) $version['name'], false );
		self::path_with_range_support( $path );
		exit;
	}

	/**
	 * Only allow browser-inline previews for passive file types.
	 */
	public static function mime_can_preview_inline( string $mime_type ): bool {
		if ( 0 === strpos( $mime_type, 'image/' ) || 0 === strpos( $mime_type, 'text/' ) ) {
			return true;
		}

		return in_array( $mime_type, array( 'application/pdf' ), true );
	}

	/**
	 * Send private download/preview headers.
	 */
	private static function send_headers( string $mime_type, string $name, bool $inline ): void {
		nocache_headers();
		header( 'Cache-Control: private, no-store, max-age=0' );
		header( 'X-Content-Type-Options: nosniff' );
		header( 'Accept-Ranges: bytes' );
		header( 'Content-Type: ' . ( $mime_type ?: 'application/octet-stream' ) );
		header( 'Content-Disposition: ' . ( $inline ? 'inline' : 'attachment' ) . '; filename="' . str_replace( '"', '', $name ) . '"' );
	}

	/**
	 * Stream a file with byte range support.
	 */
	private static function path_with_range_support( string $path ): void {
		$size = filesize( $path );
		$start = 0;
		$end = max( 0, $size - 1 );
		$range = isset( $_SERVER['HTTP_RANGE'] ) ? (string) wp_unslash( $_SERVER['HTTP_RANGE'] ) : ''; // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized

		if ( preg_match( '/bytes=(\d*)-(\d*)/', $range, $matches ) ) {
			if ( '' === $matches[1] && '' !== $matches[2] ) {
				$suffix = min( (int) $matches[2], $size );
				$start = $size - $suffix;
			} else {
				$start = '' === $matches[1] ? 0 : (int) $matches[1];
				$end = '' === $matches[2] ? $end : min( $end, (int) $matches[2] );
			}

			if ( $start > $end || $start < 0 || $end >= $size ) {
				status_header( 416 );
				header( 'Content-Range: bytes */' . $size );
				exit;
			}

			status_header( 206 );
			header( 'Content-Range: bytes ' . $start . '-' . $end . '/' . $size );
		}

		$length = $end - $start + 1;
		header( 'Content-Length: ' . $length );

		$handle = fopen( $path, 'rb' ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_fopen
		if ( ! $handle ) {
			status_header( 500 );
			return;
		}

		fseek( $handle, $start );
		$remaining = $length;
		while ( $remaining > 0 && ! feof( $handle ) ) {
			$chunk = fread( $handle, min( 8192, $remaining ) ); // phpcs:ignore WordPress.WP.AlternativeFunctions.file_system_read_fread
			if ( false === $chunk || '' === $chunk ) {
				break;
			}
			echo $chunk; // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped
			$remaining -= strlen( $chunk );
			if ( function_exists( 'flush' ) ) {
				flush();
			}
		}
		fclose( $handle );
	}

	/**
	 * Return a privacy-safe response when a target is missing or invisible.
	 */
	private static function not_found_or_forbidden( string $target_type, int $target_id, string $capability ) {
		if ( Floppy_Permissions::target_exists( $target_type, $target_id ) ) {
			Floppy_Audit::log( 'access.denied', $target_type, $target_id, '', array( 'capability' => $capability ) );
		}

		return new WP_Error( 'floppy_item_not_found', __( 'Floppy item not found.', 'floppy' ), array( 'status' => 404 ) );
	}
}
