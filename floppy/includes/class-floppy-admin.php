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
		add_action( 'admin_post_floppy_run_repair', array( __CLASS__, 'run_repair' ) );
		add_action( 'admin_post_floppy_download_debug_bundle', array( __CLASS__, 'download_debug_bundle' ) );
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
			Floppy_Permissions::CAP_READ,
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
		if ( ! current_user_can( Floppy_Permissions::CAP_READ ) && ! current_user_can( Floppy_Permissions::CAP_MANAGE ) ) {
			wp_die( esc_html__( 'You do not have permission to access Floppy.', 'floppy' ) );
		}

		$summary = Floppy_Compatibility::summary();
		$devices = Floppy_Auth::list_devices( get_current_user_id() );
		$approval = self::get_pending_device_approval();
		$settings = Floppy_Settings::get();
		$active_devices = 0;
		$revoked_devices = 0;
		foreach ( $devices as $device ) {
			if ( 'active' === ( $device['status'] ?? '' ) ) {
				++$active_devices;
			} elseif ( 'revoked' === ( $device['status'] ?? '' ) ) {
				++$revoked_devices;
			}
		}
		$failed_checks = 0;
		foreach ( $summary['checks'] as $check ) {
			if ( empty( $check['ok'] ) ) {
				++$failed_checks;
			}
		}
		?>
		<div class="wrap floppy-admin">
			<h1><?php esc_html_e( 'Floppy', 'floppy' ); ?></h1>
			<p class="floppy-admin-kicker"><?php esc_html_e( 'Private WordPress-owned file storage for Desktop Mode, scoped Mac device tokens, and Finder-native sync.', 'floppy' ); ?></p>

			<div class="floppy-admin-grid">
				<section class="floppy-admin-panel floppy-admin-hero">
					<div>
						<h2><?php esc_html_e( 'Set Up Your Private WordPress Drive', 'floppy' ); ?></h2>
						<p class="floppy-admin-note"><?php esc_html_e( 'Use this screen to confirm readiness, connect Floppy for Mac, and keep Desktop Mode as the browser-native control surface for files, shares, sync, devices, and diagnostics.', 'floppy' ); ?></p>
					</div>
					<div class="floppy-admin-overview">
						<div class="floppy-admin-metric">
							<span><?php esc_html_e( 'Readiness', 'floppy' ); ?></span>
							<strong><?php echo ! empty( $summary['ok'] ) ? esc_html__( 'Ready', 'floppy' ) : esc_html__( 'Review', 'floppy' ); ?></strong>
							<?php /* translators: %d: number of failed readiness checks. */ ?>
							<small><?php echo esc_html( sprintf( _n( '%d failed check', '%d failed checks', $failed_checks, 'floppy' ), $failed_checks ) ); ?></small>
						</div>
						<div class="floppy-admin-metric">
							<span><?php esc_html_e( 'Desktop Mode', 'floppy' ); ?></span>
							<strong><?php echo function_exists( 'desktop_mode_register_window' ) ? esc_html__( 'Detected', 'floppy' ) : esc_html__( 'Missing', 'floppy' ); ?></strong>
							<small>
								<?php
								echo function_exists( 'desktop_mode_register_window' )
									? ( ! empty( $settings['enable_desktop_mode'] ) ? esc_html__( 'Launcher enabled', 'floppy' ) : esc_html__( 'Launcher disabled', 'floppy' ) )
									: esc_html__( 'Required plugin not active', 'floppy' );
								?>
							</small>
						</div>
						<div class="floppy-admin-metric">
							<span><?php esc_html_e( 'Approved Macs', 'floppy' ); ?></span>
							<strong><?php echo esc_html( (string) $active_devices ); ?></strong>
							<?php /* translators: %d: number of revoked device tokens. */ ?>
							<small><?php echo esc_html( sprintf( _n( '%d revoked token', '%d revoked tokens', $revoked_devices, 'floppy' ), $revoked_devices ) ); ?></small>
						</div>
						<div class="floppy-admin-metric">
							<span><?php esc_html_e( 'Upload Limit', 'floppy' ); ?></span>
							<strong><?php echo esc_html( size_format( (int) ( $settings['max_file_size'] ?? wp_max_upload_size() ) ) ); ?></strong>
							<small><?php esc_html_e( 'Private storage path', 'floppy' ); ?></small>
						</div>
					</div>
					<ol class="floppy-admin-steps">
						<li>
							<strong><?php esc_html_e( 'Install and open Desktop Mode', 'floppy' ); ?></strong>
							<span><?php esc_html_e( 'Floppy registers a native window, launcher, commands, settings, title-bar actions, and file opener through public Desktop Mode APIs.', 'floppy' ); ?></span>
						</li>
						<li>
							<strong><?php esc_html_e( 'Connect Floppy for Mac', 'floppy' ); ?></strong>
							<span><?php esc_html_e( 'The Mac app uses WordPress approval for onboarding, then exchanges that temporary credential for a scoped Floppy token.', 'floppy' ); ?></span>
						</li>
						<li>
							<strong><?php esc_html_e( 'Keep tokens revocable', 'floppy' ); ?></strong>
							<span><?php esc_html_e( 'Each Mac appears below as a device that can be audited or revoked without changing the user password.', 'floppy' ); ?></span>
						</li>
					</ol>
				</section>

				<?php if ( $approval ) : ?>
					<section class="floppy-admin-panel floppy-approval-panel">
						<h2><?php esc_html_e( 'Approve This Mac For Finder Sync', 'floppy' ); ?></h2>
						<p><?php esc_html_e( 'Floppy for Mac is asking to create a scoped device token for this WordPress account. Approve only Macs you control.', 'floppy' ); ?></p>
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
							<?php submit_button( __( 'Approve Mac And Create Token', 'floppy' ), 'primary', 'submit', false ); ?>
						</form>
					</section>
				<?php endif; ?>

				<?php if ( ! empty( $_GET['floppy-approved'] ) && ! empty( $_GET['open'] ) ) : // phpcs:ignore WordPress.Security.NonceVerification.Recommended ?>
					<section class="floppy-admin-panel floppy-approval-panel">
						<h2><?php esc_html_e( 'Mac Approved', 'floppy' ); ?></h2>
						<p><?php esc_html_e( 'Floppy for Mac can now finish setup and store the scoped device token. If the app does not open automatically, use the button below.', 'floppy' ); ?></p>
						<p><a class="button button-primary" href="<?php echo esc_attr( rawurldecode( (string) wp_unslash( $_GET['open'] ) ) ); ?>"><?php esc_html_e( 'Open Floppy for Mac', 'floppy' ); ?></a></p>
					</section>
				<?php endif; ?>

				<section class="floppy-admin-panel">
					<h2><?php esc_html_e( 'Readiness And Diagnostics', 'floppy' ); ?></h2>
					<p>
						<strong><?php echo ! empty( $summary['ok'] ) ? esc_html__( 'Ready', 'floppy' ) : esc_html__( 'Needs attention', 'floppy' ); ?></strong>
						<span class="floppy-admin-note"><?php esc_html_e( 'Private storage, HTTPS, schema, Desktop Mode, and server protections are checked here.', 'floppy' ); ?></span>
					</p>
					<table class="widefat striped">
						<tbody>
						<?php foreach ( $summary['checks'] as $key => $check ) : ?>
							<?php $status = Floppy_Compatibility::check_status( $check ); ?>
							<tr>
								<td><strong><?php echo esc_html( ucwords( str_replace( '_', ' ', $key ) ) ); ?></strong></td>
								<td>
									<?php
									if ( 'warn' === $status ) {
										esc_html_e( 'Warn', 'floppy' );
									} elseif ( 'fail' === $status ) {
										esc_html_e( 'Fail', 'floppy' );
									} else {
										esc_html_e( 'Pass', 'floppy' );
									}
									?>
								</td>
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
					<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>" class="floppy-admin-actions">
						<?php wp_nonce_field( 'floppy_run_repair' ); ?>
						<input type="hidden" name="action" value="floppy_run_repair" />
						<input type="hidden" name="dry_run" value="1" />
						<?php submit_button( __( 'Download Repair Dry Run', 'floppy' ), 'secondary', 'submit', false ); ?>
					</form>
					<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>" class="floppy-admin-actions">
						<?php wp_nonce_field( 'floppy_run_repair' ); ?>
						<input type="hidden" name="action" value="floppy_run_repair" />
						<input type="hidden" name="apply" value="1" />
						<?php submit_button( __( 'Run Safe Repairs', 'floppy' ), 'secondary', 'submit', false ); ?>
					</form>
					<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>" class="floppy-admin-actions">
						<?php wp_nonce_field( 'floppy_download_debug_bundle' ); ?>
						<input type="hidden" name="action" value="floppy_download_debug_bundle" />
						<?php submit_button( __( 'Download Debug Bundle', 'floppy' ), 'secondary', 'submit', false ); ?>
					</form>
				</section>

				<section class="floppy-admin-panel">
					<h2><?php esc_html_e( 'API, Sync And Onboarding', 'floppy' ); ?></h2>
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
							<tr>
								<td><?php esc_html_e( 'Plugin Main File', 'floppy' ); ?></td>
								<td><code>floppy/floppy.php</code></td>
							</tr>
							<tr>
								<td><?php esc_html_e( 'Device Token Scope', 'floppy' ); ?></td>
								<td><code>files:read,files:write,sync</code></td>
							</tr>
							<tr>
								<td><?php esc_html_e( 'Sync Retention', 'floppy' ); ?></td>
								<?php /* translators: %d: number of days sync events are retained. */ ?>
								<td><?php echo esc_html( sprintf( _n( '%d day', '%d days', (int) ( $settings['sync_retention_days'] ?? 45 ), 'floppy' ), (int) ( $settings['sync_retention_days'] ?? 45 ) ) ); ?></td>
							</tr>
							<tr>
								<td><?php esc_html_e( 'Tombstone Retention', 'floppy' ); ?></td>
								<?php /* translators: %d: number of days tombstones are retained. */ ?>
								<td><?php echo esc_html( sprintf( _n( '%d day', '%d days', (int) ( $settings['tombstone_retention_days'] ?? 90 ), 'floppy' ), (int) ( $settings['tombstone_retention_days'] ?? 90 ) ) ); ?></td>
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
							<tr><td colspan="5"><?php esc_html_e( 'No approved devices yet. Connect Floppy for Mac to create the first scoped sync token.', 'floppy' ); ?></td></tr>
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
	 * Run or dry-run repair tools and download the redacted report.
	 */
	public static function run_repair(): void {
		check_admin_referer( 'floppy_run_repair' );
		if ( ! current_user_can( 'manage_options' ) && ! current_user_can( Floppy_Permissions::CAP_MANAGE ) ) {
			wp_die( esc_html__( 'Administrator access required.', 'floppy' ) );
		}

		$apply = ! empty( $_POST['apply'] ); // phpcs:ignore WordPress.Security.ValidatedSanitizedInput.InputNotSanitized
		self::download_json(
			'floppy-repair-' . ( $apply ? 'applied' : 'dry-run' ) . '-' . gmdate( 'Ymd-His' ) . '.json',
			array(
				'format'         => 'floppy-repair-report-v1',
				'created_at_gmt' => current_time( 'mysql', true ),
				'support'        => Floppy_Diagnostics::support_block(),
				'report'         => Floppy_Schema::repair( $apply ),
			)
		);
	}

	/**
	 * Download a redacted support/debug bundle.
	 */
	public static function download_debug_bundle(): void {
		check_admin_referer( 'floppy_download_debug_bundle' );
		if ( ! current_user_can( 'manage_options' ) && ! current_user_can( Floppy_Permissions::CAP_MANAGE ) ) {
			wp_die( esc_html__( 'Administrator access required.', 'floppy' ) );
		}

		self::download_json( 'floppy-debug-' . gmdate( 'Ymd-His' ) . '.json', Floppy_Diagnostics::debug_bundle() );
	}

	/**
	 * Send a JSON attachment with private-cache headers.
	 */
	private static function download_json( string $filename, array $data ): void {
		nocache_headers();
		header( 'Cache-Control: private, no-store, max-age=0' );
		header( 'X-Content-Type-Options: nosniff' );
		header( 'Content-Type: application/json; charset=utf-8' );
		header( 'Content-Disposition: attachment; filename="' . str_replace( '"', '', $filename ) . '"' );
		echo wp_json_encode( $data, JSON_PRETTY_PRINT ); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped
		exit;
	}

	/**
	 * Approve a browser-initiated macOS device request.
	 */
	public static function approve_device(): void {
		check_admin_referer( 'floppy_approve_device' );
		if ( ! current_user_can( Floppy_Permissions::CAP_READ ) && ! current_user_can( Floppy_Permissions::CAP_MANAGE ) ) {
			wp_die( esc_html__( 'Authentication required.', 'floppy' ) );
		}

		$device_name = isset( $_POST['device_name'] ) ? sanitize_text_field( wp_unslash( $_POST['device_name'] ) ) : __( 'Mac', 'floppy' );
		$state       = isset( $_POST['state'] ) ? sanitize_text_field( wp_unslash( $_POST['state'] ) ) : '';
		$callback    = isset( $_POST['callback'] ) ? sanitize_text_field( wp_unslash( $_POST['callback'] ) ) : '';

		if ( ! self::is_valid_device_callback( $callback ) ) {
			wp_die( esc_html__( 'Invalid Floppy callback URL.', 'floppy' ) );
		}

		$code = Floppy_Auth::create_device_exchange_code( get_current_user_id(), $device_name, $state );

		$open_url = add_query_arg(
			array(
				'site'  => home_url(),
				'code'  => $code,
				'state' => $state,
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
				<p><?php esc_html_e( 'Floppy for Mac can now finish setup and store the scoped device token. If the app does not open automatically, use the button below.', 'floppy' ); ?></p>
				<p><a class="button button-primary button-hero" href="<?php echo esc_attr( $open_url ); ?>"><?php esc_html_e( 'Open Floppy for Mac', 'floppy' ); ?></a></p>
			</div>
		</body>
		</html>
		<?php
	}
}
