<?php
/**
 * Admin screens and diagnostics.
 *
 * @package Floppy
 */

defined( 'ABSPATH' ) || exit;

/**
 * Admin UI.
 */
final class Floppy_Admin {
	/**
	 * Register hooks.
	 */
	public static function init(): void {
		add_action( 'admin_menu', array( __CLASS__, 'menu' ) );
		add_action( 'admin_enqueue_scripts', array( __CLASS__, 'enqueue_assets' ) );
		add_action( 'admin_notices', array( __CLASS__, 'admin_notices' ) );
		add_action( 'admin_post_floppy_refresh_health', array( __CLASS__, 'refresh_health' ) );
		add_action( 'admin_post_floppy_run_storage_probe', array( __CLASS__, 'run_storage_probe' ) );
		add_action( 'admin_post_floppy_approve_device', array( __CLASS__, 'approve_device' ) );
		add_filter( 'plugin_action_links_' . plugin_basename( FLOPPY_FILE ), array( __CLASS__, 'plugin_links' ) );
	}

	/**
	 * Enqueue admin assets on Floppy pages.
	 */
	public static function enqueue_assets( string $hook_suffix ): void {
		if ( false === strpos( $hook_suffix, 'floppy' ) ) {
			return;
		}

		Floppy_Desktop_Mode::register_assets();
		wp_enqueue_style( Floppy_Desktop_Mode::STYLE_HANDLE );
	}

	/**
	 * Add admin menu.
	 */
	public static function menu(): void {
		add_menu_page(
			__( 'Floppy', 'floppy' ),
			__( 'Floppy', 'floppy' ),
			'upload_files',
			'floppy',
			array( __CLASS__, 'render_page' ),
			FLOPPY_URL . 'assets/images/floppy-icon-admin.png',
			58
		);
	}

	/**
	 * Show critical notices.
	 */
	public static function admin_notices(): void {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}

		$summary = Floppy_Compatibility::summary();
		if ( ! empty( $summary['ok'] ) ) {
			return;
		}

