<?php
/**
 * Desktop Mode integration.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Registers Floppy with Desktop Mode using public extension points.
 */
final class Floppy_Desktop_Mode {
	public const WINDOW_ID = 'floppy-drive';
	public const SCRIPT_HANDLE = 'floppy-desktop-mode';
	public const STYLE_HANDLE = 'floppy-desktop-mode';
	public const DESKTOP_ICON = 'dashicons-archive';

	/**
	 * Register hooks.
	 */
	public static function init(): void {
		add_action( 'admin_enqueue_scripts', array( __CLASS__, 'register_assets' ) );
		add_action( 'desktop_mode_mode_init', array( __CLASS__, 'enqueue_shell_assets' ) );
		add_action( 'init', array( __CLASS__, 'register_desktop_mode_surfaces' ), 20 );
	}

	/**
	 * Register scripts and styles.
	 */
	public static function register_assets(): void {
		wp_register_style(
			self::STYLE_HANDLE,
			FLOPPY_URL . 'assets/css/desktop-mode.css',
			array( 'dashicons' ),
			FLOPPY_VERSION
		);

		wp_register_script(
			self::SCRIPT_HANDLE,
			FLOPPY_URL . 'assets/js/desktop-mode.js',
			array( 'wp-api-fetch', 'wp-hooks', 'wp-i18n' ),
			FLOPPY_VERSION,
			true
		);

		wp_add_inline_script(
			self::SCRIPT_HANDLE,
			'window.floppyDesktopConfig = ' . wp_json_encode(
				array(
					'windowId'       => self::WINDOW_ID,
					'restUrl'        => esc_url_raw( rest_url( Floppy_Rest::NAMESPACE . '/' ) ),
					'nonce'          => wp_create_nonce( 'wp_rest' ),
					'userId'         => get_current_user_id(),
					'maxFileSize'    => (int) Floppy_Settings::get_value( 'max_file_size', wp_max_upload_size() ),
					'desktopMode'    => function_exists( 'desktop_mode_register_window' ),
					'capabilities'   => array(
						'upload' => current_user_can( 'upload_files' ),
						'admin'  => current_user_can( 'manage_options' ),
					),
				)
			) . ';',
			'before'
		);
	}

	/**
	 * Enqueue assets when Desktop Mode is active.
	 */
	public static function enqueue_shell_assets(): void {
		self::register_assets();
		wp_enqueue_style( self::STYLE_HANDLE );
		wp_enqueue_script( self::SCRIPT_HANDLE );
	}

	/**
	 * Register Desktop Mode native window, launcher, commands, and hooks.
	 */
	public static function register_desktop_mode_surfaces(): void {
		if ( ! Floppy_Settings::get_value( 'enable_desktop_mode', true ) ) {
			return;
		}

		if ( function_exists( 'desktop_mode_register_window' ) ) {
			desktop_mode_register_window(
				self::WINDOW_ID,
				array(
					'title'          => __( 'Floppy', 'floppy' ),
					'icon'           => self::DESKTOP_ICON,
					'capabilities'   => array( 'read' ),
					'template'       => array( __CLASS__, 'render_window' ),
					'script'         => self::SCRIPT_HANDLE,
					'style'          => self::STYLE_HANDLE,
					'main_tab_label' => __( 'Files', 'floppy' ),
					'width'          => 980,
					'height'         => 680,
					'min_width'      => 720,
					'min_height'     => 480,
				)
			);
		}

		if ( function_exists( 'desktop_mode_register_icon' ) ) {
			desktop_mode_register_icon(
				self::WINDOW_ID,
				array(
					'title'        => __( 'Floppy', 'floppy' ),
					'icon'         => self::DESKTOP_ICON,
					'window'       => self::WINDOW_ID,
					'capabilities' => array( 'read' ),
					'position'     => 82,
				)
			);
		}

		if ( function_exists( 'desktop_mode_register_command_script' ) ) {
			desktop_mode_register_command_script( self::SCRIPT_HANDLE );
		}

		if ( function_exists( 'desktop_mode_register_settings_tab_script' ) ) {
			desktop_mode_register_settings_tab_script( self::SCRIPT_HANDLE );
		}

		if ( function_exists( 'desktop_mode_register_title_bar_button_script' ) ) {
			desktop_mode_register_title_bar_button_script( self::SCRIPT_HANDLE );
		}

		if ( function_exists( 'desktop_mode_register_file_opener' ) ) {
			desktop_mode_register_file_opener(
				'floppy-private-preview',
				array(
					'label'        => __( 'Open in Floppy', 'floppy' ),
					'types'        => array( 'attachment' ),
					'is_default'   => false,
					'sort'         => 20,
					'script'       => self::SCRIPT_HANDLE,
					'capabilities' => array( 'read' ),
				)
			);
		}
	}

	/**
	 * Render the native window template.
	 */
	public static function render_window(): void {
		?>
		<div class="floppy-app" data-floppy-root>
			<div class="floppy-loading"><?php esc_html_e( 'Loading Floppy...', 'floppy' ); ?></div>
		</div>
		<?php
	}

}
