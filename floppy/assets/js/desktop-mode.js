( function ( window, document, wp ) {
	'use strict';

	var config = window.floppyDesktopConfig || {};
	var desktop = wp && wp.desktop ? wp.desktop : null;
	var hooks = wp && wp.hooks ? wp.hooks : null;
	var __ = wp && wp.i18n ? wp.i18n.__ : function ( text ) { return text; };

	function apiRequest( path, options ) {
		options = options || {};
		var headers = options.headers || {};
		headers['X-WP-Nonce'] = config.nonce || '';
		options.headers = headers;

		if ( desktop && typeof desktop.fetch === 'function' ) {
			return desktop.fetch( config.restUrl + path.replace( /^\//, '' ), options ).then( parseResponse );
		}

		if ( wp && wp.apiFetch ) {
			var apiOptions = Object.assign( {}, options, { path: '/floppy/v1/' + path.replace( /^\//, '' ) } );
			return wp.apiFetch( apiOptions );
		}

		return window.fetch( config.restUrl + path.replace( /^\//, '' ), options ).then( parseResponse );
	}

	function parseResponse( response ) {
		if ( response && typeof response.json === 'function' ) {
			return response.json().then( function ( data ) {
				if ( ! response.ok ) {
					var error = new Error( data && data.message ? data.message : 'Floppy request failed.' );
					error.data = data;
					throw error;
				}
				return data;
			} );
		}
		return response;
	}

	function notify( message, type ) {
		if ( desktop && typeof desktop.notify === 'function' ) {
			desktop.notify( { title: message, meta: { type: type || 'info' } } );
			return;
		}
		if ( window.console ) {
			window.console.log( '[Floppy] ' + message );
		}
	}

	function setBadge( value ) {
		var count = parseInt( value, 10 );
		if ( ! count || count < 0 ) {
			count = 0;
		}
		if ( desktop && desktop.icons && typeof desktop.icons.setBadge === 'function' ) {
			desktop.icons.setBadge( config.windowId, count );
		}
		if ( desktop && desktop.dock && typeof desktop.dock.setBadge === 'function' ) {
			desktop.dock.setBadge( config.windowId, count );
		}
		if ( desktop && desktop.taskbar && typeof desktop.taskbar.setBadge === 'function' ) {
			desktop.taskbar.setBadge( config.windowId, count );
		}
	}

	function mount( container, ctx ) {
		var state = {
			parentId: 0,
			items: [],
			selected: null,
			health: null,
			devices: [],
			uploading: 0,
			view: 'grid'
		};

		container.innerHTML = [
			'<div class="floppy-shell">',
				'<aside class="floppy-sidebar">',
					'<div class="floppy-brand"><span class="dashicons dashicons-portfolio"></span><strong>Floppy</strong></div>',
					'<button class="floppy-nav is-active" data-panel="files"><span class="dashicons dashicons-media-default"></span><span>Files</span></button>',
					'<button class="floppy-nav" data-panel="shared"><span class="dashicons dashicons-groups"></span><span>Shared</span></button>',
					'<button class="floppy-nav" data-panel="sync"><span class="dashicons dashicons-update"></span><span>Sync</span></button>',
					'<button class="floppy-nav" data-panel="devices"><span class="dashicons dashicons-desktop"></span><span>Devices</span></button>',
					'<button class="floppy-nav" data-panel="diagnostics"><span class="dashicons dashicons-chart-area"></span><span>Diagnostics</span></button>',
				'</aside>',
				'<main class="floppy-main">',
					'<header class="floppy-toolbar">',
						'<div class="floppy-breadcrumb"><button class="floppy-icon-button" data-action="home" title="Home"><span class="dashicons dashicons-admin-home"></span></button><span>My Drive</span></div>',
						'<div class="floppy-actions">',
							'<button class="floppy-icon-button" data-action="new-folder" title="New folder"><span class="dashicons dashicons-category"></span></button>',
							'<button class="floppy-icon-button" data-action="upload" title="Upload"><span class="dashicons dashicons-upload"></span></button>',
							'<button class="floppy-icon-button" data-action="refresh" title="Refresh"><span class="dashicons dashicons-update"></span></button>',
							'<button class="floppy-icon-button" data-action="toggle-view" title="Toggle view"><span class="dashicons dashicons-list-view"></span></button>',
						'</div>',
					'</header>',
					'<div class="floppy-content" data-panel-root></div>',
					'<input class="floppy-hidden-file" type="file" multiple />',
				'</main>',
			'</div>'
		].join( '' );

		var panelRoot = container.querySelector( '[data-panel-root]' );
		var fileInput = container.querySelector( '.floppy-hidden-file' );

		function renderFiles() {
			panelRoot.innerHTML = '<div class="floppy-drop-zone"><div class="floppy-list floppy-list--' + state.view + '"></div></div>';
			var list = panelRoot.querySelector( '.floppy-list' );
			if ( ! state.items.length ) {
				list.innerHTML = '<div class="floppy-empty">No files yet.</div>';
				return;
			}
			list.innerHTML = state.items.map( function ( item ) {
				var icon = item.kind === 'folder' ? 'category' : 'media-default';
				var size = item.kind === 'file' ? '<span>' + formatBytes( item.size_bytes ) + '</span>' : '<span>Folder</span>';
				return '<button class="floppy-item" data-kind="' + item.kind + '" data-id="' + item.id + '">' +
					'<span class="dashicons dashicons-' + icon + '"></span>' +
					'<strong>' + escapeHtml( item.name ) + '</strong>' +
					size +
				'</button>';
			} ).join( '' );
		}

		function renderDiagnostics() {
			var health = state.health;
			if ( ! health ) {
				panelRoot.innerHTML = '<div class="floppy-empty">Diagnostics unavailable.</div>';
				return;
			}
			var checks = Object.keys( health.checks || {} ).map( function ( key ) {
				var check = health.checks[ key ];
				return '<tr><td>' + escapeHtml( key.replace( /_/g, ' ' ) ) + '</td><td>' + ( check.ok ? 'Pass' : 'Fail' ) + '</td><td>' + escapeHtml( check.label || '' ) + '</td><td>' + escapeHtml( check.message || '' ) + '</td></tr>';
			} ).join( '' );
			panelRoot.innerHTML = '<div class="floppy-panel"><h2>Diagnostics</h2><table><tbody>' + checks + '</tbody></table></div>';
		}

		function renderDevices() {
			var rows = state.devices.map( function ( device ) {
				return '<tr><td>' + escapeHtml( device.device_name ) + '</td><td>' + escapeHtml( device.status ) + '</td><td>' + escapeHtml( device.last_seen_at_gmt || '-' ) + '</td><td>' + escapeHtml( String( device.last_cursor || 0 ) ) + '</td></tr>';
			} ).join( '' );
			panelRoot.innerHTML = '<div class="floppy-panel"><h2>Devices</h2><table><tbody>' + ( rows || '<tr><td>No devices approved.</td></tr>' ) + '</tbody></table></div>';
		}

		function loadFiles() {
			markLoading( ctx );
			return apiRequest( 'files?parent_id=' + state.parentId + '&limit=100' ).then( function ( data ) {
				state.items = data.items || [];
				renderFiles();
				markReady( ctx );
			} ).catch( showError );
		}

		function loadHealth() {
			return apiRequest( 'health' ).then( function ( data ) {
				state.health = data;
			} ).catch( function () {} );
		}

		function loadDevices() {
			return apiRequest( 'devices' ).then( function ( data ) {
				state.devices = data.devices || [];
			} ).catch( function () {} );
		}

		function uploadFiles( files ) {
			if ( ! files || ! files.length ) {
				return;
			}
			state.uploading += files.length;
			setBadge( String( state.uploading ) );
			Array.prototype.forEach.call( files, function ( file ) {
				var body = new window.FormData();
				body.append( 'file', file );
				body.append( 'parent_id', state.parentId );
				apiRequest( 'upload', { method: 'POST', body: body } ).then( function () {
					notify( 'Uploaded ' + file.name, 'success' );
					if ( desktop && typeof desktop.broadcast === 'function' ) {
						desktop.broadcast( 'floppy.files.changed', { parentId: state.parentId } );
					}
				} ).catch( showError ).finally( function () {
					state.uploading -= 1;
					setBadge( state.uploading ? String( state.uploading ) : '' );
					loadFiles();
				} );
			} );
		}

		function createFolder() {
			panelRoot.insertAdjacentHTML(
				'afterbegin',
				'<form class="floppy-inline-form" data-folder-form><input type="text" name="folder_name" placeholder="Folder name" autocomplete="off" /><button type="submit">Create</button><button type="button" data-cancel-folder>Cancel</button></form>'
			);
			var form = panelRoot.querySelector( '[data-folder-form]' );
			var input = form.querySelector( 'input' );
			input.focus();
			form.addEventListener( 'submit', function ( event ) {
				event.preventDefault();
				if ( ! input.value.trim() ) {
					return;
				}
				apiRequest( 'folders', {
					method: 'POST',
					headers: { 'Content-Type': 'application/json' },
					body: JSON.stringify( { name: input.value.trim(), parent_id: state.parentId } )
				} ).then( loadFiles ).catch( showError );
			} );
		}

		function openItem( id, kind ) {
			var item = state.items.filter( function ( candidate ) {
				return candidate.id === id && candidate.kind === kind;
			} )[0];
			if ( ! item ) {
				return;
			}
			if ( item.kind === 'folder' ) {
				state.parentId = item.id;
				loadFiles();
				return;
			}
			window.open( item.download_url, '_blank', 'noopener' );
		}

		function switchPanel( panel ) {
			container.querySelectorAll( '.floppy-nav' ).forEach( function ( button ) {
				button.classList.toggle( 'is-active', button.getAttribute( 'data-panel' ) === panel );
			} );
			if ( panel === 'files' || panel === 'shared' ) {
				loadFiles();
			} else if ( panel === 'devices' ) {
				loadDevices().then( renderDevices );
			} else if ( panel === 'diagnostics' ) {
				loadHealth().then( renderDiagnostics );
			} else {
				panelRoot.innerHTML = '<div class="floppy-panel"><h2>Sync Activity</h2><p>Cursor-based sync is available at <code>/floppy/v1/sync/changes</code>.</p></div>';
			}
		}

		function showError( error ) {
			markReady( ctx );
			notify( error && error.message ? error.message : 'Floppy request failed.', 'error' );
		}

		container.addEventListener( 'click', function ( event ) {
			var nav = event.target.closest( '.floppy-nav' );
			if ( nav ) {
				switchPanel( nav.getAttribute( 'data-panel' ) );
				return;
			}

			var action = event.target.closest( '[data-action]' );
			if ( action ) {
				var name = action.getAttribute( 'data-action' );
				if ( name === 'upload' ) {
					fileInput.click();
				} else if ( name === 'new-folder' ) {
					createFolder();
				} else if ( name === 'refresh' ) {
					loadFiles();
				} else if ( name === 'home' ) {
					state.parentId = 0;
					loadFiles();
				} else if ( name === 'toggle-view' ) {
					state.view = state.view === 'grid' ? 'list' : 'grid';
					renderFiles();
				}
				return;
			}

			var item = event.target.closest( '.floppy-item' );
			if ( item ) {
				openItem( Number( item.getAttribute( 'data-id' ) ), item.getAttribute( 'data-kind' ) );
				return;
			}

			if ( event.target.closest( '[data-cancel-folder]' ) ) {
				var form = container.querySelector( '[data-folder-form]' );
				if ( form ) {
					form.remove();
				}
			}
		} );

		container.addEventListener( 'dragover', function ( event ) {
			event.preventDefault();
			container.classList.add( 'is-dragging' );
		} );
		container.addEventListener( 'dragleave', function () {
			container.classList.remove( 'is-dragging' );
		} );
		container.addEventListener( 'drop', function ( event ) {
			event.preventDefault();
			container.classList.remove( 'is-dragging' );
			uploadFiles( event.dataTransfer.files );
		} );
		fileInput.addEventListener( 'change', function () {
			uploadFiles( fileInput.files );
			fileInput.value = '';
		} );

		loadHealth();
		loadDevices();
		loadFiles();

		return function () {
			container.innerHTML = '';
		};
	}

	function markLoading( ctx ) {
		if ( ctx && ctx.window && typeof ctx.window.markLoading === 'function' ) {
			ctx.window.markLoading();
		}
	}

	function markReady( ctx ) {
		if ( ctx && ctx.window && typeof ctx.window.markReady === 'function' ) {
			ctx.window.markReady();
		}
	}

	function formatBytes( bytes ) {
		bytes = Number( bytes || 0 );
		if ( bytes < 1024 ) {
			return bytes + ' B';
		}
		if ( bytes < 1024 * 1024 ) {
			return Math.round( bytes / 1024 ) + ' KB';
		}
		return ( bytes / 1024 / 1024 ).toFixed( 1 ) + ' MB';
	}

	function escapeHtml( value ) {
		return String( value ).replace( /[&<>"']/g, function ( char ) {
			return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[ char ];
		} );
	}

	function registerDesktopModeExtensions() {
		window.desktopModeNativeWindows = window.desktopModeNativeWindows || {};
		window.desktopModeNativeWindows[ config.windowId || 'floppy-drive' ] = function ( container, ctx ) {
			return mount( container, ctx );
		};

		if ( desktop && typeof desktop.registerCommand === 'function' ) {
			[
				{ slug: 'floppy/open', label: 'Open Floppy', owner: 'floppy-desktop-mode', run: openWindow },
				{ slug: 'floppy/search', label: 'Search Floppy', owner: 'floppy-desktop-mode', run: openWindow },
				{ slug: 'floppy/upload', label: 'Upload to Floppy', owner: 'floppy-desktop-mode', run: openWindow },
				{ slug: 'floppy/devices', label: 'Show Floppy Devices', owner: 'floppy-desktop-mode', run: openWindow },
				{ slug: 'floppy/diagnostics', label: 'Run Floppy Diagnostics', owner: 'floppy-desktop-mode', run: openWindow }
			].forEach( function ( command ) {
				desktop.registerCommand( command );
			} );
		}

		if ( desktop && typeof desktop.registerSettingsTab === 'function' ) {
			desktop.registerSettingsTab( {
				id: 'floppy',
				label: 'Floppy',
				owner: 'floppy-desktop-mode',
				render: function ( container ) {
					container.innerHTML = '<div class="floppy-settings"><h2>Floppy</h2><p>Private storage, device sync, quotas, and diagnostics are managed from the Floppy app.</p></div>';
				}
			} );
		}

		if ( desktop && typeof desktop.registerTitleBarButton === 'function' ) {
			desktop.registerTitleBarButton( {
				id: 'floppy-upload',
				owner: 'floppy-desktop-mode',
				match: matchesFloppyWindow,
				icon: 'dashicons-upload',
				label: 'Upload',
				onClick: openWindow
			} );
			desktop.registerTitleBarButton( {
				id: 'floppy-sync-status',
				owner: 'floppy-desktop-mode',
				match: matchesFloppyWindow,
				icon: 'dashicons-update',
				label: 'Sync status',
				onClick: openWindow
			} );
		}

		if ( desktop && desktop.files && typeof desktop.files.registerOpener === 'function' ) {
			desktop.files.registerOpener( {
				id: 'floppy-private-preview',
				label: 'Open in Floppy',
				owner: 'floppy-desktop-mode',
				types: [ 'attachment' ],
				sort: 20,
				handler: { kind: 'window', windowId: config.windowId || 'floppy-drive' }
			} );
		}

		if ( desktop && typeof desktop.subscribe === 'function' ) {
			desktop.subscribe( 'floppy.files.changed', function () {
				setBadge( 1 );
			} );
		}

		if ( hooks && desktop && desktop.HOOKS ) {
			var map = desktop.HOOKS;
			addAction( map.WINDOW_FOCUSED || 'desktop-mode.window.focused', 'floppy/focus', function ( payload ) {
				if ( payload && ( payload.id === config.windowId || payload.windowId === config.windowId ) ) {
					setBadge( '' );
				}
			} );
		}

		document.addEventListener( 'desktop-mode-layout-changed', function () {
			setBadge( '' );
		} );
	}

	function addAction( hookName, namespace, callback ) {
		if ( hooks && typeof hooks.addAction === 'function' && hookName ) {
			hooks.addAction( hookName, namespace, callback );
		}
	}

	function openWindow() {
		if ( desktop && typeof desktop.openWindow === 'function' ) {
			desktop.openWindow( config.windowId || 'floppy-drive', { source: 'command' } );
		}
	}

	function matchesFloppyWindow( win ) {
		var id = config.windowId || 'floppy-drive';
		return !! ( win && win.config && ( win.config.id === id || win.config.baseId === id ) );
	}

	if ( desktop && typeof desktop.ready === 'function' ) {
		desktop.ready( registerDesktopModeExtensions );
	} else if ( document.readyState === 'loading' ) {
		document.addEventListener( 'DOMContentLoaded', registerDesktopModeExtensions );
	} else {
		registerDesktopModeExtensions();
	}
}( window, document, window.wp || {} ) );