		printf(
			'<div class="notice notice-error"><p>%s <a href="%s">%s</a></p></div>',
			esc_html__( 'Floppy needs attention before private file storage is production-ready.', 'floppy' ),
			esc_url( admin_url( 'admin.php?page=floppy' ) ),
			esc_html__( 'Open diagnostics', 'floppy' )
		);
	}

	/**
	 * Plugin action links.
	 */
	public static function plugin_links( array $links ): array {
		$links[] = '<a href="' . esc_url( admin_url( 'admin.php?page=floppy' ) ) . '">' . esc_html__( 'Diagnostics', 'floppy' ) . '</a>';
		return $links;
	}

	/**
	 * Render admin page.
	 */
	public static function render_page(): void {
		if ( ! current_user_can( 'upload_files' ) ) {
			wp_die( esc_html__( 'You do not have permission to access Floppy.', 'floppy' ) );
		}

		$summary = Floppy_Compatibility::summary();
		$devices = Floppy_Auth::list_devices( get_current_user_id() );
		$approval = self::get_pending_device_approval();
		?>
		<div class="wrap floppy-admin">
			<h1><?php esc_html_e( 'Floppy', 'floppy' ); ?></h1>
			<p><?php esc_html_e( 'Private WordPress-owned file storage for Desktop Mode and Finder-native sync.', 'floppy' ); ?></p>

			<div class="floppy-admin-grid">
				<?php if ( $approval ) : ?>
					<section class="floppy-admin-panel floppy-approval-panel">
						<h2><?php esc_html_e( 'Approve This Mac', 'floppy' ); ?></h2>
						<p><?php esc_html_e( 'A Floppy for Mac app is asking to sync this WordPress account. Only approve devices you control.', 'floppy' ); ?></p>
						<table class="widefat striped">
							<tbody>
								<tr>
									<td><?php esc_html_e( 'Device', 'floppy' ); ?></td>
									<td><?php echo esc_html( $approval['device_name'] ); ?></td>
								</tr>
								<tr>
									<td><?php esc_html_e( 'Callback', 'floppy' ); ?></td>
									<td><code><?php echo esc_html( $approval['callback'] ); ?></code></td>
								</tr>
							</tbody>
						</table>
						<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>" class="floppy-admin-actions">
							<?php wp_nonce_field( 'floppy_approve_device' ); ?>
							<input type="hidden" name="action" value="floppy_approve_device" />
							<input type="hidden" name="device_name" value="<?php echo esc_attr( $approval['device_name'] ); ?>" />
							<input type="hidden" name="state" value="<?php echo esc_attr( $approval['state'] ); ?>" />
							<input type="hidden" name="callback" value="<?php echo esc_attr( $approval['callback'] ); ?>" />
							<?php submit_button( __( 'Approve This Mac', 'floppy' ), 'primary', 'submit', false ); ?>
						</form>
					</section>
				<?php endif; ?>

				<?php if ( ! empty( $_GET['floppy-approved'] ) && ! empty( $_GET['open'] ) ) : // phpcs:ignore WordPress.Security.NonceVerification.Recommended ?>
					<section class="floppy-admin-panel floppy-approval-panel">
						<h2><?php esc_html_e( 'Mac Approved', 'floppy' ); ?></h2>
						<p><?php esc_html_e( 'Return to Floppy for Mac to finish setup. If it does not open automatically, use the button below.', 'floppy' ); ?></p>
						<p><a class="button button-primary" href="<?php echo esc_attr( rawurldecode( (string) wp_unslash( $_GET['open'] ) ) ); ?>"><?php esc_html_e( 'Open Floppy for Mac', 'floppy' ); ?></a></p>
					</section>
				<?php endif; ?>

				<section class="floppy-admin-panel">
					<h2><?php esc_html_e( 'Production Health', 'floppy' ); ?></h2>
					<p>
						<strong><?php echo ! empty( $summary['ok'] ) ? esc_html__( 'Ready', 'floppy' ) : esc_html__( 'Needs attention', 'floppy' ); ?></strong>
					</p>
					<table class="widefat striped">
						<tbody>
						<?php foreach ( $summary['checks'] as $key => $check ) : ?>
							<tr>
								<td><strong><?php echo esc_html( ucwords( str_replace( '_', ' ', $key ) ) ); ?></strong></td>
								<td><?php echo ! empty( $check['ok'] ) ? esc_html__( 'Pass', 'floppy' ) : esc_html__( 'Fail', 'floppy' ); ?></td>
								<td><?php echo esc_html( $check['label'] ?? '' ); ?></td>
								<td><?php echo esc_html( $check['message'] ?? '' ); ?></td>
							</tr>
						<?php endforeach; ?>
						</tbody>
					</table>
					<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>" class="floppy-admin-actions">
						<?php wp_nonce_field( 'floppy_refresh_health' ); ?>
						<input type="hidden" name="action" value="floppy_refresh_health" />
						<?php submit_button( __( 'Refresh Health', 'floppy' ), 'secondary', 'submit', false ); ?>
					</form>
					<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>" class="floppy-admin-actions">
						<?php wp_nonce_field( 'floppy_run_storage_probe' ); ?>
						<input type="hidden" name="action" value="floppy_run_storage_probe" />
						<?php submit_button( __( 'Run Private Storage Probe', 'floppy' ), 'secondary', 'submit', false ); ?>
					</form>
				</section>

				<section class="floppy-admin-panel">
					<h2><?php esc_html_e( 'API And Sync', 'floppy' ); ?></h2>
					<table class="widefat striped">
						<tbody>
							<tr>
								<td><?php esc_html_e( 'Discovery', 'floppy' ); ?></td>
								<td><code><?php echo esc_html( rest_url( Floppy_Rest::NAMESPACE . '/discovery' ) ); ?></code></td>
							</tr>
							<tr>
								<td><?php esc_html_e( 'REST Namespace', 'floppy' ); ?></td>
								<td><code><?php echo esc_html( Floppy_Rest::NAMESPACE ); ?></code></td>
							</tr>
							<tr>
								<td><?php esc_html_e( 'Storage Adapter', 'floppy' ); ?></td>
								<td><?php esc_html_e( 'Protected local uploads', 'floppy' ); ?></td>
							</tr>
							<tr>
								<td><?php esc_html_e( 'Private Mode', 'floppy' ); ?></td>
								<td><?php esc_html_e( 'Enabled by default', 'floppy' ); ?></td>
							</tr>
						</tbody>
					</table>
				</section>

				<section class="floppy-admin-panel">
					<h2><?php esc_html_e( 'Devices', 'floppy' ); ?></h2>
					<table class="widefat striped">
						<thead>
							<tr>
								<th><?php esc_html_e( 'Name', 'floppy' ); ?></th>
								<th><?php esc_html_e( 'User', 'floppy' ); ?></th>
								<th><?php esc_html_e( 'Status', 'floppy' ); ?></th>
								<th><?php esc_html_e( 'Last Seen', 'floppy' ); ?></th>
								<th><?php esc_html_e( 'Cursor', 'floppy' ); ?></th>
							</tr>
						</thead>
						<tbody>
						<?php if ( empty( $devices ) ) : ?>
							<tr><td colspan="5"><?php esc_html_e( 'No approved devices yet.', 'floppy' ); ?></td></tr>
						<?php endif; ?>
						<?php foreach ( $devices as $device ) : ?>
							<tr>
								<td><?php echo esc_html( $device['device_name'] ); ?></td>
								<td><?php echo esc_html( get_the_author_meta( 'user_login', (int) $device['user_id'] ) ); ?></td>
								<td><?php echo esc_html( $device['status'] ); ?></td>
								<td><?php echo esc_html( $device['last_seen_at_gmt'] ?: '-' ); ?></td>
								<td><?php echo esc_html( (string) $device['last_cursor'] ); ?></td>
							</tr>
						<?php endforeach; ?>
						</tbody>
					</table>
				</section>
			</div>
		</div>
		<?php
	}

	/**
	 * Refresh health action.
	 */
	public static function refresh_health(): void {
		check_admin_referer( 'floppy_refresh_health' );
		if ( ! current_user_can( 'manage_options' ) ) {
			wp_die( esc_html__( 'Administrator access required.', 'floppy' ) );
		}

		update_option( 'floppy_compatibility', Floppy_Compatibility::run_checks(), false );
		wp_safe_redirect( admin_url( 'admin.php?page=floppy&floppy-refreshed=1' ) );
		exit;
	}

	/**
	 * Run storage probe.
	 */
	public static function run_storage_probe(): void {
		check_admin_referer( 'floppy_run_storage_probe' );
		if ( ! current_user_can( 'manage_options' ) ) {
			wp_die( esc_html__( 'Administrator access required.', 'floppy' ) );
		}

		Floppy_Storage::direct_access_probe();
		wp_safe_redirect( admin_url( 'admin.php?page=floppy&floppy-probed=1' ) );
		exit;
	}

	/**
	 * Approve a browser-initiated macOS device request.
	 */
	public static function approve_device(): void {
		check_admin_referer( 'floppy_approve_device' );
		if ( ! current_user_can( 'read' ) ) {
			wp_die( esc_html__( 'Authentication required.', 'floppy' ) );
		}

		$device_name = isset( $_POST['device_name'] ) ? sanitize_text_field( wp_unslash( $_POST['device_name'] ) ) : __( 'Mac', 'floppy' );
		$state       = isset( $_POST['state'] ) ? sanitize_text_field( wp_unslash( $_POST['state'] ) ) : '';
		$callback    = isset( $_POST['callback'] ) ? sanitize_text_field( wp_unslash( $_POST['callback'] ) ) : '';

		if ( ! self::is_valid_device_callback( $callback ) ) {
			wp_die( esc_html__( 'Invalid Floppy callback URL.', 'floppy' ) );
		}

		$device = Floppy_Auth::create_device( get_current_user_id(), $device_name );
		if ( is_wp_error( $device ) ) {
			wp_die( esc_html( $device->get_error_message() ) );
		}

		$open_url = add_query_arg(
			array(
				'site'        => home_url(),
				'device_uuid' => $device['device_uuid'],
				'token'       => $device['token'],
				'scope'       => $device['scope'],
				'state'       => $state,
			),
			$callback
		);

		self::render_approved_device( $open_url );
		exit;
	}

	/**
	 * Get pending device approval query args.
	 */
	private static function get_pending_device_approval(): ?array {
		if ( empty( $_GET['floppy-device-approval'] ) ) { // phpcs:ignore WordPress.Security.NonceVerification.Recommended
			return null;
		}

		$callback = isset( $_GET['callback'] ) ? sanitize_text_field( wp_unslash( $_GET['callback'] ) ) : ''; // phpcs:ignore WordPress.Security.NonceVerification.Recommended
		if ( ! self::is_valid_device_callback( $callback ) ) {
			$callback = 'floppy://device-approved';
		}

		return array(
			'device_name' => isset( $_GET['device_name'] ) ? sanitize_text_field( wp_unslash( $_GET['device_name'] ) ) : __( 'Mac', 'floppy' ), // phpcs:ignore WordPress.Security.NonceVerification.Recommended
			'state'       => isset( $_GET['state'] ) ? sanitize_text_field( wp_unslash( $_GET['state'] ) ) : '', // phpcs:ignore WordPress.Security.NonceVerification.Recommended
			'callback'    => $callback,
		);
	}

	/**
	 * Validate a custom URL callback from Floppy for Mac.
	 */
	private static function is_valid_device_callback( string $callback ): bool {
		$parts = wp_parse_url( $callback );
		if ( ! is_array( $parts ) ) {
			return false;
		}

		return 'floppy' === ( $parts['scheme'] ?? '' )
			&& 'device-approved' === ( $parts['host'] ?? '' )
			&& empty( $parts['user'] )
			&& empty( $parts['pass'] );
	}

	/**
	 * Render the post-approval handoff without putting the raw token in an admin URL.
	 */
	private static function render_approved_device( string $open_url ): void {
		?>
		<!doctype html>
		<html <?php language_attributes(); ?>>
		<head>
			<meta charset="<?php bloginfo( 'charset' ); ?>" />
			<title><?php esc_html_e( 'Mac Approved', 'floppy' ); ?></title>
			<?php wp_admin_css( 'install', true ); ?>
		</head>
		<body class="wp-core-ui">
			<div class="wrap">
				<h1><?php esc_html_e( 'Mac Approved', 'floppy' ); ?></h1>
				<p><?php esc_html_e( 'Return to Floppy for Mac to finish setup. If it does not open automatically, use the button below.', 'floppy' ); ?></p>
				<p><a class="button button-primary button-hero" href="<?php echo esc_attr( $open_url ); ?>"><?php esc_html_e( 'Open Floppy for Mac', 'floppy' ); ?></a></p>
			</div>
		</body>
		</html>
		<?php
	}
}
