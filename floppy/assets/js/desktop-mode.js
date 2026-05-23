( function ( window, document, wp ) {
	'use strict';

	var config = window.floppyDesktopConfig || {};
	var desktop = wp && wp.desktop ? wp.desktop : null;
	var hooks = wp && wp.hooks ? wp.hooks : null;
	var __ = wp && wp.i18n ? wp.i18n.__ : function ( text ) { return text; };
	var WINDOW_ID = config.windowId || 'floppy-drive';
	var OWNER = 'floppy-desktop-mode';
	var FILE_RENDER_LIMIT = 300;
	var badgeState = {
		uploads: 0,
		attention: 0,
		activity: 0
	};
	var appSummary = {
		files: 0,
		devices: 0,
		failingChecks: 0,
		lastSyncCursor: 0,
		lastStatus: __( 'Ready', 'floppy' ),
		lastState: 'ready'
	};
	var decoratedLauncherNodes = [];
	var currentMount = null;
	var hookRegistrations = [];
	var FALLBACK_HOOKS = {
		WINDOW_REOPENED: 'desktop-mode.window.reopened',
		WINDOW_FOCUSED: 'desktop-mode.window.focused',
		WINDOW_CLOSING: 'desktop-mode.window.closing',
		WINDOW_CLOSED: 'desktop-mode.window.closed',
		WINDOW_CONTENT_LOADED: 'desktop-mode.window.content-loaded',
		NATIVE_WINDOW_AFTER_RENDER: 'desktop-mode.native-window.after-render',
		FILE_DROP_FILES_DETECTED: 'desktop-mode.file-drop.files-detected',
		FILE_DROP_BEFORE_UPLOAD: 'desktop-mode.file-drop.before-upload',
		FILE_DROP_UPLOAD_STARTED: 'desktop-mode.file-drop.upload-started',
		FILE_DROP_UPLOAD_PROGRESS: 'desktop-mode.file-drop.upload-progress',
		FILE_DROP_AFTER_UPLOAD: 'desktop-mode.file-drop.after-upload',
		FILE_DROP_UPLOAD_FAILED: 'desktop-mode.file-drop.upload-failed',
		DOCK_TILE_CLASS: 'desktop-mode.dock.tile-class',
		DOCK_TILE_ELEMENT: 'desktop-mode.dock.tile-element',
		DOCK_TILE_RENDERED: 'desktop-mode.dock.tile-rendered',
		DOCK_TILE_TOOLTIP: 'desktop-mode.dock.tile-tooltip',
		ICON_BADGE_CHANGED: 'desktop-mode.icon.badge-changed',
		DESKTOP_ICON_CLICKED: 'desktop-mode.desktop-icon.clicked',
		DESKTOP_ICONS_RENDERED: 'desktop-mode.desktop-icons.rendered',
		DESKTOP_ICON_MENU_ITEMS: 'desktop-mode.desktop-icon.menu-items',
		FILES_TILE_CLASS: 'desktop-mode.files.tile-class',
		FILES_TILE_ELEMENT: 'desktop-mode.files.tile-element',
		FILES_TILE_RENDERED: 'desktop-mode.files.tile-rendered',
		NATIVE_WINDOW_BEFORE_CLOSE: 'desktop-mode.native-window.before-close'
	};
	var PANEL_LABELS = {
		files: __( 'My Drive', 'floppy' ),
		recents: __( 'Recents', 'floppy' ),
		trash: __( 'Trash', 'floppy' ),
		shared: __( 'Shared', 'floppy' ),
		conflicts: __( 'Conflicts', 'floppy' ),
		versions: __( 'Versions', 'floppy' ),
		sync: __( 'Sync', 'floppy' ),
		devices: __( 'Devices', 'floppy' ),
		diagnostics: __( 'Diagnostics', 'floppy' ),
		jobs: __( 'Jobs', 'floppy' ),
		evidence: __( 'Evidence', 'floppy' ),
		settings: __( 'Settings', 'floppy' )
	};
	var PANEL_ICONS = {
		files: 'media-default',
		recents: 'clock',
		trash: 'trash',
		shared: 'groups',
		conflicts: 'warning',
		versions: 'backup',
		sync: 'update',
		devices: 'desktop',
		diagnostics: 'chart-area',
		jobs: 'hourglass',
		evidence: 'clipboard',
		settings: 'admin-generic'
	};
	var OS_VISIBILITY_LABELS = {
		desktop: __( 'Desktop', 'floppy' ),
		dock: __( 'Dock', 'floppy' ),
		both: __( 'Both', 'floppy' ),
		hidden: __( 'Hidden', 'floppy' )
	};
	var FILE_KIND_FILTERS = {
		all: __( 'All', 'floppy' ),
		folder: __( 'Folders', 'floppy' ),
		file: __( 'Files', 'floppy' )
	};
	var FILE_SORT_LABELS = {
		name: __( 'Name', 'floppy' ),
		kind: __( 'Type', 'floppy' ),
		size: __( 'Size', 'floppy' ),
		updated: __( 'Modified', 'floppy' )
	};
	var REQUIRED_DESKTOP_HOOKS = [
		'WINDOW_REOPENED',
		'WINDOW_FOCUSED',
		'WINDOW_CONTENT_LOADED',
		'NATIVE_WINDOW_AFTER_RENDER',
		'NATIVE_WINDOW_BEFORE_CLOSE',
		'DOCK_TILE_CLASS',
		'DOCK_TILE_ELEMENT',
		'DOCK_TILE_RENDERED',
		'DOCK_TILE_TOOLTIP',
		'ICON_BADGE_CHANGED',
		'DESKTOP_ICON_CLICKED',
		'DESKTOP_ICONS_RENDERED',
		'DESKTOP_ICON_MENU_ITEMS'
	];
	var FALLBACK_DROP_HOOKS = [
		'FILE_DROP_FILES_DETECTED',
		'FILE_DROP_BEFORE_UPLOAD',
		'FILE_DROP_UPLOAD_STARTED',
		'FILE_DROP_UPLOAD_PROGRESS',
		'FILE_DROP_AFTER_UPLOAD',
		'FILE_DROP_UPLOAD_FAILED'
	];
	var DESKTOP_FEATURES = [
		{ key: 'openWindow', label: __( 'Native windows', 'floppy' ), test: function () { return desktop && typeof desktop.openWindow === 'function'; } },
		{ key: 'commands', label: __( 'Command palette', 'floppy' ), test: function () { return desktop && typeof desktop.registerCommand === 'function'; } },
		{ key: 'settings', label: __( 'OS Settings tab', 'floppy' ), test: function () { return desktop && typeof desktop.registerSettingsTab === 'function'; } },
		{ key: 'titlebar', label: __( 'Title bar buttons', 'floppy' ), test: function () { return desktop && typeof desktop.registerTitleBarButton === 'function'; } },
		{ key: 'fileOpener', label: __( 'File openers', 'floppy' ), test: function () { return desktop && desktop.files && typeof desktop.files.registerOpener === 'function'; } },
		{ key: 'osSettings', label: __( 'OS placement settings', 'floppy' ), test: function () { return desktop && typeof desktop.getOsSettings === 'function' && typeof desktop.updateOsSettings === 'function'; } },
		{ key: 'openOsSettings', label: __( 'Open OS Settings', 'floppy' ), test: function () { return desktop && typeof desktop.openOsSettings === 'function'; } },
		{ key: 'dragManager', label: __( 'Native drop targets', 'floppy' ), test: function () { return desktop && desktop.dragManager && typeof desktop.dragManager.registerDropTarget === 'function'; } },
		{ key: 'broadcasts', label: __( 'Broadcasts', 'floppy' ), test: function () { return desktop && typeof desktop.broadcast === 'function' && typeof desktop.subscribe === 'function'; } },
		{ key: 'badges', label: __( 'Badges', 'floppy' ), test: function () { return !! ( desktop && ( ( desktop.icons && typeof desktop.icons.setBadge === 'function' ) || ( desktop.dock && typeof desktop.dock.setBadge === 'function' ) || ( desktop.taskbar && typeof desktop.taskbar.setBadge === 'function' ) ) ); } }
	];

	function refreshHostApis() {
		desktop = wp && wp.desktop ? wp.desktop : desktop;
		hooks = wp && wp.hooks ? wp.hooks : hooks;
	}

	function apiRequest( path, options ) {
		options = Object.assign( {}, options || {} );
		options.headers = Object.assign( {}, options.headers || {}, {
			'X-WP-Nonce': config.nonce || ''
		} );

		if ( desktop && typeof desktop.fetch === 'function' ) {
			return desktop.fetch( config.restUrl + path.replace( /^\//, '' ), options ).then( parseResponse );
		}

		if ( wp && wp.apiFetch ) {
			return wp.apiFetch( Object.assign( {}, options, {
				path: '/floppy/v1/' + path.replace( /^\//, '' )
			} ) );
		}

		return window.fetch( config.restUrl + path.replace( /^\//, '' ), options ).then( parseResponse );
	}

	function parseResponse( response ) {
		if ( response && typeof response.json === 'function' ) {
			return response.json().then( function ( data ) {
				if ( ! response.ok ) {
					var error = new Error( data && data.message ? data.message : __( 'Floppy request failed.', 'floppy' ) );
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
			desktop.notify( {
				title: message,
				meta: { type: type || 'info' }
			} );
			return;
		}
		if ( window.console ) {
			( type === 'error' && window.console.error ? window.console.error : window.console.log )( '[Floppy] ' + message );
		}
	}

	function updateBadge() {
		var value = badgeState.uploads + badgeState.attention + badgeState.activity;
		setBadge( value > 0 ? String( value ) : '' );
	}

	function setUploadBadge( count ) {
		badgeState.uploads = Math.max( 0, Number( count ) || 0 );
		updateBadge();
	}

	function setAttentionBadge( count ) {
		badgeState.attention = Math.max( 0, Number( count ) || 0 );
		updateBadge();
	}

	function setActivityBadge( count ) {
		badgeState.activity = Math.max( 0, Number( count ) || 0 );
		updateBadge();
	}

	function setBadge( value ) {
		var count = parseInt( value, 10 );
		if ( ! count || count < 0 ) {
			count = 0;
		}
		if ( desktop && desktop.icons && typeof desktop.icons.setBadge === 'function' ) {
			desktop.icons.setBadge( WINDOW_ID, count );
		}
		if ( desktop && desktop.dock && typeof desktop.dock.setBadge === 'function' ) {
			desktop.dock.setBadge( WINDOW_ID, count );
		}
		if ( desktop && desktop.taskbar && typeof desktop.taskbar.setBadge === 'function' ) {
			desktop.taskbar.setBadge( WINDOW_ID, count );
		}
	}

	function decorateLauncherElement( element, surface ) {
		if ( ! element || ! element.classList ) {
			return element;
		}
		element.classList.add( surface === 'desktop' ? 'floppy-desktop-icon' : 'floppy-dock-tile' );
		element.setAttribute( 'data-floppy-launcher', 'drive' );
		updateLauncherElementState( element );
		if ( decoratedLauncherNodes.indexOf( element ) === -1 ) {
			decoratedLauncherNodes.push( element );
		}
		return element;
	}

	function updateLauncherElementState( element ) {
		if ( ! element || typeof element.setAttribute !== 'function' ) {
			return;
		}
		element.setAttribute( 'data-floppy-status', appSummary.lastStatus );
		element.setAttribute( 'data-floppy-state', appSummary.lastState || 'ready' );
	}

	function updateDecoratedLaunchers() {
		decoratedLauncherNodes = decoratedLauncherNodes.filter( function ( element ) {
			return element && element.isConnected;
		} );
		decoratedLauncherNodes.forEach( updateLauncherElementState );
	}

	function addClassValue( classes, className ) {
		var list = Array.isArray( classes ) ? classes.slice() : String( classes || '' ).split( /\s+/ ).filter( Boolean );
		if ( list.indexOf( className ) === -1 ) {
			list.push( className );
		}
		return list;
	}

	function addClassString( classes, className ) {
		return addClassValue( classes, className ).join( ' ' );
	}

	function placementMatchesFloppy( placement ) {
		var file = placement && placement.file ? placement.file : {};
		var meta = placement && placement.meta && typeof placement.meta === 'object' ? placement.meta : {};
		var refs = [
			file.ref,
			file.shortcutWindow,
			file.window,
			file.windowId,
			meta.__synthFromDockItem,
			meta.shortcutWindow,
			meta.windowId
		];
		return refs.some( function ( ref ) {
			return ref === WINDOW_ID || ref === 'desktop:' + WINDOW_ID || ref === 'dock:' + WINDOW_ID || ref === 'dock-promoted:' + WINDOW_ID;
		} );
	}

	function decorateFileTile( tile, placement ) {
		if ( ! tile || ! placementMatchesFloppy( placement ) ) {
			return tile;
		}
		tile.classList.add( 'floppy-desktop-file-tile' );
		tile.setAttribute( 'data-floppy-launcher', 'drive' );
		updateLauncherElementState( tile );
		if ( decoratedLauncherNodes.indexOf( tile ) === -1 ) {
			decoratedLauncherNodes.push( tile );
		}
		return tile;
	}

	function mount( container, ctx ) {
		refreshHostApis();

		var state = {
			parentId: 0,
			items: [],
			selected: null,
			shareTarget: null,
			health: null,
			healthError: null,
			deepHealth: null,
			deepHealthError: null,
			repairReport: null,
			debugBundle: null,
			devices: [],
			deviceError: null,
			sync: null,
				syncEvents: [],
				sharedEvents: [],
				recovery: null,
				recents: [],
				trashItems: [],
				conflicts: [],
				conflictError: null,
			conflictEndpointAvailable: null,
			versionTarget: null,
			versions: [],
			versionsError: null,
			versionsEndpointAvailable: null,
			exportJob: null,
			exportJobError: null,
			endpointAvailability: {},
			syncCursor: 0,
			uploading: 0,
			selected: {},
			filterText: '',
			kindFilter: 'all',
			sortKey: 'name',
			sortDirection: 'asc',
			nextCursor: '',
			hasMore: false,
			loadingMore: false,
			panel: 'files',
			osSettings: null,
			lastError: null,
			requestRaceCount: 0,
			dragTargetMode: 'none'
		};
		var cleanup = [];
		var namespace = OWNER + '/window-' + String( Date.now() ) + '-' + String( Math.random() ).slice( 2 );
		var panelRequestSerial = 0;

		container.classList.add( 'floppy-app' );
		setCurrentStateReference( container, state );
		setCurrentItemsReference( container, state.items );
		container.__floppyPaintFileList = paintFileList;
		container.innerHTML = [
			'<div class="floppy-shell">',
				'<aside class="floppy-sidebar" aria-label="' + escapeHtml( __( 'Floppy navigation', 'floppy' ) ) + '">',
					'<div class="floppy-brand"><span class="dashicons dashicons-archive" aria-hidden="true"></span><div><strong>Floppy</strong><span data-floppy-status aria-live="polite" aria-atomic="true">Ready</span></div></div>',
					renderNavButton( 'files', true ),
					renderNavButton( 'recents' ),
					renderNavButton( 'trash' ),
					renderNavButton( 'shared' ),
					renderNavButton( 'conflicts' ),
					renderNavButton( 'versions' ),
					renderNavButton( 'sync' ),
					renderNavButton( 'devices' ),
					renderNavButton( 'diagnostics' ),
					renderNavButton( 'jobs' ),
					renderNavButton( 'evidence' ),
					renderNavButton( 'settings' ),
				'</aside>',
				'<main class="floppy-main">',
					'<header class="floppy-toolbar">',
						'<div class="floppy-breadcrumb">',
							'<button class="floppy-icon-button" data-action="home" title="' + escapeHtml( __( 'Home', 'floppy' ) ) + '" aria-label="' + escapeHtml( __( 'Home', 'floppy' ) ) + '"><span class="dashicons dashicons-admin-home" aria-hidden="true"></span></button>',
							'<div><strong data-toolbar-title>My Drive</strong><span data-toolbar-subtitle>Private WordPress Drive</span></div>',
						'</div>',
						'<div class="floppy-actions">',
							'<button class="floppy-icon-button" data-action="new-folder" title="' + escapeHtml( __( 'New folder', 'floppy' ) ) + '" aria-label="' + escapeHtml( __( 'New folder', 'floppy' ) ) + '"><span class="dashicons dashicons-category" aria-hidden="true"></span></button>',
							'<button class="floppy-icon-button" data-action="upload" title="' + escapeHtml( __( 'Upload', 'floppy' ) ) + '" aria-label="' + escapeHtml( __( 'Upload', 'floppy' ) ) + '"><span class="dashicons dashicons-upload" aria-hidden="true"></span></button>',
							'<button class="floppy-icon-button" data-action="refresh" title="' + escapeHtml( __( 'Refresh', 'floppy' ) ) + '" aria-label="' + escapeHtml( __( 'Refresh', 'floppy' ) ) + '"><span class="dashicons dashicons-update" aria-hidden="true"></span></button>',
						'</div>',
					'</header>',
					'<div class="floppy-content" data-panel-root></div>',
					'<input class="floppy-hidden-file" type="file" multiple />',
				'</main>',
			'</div>'
		].join( '' );

		var panelRoot = container.querySelector( '[data-panel-root]' );
		var fileInput = container.querySelector( '.floppy-hidden-file' );
		var statusNode = container.querySelector( '[data-floppy-status]' );
		var titleNode = container.querySelector( '[data-toolbar-title]' );
		var subtitleNode = container.querySelector( '[data-toolbar-subtitle]' );

		function renderNavButton( panel, active ) {
			return '<button type="button" class="floppy-nav' + ( active ? ' is-active' : '' ) + '" data-panel="' + panel + '"' + ( active ? ' aria-current="page"' : '' ) + '>' +
				'<span class="dashicons dashicons-' + escapeHtml( PANEL_ICONS[ panel ] || 'admin-generic' ) + '" aria-hidden="true"></span><span>' + escapeHtml( PANEL_LABELS[ panel ] ) + '</span>' +
			'</button>';
		}

		function setStatus( message, type ) {
			appSummary.lastStatus = message || __( 'Ready', 'floppy' );
			appSummary.lastState = type || 'ready';
			updateDecoratedLaunchers();
			if ( statusNode ) {
				statusNode.textContent = appSummary.lastStatus;
				statusNode.className = type ? 'is-' + type : '';
			}
		}

		function updateChrome() {
			container.querySelectorAll( '.floppy-nav' ).forEach( function ( button ) {
				var active = button.getAttribute( 'data-panel' ) === state.panel;
				button.classList.toggle( 'is-active', active );
				if ( active ) {
					button.setAttribute( 'aria-current', 'page' );
				} else {
					button.removeAttribute( 'aria-current' );
				}
			} );
			if ( titleNode ) {
				titleNode.textContent = PANEL_LABELS[ state.panel ] || PANEL_LABELS.files;
			}
			if ( subtitleNode ) {
				subtitleNode.textContent = state.panel === 'files' && state.parentId ? __( 'Folder contents', 'floppy' ) : __( 'Private WordPress Drive', 'floppy' );
			}
		}

		function renderLoading( label ) {
			panelRoot.innerHTML = '<div class="floppy-loading-panel" role="status" aria-live="polite" aria-atomic="true"><span class="dashicons dashicons-update" aria-hidden="true"></span><strong>' + escapeHtml( label ) + '</strong></div>';
		}

		function beginPanelRequest( label ) {
			var token = ++panelRequestSerial;
			state.lastError = null;
			markLoading( ctx );
			renderLoading( label );
			return token;
		}

		function panelRequestIsCurrent( token ) {
			var current = token === panelRequestSerial;
			if ( ! current ) {
				state.requestRaceCount += 1;
			}
			return current;
		}

		function showPanelError( token ) {
			return function ( error ) {
				if ( ! panelRequestIsCurrent( token ) ) {
					return null;
				}
				showError( error );
				return null;
			};
		}

		function renderInlineError( error ) {
			var message = error && error.message ? error.message : __( 'Floppy request failed.', 'floppy' );
			state.lastError = {
				message: message,
				panel: state.panel,
				at: new Date().toISOString()
			};
			panelRoot.innerHTML = '<div class="floppy-empty floppy-error-state" role="alert"><strong>' + escapeHtml( __( 'Could not load this panel.', 'floppy' ) ) + '</strong><span>' + escapeHtml( message ) + '</span><button type="button" class="button button-primary" data-action="retry-panel">' + escapeHtml( __( 'Try Again', 'floppy' ) ) + '</button></div>';
		}

		function renderFiles() {
			updateChrome();
			var uploadLine = state.uploading ? '<div class="floppy-callout is-info"><strong>' + escapeHtml( String( state.uploading ) ) + '</strong> ' + escapeHtml( __( 'uploading now', 'floppy' ) ) + '</div>' : '';
			panelRoot.innerHTML = [
				'<div class="floppy-drop-zone floppy-files" data-files-panel>',
					uploadLine,
					'<div class="floppy-files-toolbar">',
						'<div class="floppy-files-title"><h2>' + escapeHtml( state.parentId ? __( 'Folder', 'floppy' ) : __( 'My Drive', 'floppy' ) ) + '</h2><span data-file-count></span></div>',
						'<label class="floppy-search"><span class="screen-reader-text">' + escapeHtml( __( 'Search this drive', 'floppy' ) ) + '</span><span class="dashicons dashicons-search" aria-hidden="true"></span><input type="search" data-file-search value="' + escapeHtml( state.filterText ) + '" placeholder="' + escapeHtml( __( 'Search this drive', 'floppy' ) ) + '" /></label>',
						'<div class="floppy-filter-tabs" role="group" aria-label="' + escapeHtml( __( 'File type filter', 'floppy' ) ) + '">' + renderKindFilterButtons() + '</div>',
						'<span class="floppy-sort-summary" data-file-sort-summary></span>',
					'</div>',
					'<div class="floppy-selection-bar" data-selection-bar hidden></div>',
					'<div class="floppy-file-list-wrap" data-file-list-wrap></div>',
				'</div>'
			].join( '' );
			paintFileList();
		}

		function renderKindFilterButtons() {
			return Object.keys( FILE_KIND_FILTERS ).map( function ( key ) {
				var active = state.kindFilter === key;
				return '<button type="button" class="' + ( active ? 'is-active' : '' ) + '" data-kind-filter="' + escapeHtml( key ) + '" aria-pressed="' + ( active ? 'true' : 'false' ) + '">' + escapeHtml( FILE_KIND_FILTERS[ key ] ) + '</button>';
			} ).join( '' );
		}

		function paintFileList() {
			currentMount = container;
			var wrap = panelRoot.querySelector( '[data-file-list-wrap]' );
			if ( ! wrap ) {
				return;
			}
			var visible = visibleFileItems();
			var selected = selectedFileItems();
			var rendered = visible.slice( 0, FILE_RENDER_LIMIT );
			var renderedSelected = rendered.filter( function ( item ) {
				return !! state.selected[ targetKey( item ) ];
			} );
			var countNode = panelRoot.querySelector( '[data-file-count]' );
			var sortNode = panelRoot.querySelector( '[data-file-sort-summary]' );
			var selectionBar = panelRoot.querySelector( '[data-selection-bar]' );
			if ( countNode ) {
				countNode.textContent = fileCountLabel( visible.length );
			}
			if ( sortNode ) {
				sortNode.textContent = sortSummaryLabel();
			}
			if ( selectionBar ) {
				selectionBar.hidden = ! selected.length;
				selectionBar.innerHTML = selected.length ? renderSelectionBar( selected ) : '';
			}
			if ( ! state.items.length ) {
				wrap.innerHTML = '<div class="floppy-empty"><strong>' + escapeHtml( __( 'No files yet.', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Drop files here or use the upload button to start a private drive.', 'floppy' ) ) + '</span></div>';
				return;
			}
			if ( ! visible.length ) {
				wrap.innerHTML = '<div class="floppy-empty"><strong>' + escapeHtml( __( 'No matching files.', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Try a different search or filter.', 'floppy' ) ) + '</span></div>';
				return;
			}
			var limitNotice = visible.length > rendered.length ? '<div class="floppy-list-limit"><span class="dashicons dashicons-performance" aria-hidden="true"></span><span>' + escapeHtml( __( 'Showing the first ', 'floppy' ) + String( rendered.length ) + __( ' matching items. Search, filter, sort, or load another page to narrow this large folder.', 'floppy' ) ) + '</span></div>' : '';
			wrap.innerHTML = [
				'<table class="floppy-file-table" aria-label="' + escapeHtml( __( 'Floppy files', 'floppy' ) ) + '">',
					'<colgroup><col class="floppy-col-check" /><col class="floppy-col-name" /><col class="floppy-col-type" /><col class="floppy-col-size" /><col class="floppy-col-modified" /><col class="floppy-col-actions" /></colgroup>',
					'<thead><tr>',
						'<th scope="col" class="floppy-file-check"><input type="checkbox" data-select-visible ' + ( renderedSelected.length && renderedSelected.length === rendered.length ? 'checked ' : '' ) + 'aria-label="' + escapeHtml( __( 'Select all rendered files', 'floppy' ) ) + '" /></th>',
						renderSortHeading( 'name', FILE_SORT_LABELS.name, 'floppy-file-name-heading' ),
						renderSortHeading( 'kind', FILE_SORT_LABELS.kind, '' ),
						renderSortHeading( 'size', FILE_SORT_LABELS.size, 'is-number' ),
						renderSortHeading( 'updated', FILE_SORT_LABELS.updated, '' ),
						'<th scope="col" class="floppy-file-actions-heading"><span class="screen-reader-text">' + escapeHtml( __( 'Actions', 'floppy' ) ) + '</span></th>',
					'</tr></thead>',
					'<tbody>',
						rendered.map( renderFileRow ).join( '' ),
					'</tbody>',
				'</table>',
				limitNotice,
				state.hasMore ? '<div class="floppy-file-footer"><button type="button" class="button" data-action="load-more" ' + ( state.loadingMore ? 'disabled' : '' ) + '>' + escapeHtml( state.loadingMore ? __( 'Loading...', 'floppy' ) : __( 'Load More', 'floppy' ) ) + '</button></div>' : ''
			].join( '' );
		}

		function renderSortHeading( key, label, className ) {
			var active = state.sortKey === key;
			var aria = active ? ( state.sortDirection === 'asc' ? 'ascending' : 'descending' ) : 'none';
			var icon = active && state.sortDirection === 'desc' ? 'arrow-down-alt2' : 'arrow-up-alt2';
			return '<th scope="col" class="' + escapeHtml( className || '' ) + '" aria-sort="' + aria + '"><button type="button" data-sort-key="' + escapeHtml( key ) + '" aria-label="' + escapeHtml( __( 'Sort by ', 'floppy' ) + label ) + '"><span>' + escapeHtml( label ) + '</span><span class="dashicons dashicons-' + icon + '" aria-hidden="true"></span></button></th>';
		}

		function renderSelectionBar( selected ) {
			var first = selected[0];
			var many = selected.length > 1;
			var canDownload = first && first.kind === 'file' && ! many;
			return [
				'<strong>' + escapeHtml( plural( selected.length, 'selected item', 'selected items' ) ) + '</strong>',
				'<button type="button" class="button" data-action="open-selected">' + escapeHtml( __( 'Open', 'floppy' ) ) + '</button>',
				'<button type="button" class="button" data-action="download-selected" ' + ( canDownload ? '' : 'disabled' ) + '>' + escapeHtml( __( 'Download', 'floppy' ) ) + '</button>',
				'<button type="button" class="button" data-action="share-selected" ' + ( many ? 'disabled' : '' ) + '>' + escapeHtml( __( 'Share', 'floppy' ) ) + '</button>',
				'<button type="button" class="button" data-action="rename-selected" ' + ( many ? 'disabled' : '' ) + '>' + escapeHtml( __( 'Rename', 'floppy' ) ) + '</button>',
				'<button type="button" class="button" data-action="trash-selected">' + escapeHtml( __( 'Move to Trash', 'floppy' ) ) + '</button>',
				'<button type="button" class="button button-link" data-action="clear-selection">' + escapeHtml( __( 'Clear', 'floppy' ) ) + '</button>'
			].join( '' );
		}

		function renderFileRow( item ) {
			var icon = item.kind === 'folder' ? 'category' : fileIcon( item.mime_type );
			var size = item.kind === 'file' ? formatBytes( item.size_bytes ) : __( 'Folder', 'floppy' );
			var updated = item.updated_at_gmt ? formatDate( item.updated_at_gmt ) : '';
			var key = targetKey( item );
			var selected = !! state.selected[ key ];
			return '<tr class="floppy-file-row' + ( selected ? ' is-selected' : '' ) + '" tabindex="0" aria-selected="' + ( selected ? 'true' : 'false' ) + '" data-selectable-row="1" data-row-key="' + escapeHtml( key ) + '" data-kind="' + escapeHtml( item.kind ) + '" data-id="' + escapeHtml( String( item.id ) ) + '">' +
				'<td class="floppy-file-check"><input type="checkbox" data-select-item="' + escapeHtml( key ) + '" ' + ( selected ? 'checked ' : '' ) + 'aria-label="' + escapeHtml( __( 'Select ', 'floppy' ) + item.name ) + '" /></td>' +
				'<td class="floppy-file-name-cell"><button type="button" class="floppy-file-open" data-open-item="' + escapeHtml( key ) + '"><span class="dashicons dashicons-' + icon + '" aria-hidden="true"></span><span><strong>' + escapeHtml( item.name ) + '</strong><small>' + escapeHtml( itemSubtitle( item ) ) + '</small></span></button></td>' +
				'<td>' + escapeHtml( kindLabel( item ) ) + '</td>' +
				'<td class="is-number">' + escapeHtml( size ) + '</td>' +
				'<td>' + escapeHtml( updated || '-' ) + '</td>' +
				'<td class="floppy-file-actions">' +
					( item.kind === 'file' ? '<button type="button" class="floppy-row-action" data-action="download-item" data-row-key="' + escapeHtml( key ) + '" title="' + escapeHtml( __( 'Download', 'floppy' ) ) + '" aria-label="' + escapeHtml( __( 'Download ', 'floppy' ) + item.name ) + '"><span class="dashicons dashicons-download" aria-hidden="true"></span></button>' : '' ) +
					'<button type="button" class="floppy-row-action" data-action="share-item" data-row-key="' + escapeHtml( key ) + '" title="' + escapeHtml( __( 'Share', 'floppy' ) ) + '" aria-label="' + escapeHtml( __( 'Share ', 'floppy' ) + item.name ) + '"><span class="dashicons dashicons-groups" aria-hidden="true"></span></button>' +
					'<button type="button" class="floppy-row-action" data-action="rename-item" data-row-key="' + escapeHtml( key ) + '" title="' + escapeHtml( __( 'Rename', 'floppy' ) ) + '" aria-label="' + escapeHtml( __( 'Rename ', 'floppy' ) + item.name ) + '"><span class="dashicons dashicons-edit" aria-hidden="true"></span></button>' +
					'<button type="button" class="floppy-row-action is-danger" data-action="trash-item" data-row-key="' + escapeHtml( key ) + '" title="' + escapeHtml( __( 'Move to Trash', 'floppy' ) ) + '" aria-label="' + escapeHtml( __( 'Move to Trash ', 'floppy' ) + item.name ) + '"><span class="dashicons dashicons-trash" aria-hidden="true"></span></button>' +
				'</td>' +
			'</tr>';
		}

		function currentShareTarget() {
			if ( ! state.shareTarget && state.items.length ) {
				state.shareTarget = targetKey( state.items[0] );
			}
			if ( ! state.shareTarget ) {
				return null;
			}
			var parts = state.shareTarget.split( ':' );
			return state.items.filter( function ( item ) {
				return item.kind === parts[0] && Number( item.id ) === Number( parts[1] );
			} )[0] || null;
		}

		function renderShared() {
			updateChrome();
			var target = currentShareTarget();
			var itemList = state.items.length ? state.items.map( function ( item ) {
				var active = target && target.kind === item.kind && Number( target.id ) === Number( item.id );
				return '<button type="button" class="floppy-target' + ( active ? ' is-active' : '' ) + '" data-share-target="' + escapeHtml( targetKey( item ) ) + '">' +
					'<span class="dashicons dashicons-' + ( item.kind === 'folder' ? 'category' : 'media-default' ) + '"></span>' +
					'<span><strong>' + escapeHtml( item.name ) + '</strong><small>' + escapeHtml( item.kind === 'folder' ? __( 'Folder', 'floppy' ) : formatBytes( item.size_bytes ) ) + '</small></span>' +
				'</button>';
			} ).join( '' ) : '<div class="floppy-empty"><strong>' + escapeHtml( __( 'Nothing to share yet.', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Add files first, then grant access here.', 'floppy' ) ) + '</span></div>';
			var events = state.sharedEvents.length ? state.sharedEvents.map( renderSyncEvent ).join( '' ) : '<div class="floppy-empty"><strong>' + escapeHtml( __( 'No recent share changes.', 'floppy' ) ) + '</strong></div>';

			panelRoot.innerHTML = [
				'<div class="floppy-panel-grid">',
					'<section class="floppy-panel">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Share Access', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Grant or revoke exact user and role access for the selected file or folder.', 'floppy' ) ) + '</p></div></div>',
						'<div class="floppy-target-list">' + itemList + '</div>',
					'</section>',
					'<section class="floppy-panel">',
						'<h2>' + escapeHtml( target ? target.name : __( 'Selected Item', 'floppy' ) ) + '</h2>',
						renderShareForm( target ),
					'</section>',
					'<section class="floppy-panel floppy-panel--wide">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Share Activity', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Recent access changes from the sync feed.', 'floppy' ) ) + '</p></div></div>',
						'<div class="floppy-event-list">' + events + '</div>',
					'</section>',
				'</div>'
			].join( '' );
		}

		function renderShareForm( target ) {
			if ( ! target ) {
				return '<div class="floppy-empty"><strong>' + escapeHtml( __( 'Choose an item', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Select a file or folder from the list to manage access.', 'floppy' ) ) + '</span></div>';
			}
			return [
				'<form class="floppy-form floppy-share-form" data-share-form>',
					'<label><span>' + escapeHtml( __( 'Principal', 'floppy' ) ) + '</span><select name="principal_type"><option value="user">' + escapeHtml( __( 'WordPress user ID', 'floppy' ) ) + '</option><option value="role">' + escapeHtml( __( 'Role slug', 'floppy' ) ) + '</option></select></label>',
					'<label><span>' + escapeHtml( __( 'Value', 'floppy' ) ) + '</span><input type="text" name="principal_ref" autocomplete="off" placeholder="12 or editor" required /></label>',
					'<label><span>' + escapeHtml( __( 'Access', 'floppy' ) ) + '</span><select name="capability"><option value="read">' + escapeHtml( __( 'Read', 'floppy' ) ) + '</option><option value="write">' + escapeHtml( __( 'Write', 'floppy' ) ) + '</option></select></label>',
					'<div class="floppy-form-actions"><button type="submit" class="button button-primary">' + escapeHtml( __( 'Share', 'floppy' ) ) + '</button><button type="button" class="button" data-action="unshare">' + escapeHtml( __( 'Revoke Exact Grant', 'floppy' ) ) + '</button></div>',
				'</form>'
			].join( '' );
		}

		function renderRecents() {
			updateChrome();
			setCurrentItemsReference( container, state.recents );
			panelRoot.innerHTML = [
				'<div class="floppy-panel-grid">',
					'<section class="floppy-stat"><span class="dashicons dashicons-clock"></span><strong>' + escapeHtml( String( state.recents.length ) ) + '</strong><small>' + escapeHtml( __( 'Recent items', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-stat"><span class="dashicons dashicons-shield"></span><strong>' + escapeHtml( __( 'Private', 'floppy' ) ) + '</strong><small>' + escapeHtml( __( 'Authenticated access', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-panel floppy-panel--wide">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Recents', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Recently updated WordPress-owned files and folders.', 'floppy' ) ) + '</p></div><button type="button" class="button button-primary" data-action="recents-refresh">' + escapeHtml( __( 'Refresh', 'floppy' ) ) + '</button></div>',
						renderRecoveryTable( state.recents, 'recents' ),
					'</section>',
				'</div>'
			].join( '' );
		}

		function renderTrash() {
			updateChrome();
			setCurrentItemsReference( container, state.trashItems );
			var counts = state.recovery && state.recovery.trash && state.recovery.trash.counts ? state.recovery.trash.counts : {};
			panelRoot.innerHTML = [
				'<div class="floppy-panel-grid">',
					'<section class="floppy-stat"><span class="dashicons dashicons-media-default"></span><strong>' + escapeHtml( String( counts.files || 0 ) ) + '</strong><small>' + escapeHtml( __( 'Trashed files', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-stat"><span class="dashicons dashicons-category"></span><strong>' + escapeHtml( String( counts.folders || 0 ) ) + '</strong><small>' + escapeHtml( __( 'Trashed folders', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-panel floppy-panel--wide">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Trash', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Restore deleted items before they leave the retention window.', 'floppy' ) ) + '</p></div><button type="button" class="button button-primary" data-action="trash-refresh">' + escapeHtml( __( 'Refresh', 'floppy' ) ) + '</button></div>',
						renderRecoveryTable( state.trashItems, 'trash' ),
					'</section>',
				'</div>'
			].join( '' );
		}

		function renderRecoveryTable( items, mode ) {
			if ( ! items.length ) {
				var emptyTitle = mode === 'trash' ? __( 'Trash is empty.', 'floppy' ) : __( 'No recent items yet.', 'floppy' );
				var emptyText = mode === 'trash' ? __( 'Trashed files and folders will appear here with restore actions.', 'floppy' ) : __( 'Updates from your private drive will appear here.', 'floppy' );
				return '<div class="floppy-empty"><strong>' + escapeHtml( emptyTitle ) + '</strong><span>' + escapeHtml( emptyText ) + '</span></div>';
			}

			return [
				'<div class="floppy-table-wrap">',
					'<table class="floppy-file-table" aria-label="' + escapeHtml( mode === 'trash' ? __( 'Trash', 'floppy' ) : __( 'Recents', 'floppy' ) ) + '">',
						'<colgroup><col class="floppy-col-name" /><col class="floppy-col-type" /><col class="floppy-col-size" /><col class="floppy-col-modified" /><col class="floppy-col-actions" /></colgroup>',
						'<thead><tr><th scope="col">' + escapeHtml( __( 'Name', 'floppy' ) ) + '</th><th scope="col">' + escapeHtml( __( 'Type', 'floppy' ) ) + '</th><th scope="col" class="is-number">' + escapeHtml( __( 'Size', 'floppy' ) ) + '</th><th scope="col">' + escapeHtml( __( 'Modified', 'floppy' ) ) + '</th><th scope="col"><span class="screen-reader-text">' + escapeHtml( __( 'Actions', 'floppy' ) ) + '</span></th></tr></thead>',
						'<tbody>' + items.map( function ( item ) { return renderRecoveryRow( item, mode ); } ).join( '' ) + '</tbody>',
					'</table>',
				'</div>'
			].join( '' );
		}

		function renderRecoveryRow( item, mode ) {
			var key = targetKey( item );
			var icon = item.kind === 'folder' ? 'category' : fileIcon( item.mime_type );
			var size = item.kind === 'file' ? formatBytes( item.size_bytes ) : __( 'Folder', 'floppy' );
			var updated = item.updated_at_gmt ? formatDate( item.updated_at_gmt ) : '';
			var primary = mode === 'trash' ? __( 'Restore ', 'floppy' ) + item.name : __( 'Open ', 'floppy' ) + item.name;
			var primaryAction = mode === 'trash' ? 'restore-item' : 'open-recovery-item';
			var actions = mode === 'trash'
				? '<button type="button" class="button button-primary" data-action="restore-item" data-row-key="' + escapeHtml( key ) + '">' + escapeHtml( __( 'Restore', 'floppy' ) ) + '</button>'
				: '<button type="button" class="button" data-action="open-recovery-item" data-row-key="' + escapeHtml( key ) + '">' + escapeHtml( __( 'Open', 'floppy' ) ) + '</button>';

			return '<tr class="floppy-file-row" tabindex="0" data-recovery-mode="' + escapeHtml( mode ) + '" data-row-key="' + escapeHtml( key ) + '" data-kind="' + escapeHtml( item.kind ) + '" data-id="' + escapeHtml( String( item.id ) ) + '">' +
				'<td class="floppy-file-name-cell"><button type="button" class="floppy-file-open" data-action="' + escapeHtml( primaryAction ) + '" data-row-key="' + escapeHtml( key ) + '" aria-label="' + escapeHtml( primary ) + '"><span class="dashicons dashicons-' + icon + '" aria-hidden="true"></span><span><strong>' + escapeHtml( item.name ) + '</strong><small>' + escapeHtml( itemSubtitle( item ) ) + '</small></span></button></td>' +
				'<td>' + escapeHtml( kindLabel( item ) ) + '</td>' +
				'<td class="is-number">' + escapeHtml( size ) + '</td>' +
				'<td>' + escapeHtml( updated || '-' ) + '</td>' +
				'<td class="floppy-file-actions">' + actions + '</td>' +
			'</tr>';
		}

		function renderConflicts() {
			updateChrome();
			var cards = state.conflicts.length ? state.conflicts.map( renderConflictCard ).join( '' ) : '<div class="floppy-empty"><strong>' + escapeHtml( __( 'No conflicts found.', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Stale edits and rename collisions will appear here when the sync feed reports them.', 'floppy' ) ) + '</span></div>';
			var endpointNotice = state.conflictEndpointAvailable === false ? '<div class="floppy-callout"><strong>' + escapeHtml( __( 'Server conflict queue not installed yet', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'This beta shell is using conflict events from the sync feed until the optional conflicts endpoint is available.', 'floppy' ) ) + '</span></div>' : '';
			panelRoot.innerHTML = [
				'<div class="floppy-panel-grid">',
					'<section class="floppy-stat"><span class="dashicons dashicons-warning"></span><strong>' + escapeHtml( String( state.conflicts.length ) ) + '</strong><small>' + escapeHtml( __( 'Open conflicts', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-stat"><span class="dashicons dashicons-update"></span><strong>' + escapeHtml( String( state.syncCursor || 0 ) ) + '</strong><small>' + escapeHtml( __( 'Sync cursor', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-panel floppy-panel--wide">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Conflict Center', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Review stale writes and collisions without overwriting user edits.', 'floppy' ) ) + '</p></div><div class="floppy-button-row"><button type="button" class="button" data-action="open-sync">' + escapeHtml( __( 'Open Sync Feed', 'floppy' ) ) + '</button><button type="button" class="button button-primary" data-action="conflict-refresh">' + escapeHtml( __( 'Refresh', 'floppy' ) ) + '</button></div></div>',
						endpointNotice,
						'<div class="floppy-card-list">' + cards + '</div>',
					'</section>',
				'</div>'
			].join( '' );
		}

		function renderConflictCard( conflict ) {
			var reason = conflict.reason || conflict.event_type || __( 'Conflict', 'floppy' );
			var name = conflict.local_name || conflict.name || conflict.target_name || conflict.item_name || '';
			var status = conflict.state || conflict.status || 'open';
			var uuid = conflict.conflict_uuid || conflict.uuid || '';
			var target = conflict.target_type ? conflict.target_type + ' #' + String( conflict.target_id || 0 ) : ( conflict.file_id ? 'file #' + String( conflict.file_id ) : '' );
			var actions = uuid && status === 'open' ? '<div class="floppy-card-actions">' +
				renderConflictActionButton( uuid, 'retry_upload', __( 'Retry', 'floppy' ), '' ) +
				renderConflictActionButton( uuid, 'keep_both', __( 'Keep Both', 'floppy' ), '' ) +
				renderConflictActionButton( uuid, 'mark_resolved', __( 'Resolve', 'floppy' ), 'button-primary' ) +
				renderConflictActionButton( uuid, 'discard_local_copy', __( 'Discard', 'floppy' ), 'button-link-delete' ) +
			'</div>' : '';
			return '<article class="floppy-card is-warning">' +
				'<div><span class="dashicons dashicons-warning" aria-hidden="true"></span><div><strong>' + escapeHtml( reason ) + '</strong><small>' + escapeHtml( [ target, name, status, formatDate( conflict.created_at_gmt || conflict.updated_at_gmt ) ].filter( Boolean ).join( ' · ' ) ) + '</small></div></div>' +
				'<p>' + escapeHtml( conflict.message || __( 'The server kept the canonical item and Floppy preserved the user edit as a separate conflict copy.', 'floppy' ) ) + '</p>' +
				actions +
			'</article>';
		}

		function renderConflictActionButton( uuid, actionName, label, className ) {
			return '<button type="button" class="button ' + escapeHtml( className || '' ) + '" data-action="conflict-action" data-conflict-uuid="' + escapeHtml( uuid ) + '" data-conflict-action="' + escapeHtml( actionName ) + '">' + escapeHtml( label ) + '</button>';
		}

		function renderVersions() {
			updateChrome();
			var files = state.items.filter( function ( item ) {
				return item.kind === 'file';
			} );
			var target = currentVersionTarget();
			var targetList = files.length ? files.map( function ( item ) {
				var active = target && Number( target.id ) === Number( item.id );
				return '<button type="button" class="floppy-target' + ( active ? ' is-active' : '' ) + '" data-version-target="' + escapeHtml( targetKey( item ) ) + '">' +
					'<span class="dashicons dashicons-' + fileIcon( item.mime_type ) + '"></span>' +
					'<span><strong>' + escapeHtml( item.name ) + '</strong><small>' + escapeHtml( formatBytes( item.size_bytes ) + ' · ' + ( item.content_version || __( 'current version', 'floppy' ) ) ) + '</small></span>' +
				'</button>';
			} ).join( '' ) : '<div class="floppy-empty"><strong>' + escapeHtml( __( 'No files loaded yet.', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Upload a file to see version evidence.', 'floppy' ) ) + '</span></div>';
			var versionRows = state.versions.length ? state.versions.map( renderVersionRow ).join( '' ) : renderCurrentVersionFallback( target );
			var endpointNotice = state.versionsEndpointAvailable === false ? '<div class="floppy-callout"><strong>' + escapeHtml( __( 'Version history endpoint not installed yet', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'This shell shows the current content and metadata versions now, and will render full history when the optional endpoint exists.', 'floppy' ) ) + '</span></div>' : '';

			panelRoot.innerHTML = [
				'<div class="floppy-panel-grid">',
					'<section class="floppy-panel">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Files', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Choose a file to inspect restore-ready version data.', 'floppy' ) ) + '</p></div></div>',
						'<div class="floppy-target-list">' + targetList + '</div>',
					'</section>',
					'<section class="floppy-panel">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( target ? target.name : __( 'Version History', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Version surfaces are authenticated and never use public media URLs.', 'floppy' ) ) + '</p></div><button type="button" class="button" data-action="version-refresh">' + escapeHtml( __( 'Refresh', 'floppy' ) ) + '</button></div>',
						endpointNotice,
						'<div class="floppy-card-list">' + versionRows + '</div>',
					'</section>',
				'</div>'
			].join( '' );
		}

		function renderVersionRow( version ) {
			var versionId = version.id || '';
			var actions = versionId ? '<div class="floppy-card-actions">' +
				'<button type="button" class="button" data-action="version-download" data-version-id="' + escapeHtml( String( versionId ) ) + '">' + escapeHtml( __( 'Download', 'floppy' ) ) + '</button>' +
				'<button type="button" class="button button-primary" data-action="version-restore" data-version-id="' + escapeHtml( String( versionId ) ) + '">' + escapeHtml( __( 'Restore', 'floppy' ) ) + '</button>' +
			'</div>' : '';
			return '<article class="floppy-card">' +
				'<div><span class="dashicons dashicons-backup" aria-hidden="true"></span><div><strong>' + escapeHtml( version.label || version.content_version || __( 'Version', 'floppy' ) ) + '</strong><small>' + escapeHtml( [ formatBytes( version.size_bytes ), version.content_hash ? version.content_hash.slice( 0, 12 ) : '', formatDate( version.created_at_gmt || version.updated_at_gmt ) ].filter( Boolean ).join( ' · ' ) ) + '</small></div></div>' +
				actions +
			'</article>';
		}

		function renderCurrentVersionFallback( target ) {
			if ( ! target ) {
				return '<div class="floppy-empty"><strong>' + escapeHtml( __( 'Choose a file', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Current version metadata will appear here.', 'floppy' ) ) + '</span></div>';
			}
			return '<article class="floppy-card">' +
				'<div><span class="dashicons dashicons-backup" aria-hidden="true"></span><div><strong>' + escapeHtml( __( 'Current version', 'floppy' ) ) + '</strong><small>' + escapeHtml( formatBytes( target.size_bytes ) + ' · ' + formatDate( target.updated_at_gmt ) ) + '</small></div></div>' +
				'<dl class="floppy-definition-list"><div><dt>' + escapeHtml( __( 'Content version', 'floppy' ) ) + '</dt><dd>' + escapeHtml( target.content_version || '-' ) + '</dd></div><div><dt>' + escapeHtml( __( 'Metadata version', 'floppy' ) ) + '</dt><dd>' + escapeHtml( target.metadata_version || '-' ) + '</dd></div><div><dt>' + escapeHtml( __( 'Checksum', 'floppy' ) ) + '</dt><dd>' + escapeHtml( target.content_hash || '-' ) + '</dd></div></dl>' +
			'</article>';
		}

		function renderJobs() {
			updateChrome();
			var queue = state.deepHealth && state.deepHealth.queues ? state.deepHealth.queues : {};
			var byStatus = queue.by_status || {};
			var exportMarkup = renderExportJob();
			panelRoot.innerHTML = [
				'<div class="floppy-panel-grid">',
					'<section class="floppy-stat"><span class="dashicons dashicons-clock"></span><strong>' + escapeHtml( String( countObjectValues( byStatus ) ) ) + '</strong><small>' + escapeHtml( __( 'Known jobs', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-stat"><span class="dashicons dashicons-warning"></span><strong>' + escapeHtml( String( queue.stale_running || 0 ) ) + '</strong><small>' + escapeHtml( __( 'Stale running', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-panel">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Job Queues', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Queue counts come from the admin deep-health endpoint.', 'floppy' ) ) + '</p></div><button type="button" class="button" data-action="jobs-refresh">' + escapeHtml( __( 'Refresh', 'floppy' ) ) + '</button></div>',
						renderStatusCounts( byStatus ),
					'</section>',
					'<section class="floppy-panel">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Export Drill', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Start an authenticated export job and track the redacted job response.', 'floppy' ) ) + '</p></div></div>',
						exportMarkup,
					'</section>',
				'</div>'
			].join( '' );
		}

		function renderExportJob() {
			if ( state.exportJobError ) {
				return '<div class="floppy-callout is-error"><strong>' + escapeHtml( __( 'Export unavailable', 'floppy' ) ) + '</strong><span>' + escapeHtml( state.exportJobError.message || __( 'The export endpoint is not available for this session.', 'floppy' ) ) + '</span></div><button type="button" class="button button-primary" data-action="export-start">' + escapeHtml( __( 'Try Export Drill', 'floppy' ) ) + '</button>';
			}
			if ( ! state.exportJob ) {
				return '<div class="floppy-callout"><strong>' + escapeHtml( __( 'No export drill started', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Use this before a beta tag to prove users can leave with metadata and files intact.', 'floppy' ) ) + '</span></div><button type="button" class="button button-primary" data-action="export-start">' + escapeHtml( __( 'Start Export Drill', 'floppy' ) ) + '</button>';
			}
			return '<div class="floppy-card-list">' +
				'<article class="floppy-card"><div><span class="dashicons dashicons-download" aria-hidden="true"></span><div><strong>' + escapeHtml( state.exportJob.status || __( 'queued', 'floppy' ) ) + '</strong><small>' + escapeHtml( state.exportJob.job_uuid || state.exportJob.uuid || '' ) + '</small></div></div>' + renderJobProgress( state.exportJob ) + '</article>' +
				'</div><div class="floppy-button-row"><button type="button" class="button" data-action="export-check">' + escapeHtml( __( 'Check Status', 'floppy' ) ) + '</button><button type="button" class="button button-primary" data-action="export-download" ' + ( state.exportJob.status === 'complete' ? '' : 'disabled' ) + '>' + escapeHtml( __( 'Download Export', 'floppy' ) ) + '</button></div>';
		}

		function renderEvidence() {
			updateChrome();
			var evidence = buildReleaseEvidence();
			var gates = releaseGates( evidence );
			var gateRows = gates.map( function ( gate ) {
				return '<article class="floppy-gate is-' + escapeHtml( gate.status ) + '"><span class="dashicons dashicons-' + ( gate.status === 'pass' ? 'yes-alt' : gate.status === 'fail' ? 'dismiss' : 'warning' ) + '"></span><div><strong>' + escapeHtml( gate.label ) + '</strong><small>' + escapeHtml( gate.message ) + '</small></div></article>';
			} ).join( '' );
			panelRoot.innerHTML = [
				'<div class="floppy-panel-grid">',
					'<section class="floppy-stat"><span class="dashicons dashicons-clipboard"></span><strong>' + escapeHtml( String( gates.filter( function ( gate ) { return gate.status === 'pass'; } ).length ) ) + '</strong><small>' + escapeHtml( __( 'Passing gates', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-stat"><span class="dashicons dashicons-admin-links"></span><strong>' + escapeHtml( evidence.support.correlation_id || '-' ) + '</strong><small>' + escapeHtml( __( 'Support correlation', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-panel floppy-panel--wide">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Release Evidence', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'A redacted Desktop Mode sidecar for beta release notes and support handoff.', 'floppy' ) ) + '</p></div><div class="floppy-button-row"><button type="button" class="button" data-action="evidence-refresh">' + escapeHtml( __( 'Refresh', 'floppy' ) ) + '</button><button type="button" class="button" data-action="debug-download">' + escapeHtml( __( 'Debug Bundle', 'floppy' ) ) + '</button><button type="button" class="button button-primary" data-action="evidence-download">' + escapeHtml( __( 'Download Evidence JSON', 'floppy' ) ) + '</button></div></div>',
						'<div class="floppy-gate-list">' + gateRows + '</div>',
					'</section>',
					'<section class="floppy-panel">',
						'<h2>' + escapeHtml( __( 'Desktop Mode Smoke', 'floppy' ) ) + '</h2>',
						renderHookAudit( evidence.desktop_mode ),
					'</section>',
					'<section class="floppy-panel">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Repair Dry Run', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Admin-only repair evidence without applying changes.', 'floppy' ) ) + '</p></div><button type="button" class="button" data-action="repair-dry-run">' + escapeHtml( __( 'Run Dry Run', 'floppy' ) ) + '</button></div>',
						renderRepairSummary( state.repairReport ),
					'</section>',
				'</div>'
			].join( '' );
		}

		function renderSync() {
			updateChrome();
			var events = state.syncEvents.length ? state.syncEvents.map( renderSyncEvent ).join( '' ) : '<div class="floppy-empty"><strong>' + escapeHtml( __( 'No sync changes found.', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'New uploads, shares, moves, and deletes will appear here.', 'floppy' ) ) + '</span></div>';
			var conflictCount = state.syncEvents.filter( function ( event ) {
				return String( event.event_type || '' ).indexOf( 'conflict' ) !== -1;
			} ).length;
			panelRoot.innerHTML = [
				'<div class="floppy-panel-grid">',
					'<section class="floppy-stat"><span class="dashicons dashicons-update"></span><strong>' + escapeHtml( String( state.syncCursor || 0 ) ) + '</strong><small>' + escapeHtml( __( 'Current cursor', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-stat"><span class="dashicons dashicons-clock"></span><strong>' + escapeHtml( String( state.syncEvents.length ) ) + '</strong><small>' + escapeHtml( __( 'Loaded events', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-stat"><span class="dashicons dashicons-warning"></span><strong>' + escapeHtml( String( conflictCount ) ) + '</strong><small>' + escapeHtml( __( 'Conflicts', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-panel floppy-panel--wide">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Sync Feed', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Append-only changes used by Finder and Desktop Mode clients.', 'floppy' ) ) + '</p></div><div class="floppy-button-row"><button type="button" class="button" data-action="sync-reset">' + escapeHtml( __( 'Latest', 'floppy' ) ) + '</button><button type="button" class="button button-primary" data-action="sync-more">' + escapeHtml( state.sync && state.sync.has_more ? __( 'Load More', 'floppy' ) : __( 'Refresh', 'floppy' ) ) + '</button></div></div>',
						'<div class="floppy-event-list">' + events + '</div>',
					'</section>',
				'</div>'
			].join( '' );
		}

		function renderSyncEvent( event ) {
			var payload = event.payload || {};
			var name = payload.name || payload.target_name || payload.principal_ref || '';
			return '<article class="floppy-event">' +
				'<span class="dashicons dashicons-' + eventIcon( event.event_type ) + '"></span>' +
				'<div><strong>' + escapeHtml( event.event_type || __( 'event', 'floppy' ) ) + '</strong><small>' + escapeHtml( event.target_type || '' ) + ' #' + escapeHtml( String( event.target_id || 0 ) ) + ( name ? ' · ' + escapeHtml( name ) : '' ) + '</small></div>' +
				'<time>' + escapeHtml( formatDate( event.created_at_gmt ) ) + '</time>' +
			'</article>';
		}

		function renderDevices() {
			updateChrome();
			var active = state.devices.filter( function ( device ) {
				return device.status === 'active';
			} ).length;
			var errored = state.devices.filter( function ( device ) {
				return !! device.last_error;
			} ).length;
			var rows = state.devices.length ? state.devices.map( function ( device ) {
				return '<article class="floppy-device">' +
					'<div><span class="dashicons dashicons-desktop"></span><strong>' + escapeHtml( device.device_name ) + '</strong><small>' + escapeHtml( device.scope || '' ) + '</small></div>' +
					'<span class="floppy-pill is-' + escapeHtml( device.status || 'unknown' ) + '">' + escapeHtml( device.status || __( 'unknown', 'floppy' ) ) + '</span>' +
					'<dl><div><dt>' + escapeHtml( __( 'Last Seen', 'floppy' ) ) + '</dt><dd>' + escapeHtml( formatDate( device.last_seen_at_gmt ) ) + '</dd></div><div><dt>' + escapeHtml( __( 'Last Sync', 'floppy' ) ) + '</dt><dd>' + escapeHtml( formatDate( device.last_sync_at_gmt ) ) + '</dd></div><div><dt>' + escapeHtml( __( 'Cursor', 'floppy' ) ) + '</dt><dd>' + escapeHtml( String( device.last_cursor || 0 ) ) + '</dd></div></dl>' +
					( device.last_error ? '<p class="floppy-error-text">' + escapeHtml( device.last_error ) + '</p>' : '' ) +
					( device.status === 'active' ? '<button type="button" class="button" data-action="device-revoke" data-device-uuid="' + escapeHtml( device.device_uuid ) + '">' + escapeHtml( __( 'Revoke', 'floppy' ) ) + '</button>' : '' ) +
				'</article>';
			} ).join( '' ) : '<div class="floppy-empty"><strong>' + escapeHtml( __( 'No approved devices yet.', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Connect Floppy for Mac to create a scoped sync device.', 'floppy' ) ) + '</span></div>';

			panelRoot.innerHTML = [
				'<div class="floppy-panel-grid">',
					'<section class="floppy-stat"><span class="dashicons dashicons-yes-alt"></span><strong>' + escapeHtml( String( active ) ) + '</strong><small>' + escapeHtml( __( 'Active devices', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-stat"><span class="dashicons dashicons-warning"></span><strong>' + escapeHtml( String( errored ) ) + '</strong><small>' + escapeHtml( __( 'Need attention', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-panel floppy-panel--wide">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Approved Macs', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Each device uses a scoped token that can be revoked without changing the WordPress password.', 'floppy' ) ) + '</p></div><button type="button" class="button" data-action="devices-refresh">' + escapeHtml( __( 'Refresh', 'floppy' ) ) + '</button></div>',
						'<div class="floppy-device-list">' + rows + '</div>',
					'</section>',
				'</div>'
			].join( '' );
		}

		function renderDiagnostics() {
			updateChrome();
			if ( state.healthError ) {
				panelRoot.innerHTML = '<div class="floppy-empty"><strong>' + escapeHtml( __( 'Diagnostics unavailable.', 'floppy' ) ) + '</strong><span>' + escapeHtml( state.healthError.message || __( 'Administrator diagnostics require a browser session.', 'floppy' ) ) + '</span></div>';
				return;
			}
			if ( ! state.health ) {
				panelRoot.innerHTML = '<div class="floppy-empty"><strong>' + escapeHtml( __( 'Diagnostics have not run yet.', 'floppy' ) ) + '</strong></div>';
				return;
			}
			var checks = Object.keys( state.health.checks || {} );
			var failing = checks.filter( function ( key ) {
				return ! state.health.checks[ key ].ok;
			} ).length;
			var rows = checks.map( function ( key ) {
				var check = state.health.checks[ key ];
				return '<tr><td><strong>' + escapeHtml( key.replace( /_/g, ' ' ) ) + '</strong></td><td><span class="floppy-pill is-' + ( check.ok ? 'pass' : 'fail' ) + '">' + escapeHtml( check.ok ? __( 'Pass', 'floppy' ) : __( 'Fail', 'floppy' ) ) + '</span></td><td>' + escapeHtml( check.label || '' ) + '</td><td>' + escapeHtml( check.message || '' ) + '</td></tr>';
			} ).join( '' );
			panelRoot.innerHTML = [
				'<div class="floppy-panel-grid">',
					'<section class="floppy-stat"><span class="dashicons dashicons-shield"></span><strong>' + escapeHtml( state.health.ok ? __( 'Ready', 'floppy' ) : __( 'Review', 'floppy' ) ) + '</strong><small>' + escapeHtml( __( 'Production health', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-stat"><span class="dashicons dashicons-warning"></span><strong>' + escapeHtml( String( failing ) ) + '</strong><small>' + escapeHtml( __( 'Failed checks', 'floppy' ) ) + '</small></section>',
					'<section class="floppy-panel floppy-panel--wide">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Diagnostics', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Private storage, HTTPS, schema, and Desktop Mode readiness.', 'floppy' ) ) + '</p></div><button type="button" class="button" data-action="health-refresh">' + escapeHtml( __( 'Refresh', 'floppy' ) ) + '</button></div>',
						'<div class="floppy-table-wrap"><table><tbody>' + rows + '</tbody></table></div>',
					'</section>',
				'</div>'
			].join( '' );
		}

		function renderSettings() {
			updateChrome();
			panelRoot.innerHTML = [
				'<div class="floppy-panel-grid">',
					'<section class="floppy-panel">',
						'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Desktop Placement', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Uses Desktop Mode OS Settings for the Floppy launcher.', 'floppy' ) ) + '</p></div></div>',
						renderOsSettingsControls( state.osSettings ),
						'<div class="floppy-button-row"><button type="button" class="button" data-action="desktop-settings">' + escapeHtml( __( 'Open OS Settings', 'floppy' ) ) + '</button><button type="button" class="button" data-action="settings-refresh">' + escapeHtml( __( 'Refresh', 'floppy' ) ) + '</button></div>',
					'</section>',
					'<section class="floppy-panel">',
						'<h2>' + escapeHtml( __( 'Limits', 'floppy' ) ) + '</h2>',
						'<dl class="floppy-definition-list"><div><dt>' + escapeHtml( __( 'Maximum upload', 'floppy' ) ) + '</dt><dd>' + escapeHtml( formatBytes( config.maxFileSize || 0 ) ) + '</dd></div><div><dt>' + escapeHtml( __( 'Desktop Mode', 'floppy' ) ) + '</dt><dd>' + escapeHtml( config.desktopMode ? __( 'Available', 'floppy' ) : __( 'Not detected', 'floppy' ) ) + '</dd></div><div><dt>' + escapeHtml( __( 'Uploads', 'floppy' ) ) + '</dt><dd>' + escapeHtml( config.capabilities && config.capabilities.upload ? __( 'Allowed', 'floppy' ) : __( 'Unavailable', 'floppy' ) ) + '</dd></div></dl>',
					'</section>',
					'<section class="floppy-panel floppy-panel--wide">',
						renderOnboardingMarkup(),
					'</section>',
				'</div>'
			].join( '' );
		}

		function fetchFiles( append ) {
			var path = 'files?parent_id=' + encodeURIComponent( state.parentId ) + '&limit=100';
			if ( append && state.nextCursor ) {
				path += '&cursor=' + encodeURIComponent( state.nextCursor );
			}
			return apiRequest( path ).then( function ( data ) {
				state.items = append ? mergeItems( state.items, data.items || [] ) : ( data.items || [] );
				state.nextCursor = data.next_cursor || '';
				state.hasMore = !! data.has_more;
				setCurrentItemsReference( container, state.items );
				pruneSelection();
				appSummary.files = state.items.length;
				return data;
			} );
		}

		function loadFiles() {
			var token = beginPanelRequest( __( 'Loading files', 'floppy' ) );
			state.nextCursor = '';
			state.hasMore = false;
			return fetchFiles( false ).then( function () {
				if ( ! panelRequestIsCurrent( token ) ) {
					return null;
				}
				renderFiles();
				markReady( ctx );
			} ).catch( showPanelError( token ) );
		}

		function loadMoreFiles() {
			if ( state.loadingMore || ! state.hasMore ) {
				return;
			}
			state.loadingMore = true;
			paintFileList();
			fetchFiles( true ).then( function () {
				state.loadingMore = false;
				paintFileList();
			} ).catch( function ( error ) {
				state.loadingMore = false;
				paintFileList();
				showError( error );
			} );
		}

		function loadShared() {
			var token = beginPanelRequest( __( 'Loading sharing', 'floppy' ) );
			return Promise.all( [
				fetchFiles(),
				fetchSharedEvents()
			] ).then( function () {
				if ( ! panelRequestIsCurrent( token ) ) {
					return null;
				}
				if ( ! currentShareTarget() && state.items.length ) {
					state.shareTarget = targetKey( state.items[0] );
				}
				renderShared();
				markReady( ctx );
			} ).catch( showPanelError( token ) );
		}

		function fetchRecoveryCenter() {
			return apiRequest( 'recovery?limit=75' ).then( function ( data ) {
				state.recovery = data || {};
				state.recents = data && data.recents && data.recents.items ? data.recents.items : [];
				state.trashItems = data && data.trash && data.trash.items ? data.trash.items : [];
				state.endpointAvailability.recovery = {
					available: true,
					checked_at: new Date().toISOString()
				};
				return data;
			} ).catch( function ( error ) {
				state.recovery = null;
				state.recents = [];
				state.trashItems = [];
				state.endpointAvailability.recovery = {
					available: false,
					status: errorStatus( error ),
					message: error && error.message ? error.message : __( 'Recovery endpoint unavailable.', 'floppy' ),
					checked_at: new Date().toISOString()
				};
				throw error;
			} );
		}

		function loadRecents() {
			var token = beginPanelRequest( __( 'Loading recents', 'floppy' ) );
			return fetchRecoveryCenter().then( function () {
				if ( ! panelRequestIsCurrent( token ) ) {
					return null;
				}
				renderRecents();
				markReady( ctx );
			} ).catch( showPanelError( token ) );
		}

		function loadTrash() {
			var token = beginPanelRequest( __( 'Loading Trash', 'floppy' ) );
			return fetchRecoveryCenter().then( function () {
				if ( ! panelRequestIsCurrent( token ) ) {
					return null;
				}
				renderTrash();
				markReady( ctx );
			} ).catch( showPanelError( token ) );
		}

		function fetchSharedEvents() {
			return apiRequest( 'sync/changes?cursor=0&limit=50' ).then( function ( data ) {
				state.sharedEvents = ( data.events || [] ).filter( function ( event ) {
					return String( event.event_type || '' ).indexOf( 'share.' ) === 0;
				} ).slice( -10 ).reverse();
			} ).catch( function () {
				state.sharedEvents = [];
			} );
		}

		function optionalRequest( path, key ) {
			return apiRequest( path ).then( function ( data ) {
				state.endpointAvailability[ key ] = {
					available: true,
					checked_at: new Date().toISOString()
				};
				return data;
			} ).catch( function ( error ) {
				state.endpointAvailability[ key ] = {
					available: false,
					status: errorStatus( error ),
					message: error && error.message ? error.message : __( 'Endpoint unavailable.', 'floppy' ),
					checked_at: new Date().toISOString()
				};
				return null;
			} );
		}

		function ensureSyncEvents() {
			if ( state.syncEvents.length ) {
				return Promise.resolve( state.syncEvents );
			}
			return apiRequest( 'sync/changes?cursor=0&limit=50' ).then( function ( data ) {
				state.sync = data;
				state.syncCursor = data.next_cursor || 0;
				state.syncEvents = data.events || [];
				return state.syncEvents;
			} ).catch( function () {
				state.syncEvents = [];
				return state.syncEvents;
			} );
		}

		function loadHealth() {
			return apiRequest( 'health' ).then( function ( data ) {
				state.health = data;
				state.healthError = null;
				appSummary.failingChecks = failingCheckCount( data );
				setAttentionBadge( appSummary.failingChecks );
			} ).catch( function ( error ) {
				state.health = null;
				state.healthError = error;
			} );
		}

		function loadDiagnostics() {
			var token = beginPanelRequest( __( 'Loading diagnostics', 'floppy' ) );
			return loadHealth().then( function () {
				if ( ! panelRequestIsCurrent( token ) ) {
					return null;
				}
				renderDiagnostics();
				markReady( ctx );
			} ).catch( showPanelError( token ) );
		}

		function loadDeepHealth() {
			return optionalRequest( 'maintenance/deep-health', 'deep_health' ).then( function ( data ) {
				state.deepHealth = data;
				state.deepHealthError = data ? null : state.endpointAvailability.deep_health;
				return data;
			} );
		}

		function loadRepairDryRun() {
			return optionalRequest( 'maintenance/repair', 'repair' ).then( function ( data ) {
				state.repairReport = data;
				return data;
			} );
		}

		function loadConflicts() {
			var token = beginPanelRequest( __( 'Loading conflicts', 'floppy' ) );
			return Promise.all( [
				optionalRequest( 'conflicts?limit=50', 'conflicts' ),
				ensureSyncEvents()
			] ).then( function ( results ) {
				if ( ! panelRequestIsCurrent( token ) ) {
					return null;
				}
				var data = results[0];
				state.conflictEndpointAvailable = !! data;
				state.conflicts = normalizeConflictRows( data, state.syncEvents );
				renderConflicts();
				markReady( ctx );
			} ).catch( showPanelError( token ) );
		}

		function loadVersions() {
			var token = beginPanelRequest( __( 'Loading versions', 'floppy' ) );
			return fetchFiles( false ).then( function () {
				if ( ! panelRequestIsCurrent( token ) ) {
					return null;
				}
				var target = currentVersionTarget();
				if ( ! target ) {
					state.versions = [];
					renderVersions();
					markReady( ctx );
					return null;
				}
				return optionalRequest( 'files/' + encodeURIComponent( target.id ) + '/versions?limit=25', 'versions' ).then( function ( data ) {
					if ( ! panelRequestIsCurrent( token ) ) {
						return data;
					}
					state.versionsEndpointAvailable = !! data;
					state.versions = normalizeVersionRows( data );
					renderVersions();
					markReady( ctx );
					return data;
				} );
			} ).catch( showPanelError( token ) );
		}

		function loadJobs() {
			var token = beginPanelRequest( __( 'Loading jobs', 'floppy' ) );
			return loadDeepHealth().then( function () {
				if ( state.exportJob && ( state.exportJob.job_uuid || state.exportJob.uuid ) ) {
					return refreshExportJob();
				}
				return null;
			} ).then( function () {
				if ( ! panelRequestIsCurrent( token ) ) {
					return null;
				}
				renderJobs();
				markReady( ctx );
			} ).catch( showPanelError( token ) );
		}

		function loadEvidence() {
			var token = beginPanelRequest( __( 'Loading release evidence', 'floppy' ) );
			return Promise.all( [
				loadHealth(),
				loadDeepHealth(),
				loadRepairDryRun()
			] ).then( function () {
				if ( ! panelRequestIsCurrent( token ) ) {
					return null;
				}
				renderEvidence();
				markReady( ctx );
			} ).catch( showPanelError( token ) );
		}

		function loadDevices() {
			return apiRequest( 'devices' ).then( function ( data ) {
				state.devices = data.devices || [];
				state.deviceError = null;
				appSummary.devices = state.devices.filter( function ( device ) {
					return device.status === 'active';
				} ).length;
			} ).catch( function ( error ) {
				state.deviceError = error;
				state.devices = [];
			} );
		}

		function loadDevicePanel() {
			var token = beginPanelRequest( __( 'Loading devices', 'floppy' ) );
			return loadDevices().then( function () {
				if ( ! panelRequestIsCurrent( token ) ) {
					return null;
				}
				renderDevices();
				markReady( ctx );
			} ).catch( showPanelError( token ) );
		}

		function loadSync( reset ) {
			var cursor = reset ? 0 : state.syncCursor;
			var token = beginPanelRequest( __( 'Loading sync feed', 'floppy' ) );
			return apiRequest( 'sync/changes?cursor=' + encodeURIComponent( cursor || 0 ) + '&limit=50' ).then( function ( data ) {
				if ( ! panelRequestIsCurrent( token ) ) {
					return null;
				}
				state.sync = data;
				state.syncCursor = data.next_cursor || cursor || 0;
				appSummary.lastSyncCursor = state.syncCursor;
				state.syncEvents = reset ? ( data.events || [] ) : mergeEvents( state.syncEvents, data.events || [] );
				renderSync();
				markReady( ctx );
			} ).catch( showPanelError( token ) );
		}

		function refreshOsSettings( shouldRender ) {
			return readOsSettings().then( function ( settings ) {
				state.osSettings = settings;
				if ( shouldRender && state.panel === 'settings' ) {
					renderSettings();
				}
			} );
		}

		function uploadFiles( files ) {
			files = Array.prototype.slice.call( files || [] );
			if ( ! files.length ) {
				return;
			}
			if ( config.capabilities && ! config.capabilities.upload ) {
				notify( __( 'Uploads are not available for this account.', 'floppy' ), 'error' );
				return;
			}
			var accepted = files.filter( function ( file ) {
				if ( config.maxFileSize && file.size > config.maxFileSize ) {
					notify( file.name + ' ' + __( 'is larger than the Floppy upload limit.', 'floppy' ), 'error' );
					return false;
				}
				return true;
			} );
			if ( ! accepted.length ) {
				return;
			}
			state.uploading += accepted.length;
			setUploadBadge( state.uploading );
			setStatus( __( 'Uploading', 'floppy' ), 'busy' );
			accepted.forEach( function ( file ) {
				var body = new window.FormData();
				body.append( 'file', file );
				body.append( 'parent_id', state.parentId );
				apiRequest( 'upload', {
					method: 'POST',
					body: body
				} ).then( function () {
					notify( __( 'Uploaded ', 'floppy' ) + file.name, 'success' );
					setActivityBadge( badgeState.activity + 1 );
					if ( desktop && typeof desktop.broadcast === 'function' ) {
						desktop.broadcast( 'floppy.files.changed', { parentId: state.parentId } );
					}
				} ).catch( showError ).finally( function () {
					state.uploading -= 1;
					setUploadBadge( state.uploading );
					if ( state.uploading === 0 ) {
						setStatus( __( 'Ready', 'floppy' ) );
						reloadCurrentPanel();
					}
				} );
			} );
		}

		function createFolder() {
			if ( panelRoot.querySelector( '[data-folder-form]' ) ) {
				return;
			}
			panelRoot.insertAdjacentHTML(
				'afterbegin',
				'<form class="floppy-inline-form" data-folder-form><input type="text" name="folder_name" placeholder="' + escapeHtml( __( 'Folder name', 'floppy' ) ) + '" autocomplete="off" /><button type="submit" class="button button-primary">' + escapeHtml( __( 'Create', 'floppy' ) ) + '</button><button type="button" class="button" data-cancel-folder>' + escapeHtml( __( 'Cancel', 'floppy' ) ) + '</button></form>'
			);
			var input = panelRoot.querySelector( '[data-folder-form] input' );
			if ( input ) {
				input.focus();
			}
		}

		function submitFolderForm( form ) {
			var input = form.querySelector( 'input' );
			if ( ! input || ! input.value.trim() ) {
				return;
			}
			apiRequest( 'folders', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify( {
					name: input.value.trim(),
					parent_id: state.parentId
				} )
			} ).then( loadFiles ).catch( showError );
		}

		function shareTarget() {
			var target = currentShareTarget();
			var form = panelRoot.querySelector( '[data-share-form]' );
			if ( ! target || ! form ) {
				return;
			}
			var principalRef = form.principal_ref.value.trim();
			if ( ! principalRef ) {
				return;
			}
			apiRequest( 'share', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify( {
					target_type: target.kind,
					target_id: target.id,
					principal_type: form.principal_type.value,
					principal_ref: principalRef,
					capability: form.capability.value
				} )
			} ).then( function () {
				notify( __( 'Share updated.', 'floppy' ), 'success' );
				return loadShared();
			} ).catch( showError );
		}

		function unshareTarget() {
			var target = currentShareTarget();
			var form = panelRoot.querySelector( '[data-share-form]' );
			if ( ! target || ! form || ! form.principal_ref.value.trim() ) {
				return;
			}
			apiRequest( 'share', {
				method: 'DELETE',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify( {
					target_type: target.kind,
					target_id: target.id,
					principal_type: form.principal_type.value,
					principal_ref: form.principal_ref.value.trim()
				} )
			} ).then( function () {
				notify( __( 'Share revoked.', 'floppy' ), 'success' );
				return loadShared();
			} ).catch( showError );
		}

		function revokeDevice( uuid ) {
			if ( ! uuid || ! window.confirm( __( 'Revoke this Floppy device token?', 'floppy' ) ) ) {
				return;
			}
			apiRequest( 'devices/' + encodeURIComponent( uuid ) + '/revoke', {
				method: 'POST'
			} ).then( function () {
				notify( __( 'Device revoked.', 'floppy' ), 'success' );
				return loadDevicePanel();
			} ).catch( showError );
		}

		function applyConflictAction( uuid, actionName ) {
			if ( ! uuid || ! actionName ) {
				return;
			}
			return apiRequest( 'conflicts/' + encodeURIComponent( uuid ) + '/actions', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify( { action: actionName } )
			} ).catch( function ( error ) {
				var status = errorStatus( error );
				if ( status !== 404 && status !== 405 ) {
					throw error;
				}
				return apiRequest( 'conflicts/' + encodeURIComponent( uuid ) + '/resolve', {
					method: 'POST',
					headers: { 'Content-Type': 'application/json' },
					body: JSON.stringify( { action: legacyConflictAction( actionName ) } )
				} );
			} ).then( function () {
				notify( __( 'Conflict updated.', 'floppy' ), 'success' );
				if ( desktop && typeof desktop.broadcast === 'function' ) {
					desktop.broadcast( 'floppy.conflicts.changed', { conflict: uuid } );
				}
				return loadConflicts();
			} ).catch( showError );
		}

		function legacyConflictAction( actionName ) {
			var map = {
				mark_resolved: 'resolve',
				discard_local_copy: 'discard',
				keep_both: 'keep',
				retry_upload: 'retry'
			};
			return map[ actionName ] || actionName;
		}

		function downloadVersion( versionId ) {
			var target = currentVersionTarget();
			if ( ! target || ! versionId ) {
				return;
			}
			var version = versionById( versionId );
			var url = version && version.download_url ? version.download_url : config.restUrl + 'files/' + encodeURIComponent( target.id ) + '/versions/' + encodeURIComponent( versionId ) + '/download';
			window.open( url, '_blank', 'noopener' );
		}

		function restoreVersion( versionId ) {
			var target = currentVersionTarget();
			if ( ! target || ! versionId || ! target.content_version ) {
				return;
			}
			if ( ! window.confirm( __( 'Restore this retained version? Floppy will keep the current file as a new version before restoring.', 'floppy' ) ) ) {
				return;
			}
			return apiRequest( 'files/' + encodeURIComponent( target.id ) + '/versions/' + encodeURIComponent( versionId ) + '/restore', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify( { content_version: target.content_version } )
			} ).then( function () {
				notify( __( 'Version restored.', 'floppy' ), 'success' );
				if ( desktop && typeof desktop.broadcast === 'function' ) {
					desktop.broadcast( 'floppy.files.changed', { parentId: target.parent_id || 0 } );
				}
				return loadVersions();
			} ).catch( showError );
		}

		function openItem( id, kind ) {
			var item = state.items.filter( function ( candidate ) {
				return Number( candidate.id ) === Number( id ) && candidate.kind === kind;
			} )[0];
			if ( ! item ) {
				return;
			}
			if ( item.kind === 'folder' ) {
				state.parentId = item.id;
				state.panel = 'files';
				loadFiles();
				return;
			}
			window.open( item.download_url, '_blank', 'noopener' );
		}

		function openItemByKey( key ) {
			var item = itemByKey( key );
			if ( item ) {
				openItem( item.id, item.kind );
			}
		}

		function downloadItem( item ) {
			if ( ! item ) {
				return;
			}
			if ( item.kind === 'folder' ) {
				openItem( item.id, item.kind );
				return;
			}
			window.open( item.download_url, '_blank', 'noopener' );
		}

		function shareItem( item ) {
			if ( ! item ) {
				return;
			}
			state.shareTarget = targetKey( item );
			switchPanel( 'shared' );
		}

		function renameItem( item ) {
			if ( ! item ) {
				return;
			}
			var nextName = window.prompt( __( 'Rename this item', 'floppy' ), item.name );
			if ( ! nextName || nextName.trim() === item.name ) {
				return;
			}
			updateItemMetadata( item, 'rename', { name: nextName.trim() } ).then( function () {
				notify( __( 'Renamed.', 'floppy' ), 'success' );
				return loadFiles();
			} ).catch( showError );
		}

		function trashItems( items ) {
			items = items.filter( Boolean );
			if ( ! items.length || ! window.confirm( __( 'Move selected items to Trash?', 'floppy' ) ) ) {
				return;
			}
			Promise.all( items.map( function ( item ) {
				return updateItemMetadata( item, 'trash', {} );
			} ) ).then( function () {
				state.selected = {};
				notify( __( 'Moved to Trash.', 'floppy' ), 'success' );
				return loadFiles();
				} ).catch( showError );
			}

		function restoreItem( item ) {
			if ( ! item ) {
				return;
			}
			updateItemMetadata( item, 'restore', {} ).then( function () {
				notify( __( 'Restored.', 'floppy' ), 'success' );
				if ( desktop && typeof desktop.broadcast === 'function' ) {
					desktop.broadcast( 'floppy.files.changed', { parentId: item.parent_id || 0 } );
				}
				return loadTrash();
			} ).catch( showError );
		}

		function updateItemMetadata( item, action, body ) {
			body = Object.assign( {}, body || {}, {
				metadata_version: item.metadata_version || ''
			} );
			return apiRequest( ( item.kind === 'folder' ? 'folders/' : 'files/' ) + encodeURIComponent( item.id ) + '/' + action, {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify( body )
			} );
		}

		function startExportJob() {
			state.exportJobError = null;
			return apiRequest( 'exports', {
				method: 'POST'
			} ).then( function ( data ) {
				state.exportJob = data;
				notify( __( 'Export drill queued.', 'floppy' ), 'success' );
				renderJobs();
			} ).catch( function ( error ) {
				state.exportJobError = error;
				renderJobs();
			} );
		}

		function refreshExportJob() {
			var uuid = state.exportJob && ( state.exportJob.job_uuid || state.exportJob.uuid );
			if ( ! uuid ) {
				return Promise.resolve( null );
			}
			return optionalRequest( 'jobs/' + encodeURIComponent( uuid ), 'job_status' ).then( function ( data ) {
				if ( data ) {
					state.exportJob = Object.assign( {}, state.exportJob, data );
					state.exportJobError = null;
				}
				return data;
			} );
		}

		function downloadExportJob() {
			if ( ! state.exportJob ) {
				return;
			}
			var url = state.exportJob.download_url;
			var uuid = state.exportJob.job_uuid || state.exportJob.uuid;
			if ( ! url && uuid ) {
				url = config.restUrl + 'exports/' + encodeURIComponent( uuid ) + '/download';
			}
			if ( url ) {
				window.open( url, '_blank', 'noopener' );
			}
		}

		function downloadDebugBundle() {
			return optionalRequest( 'debug-bundle', 'debug_bundle' ).then( function ( data ) {
				if ( data ) {
					state.debugBundle = data;
					downloadJson( data, 'floppy-debug-bundle-' + safeFilenameStamp() + '.json' );
				}
			} );
		}

		function downloadEvidence() {
			downloadJson( buildReleaseEvidence(), 'floppy-release-evidence-' + safeFilenameStamp() + '.json' );
		}

		function currentVersionTarget() {
			var selected = selectedFileItems().filter( function ( item ) {
				return item.kind === 'file';
			} )[0];
			if ( selected ) {
				state.versionTarget = targetKey( selected );
				return selected;
			}
			if ( state.versionTarget ) {
				var fromState = itemByKey( state.versionTarget );
				if ( fromState && fromState.kind === 'file' ) {
					return fromState;
				}
			}
			var firstFile = state.items.filter( function ( item ) {
				return item.kind === 'file';
			} )[0] || null;
			if ( firstFile ) {
				state.versionTarget = targetKey( firstFile );
			}
			return firstFile;
		}

		function normalizeConflictRows( data, events ) {
			var rows = [];
			if ( Array.isArray( data ) ) {
				rows = data;
			} else if ( data && Array.isArray( data.conflicts ) ) {
				rows = data.conflicts;
			} else if ( data && Array.isArray( data.items ) ) {
				rows = data.items;
			}
			if ( rows.length ) {
				return rows;
			}
			return ( events || [] ).filter( function ( event ) {
				return String( event.event_type || '' ).indexOf( 'conflict' ) !== -1;
			} ).map( function ( event ) {
				var payload = event.payload || {};
				return Object.assign( {}, payload, {
					event_type: event.event_type,
					target_type: event.target_type,
					target_id: event.target_id,
					created_at_gmt: event.created_at_gmt,
					reason: payload.reason || event.event_type,
					name: payload.name || payload.target_name || ''
				} );
			} );
		}

		function normalizeVersionRows( data ) {
			if ( Array.isArray( data ) ) {
				return data;
			}
			if ( data && Array.isArray( data.versions ) ) {
				return data.versions;
			}
			if ( data && Array.isArray( data.items ) ) {
				return data.items;
			}
			return [];
		}

		function versionById( versionId ) {
			versionId = String( versionId || '' );
			return state.versions.filter( function ( version ) {
				return String( version.id || '' ) === versionId;
			} )[0] || null;
		}

		function countObjectValues( object ) {
			return Object.keys( object || {} ).reduce( function ( total, key ) {
				return total + Number( object[ key ] || 0 );
			}, 0 );
		}

		function renderStatusCounts( counts ) {
			var keys = Object.keys( counts || {} );
			if ( ! keys.length ) {
				return '<div class="floppy-empty"><strong>' + escapeHtml( __( 'No queue data yet.', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Refresh after background jobs have been created.', 'floppy' ) ) + '</span></div>';
			}
			return '<dl class="floppy-definition-list">' + keys.map( function ( key ) {
				return '<div><dt>' + escapeHtml( key ) + '</dt><dd>' + escapeHtml( String( counts[ key ] ) ) + '</dd></div>';
			} ).join( '' ) + '</dl>';
		}

		function renderJobProgress( job ) {
			var progress = typeof job.progress === 'number' ? Math.max( 0, Math.min( 100, job.progress ) ) : null;
			var result = job.result && typeof job.result === 'object' ? job.result : {};
			return '<dl class="floppy-definition-list"><div><dt>' + escapeHtml( __( 'Progress', 'floppy' ) ) + '</dt><dd>' + escapeHtml( progress === null ? '-' : String( progress ) + '%' ) + '</dd></div><div><dt>' + escapeHtml( __( 'Attempts', 'floppy' ) ) + '</dt><dd>' + escapeHtml( String( job.attempts || 0 ) ) + '</dd></div><div><dt>' + escapeHtml( __( 'Updated', 'floppy' ) ) + '</dt><dd>' + escapeHtml( formatDate( job.updated_at_gmt ) ) + '</dd></div><div><dt>' + escapeHtml( __( 'Result', 'floppy' ) ) + '</dt><dd>' + escapeHtml( result.files || result.folders ? ( String( result.files || 0 ) + ' files · ' + String( result.folders || 0 ) + ' folders' ) : '-' ) + '</dd></div></dl>';
		}

		function renderHookAudit( evidence ) {
			var features = evidence.features.map( function ( feature ) {
				return '<article class="floppy-gate is-' + ( feature.available ? 'pass' : 'warn' ) + '"><span class="dashicons dashicons-' + ( feature.available ? 'yes-alt' : 'warning' ) + '"></span><div><strong>' + escapeHtml( feature.label ) + '</strong><small>' + escapeHtml( feature.available ? __( 'Detected', 'floppy' ) : __( 'Graceful fallback active', 'floppy' ) ) + '</small></div></article>';
			} ).join( '' );
			var hooksMarkup = evidence.hooks.map( function ( hook ) {
				return '<article class="floppy-gate is-' + ( hook.registered ? 'pass' : 'warn' ) + '"><span class="dashicons dashicons-' + ( hook.registered ? 'yes-alt' : 'warning' ) + '"></span><div><strong>' + escapeHtml( hook.key ) + '</strong><small>' + escapeHtml( hook.name + ( hook.has_constant ? ' · constant' : ' · fallback name' ) ) + '</small></div></article>';
			} ).join( '' );
			return '<div class="floppy-gate-list">' + features + hooksMarkup + '</div>';
		}

		function renderRepairSummary( repair ) {
			if ( ! repair ) {
				return '<div class="floppy-empty"><strong>' + escapeHtml( __( 'No repair dry run loaded.', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Run a dry run to include schema repair evidence in the sidecar.', 'floppy' ) ) + '</span></div>';
			}
			var report = repair.report || {};
			var keys = Object.keys( report );
			if ( ! keys.length ) {
				return '<div class="floppy-empty"><strong>' + escapeHtml( __( 'No repair findings.', 'floppy' ) ) + '</strong></div>';
			}
			return '<dl class="floppy-definition-list">' + keys.map( function ( key ) {
				return '<div><dt>' + escapeHtml( key.replace( /_/g, ' ' ) ) + '</dt><dd>' + escapeHtml( summarizeObject( report[ key ] ) ) + '</dd></div>';
			} ).join( '' ) + '</dl>';
		}

		function buildReleaseEvidence() {
			var support = supportBlockFrom( state.health ) || supportBlockFrom( state.deepHealth ) || supportBlockFrom( state.repairReport ) || {};
			return {
				format: 'floppy-desktop-mode-release-evidence-v2',
				generated_at: new Date().toISOString(),
				support: support,
				plugin: {
					rest_url: redactUrl( config.restUrl || '' ),
					desktop_mode_detected: !! config.desktopMode
				},
				desktop_mode: desktopSmokeEvidence(),
				state: {
					panel: state.panel,
					files_loaded: state.items.length,
					selected_count: selectedFileItems().length,
					sync_cursor: state.syncCursor || 0,
					sync_events_loaded: state.syncEvents.length,
					conflicts_loaded: state.conflicts.length,
					request_race_count: state.requestRaceCount || 0,
					drag_target_mode: state.dragTargetMode || 'none',
					last_error: state.lastError,
					export_job_status: state.exportJob ? state.exportJob.status || 'queued' : '',
					failed_health_checks: state.health ? failingCheckCount( state.health ) : null
				},
				endpoints: state.endpointAvailability,
				health: state.health || null,
				deep_health: state.deepHealth || null,
				repair_dry_run: state.repairReport || null
			};
		}

		function releaseGates( evidence ) {
			var healthFailures = evidence.state.failed_health_checks;
			var deepAvailable = evidence.endpoints.deep_health && evidence.endpoints.deep_health.available;
			var repairAvailable = evidence.endpoints.repair && evidence.endpoints.repair.available;
			var debugAvailable = evidence.endpoints.debug_bundle && evidence.endpoints.debug_bundle.available;
			var dragNative = evidence.desktop_mode.drag_target_mode === 'dragManager' || evidence.desktop_mode.drag_target_mode === 'available';
			var hookMissing = evidence.desktop_mode.hooks.filter( function ( hook ) {
				return ! hook.registered;
			} ).length;
			return [
				{ label: __( 'Desktop Mode public hooks', 'floppy' ), status: hookMissing ? 'warn' : 'pass', message: hookMissing ? __( 'Some hooks are falling back or not registered in this shell.', 'floppy' ) : __( 'Required public hook registrations were detected.', 'floppy' ) },
				{ label: __( 'Native drop target', 'floppy' ), status: dragNative ? 'pass' : 'warn', message: dragNative ? __( 'Using wp.desktop.dragManager for drops.', 'floppy' ) : __( 'Using legacy drop-hook fallback because dragManager is unavailable.', 'floppy' ) },
				{ label: __( 'Health endpoint', 'floppy' ), status: state.health ? ( healthFailures ? 'warn' : 'pass' ) : 'fail', message: state.health ? plural( healthFailures || 0, 'failed check', 'failed checks' ) : __( 'Health endpoint did not return.', 'floppy' ) },
				{ label: __( 'Deep health endpoint', 'floppy' ), status: deepAvailable ? 'pass' : 'warn', message: deepAvailable ? __( 'Admin deep-health evidence loaded.', 'floppy' ) : __( 'Deep-health endpoint unavailable or unauthorized.', 'floppy' ) },
				{ label: __( 'Repair dry run', 'floppy' ), status: repairAvailable ? 'pass' : 'warn', message: repairAvailable ? __( 'Repair dry-run evidence loaded without applying changes.', 'floppy' ) : __( 'Repair dry-run evidence has not loaded.', 'floppy' ) },
				{ label: __( 'Debug bundle', 'floppy' ), status: debugAvailable || state.debugBundle ? 'pass' : 'warn', message: debugAvailable || state.debugBundle ? __( 'Debug bundle endpoint verified.', 'floppy' ) : __( 'Download the debug bundle before tagging.', 'floppy' ) },
				{ label: __( 'Export drill', 'floppy' ), status: state.exportJob ? 'pass' : 'warn', message: state.exportJob ? __( 'Export job evidence exists in this session.', 'floppy' ) : __( 'Run an export drill before the beta tag.', 'floppy' ) }
			];
		}

		function switchPanel( panel ) {
			state.panel = panel || 'files';
			updateChrome();
			if ( state.panel === 'files' ) {
				loadFiles();
			} else if ( state.panel === 'recents' ) {
				loadRecents();
			} else if ( state.panel === 'trash' ) {
				loadTrash();
			} else if ( state.panel === 'shared' ) {
				loadShared();
			} else if ( state.panel === 'conflicts' ) {
				loadConflicts();
			} else if ( state.panel === 'versions' ) {
				loadVersions();
			} else if ( state.panel === 'sync' ) {
				loadSync( true );
			} else if ( state.panel === 'devices' ) {
				loadDevicePanel();
			} else if ( state.panel === 'diagnostics' ) {
				loadDiagnostics();
			} else if ( state.panel === 'jobs' ) {
				loadJobs();
			} else if ( state.panel === 'evidence' ) {
				loadEvidence();
			} else {
				refreshOsSettings( false ).then( renderSettings );
			}
		}

		function reloadCurrentPanel() {
			if ( state.panel === 'recents' ) {
				loadRecents();
			} else if ( state.panel === 'trash' ) {
				loadTrash();
			} else if ( state.panel === 'shared' ) {
				loadShared();
			} else if ( state.panel === 'conflicts' ) {
				loadConflicts();
			} else if ( state.panel === 'versions' ) {
				loadVersions();
			} else if ( state.panel === 'sync' ) {
				loadSync( true );
			} else if ( state.panel === 'devices' ) {
				loadDevicePanel();
			} else if ( state.panel === 'diagnostics' ) {
				loadDiagnostics();
			} else if ( state.panel === 'jobs' ) {
				loadJobs();
			} else if ( state.panel === 'evidence' ) {
				loadEvidence();
			} else if ( state.panel === 'settings' ) {
				refreshOsSettings( true );
			} else {
				loadFiles();
			}
		}

		function showError( error ) {
			markReady( ctx );
			setStatus( __( 'Needs attention', 'floppy' ), 'error' );
			renderInlineError( error );
			notify( error && error.message ? error.message : __( 'Floppy request failed.', 'floppy' ), 'error' );
		}

		function handleNativeDropPayload( payload ) {
			var files = filesFromPayload( payload );
			if ( files.length ) {
				uploadFiles( files );
			}
		}

		function handlePanelAction( action ) {
			var name = action.getAttribute( 'data-action' );
			var rowItem = itemByKey( action.getAttribute( 'data-row-key' ) );
			var selectedItems = selectedFileItems();
			if ( action.disabled ) {
				return;
			}
			if ( name === 'retry-panel' ) {
				reloadCurrentPanel();
			} else if ( name === 'upload' ) {
				fileInput.click();
			} else if ( name === 'new-folder' ) {
				state.panel = 'files';
				updateChrome();
				if ( panelRoot.querySelector( '[data-files-panel]' ) ) {
					createFolder();
				} else {
					loadFiles().then( createFolder );
				}
			} else if ( name === 'refresh' ) {
				reloadCurrentPanel();
			} else if ( name === 'home' ) {
				state.parentId = 0;
				state.panel = 'files';
				loadFiles();
			} else if ( name === 'load-more' ) {
				loadMoreFiles();
			} else if ( name === 'open-selected' ) {
				if ( selectedItems[0] ) {
					openItem( selectedItems[0].id, selectedItems[0].kind );
				}
			} else if ( name === 'download-selected' ) {
				downloadItem( selectedItems[0] );
			} else if ( name === 'share-selected' ) {
				shareItem( selectedItems[0] );
			} else if ( name === 'rename-selected' ) {
				renameItem( selectedItems[0] );
			} else if ( name === 'trash-selected' ) {
				trashItems( selectedItems );
			} else if ( name === 'clear-selection' ) {
				state.selected = {};
				paintFileList();
			} else if ( name === 'download-item' ) {
				downloadItem( rowItem );
			} else if ( name === 'share-item' ) {
				shareItem( rowItem );
			} else if ( name === 'rename-item' ) {
				renameItem( rowItem );
				} else if ( name === 'trash-item' ) {
					trashItems( [ rowItem ] );
				} else if ( name === 'restore-item' ) {
					restoreItem( rowItem );
				} else if ( name === 'open-recovery-item' ) {
					openItemByKey( action.getAttribute( 'data-row-key' ) );
				} else if ( name === 'unshare' ) {
					unshareTarget();
			} else if ( name === 'open-sync' ) {
				switchPanel( 'sync' );
			} else if ( name === 'conflict-refresh' ) {
				loadConflicts();
			} else if ( name === 'conflict-action' ) {
				applyConflictAction( action.getAttribute( 'data-conflict-uuid' ), action.getAttribute( 'data-conflict-action' ) );
			} else if ( name === 'version-refresh' ) {
				loadVersions();
			} else if ( name === 'version-download' ) {
				downloadVersion( action.getAttribute( 'data-version-id' ) );
			} else if ( name === 'version-restore' ) {
				restoreVersion( action.getAttribute( 'data-version-id' ) );
			} else if ( name === 'sync-reset' ) {
				state.syncCursor = 0;
				state.syncEvents = [];
				loadSync( true );
				} else if ( name === 'sync-more' ) {
					loadSync( false );
				} else if ( name === 'recents-refresh' ) {
					loadRecents();
				} else if ( name === 'trash-refresh' ) {
					loadTrash();
				} else if ( name === 'health-refresh' ) {
				loadDiagnostics();
			} else if ( name === 'devices-refresh' ) {
				loadDevicePanel();
			} else if ( name === 'device-revoke' ) {
				revokeDevice( action.getAttribute( 'data-device-uuid' ) );
			} else if ( name === 'jobs-refresh' ) {
				loadJobs();
			} else if ( name === 'export-start' ) {
				startExportJob();
			} else if ( name === 'export-check' ) {
				refreshExportJob().then( renderJobs );
			} else if ( name === 'export-download' ) {
				downloadExportJob();
			} else if ( name === 'evidence-refresh' ) {
				loadEvidence();
			} else if ( name === 'evidence-download' ) {
				downloadEvidence();
			} else if ( name === 'debug-download' ) {
				downloadDebugBundle();
			} else if ( name === 'repair-dry-run' ) {
				loadRepairDryRun().then( renderEvidence );
			} else if ( name === 'settings-refresh' ) {
				refreshOsSettings( true );
			} else if ( name === 'desktop-settings' ) {
				openDesktopSettings();
			}
		}

		function handleKeyboardNavigation( event ) {
			var activeTag = event.target && event.target.tagName ? event.target.tagName.toLowerCase() : '';
			var isTextInput = activeTag === 'input' || activeTag === 'textarea' || activeTag === 'select';
			if ( event.key === '/' && ! isTextInput ) {
				var search = panelRoot.querySelector( '[data-file-search]' );
				if ( search ) {
					event.preventDefault();
					search.focus();
				}
				return;
			}
			if ( event.key === 'Escape' && state.panel === 'files' ) {
				state.selected = {};
				paintFileList();
				return;
			}
			if ( ( event.metaKey || event.ctrlKey ) && event.key.toLowerCase() === 'a' && state.panel === 'files' && ! isTextInput ) {
				event.preventDefault();
				setVisibleSelection( true );
				return;
			}

			var row = event.target.closest ? event.target.closest( '.floppy-file-row' ) : null;
			if ( ! row ) {
				return;
			}
			if ( event.key === 'Enter' ) {
				event.preventDefault();
				if ( row.getAttribute( 'data-recovery-mode' ) === 'trash' ) {
					restoreItem( itemByKey( row.getAttribute( 'data-row-key' ) ) );
				} else {
					openItemByKey( row.getAttribute( 'data-row-key' ) );
				}
			} else if ( event.key === ' ' ) {
				event.preventDefault();
				if ( row.hasAttribute( 'data-selectable-row' ) ) {
					toggleSelectedItem( row.getAttribute( 'data-row-key' ) );
				}
			} else if ( event.key === 'ArrowDown' || event.key === 'ArrowUp' ) {
				event.preventDefault();
				focusSiblingRow( row, event.key === 'ArrowDown' ? 1 : -1 );
			}
		}

		function focusSiblingRow( row, direction ) {
			var rows = Array.prototype.slice.call( panelRoot.querySelectorAll( '.floppy-file-row' ) );
			var index = rows.indexOf( row );
			var next = rows[ index + direction ];
			if ( next ) {
				next.focus();
			}
		}

		function addManagedListener( element, type, listener, options ) {
			if ( ! element || typeof element.addEventListener !== 'function' ) {
				return;
			}
			element.addEventListener( type, listener, options );
			cleanup.push( function () {
				if ( typeof element.removeEventListener === 'function' ) {
					element.removeEventListener( type, listener, options );
				}
			} );
		}

		addManagedListener( container, 'click', function ( event ) {
			currentMount = container;
			var nav = event.target.closest( '.floppy-nav' );
			if ( nav ) {
				switchPanel( nav.getAttribute( 'data-panel' ) );
				return;
			}

			var targetButton = event.target.closest( '[data-share-target]' );
			if ( targetButton ) {
				state.shareTarget = targetButton.getAttribute( 'data-share-target' );
				renderShared();
				return;
			}

			var versionButton = event.target.closest( '[data-version-target]' );
			if ( versionButton ) {
				state.versionTarget = versionButton.getAttribute( 'data-version-target' );
				loadVersions();
				return;
			}

			var visibilityButton = event.target.closest( '[data-os-visibility]' );
			if ( visibilityButton ) {
				updateOsVisibility( visibilityButton.getAttribute( 'data-os-visibility' ) ).then( function () {
					return refreshOsSettings( true );
				} ).catch( showError );
				return;
			}

			var sortButton = event.target.closest( '[data-sort-key]' );
			if ( sortButton ) {
				setFileSort( sortButton.getAttribute( 'data-sort-key' ) );
				return;
			}

			var filterButton = event.target.closest( '[data-kind-filter]' );
			if ( filterButton ) {
				state.kindFilter = filterButton.getAttribute( 'data-kind-filter' ) || 'all';
				container.querySelectorAll( '[data-kind-filter]' ).forEach( function ( button ) {
					var active = button.getAttribute( 'data-kind-filter' ) === state.kindFilter;
					button.classList.toggle( 'is-active', active );
					button.setAttribute( 'aria-pressed', active ? 'true' : 'false' );
				} );
				paintFileList();
				return;
			}

			var openButton = event.target.closest( '[data-open-item]' );
			if ( openButton ) {
				openItemByKey( openButton.getAttribute( 'data-open-item' ) );
				return;
			}

			var action = event.target.closest( '[data-action]' );
			if ( action ) {
				handlePanelAction( action );
				return;
			}

			var row = event.target.closest( '.floppy-file-row' );
			if ( row && row.hasAttribute( 'data-selectable-row' ) && ! event.target.closest( 'button,input,a' ) ) {
				toggleSelectedItem( row.getAttribute( 'data-row-key' ) );
				return;
			}

			if ( event.target.closest( '[data-cancel-folder]' ) ) {
				var form = container.querySelector( '[data-folder-form]' );
				if ( form ) {
					form.remove();
				}
			}
		} );

		addManagedListener( container, 'dblclick', function ( event ) {
			currentMount = container;
			var row = event.target.closest( '.floppy-file-row' );
			if ( row && ! event.target.closest( 'button,input,a' ) ) {
				if ( row.getAttribute( 'data-recovery-mode' ) === 'trash' ) {
					restoreItem( itemByKey( row.getAttribute( 'data-row-key' ) ) );
				} else {
					openItemByKey( row.getAttribute( 'data-row-key' ) );
				}
			}
		} );

		addManagedListener( container, 'keydown', function ( event ) {
			currentMount = container;
			handleKeyboardNavigation( event );
		} );

		addManagedListener( container, 'input', function ( event ) {
			currentMount = container;
			var search = event.target.closest( '[data-file-search]' );
			if ( search ) {
				state.filterText = search.value || '';
				paintFileList();
			}
		} );

		addManagedListener( container, 'change', function ( event ) {
			currentMount = container;
			var selectVisible = event.target.closest( '[data-select-visible]' );
			var selectItem = event.target.closest( '[data-select-item]' );
			if ( selectVisible ) {
				setVisibleSelection( selectVisible.checked );
			} else if ( selectItem ) {
				setSelectedItem( selectItem.getAttribute( 'data-select-item' ), selectItem.checked );
			}
		} );

		addManagedListener( container, 'submit', function ( event ) {
			var folderForm = event.target.closest( '[data-folder-form]' );
			var shareForm = event.target.closest( '[data-share-form]' );
			if ( folderForm ) {
				event.preventDefault();
				submitFolderForm( folderForm );
			} else if ( shareForm ) {
				event.preventDefault();
				shareTarget();
			}
		} );

		addManagedListener( container, 'dragover', function ( event ) {
			event.preventDefault();
			container.classList.add( 'is-dragging' );
		} );
		addManagedListener( container, 'dragleave', function () {
			container.classList.remove( 'is-dragging' );
		} );
		addManagedListener( container, 'drop', function ( event ) {
			event.preventDefault();
			container.classList.remove( 'is-dragging' );
			uploadFiles( event.dataTransfer.files );
		} );
		addManagedListener( fileInput, 'change', function () {
			uploadFiles( fileInput.files );
			fileInput.value = '';
		} );

		addHookAction( 'FILE_DROP_FILES_DETECTED', namespace + '/drop-detected', function ( payload ) {
			if ( state.dragTargetMode !== 'dragManager' && payloadMatchesWindow( payload ) ) {
				container.classList.add( 'is-dragging' );
			}
		}, cleanup );
		addHookAction( 'FILE_DROP_BEFORE_UPLOAD', namespace + '/drop-before-upload', function ( payload ) {
			if ( state.dragTargetMode !== 'dragManager' && payloadMatchesWindow( payload ) ) {
				handleNativeDropPayload( payload );
			}
		}, cleanup );
		addHookAction( 'FILE_DROP_UPLOAD_STARTED', namespace + '/drop-upload-started', function ( payload ) {
			if ( state.dragTargetMode !== 'dragManager' && payloadMatchesWindow( payload ) ) {
				setStatus( __( 'Uploading dropped files', 'floppy' ), 'busy' );
			}
		}, cleanup );
		addHookAction( 'FILE_DROP_UPLOAD_PROGRESS', namespace + '/drop-upload-progress', function ( payload ) {
			if ( state.dragTargetMode !== 'dragManager' && payloadMatchesWindow( payload ) && payload && payload.progress ) {
				setStatus( __( 'Uploading ', 'floppy' ) + String( Math.round( payload.progress ) ) + '%', 'busy' );
			}
		}, cleanup );
		addHookAction( 'FILE_DROP_AFTER_UPLOAD', namespace + '/drop-after-upload', function ( payload ) {
			if ( state.dragTargetMode !== 'dragManager' && payloadMatchesWindow( payload ) ) {
				container.classList.remove( 'is-dragging' );
				setStatus( __( 'Ready', 'floppy' ) );
				reloadCurrentPanel();
			}
		}, cleanup );
		addHookAction( 'FILE_DROP_UPLOAD_FAILED', namespace + '/drop-upload-failed', function ( payload ) {
			if ( state.dragTargetMode !== 'dragManager' && payloadMatchesWindow( payload ) ) {
				container.classList.remove( 'is-dragging' );
				setStatus( __( 'Upload failed', 'floppy' ), 'error' );
			}
		}, cleanup );
		registerNativeDropTarget( cleanup );
		addHookAction( 'WINDOW_REOPENED', namespace + '/reopened', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				var panel = panelFromPayload( payload );
				if ( panel && PANEL_LABELS[ panel ] ) {
					switchPanel( panel );
				}
			}
		}, cleanup );
		addHookAction( 'WINDOW_CONTENT_LOADED', namespace + '/content-loaded', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				markReady( ctx );
			}
		}, cleanup );
		addHookAction( 'WINDOW_FOCUSED', namespace + '/focus', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				setActivityBadge( 0 );
			}
		}, cleanup );
		addHookAction( 'NATIVE_WINDOW_AFTER_RENDER', namespace + '/after-render', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				markReady( ctx );
			}
		}, cleanup );
		addHookFilter( 'NATIVE_WINDOW_BEFORE_CLOSE', namespace + '/before-close', function ( allowed, closeContext ) {
			if ( payloadMatchesWindow( closeContext ) && state.uploading > 0 ) {
				notify( __( 'Uploads are still running. Wait for Floppy to finish before closing.', 'floppy' ), 'error' );
				return false;
			}
			return allowed;
		}, cleanup );

		if ( desktop && typeof desktop.subscribe === 'function' ) {
			var unsubscribeFiles = desktop.subscribe( 'floppy.files.changed', function () {
				setActivityBadge( badgeState.activity + 1 );
				if ( state.panel === 'files' || state.panel === 'shared' ) {
					reloadCurrentPanel();
				}
			} );
			if ( typeof unsubscribeFiles === 'function' ) {
				cleanup.push( unsubscribeFiles );
			}
			var unsubscribePanel = desktop.subscribe( 'floppy.panel.open', function ( payload ) {
				if ( payload && payload.panel ) {
					switchPanel( payload.panel );
				}
			} );
			if ( typeof unsubscribePanel === 'function' ) {
				cleanup.push( unsubscribePanel );
			}
			var unsubscribeUpload = desktop.subscribe( 'floppy.upload.requested', function () {
				fileInput.click();
			} );
			if ( typeof unsubscribeUpload === 'function' ) {
				cleanup.push( unsubscribeUpload );
			}
		}

		function registerNativeDropTarget( cleanupList ) {
			if ( ! desktop || ! desktop.dragManager || typeof desktop.dragManager.registerDropTarget !== 'function' ) {
				state.dragTargetMode = 'fallback-hooks';
				return;
			}
			var deregister = desktop.dragManager.registerDropTarget( {
				id: WINDOW_ID + '/dropzone',
				element: container,
				accept: function ( payload ) {
					return filesFromPayload( payload ).length > 0 || payloadMatchesWindow( payload ) || ( payload && ( payload.type === 'desktop-file' || payload.type === 'file' ) );
				},
				onEnter: function () {
					container.classList.add( 'is-dragging' );
				},
				onLeave: function () {
					container.classList.remove( 'is-dragging' );
				},
				onDrop: function ( session ) {
					container.classList.remove( 'is-dragging' );
					handleNativeDropPayload( session && session.payload ? session.payload : session );
				}
			} );
			state.dragTargetMode = 'dragManager';
			if ( typeof deregister === 'function' ) {
				cleanupList.push( function () {
					deregister();
				} );
			}
		}

		if ( desktop && typeof desktop.subscribeOsSettings === 'function' ) {
			var unsubscribeOsSettings = desktop.subscribeOsSettings( function ( settings ) {
				state.osSettings = settings || {};
				if ( state.panel === 'settings' ) {
					renderSettings();
				}
			} );
			if ( typeof unsubscribeOsSettings === 'function' ) {
				cleanup.push( unsubscribeOsSettings );
			}
		}

		loadHealth();
		loadDevices();
		refreshOsSettings( false );
		loadFiles();

		var disposed = false;
		return function () {
			if ( disposed ) {
				return;
			}
			disposed = true;
			cleanup.forEach( function ( dispose ) {
				if ( typeof dispose === 'function' ) {
					dispose();
				}
			} );
			if ( currentMount === container ) {
				currentMount = null;
			}
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

	function readOsSettings() {
		if ( ! desktop || typeof desktop.getOsSettings !== 'function' ) {
			return Promise.resolve( null );
		}
		try {
			return Promise.resolve( desktop.getOsSettings() ).catch( function () {
				return null;
			} );
		} catch ( error ) {
			return Promise.resolve( null );
		}
	}

	function updateOsVisibility( visibility ) {
		if ( ! OS_VISIBILITY_LABELS[ visibility ] ) {
			return Promise.reject( new Error( __( 'Unknown Desktop Mode placement.', 'floppy' ) ) );
		}
		if ( ! desktop || typeof desktop.updateOsSettings !== 'function' ) {
			return Promise.reject( new Error( __( 'Desktop Mode OS Settings are not available.', 'floppy' ) ) );
		}
		var patch = { itemVisibility: {} };
		patch.itemVisibility[ WINDOW_ID ] = visibility;
		return Promise.resolve( desktop.updateOsSettings( patch ) ).then( function () {
			if ( desktop && typeof desktop.refreshMenu === 'function' ) {
				desktop.refreshMenu();
			}
			notify( __( 'Floppy placement updated.', 'floppy' ), 'success' );
		} );
	}

	function openDesktopSettings() {
		if ( desktop && typeof desktop.openOsSettings === 'function' ) {
			desktop.openOsSettings( { tabId: 'floppy', source: OWNER } );
			return;
		}
		if ( desktop && typeof desktop.openSettings === 'function' ) {
			desktop.openSettings( { tab: 'floppy', tabId: 'floppy', source: OWNER } );
			return;
		}
		openWindow( 'settings', 'settings' );
	}

	function renderSettingsTab( container ) {
		var tabSettings = null;
		var cleanup = [];

		function draw() {
			container.innerHTML = [
				'<div class="floppy-settings">',
					'<section class="floppy-panel">',
						'<h2>' + escapeHtml( __( 'Floppy', 'floppy' ) ) + '</h2>',
						'<p>' + escapeHtml( __( 'Private WordPress Drive, Desktop Mode launcher placement, Finder sync devices, and readiness checks.', 'floppy' ) ) + '</p>',
						renderOsSettingsControls( tabSettings ),
						'<div class="floppy-button-row"><button type="button" class="button button-primary" data-action="open-floppy">' + escapeHtml( __( 'Open Floppy', 'floppy' ) ) + '</button><button type="button" class="button" data-action="refresh-settings">' + escapeHtml( __( 'Refresh', 'floppy' ) ) + '</button></div>',
					'</section>',
					'<section class="floppy-panel">',
						renderOnboardingMarkup(),
					'</section>',
				'</div>'
			].join( '' );
		}

		function refresh() {
			return readOsSettings().then( function ( settings ) {
				tabSettings = settings;
				draw();
			} );
		}

		function handleSettingsTabClick( event ) {
			var visibilityButton = event.target.closest( '[data-os-visibility]' );
			var action = event.target.closest( '[data-action]' );
			if ( visibilityButton ) {
				updateOsVisibility( visibilityButton.getAttribute( 'data-os-visibility' ) ).then( refresh );
				return;
			}
			if ( action && action.getAttribute( 'data-action' ) === 'open-floppy' ) {
				openWindow( 'files', 'settings' );
			} else if ( action && action.getAttribute( 'data-action' ) === 'refresh-settings' ) {
				refresh();
			}
		}

		container.addEventListener( 'click', handleSettingsTabClick );
		cleanup.push( function () {
			container.removeEventListener( 'click', handleSettingsTabClick );
		} );

		if ( desktop && typeof desktop.subscribeOsSettings === 'function' ) {
			var unsubscribe = desktop.subscribeOsSettings( function ( settings ) {
				tabSettings = settings || {};
				draw();
			} );
			if ( typeof unsubscribe === 'function' ) {
				cleanup.push( unsubscribe );
			}
		}

		refresh();

		return function () {
			cleanup.forEach( function ( dispose ) {
				if ( typeof dispose === 'function' ) {
					dispose();
				}
			} );
		};
	}

	function renderOsSettingsControls( settings ) {
		if ( ! desktop || typeof desktop.getOsSettings !== 'function' || typeof desktop.updateOsSettings !== 'function' ) {
			return '<div class="floppy-callout"><strong>' + escapeHtml( __( 'Desktop Mode OS Settings unavailable', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Install or update Desktop Mode to place Floppy on the desktop or dock.', 'floppy' ) ) + '</span></div>';
		}
		var visibility = getOsVisibility( settings );
		return '<div class="floppy-segmented" role="group" aria-label="' + escapeHtml( __( 'Floppy launcher placement', 'floppy' ) ) + '">' + Object.keys( OS_VISIBILITY_LABELS ).map( function ( key ) {
			var active = visibility === key;
			return '<button type="button" class="' + ( active ? 'is-active' : '' ) + '" data-os-visibility="' + escapeHtml( key ) + '" aria-pressed="' + ( active ? 'true' : 'false' ) + '">' + escapeHtml( OS_VISIBILITY_LABELS[ key ] ) + '</button>';
		} ).join( '' ) + '</div>';
	}

	function renderOnboardingMarkup() {
		return [
			'<div class="floppy-onboarding">',
				'<div class="floppy-surface-head"><div><h2>' + escapeHtml( __( 'Mac Onboarding', 'floppy' ) ) + '</h2><p>' + escapeHtml( __( 'Floppy for Mac starts with WordPress approval, then stores only a scoped Floppy device token.', 'floppy' ) ) + '</p></div></div>',
				'<ol class="floppy-steps">',
					'<li><strong>' + escapeHtml( __( 'Approve WordPress access', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Use the native Application Password screen to confirm the site and account.', 'floppy' ) ) + '</span></li>',
					'<li><strong>' + escapeHtml( __( 'Install the plugin ZIP', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'The Mac app opens the WordPress upload screen for the GitHub release ZIP.', 'floppy' ) ) + '</span></li>',
					'<li><strong>' + escapeHtml( __( 'Create a device token', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'Floppy exchanges the temporary credential for a revocable files and sync token.', 'floppy' ) ) + '</span></li>',
					'<li><strong>' + escapeHtml( __( 'Use Finder sync', 'floppy' ) ) + '</strong><span>' + escapeHtml( __( 'The Desktop Mode app remains the control surface for files, shares, diagnostics, and devices.', 'floppy' ) ) + '</span></li>',
				'</ol>',
			'</div>'
		].join( '' );
	}

	function getOsVisibility( settings ) {
		var visibility = settings && settings.itemVisibility ? settings.itemVisibility[ WINDOW_ID ] : '';
		return OS_VISIBILITY_LABELS[ visibility ] ? visibility : 'both';
	}

	function itemByKey( key ) {
		return ( key ? currentItems().filter( function ( item ) {
			return targetKey( item ) === key;
		} )[0] : null ) || null;
	}

	function currentItems() {
		var items = Array.isArray( appCurrentStateItems() ) ? appCurrentStateItems() : [];
		if ( hooks && typeof hooks.applyFilters === 'function' ) {
			var filtered = hooks.applyFilters( 'floppy.desktop.files.items', items.slice(), {
				windowId: WINDOW_ID,
				owner: OWNER,
				parentId: appFileState().parentId || 0
			} );
			return Array.isArray( filtered ) ? filtered : items;
		}
		return items;
	}

	function appCurrentStateItems() {
		var node = currentMount || document.querySelector( '[data-floppy-root].floppy-app, .floppy-app' );
		return node && node.__floppyItems ? node.__floppyItems : [];
	}

	function setCurrentItemsReference( container, items ) {
		currentMount = container;
		container.__floppyItems = items || [];
	}

	function visibleFileItems() {
		var query = normalizeSearch( appFileState().filterText );
		var kindFilter = appFileState().kindFilter || 'all';
		return currentItems().filter( function ( item ) {
			if ( kindFilter !== 'all' && item.kind !== kindFilter ) {
				return false;
			}
			if ( ! query ) {
				return true;
			}
			return normalizeSearch( item.name + ' ' + itemSubtitle( item ) + ' ' + kindLabel( item ) ).indexOf( query ) !== -1;
		} ).sort( compareFileItems );
	}

	function appFileState() {
		var node = currentMount || document.querySelector( '[data-floppy-root].floppy-app, .floppy-app' );
		return node && node.__floppyState ? node.__floppyState : {};
	}

	function setCurrentStateReference( container, state ) {
		currentMount = container;
		container.__floppyState = state || {};
	}

	function selectedFileItems() {
		var selected = appFileState().selected || {};
		return currentItems().filter( function ( item ) {
			return !! selected[ targetKey( item ) ];
		} );
	}

	function mergeItems( existing, incoming ) {
		var seen = {};
		return existing.concat( incoming ).filter( function ( item ) {
			var key = targetKey( item );
			if ( seen[ key ] ) {
				return false;
			}
			seen[ key ] = true;
			return true;
		} );
	}

	function pruneSelection() {
		var state = appFileState();
		var selected = state.selected || {};
		state.selected = selected;
		var live = {};
		currentItems().forEach( function ( item ) {
			live[ targetKey( item ) ] = true;
		} );
		Object.keys( selected ).forEach( function ( key ) {
			if ( ! live[ key ] ) {
				delete selected[ key ];
			}
		} );
	}

	function setSelectedItem( key, selected ) {
		var state = appFileState();
		state.selected = state.selected || {};
		if ( ! key ) {
			return;
		}
		if ( selected ) {
			state.selected[ key ] = true;
		} else {
			delete state.selected[ key ];
		}
		repaintCurrentFileList();
	}

	function toggleSelectedItem( key ) {
		var state = appFileState();
		setSelectedItem( key, ! state.selected[ key ] );
	}

	function setVisibleSelection( selected ) {
		var state = appFileState();
		state.selected = state.selected || {};
		visibleFileItems().slice( 0, FILE_RENDER_LIMIT ).forEach( function ( item ) {
			var key = targetKey( item );
			if ( selected ) {
				state.selected[ key ] = true;
			} else {
				delete state.selected[ key ];
			}
		} );
		repaintCurrentFileList();
	}

	function repaintCurrentFileList() {
		var node = currentMount || document.querySelector( '[data-floppy-root].floppy-app, .floppy-app' );
		if ( node && typeof node.__floppyPaintFileList === 'function' ) {
			node.__floppyPaintFileList();
		}
	}

	function setFileSort( key ) {
		var state = appFileState();
		if ( ! FILE_SORT_LABELS[ key ] ) {
			return;
		}
		state.sortKey = state.sortKey || 'name';
		state.sortDirection = state.sortDirection || 'asc';
		if ( state.sortKey === key ) {
			state.sortDirection = state.sortDirection === 'asc' ? 'desc' : 'asc';
		} else {
			state.sortKey = key;
			state.sortDirection = key === 'updated' ? 'desc' : 'asc';
		}
		repaintCurrentFileList();
	}

	function compareFileItems( a, b ) {
		var state = appFileState();
		var direction = state.sortDirection === 'desc' ? -1 : 1;
		if ( state.sortKey !== 'kind' && a.kind !== b.kind ) {
			return a.kind === 'folder' ? -1 : 1;
		}
		var av = sortValue( a, state.sortKey );
		var bv = sortValue( b, state.sortKey );
		if ( av < bv ) {
			return -1 * direction;
		}
		if ( av > bv ) {
			return 1 * direction;
		}
		return String( a.name || '' ).localeCompare( String( b.name || '' ) );
	}

	function sortValue( item, key ) {
		if ( key === 'size' ) {
			return item.kind === 'folder' ? -1 : Number( item.size_bytes || 0 );
		}
		if ( key === 'updated' ) {
			return sortableTime( item.updated_at_gmt );
		}
		if ( key === 'kind' ) {
			return kindLabel( item ).toLowerCase();
		}
		return String( item.name || '' ).toLowerCase();
	}

	function itemSubtitle( item ) {
		if ( item.kind === 'folder' ) {
			return __( 'Folder', 'floppy' );
		}
		return item.mime_type || __( 'File', 'floppy' );
	}

	function kindLabel( item ) {
		if ( item.kind === 'folder' ) {
			return __( 'Folder', 'floppy' );
		}
		if ( /^image\//.test( item.mime_type || '' ) ) {
			return __( 'Image', 'floppy' );
		}
		if ( /^audio\//.test( item.mime_type || '' ) ) {
			return __( 'Audio', 'floppy' );
		}
		if ( /^video\//.test( item.mime_type || '' ) ) {
			return __( 'Video', 'floppy' );
		}
		if ( /pdf/.test( item.mime_type || '' ) ) {
			return __( 'PDF', 'floppy' );
		}
		return __( 'File', 'floppy' );
	}

	function normalizeSearch( value ) {
		return String( value || '' ).toLowerCase().trim();
	}

	function sortableTime( value ) {
		if ( ! value ) {
			return 0;
		}
		var normalized = String( value ).replace( ' ', 'T' );
		if ( normalized.indexOf( 'Z' ) === -1 ) {
			normalized += 'Z';
		}
		var date = new Date( normalized );
		return Number.isNaN( date.getTime() ) ? 0 : date.getTime();
	}

	function fileCountLabel( visibleCount ) {
		var state = appFileState();
		var total = currentItems().length;
		var label = visibleCount === total ? plural( total, 'item', 'items' ) : plural( visibleCount, 'shown item', 'shown items' ) + ' / ' + plural( total, 'loaded item', 'loaded items' );
		return state.hasMore ? label + ' · ' + __( 'more available', 'floppy' ) : label;
	}

	function sortSummaryLabel() {
		var state = appFileState();
		var label = FILE_SORT_LABELS[ state.sortKey ] || FILE_SORT_LABELS.name;
		return label + ' · ' + ( state.sortDirection === 'desc' ? __( 'descending', 'floppy' ) : __( 'ascending', 'floppy' ) );
	}

	function targetKey( item ) {
		return item ? item.kind + ':' + String( item.id ) : '';
	}

	function mergeEvents( existing, incoming ) {
		var seen = {};
		return existing.concat( incoming ).filter( function ( event ) {
			var key = String( event.seq || event.event_uuid || Math.random() );
			if ( seen[ key ] ) {
				return false;
			}
			seen[ key ] = true;
			return true;
		} );
	}

	function failingCheckCount( health ) {
		return Object.keys( health && health.checks ? health.checks : {} ).filter( function ( key ) {
			return ! health.checks[ key ].ok;
		} ).length;
	}

	function formatBytes( bytes ) {
		bytes = Number( bytes || 0 );
		if ( bytes < 1024 ) {
			return bytes + ' B';
		}
		if ( bytes < 1024 * 1024 ) {
			return Math.round( bytes / 1024 ) + ' KB';
		}
		if ( bytes < 1024 * 1024 * 1024 ) {
			return ( bytes / 1024 / 1024 ).toFixed( 1 ) + ' MB';
		}
		return ( bytes / 1024 / 1024 / 1024 ).toFixed( 1 ) + ' GB';
	}

	function formatDate( value ) {
		if ( ! value ) {
			return '-';
		}
		var normalized = String( value ).replace( ' ', 'T' );
		if ( normalized.indexOf( 'Z' ) === -1 ) {
			normalized += 'Z';
		}
		var date = new Date( normalized );
		if ( Number.isNaN( date.getTime() ) ) {
			return value;
		}
		return date.toLocaleString();
	}

	function errorStatus( error ) {
		if ( error && error.data && error.data.data && error.data.data.status ) {
			return Number( error.data.data.status );
		}
		if ( error && error.data && error.data.status ) {
			return Number( error.data.status );
		}
		return 0;
	}

	function supportBlockFrom( value ) {
		return value && value.support && typeof value.support === 'object' ? value.support : null;
	}

	function redactUrl( value ) {
		try {
			var url = new URL( value, window.location.href );
			return url.origin + url.pathname;
		} catch ( error ) {
			return '';
		}
	}

	function summarizeObject( value ) {
		if ( value == null ) {
			return '-';
		}
		if ( typeof value !== 'object' ) {
			return String( value );
		}
		return Object.keys( value ).map( function ( key ) {
			var item = value[ key ];
			if ( typeof item === 'object' && item !== null ) {
				item = JSON.stringify( item );
			}
			return key + ': ' + String( item );
		} ).join( ' · ' );
	}

	function safeFilenameStamp() {
		return new Date().toISOString().replace( /[:.]/g, '-' );
	}

	function downloadJson( data, filename ) {
		var blob = new Blob( [ JSON.stringify( data, null, 2 ) + '\n' ], { type: 'application/json' } );
		var url = URL.createObjectURL( blob );
		var link = document.createElement( 'a' );
		link.href = url;
		link.download = filename;
		document.body.appendChild( link );
		link.click();
		link.remove();
		window.setTimeout( function () {
			URL.revokeObjectURL( url );
		}, 0 );
	}

	function plural( count, singular, many ) {
		return String( count ) + ' ' + ( Number( count ) === 1 ? singular : many );
	}

	function fileIcon( mimeType ) {
		if ( /^image\//.test( mimeType || '' ) ) {
			return 'format-image';
		}
		if ( /^audio\//.test( mimeType || '' ) ) {
			return 'format-audio';
		}
		if ( /^video\//.test( mimeType || '' ) ) {
			return 'format-video';
		}
		if ( /pdf/.test( mimeType || '' ) ) {
			return 'pdf';
		}
		return 'media-default';
	}

	function eventIcon( eventType ) {
		eventType = String( eventType || '' );
		if ( eventType.indexOf( 'share.' ) === 0 ) {
			return 'groups';
		}
		if ( eventType.indexOf( 'delete' ) !== -1 || eventType.indexOf( 'trash' ) !== -1 ) {
			return 'trash';
		}
		if ( eventType.indexOf( 'folder.' ) === 0 ) {
			return 'category';
		}
		if ( eventType.indexOf( 'conflict' ) !== -1 ) {
			return 'warning';
		}
		return 'update';
	}

	function desktopSmokeEvidence() {
		refreshHostApis();
		var registrations = uniqueHookRegistrations();
		return {
			format: 'floppy-desktop-mode-smoke-v1',
			window_id: WINDOW_ID,
			has_wp_hooks: !! ( hooks && typeof hooks.addAction === 'function' ),
			has_wp_desktop: !! desktop,
			native_window_callback: !! ( window.desktopModeNativeWindows && window.desktopModeNativeWindows[ WINDOW_ID ] ),
			drag_target_mode: appFileState().dragTargetMode || ( desktop && desktop.dragManager && typeof desktop.dragManager.registerDropTarget === 'function' ? 'available' : 'fallback-hooks' ),
			request_race_count: Number( appFileState().requestRaceCount || 0 ),
			features: DESKTOP_FEATURES.map( function ( feature ) {
				return {
					key: feature.key,
					label: feature.label,
					available: !! feature.test()
				};
			} ),
			hooks: REQUIRED_DESKTOP_HOOKS.map( function ( key ) {
				var name = hookName( key );
				return {
					key: key,
					name: name,
					has_constant: !! ( desktop && desktop.HOOKS && desktop.HOOKS[ key ] ),
					registered: registrations.some( function ( registration ) {
						return registration.key === key;
					} )
				};
			} ),
			fallback_drop_hooks: FALLBACK_DROP_HOOKS.map( function ( key ) {
				var name = hookName( key );
				return {
					key: key,
					name: name,
					has_constant: !! ( desktop && desktop.HOOKS && desktop.HOOKS[ key ] ),
					registered: registrations.some( function ( registration ) {
						return registration.key === key;
					} )
				};
			} ),
			registrations: registrations
		};
	}

	function uniqueHookRegistrations() {
		var seen = {};
		return hookRegistrations.filter( function ( registration ) {
			var key = registration.type + ':' + registration.key + ':' + registration.namespace;
			if ( seen[ key ] ) {
				return false;
			}
			seen[ key ] = true;
			return true;
		} );
	}

	function escapeHtml( value ) {
		return String( value == null ? '' : value ).replace( /[&<>"']/g, function ( char ) {
			return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[ char ];
		} );
	}

	function hookName( key ) {
		return desktop && desktop.HOOKS && desktop.HOOKS[ key ] ? desktop.HOOKS[ key ] : FALLBACK_HOOKS[ key ];
	}

	function addHookAction( key, namespace, callback, cleanup ) {
		var name = hookName( key );
		if ( hooks && typeof hooks.addAction === 'function' && name ) {
			hooks.addAction( name, namespace, callback );
			hookRegistrations.push( {
				type: 'action',
				key: key,
				name: name,
				namespace: namespace,
				has_constant: !! ( desktop && desktop.HOOKS && desktop.HOOKS[ key ] )
			} );
			if ( cleanup ) {
				cleanup.push( function () {
					if ( hooks && typeof hooks.removeAction === 'function' ) {
						hooks.removeAction( name, namespace );
					}
				} );
			}
		}
	}

	function addHookFilter( key, namespace, callback, cleanup ) {
		var name = hookName( key );
		if ( hooks && typeof hooks.addFilter === 'function' && name ) {
			hooks.addFilter( name, namespace, callback );
			hookRegistrations.push( {
				type: 'filter',
				key: key,
				name: name,
				namespace: namespace,
				has_constant: !! ( desktop && desktop.HOOKS && desktop.HOOKS[ key ] )
			} );
			if ( cleanup ) {
				cleanup.push( function () {
					if ( hooks && typeof hooks.removeFilter === 'function' ) {
						hooks.removeFilter( name, namespace );
					}
				} );
			}
		}
	}

	function payloadMatchesWindow( payload ) {
		if ( payload === WINDOW_ID ) {
			return true;
		}
		if ( ! payload || typeof payload !== 'object' ) {
			return false;
		}
		var candidates = [
			payload.id,
			payload.windowId,
			payload.appId,
			payload.itemId,
			payload.iconId,
			payload.tileId,
			payload.targetId,
			payload.icon && payload.icon.id,
			payload.icon && payload.icon.window,
			payload.icon && payload.icon.windowId,
			payload.item && payload.item.id,
			payload.item && payload.item.window,
			payload.item && payload.item.baseId,
			payload.window && payload.window.id,
			payload.window && payload.window.config && payload.window.config.id,
			payload.window && payload.window.config && payload.window.config.baseId,
			payload.config && payload.config.id,
			payload.config && payload.config.baseId
		];
		return candidates.some( function ( candidate ) {
			return candidate === WINDOW_ID;
		} );
	}

	function panelFromPayload( payload ) {
		if ( ! payload || typeof payload !== 'object' ) {
			return '';
		}
		return payload.panel ||
			( payload.options && payload.options.panel ) ||
			( payload.detail && payload.detail.panel ) ||
			( payload.window && payload.window.panel ) ||
			( payload.window && payload.window.options && payload.window.options.panel ) ||
			'';
	}

	function filesFromPayload( payload ) {
		if ( ! payload || typeof payload !== 'object' ) {
			return [];
		}
		if ( payload.files && typeof payload.files.length === 'number' ) {
			return Array.prototype.slice.call( payload.files );
		}
		if ( payload.dataTransfer && payload.dataTransfer.files ) {
			return Array.prototype.slice.call( payload.dataTransfer.files );
		}
		if ( payload.event && payload.event.dataTransfer && payload.event.dataTransfer.files ) {
			return Array.prototype.slice.call( payload.event.dataTransfer.files );
		}
		return [];
	}

	function registerDesktopModeExtensions() {
		refreshHostApis();

		window.desktopModeNativeWindows = window.desktopModeNativeWindows || {};
		window.desktopModeNativeWindows[ WINDOW_ID ] = function ( container, ctx ) {
			return mount( container, ctx );
		};

		if ( window.__floppyDesktopRegistered ) {
			return;
		}
		window.__floppyDesktopRegistered = true;

		if ( desktop && typeof desktop.registerCommand === 'function' ) {
			[
				{ slug: 'floppy/open', label: __( 'Open Floppy', 'floppy' ), panel: 'files' },
				{ slug: 'floppy/recents', label: __( 'Floppy Recents', 'floppy' ), panel: 'recents' },
				{ slug: 'floppy/trash', label: __( 'Floppy Trash', 'floppy' ), panel: 'trash' },
				{ slug: 'floppy/shared', label: __( 'Floppy Shared Files', 'floppy' ), panel: 'shared' },
				{ slug: 'floppy/conflicts', label: __( 'Floppy Conflicts', 'floppy' ), panel: 'conflicts' },
				{ slug: 'floppy/versions', label: __( 'Floppy Versions', 'floppy' ), panel: 'versions' },
				{ slug: 'floppy/sync', label: __( 'Floppy Sync Feed', 'floppy' ), panel: 'sync' },
				{ slug: 'floppy/upload', label: __( 'Upload to Floppy', 'floppy' ), panel: 'files', upload: true },
				{ slug: 'floppy/devices', label: __( 'Show Floppy Devices', 'floppy' ), panel: 'devices' },
				{ slug: 'floppy/diagnostics', label: __( 'Run Floppy Diagnostics', 'floppy' ), panel: 'diagnostics' },
				{ slug: 'floppy/jobs', label: __( 'Floppy Jobs', 'floppy' ), panel: 'jobs' },
				{ slug: 'floppy/evidence', label: __( 'Floppy Release Evidence', 'floppy' ), panel: 'evidence' },
				{ slug: 'floppy/settings', label: __( 'Floppy Settings', 'floppy' ), panel: 'settings' }
			].forEach( function ( command ) {
				desktop.registerCommand( {
					slug: command.slug,
					label: command.label,
					owner: OWNER,
					run: function () {
						if ( command.upload && desktop && typeof desktop.broadcast === 'function' ) {
							desktop.broadcast( 'floppy.upload.requested', {} );
						}
						openWindow( command.panel, 'command' );
					}
				} );
			} );
		}

		if ( desktop && typeof desktop.registerSettingsTab === 'function' ) {
			desktop.registerSettingsTab( {
				id: 'floppy',
				label: __( 'Floppy', 'floppy' ),
				owner: OWNER,
				render: renderSettingsTab
			} );
		}

		if ( desktop && typeof desktop.registerTitleBarButton === 'function' ) {
			[
				{ id: 'floppy-upload', icon: 'dashicons-upload', label: __( 'Upload', 'floppy' ), panel: 'files', upload: true },
				{ id: 'floppy-recents', icon: 'dashicons-clock', label: __( 'Recents', 'floppy' ), panel: 'recents' },
				{ id: 'floppy-shared', icon: 'dashicons-groups', label: __( 'Shared', 'floppy' ), panel: 'shared' },
				{ id: 'floppy-sync-status', icon: 'dashicons-update', label: __( 'Sync status', 'floppy' ), panel: 'sync' },
				{ id: 'floppy-evidence', icon: 'dashicons-clipboard', label: __( 'Release evidence', 'floppy' ), panel: 'evidence' }
			].forEach( function ( button ) {
				desktop.registerTitleBarButton( {
					id: button.id,
					owner: OWNER,
					match: matchesFloppyWindow,
					icon: button.icon,
					label: button.label,
					onClick: function () {
						if ( button.upload && desktop && typeof desktop.broadcast === 'function' ) {
							desktop.broadcast( 'floppy.upload.requested', {} );
						}
						openWindow( button.panel, 'titlebar' );
					}
				} );
			} );
		}

		if ( desktop && desktop.files && typeof desktop.files.registerOpener === 'function' ) {
			desktop.files.registerOpener( {
				id: 'floppy-private-preview',
				label: __( 'Open in Floppy', 'floppy' ),
				owner: OWNER,
				types: [ 'attachment' ],
				sort: 20,
				handler: { kind: 'window', windowId: WINDOW_ID }
			} );
		}

		if ( desktop && typeof desktop.subscribe === 'function' ) {
			desktop.subscribe( 'floppy.files.changed', function () {
				setActivityBadge( badgeState.activity + 1 );
			} );
		}

		addHookAction( 'WINDOW_FOCUSED', 'floppy/focus', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				setActivityBadge( 0 );
			}
		} );
		addHookAction( 'WINDOW_REOPENED', 'floppy/reopened', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				var panel = panelFromPayload( payload );
				if ( panel && desktop && typeof desktop.broadcast === 'function' ) {
					desktop.broadcast( 'floppy.panel.open', { panel: panel } );
				}
			}
		} );
		addHookAction( 'WINDOW_CONTENT_LOADED', 'floppy/content-loaded', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				setActivityBadge( 0 );
			}
		} );
		addHookAction( 'WINDOW_CLOSED', 'floppy/closed', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				setActivityBadge( 0 );
			}
		} );
		addHookAction( 'DESKTOP_ICON_CLICKED', 'floppy/icon-clicked', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				setActivityBadge( 0 );
			}
		} );
		addHookAction( 'ICON_BADGE_CHANGED', 'floppy/icon-badge-changed', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				updateDecoratedLaunchers();
			}
		} );
		addHookAction( 'DESKTOP_ICONS_RENDERED', 'floppy/desktop-icon-rendered', function ( payload ) {
			var tile = payload && payload.tiles && typeof payload.tiles.get === 'function' ? payload.tiles.get( WINDOW_ID ) : null;
			if ( tile ) {
				decorateLauncherElement( tile, 'desktop' );
			}
		} );
		addHookFilter( 'DESKTOP_ICON_MENU_ITEMS', 'floppy/desktop-icon-menu-items', function ( items, context ) {
			if ( ! payloadMatchesWindow( context ) ) {
				return items;
			}
			return ( Array.isArray( items ) ? items.slice() : [] ).concat( [
				{
					id: 'floppy-open-drive',
					label: __( 'Open Floppy Drive', 'floppy' ),
					icon: 'dashicons-archive',
					onSelect: function () {
						openWindow( 'files', 'desktop-icon-menu' );
					}
				},
				{
					id: 'floppy-upload-files',
					label: __( 'Upload files...', 'floppy' ),
					icon: 'dashicons-upload',
					onSelect: function () {
						if ( desktop && typeof desktop.broadcast === 'function' ) {
							desktop.broadcast( 'floppy.upload.requested', {} );
						}
						openWindow( 'files', 'desktop-icon-menu' );
					}
				},
				{
					id: 'floppy-open-settings',
					label: __( 'Floppy Settings...', 'floppy' ),
					icon: 'dashicons-admin-generic',
					onSelect: function () {
						openWindow( 'settings', 'desktop-icon-menu' );
					}
				}
			] );
		} );
		addHookFilter( 'FILES_TILE_CLASS', 'floppy/files-tile-class', function ( classes, placement ) {
			return placementMatchesFloppy( placement ) ? addClassString( classes, 'floppy-desktop-file-tile' ) : classes;
		} );
		addHookFilter( 'FILES_TILE_ELEMENT', 'floppy/files-tile-element', function ( element, placement ) {
			if ( ! placementMatchesFloppy( placement ) || element ) {
				return element;
			}
			var badge = document.createElement( 'span' );
			badge.className = 'floppy-desktop-file-tile__badge';
			badge.setAttribute( 'aria-hidden', 'true' );
			return badge;
		} );
		addHookAction( 'FILES_TILE_RENDERED', 'floppy/files-tile-rendered', function ( payload ) {
			if ( payload && payload.tile ) {
				decorateFileTile( payload.tile, payload.placement );
			}
		} );
		addHookFilter( 'DOCK_TILE_CLASS', 'floppy/dock-class', function ( classes, payload ) {
			return payloadMatchesWindow( payload ) ? addClassValue( classes, 'floppy-dock-tile' ) : classes;
		} );
		addHookFilter( 'DOCK_TILE_ELEMENT', 'floppy/dock-element', function ( element, payload ) {
			return payloadMatchesWindow( payload ) ? decorateLauncherElement( element, 'dock' ) : element;
		} );
		addHookFilter( 'DOCK_TILE_TOOLTIP', 'floppy/dock-tooltip', function ( tooltip, payload ) {
			if ( ! payloadMatchesWindow( payload ) ) {
				return tooltip;
			}
			return __( 'Floppy', 'floppy' ) + ' · ' + appSummary.lastStatus;
		} );
		addHookAction( 'DOCK_TILE_RENDERED', 'floppy/dock-rendered', function ( payload ) {
			var element = payload && ( payload.el || payload.element );
			if ( payloadMatchesWindow( payload ) && element ) {
				decorateLauncherElement( element, 'dock' );
			}
		} );

	}

	function openWindow( panel, source ) {
		if ( desktop && typeof desktop.openWindow === 'function' ) {
			desktop.openWindow( WINDOW_ID, { source: source || OWNER, panel: panel || 'files' } );
			if ( panel && desktop && typeof desktop.broadcast === 'function' ) {
				window.setTimeout( function () {
					desktop.broadcast( 'floppy.panel.open', { panel: panel } );
				}, 0 );
			}
		}
	}

	function matchesFloppyWindow( win ) {
		return !! ( win && win.config && ( win.config.id === WINDOW_ID || win.config.baseId === WINDOW_ID ) );
	}

	if ( desktop && typeof desktop.ready === 'function' ) {
		desktop.ready( registerDesktopModeExtensions );
	} else if ( document.readyState === 'loading' ) {
		document.addEventListener( 'DOMContentLoaded', registerDesktopModeExtensions );
	} else {
		registerDesktopModeExtensions();
	}
}( window, document, window.wp || {} ) );
