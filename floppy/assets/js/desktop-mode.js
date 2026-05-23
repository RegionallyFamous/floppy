( function ( window, document, wp ) {
	'use strict';

	var config = window.floppyDesktopConfig || {};
	var desktop = wp && wp.desktop ? wp.desktop : null;
	var hooks = wp && wp.hooks ? wp.hooks : null;
	var __ = wp && wp.i18n ? wp.i18n.__ : function ( text ) { return text; };
	var WINDOW_ID = config.windowId || 'floppy-drive';
	var OWNER = 'floppy-desktop-mode';
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
	var FALLBACK_HOOKS = {
		WINDOW_FOCUSED: 'desktop-mode.window.focused',
		WINDOW_CLOSING: 'desktop-mode.window.closing',
		WINDOW_CLOSED: 'desktop-mode.window.closed',
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
		shared: __( 'Shared', 'floppy' ),
		sync: __( 'Sync', 'floppy' ),
		devices: __( 'Devices', 'floppy' ),
		diagnostics: __( 'Diagnostics', 'floppy' ),
		settings: __( 'Settings', 'floppy' )
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
			devices: [],
			deviceError: null,
			sync: null,
			syncEvents: [],
			sharedEvents: [],
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
			osSettings: null
		};
		var cleanup = [];
		var namespace = OWNER + '/window-' + String( Date.now() ) + '-' + String( Math.random() ).slice( 2 );

		container.classList.add( 'floppy-app' );
		setCurrentStateReference( container, state );
		setCurrentItemsReference( container, state.items );
		container.__floppyPaintFileList = paintFileList;
		container.innerHTML = [
			'<div class="floppy-shell">',
				'<aside class="floppy-sidebar">',
					'<div class="floppy-brand"><span class="dashicons dashicons-archive"></span><div><strong>Floppy</strong><span data-floppy-status>Ready</span></div></div>',
					renderNavButton( 'files', 'media-default', true ),
					renderNavButton( 'shared', 'groups' ),
					renderNavButton( 'sync', 'update' ),
					renderNavButton( 'devices', 'desktop' ),
					renderNavButton( 'diagnostics', 'chart-area' ),
					renderNavButton( 'settings', 'admin-generic' ),
				'</aside>',
				'<main class="floppy-main">',
					'<header class="floppy-toolbar">',
						'<div class="floppy-breadcrumb">',
							'<button class="floppy-icon-button" data-action="home" title="Home"><span class="dashicons dashicons-admin-home"></span></button>',
							'<div><strong data-toolbar-title>My Drive</strong><span data-toolbar-subtitle>Private WordPress Drive</span></div>',
						'</div>',
						'<div class="floppy-actions">',
							'<button class="floppy-icon-button" data-action="new-folder" title="New folder"><span class="dashicons dashicons-category"></span></button>',
							'<button class="floppy-icon-button" data-action="upload" title="Upload"><span class="dashicons dashicons-upload"></span></button>',
							'<button class="floppy-icon-button" data-action="refresh" title="Refresh"><span class="dashicons dashicons-update"></span></button>',
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

		function renderNavButton( panel, icon, active ) {
			return '<button class="floppy-nav' + ( active ? ' is-active' : '' ) + '" data-panel="' + panel + '">' +
				'<span class="dashicons dashicons-' + icon + '"></span><span>' + escapeHtml( PANEL_LABELS[ panel ] ) + '</span>' +
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
				button.classList.toggle( 'is-active', button.getAttribute( 'data-panel' ) === state.panel );
			} );
			if ( titleNode ) {
				titleNode.textContent = PANEL_LABELS[ state.panel ] || PANEL_LABELS.files;
			}
			if ( subtitleNode ) {
				subtitleNode.textContent = state.panel === 'files' && state.parentId ? __( 'Folder contents', 'floppy' ) : __( 'Private WordPress Drive', 'floppy' );
			}
		}

		function renderLoading( label ) {
			panelRoot.innerHTML = '<div class="floppy-loading-panel"><span class="dashicons dashicons-update"></span><strong>' + escapeHtml( label ) + '</strong></div>';
		}

		function renderFiles() {
			updateChrome();
			var uploadLine = state.uploading ? '<div class="floppy-callout is-info"><strong>' + escapeHtml( String( state.uploading ) ) + '</strong> ' + escapeHtml( __( 'uploading now', 'floppy' ) ) + '</div>' : '';
			panelRoot.innerHTML = [
				'<div class="floppy-drop-zone floppy-files" data-files-panel>',
					uploadLine,
					'<div class="floppy-files-toolbar">',
						'<div class="floppy-files-title"><h2>' + escapeHtml( state.parentId ? __( 'Folder', 'floppy' ) : __( 'My Drive', 'floppy' ) ) + '</h2><span data-file-count></span></div>',
						'<label class="floppy-search"><span class="dashicons dashicons-search" aria-hidden="true"></span><input type="search" data-file-search value="' + escapeHtml( state.filterText ) + '" placeholder="' + escapeHtml( __( 'Search this drive', 'floppy' ) ) + '" /></label>',
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
				return '<button type="button" class="' + ( state.kindFilter === key ? 'is-active' : '' ) + '" data-kind-filter="' + escapeHtml( key ) + '">' + escapeHtml( FILE_KIND_FILTERS[ key ] ) + '</button>';
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
			wrap.innerHTML = [
				'<table class="floppy-file-table" aria-label="' + escapeHtml( __( 'Floppy files', 'floppy' ) ) + '">',
					'<thead><tr>',
						'<th scope="col" class="floppy-file-check"><input type="checkbox" data-select-visible ' + ( selected.length && selected.length === visible.length ? 'checked ' : '' ) + 'aria-label="' + escapeHtml( __( 'Select all visible files', 'floppy' ) ) + '" /></th>',
						renderSortHeading( 'name', FILE_SORT_LABELS.name, 'floppy-file-name-heading' ),
						renderSortHeading( 'kind', FILE_SORT_LABELS.kind, '' ),
						renderSortHeading( 'size', FILE_SORT_LABELS.size, 'is-number' ),
						renderSortHeading( 'updated', FILE_SORT_LABELS.updated, '' ),
						'<th scope="col" class="floppy-file-actions-heading"><span class="screen-reader-text">' + escapeHtml( __( 'Actions', 'floppy' ) ) + '</span></th>',
					'</tr></thead>',
					'<tbody>',
						visible.map( renderFileRow ).join( '' ),
					'</tbody>',
				'</table>',
				state.hasMore ? '<div class="floppy-file-footer"><button type="button" class="button" data-action="load-more" ' + ( state.loadingMore ? 'disabled' : '' ) + '>' + escapeHtml( state.loadingMore ? __( 'Loading...', 'floppy' ) : __( 'Load More', 'floppy' ) ) + '</button></div>' : ''
			].join( '' );
		}

		function renderSortHeading( key, label, className ) {
			var active = state.sortKey === key;
			var aria = active ? ( state.sortDirection === 'asc' ? 'ascending' : 'descending' ) : 'none';
			var icon = active && state.sortDirection === 'desc' ? 'arrow-down-alt2' : 'arrow-up-alt2';
			return '<th scope="col" class="' + escapeHtml( className || '' ) + '" aria-sort="' + aria + '"><button type="button" data-sort-key="' + escapeHtml( key ) + '"><span>' + escapeHtml( label ) + '</span><span class="dashicons dashicons-' + icon + '" aria-hidden="true"></span></button></th>';
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
			return '<tr class="floppy-file-row' + ( selected ? ' is-selected' : '' ) + '" data-row-key="' + escapeHtml( key ) + '" data-kind="' + escapeHtml( item.kind ) + '" data-id="' + escapeHtml( String( item.id ) ) + '">' +
				'<td class="floppy-file-check"><input type="checkbox" data-select-item="' + escapeHtml( key ) + '" ' + ( selected ? 'checked ' : '' ) + 'aria-label="' + escapeHtml( __( 'Select ', 'floppy' ) + item.name ) + '" /></td>' +
				'<td class="floppy-file-name-cell"><button type="button" class="floppy-file-open" data-open-item="' + escapeHtml( key ) + '"><span class="dashicons dashicons-' + icon + '" aria-hidden="true"></span><span><strong>' + escapeHtml( item.name ) + '</strong><small>' + escapeHtml( itemSubtitle( item ) ) + '</small></span></button></td>' +
				'<td>' + escapeHtml( kindLabel( item ) ) + '</td>' +
				'<td class="is-number">' + escapeHtml( size ) + '</td>' +
				'<td>' + escapeHtml( updated || '-' ) + '</td>' +
				'<td class="floppy-file-actions">' +
					( item.kind === 'file' ? '<button type="button" class="floppy-row-action" data-action="download-item" data-row-key="' + escapeHtml( key ) + '" title="' + escapeHtml( __( 'Download', 'floppy' ) ) + '"><span class="dashicons dashicons-download" aria-hidden="true"></span></button>' : '' ) +
					'<button type="button" class="floppy-row-action" data-action="share-item" data-row-key="' + escapeHtml( key ) + '" title="' + escapeHtml( __( 'Share', 'floppy' ) ) + '"><span class="dashicons dashicons-groups" aria-hidden="true"></span></button>' +
					'<button type="button" class="floppy-row-action" data-action="rename-item" data-row-key="' + escapeHtml( key ) + '" title="' + escapeHtml( __( 'Rename', 'floppy' ) ) + '"><span class="dashicons dashicons-edit" aria-hidden="true"></span></button>' +
					'<button type="button" class="floppy-row-action is-danger" data-action="trash-item" data-row-key="' + escapeHtml( key ) + '" title="' + escapeHtml( __( 'Move to Trash', 'floppy' ) ) + '"><span class="dashicons dashicons-trash" aria-hidden="true"></span></button>' +
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
			markLoading( ctx );
			renderLoading( __( 'Loading files', 'floppy' ) );
			state.nextCursor = '';
			state.hasMore = false;
			return fetchFiles( false ).then( function () {
				renderFiles();
				markReady( ctx );
			} ).catch( showError );
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
			markLoading( ctx );
			renderLoading( __( 'Loading sharing', 'floppy' ) );
			return Promise.all( [
				fetchFiles(),
				fetchSharedEvents()
			] ).then( function () {
				if ( ! currentShareTarget() && state.items.length ) {
					state.shareTarget = targetKey( state.items[0] );
				}
				renderShared();
				markReady( ctx );
			} ).catch( showError );
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
			markLoading( ctx );
			renderLoading( __( 'Loading diagnostics', 'floppy' ) );
			return loadHealth().then( function () {
				renderDiagnostics();
				markReady( ctx );
			} ).catch( showError );
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
			markLoading( ctx );
			renderLoading( __( 'Loading devices', 'floppy' ) );
			return loadDevices().then( function () {
				renderDevices();
				markReady( ctx );
			} ).catch( showError );
		}

		function loadSync( reset ) {
			var cursor = reset ? 0 : state.syncCursor;
			markLoading( ctx );
			renderLoading( __( 'Loading sync feed', 'floppy' ) );
			return apiRequest( 'sync/changes?cursor=' + encodeURIComponent( cursor || 0 ) + '&limit=50' ).then( function ( data ) {
				state.sync = data;
				state.syncCursor = data.next_cursor || cursor || 0;
				appSummary.lastSyncCursor = state.syncCursor;
				state.syncEvents = reset ? ( data.events || [] ) : mergeEvents( state.syncEvents, data.events || [] );
				renderSync();
				markReady( ctx );
			} ).catch( showError );
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

		function switchPanel( panel ) {
			state.panel = panel || 'files';
			updateChrome();
			if ( state.panel === 'files' ) {
				loadFiles();
			} else if ( state.panel === 'shared' ) {
				loadShared();
			} else if ( state.panel === 'sync' ) {
				loadSync( true );
			} else if ( state.panel === 'devices' ) {
				loadDevicePanel();
			} else if ( state.panel === 'diagnostics' ) {
				loadDiagnostics();
			} else {
				refreshOsSettings( false ).then( renderSettings );
			}
		}

		function reloadCurrentPanel() {
			if ( state.panel === 'shared' ) {
				loadShared();
			} else if ( state.panel === 'sync' ) {
				loadSync( true );
			} else if ( state.panel === 'devices' ) {
				loadDevicePanel();
			} else if ( state.panel === 'diagnostics' ) {
				loadDiagnostics();
			} else if ( state.panel === 'settings' ) {
				refreshOsSettings( true );
			} else {
				loadFiles();
			}
		}

		function showError( error ) {
			markReady( ctx );
			setStatus( __( 'Needs attention', 'floppy' ), 'error' );
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
			if ( name === 'upload' ) {
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
			} else if ( name === 'unshare' ) {
				unshareTarget();
			} else if ( name === 'sync-reset' ) {
				state.syncCursor = 0;
				state.syncEvents = [];
				loadSync( true );
			} else if ( name === 'sync-more' ) {
				loadSync( false );
			} else if ( name === 'health-refresh' ) {
				loadDiagnostics();
			} else if ( name === 'devices-refresh' ) {
				loadDevicePanel();
			} else if ( name === 'device-revoke' ) {
				revokeDevice( action.getAttribute( 'data-device-uuid' ) );
			} else if ( name === 'settings-refresh' ) {
				refreshOsSettings( true );
			} else if ( name === 'desktop-settings' ) {
				openDesktopSettings();
			}
		}

		container.addEventListener( 'click', function ( event ) {
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
					button.classList.toggle( 'is-active', button.getAttribute( 'data-kind-filter' ) === state.kindFilter );
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
			if ( row && ! event.target.closest( 'button,input,a' ) ) {
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

		container.addEventListener( 'dblclick', function ( event ) {
			currentMount = container;
			var row = event.target.closest( '.floppy-file-row' );
			if ( row && ! event.target.closest( 'button,input,a' ) ) {
				openItemByKey( row.getAttribute( 'data-row-key' ) );
			}
		} );

		container.addEventListener( 'input', function ( event ) {
			currentMount = container;
			var search = event.target.closest( '[data-file-search]' );
			if ( search ) {
				state.filterText = search.value || '';
				paintFileList();
			}
		} );

		container.addEventListener( 'change', function ( event ) {
			currentMount = container;
			var selectVisible = event.target.closest( '[data-select-visible]' );
			var selectItem = event.target.closest( '[data-select-item]' );
			if ( selectVisible ) {
				setVisibleSelection( selectVisible.checked );
			} else if ( selectItem ) {
				setSelectedItem( selectItem.getAttribute( 'data-select-item' ), selectItem.checked );
			}
		} );

		container.addEventListener( 'submit', function ( event ) {
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

		addHookAction( 'FILE_DROP_FILES_DETECTED', namespace + '/drop-detected', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				container.classList.add( 'is-dragging' );
			}
		}, cleanup );
		addHookAction( 'FILE_DROP_BEFORE_UPLOAD', namespace + '/drop-before-upload', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				handleNativeDropPayload( payload );
			}
		}, cleanup );
		addHookAction( 'FILE_DROP_UPLOAD_STARTED', namespace + '/drop-upload-started', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				setStatus( __( 'Uploading dropped files', 'floppy' ), 'busy' );
			}
		}, cleanup );
		addHookAction( 'FILE_DROP_UPLOAD_PROGRESS', namespace + '/drop-upload-progress', function ( payload ) {
			if ( payloadMatchesWindow( payload ) && payload && payload.progress ) {
				setStatus( __( 'Uploading ', 'floppy' ) + String( Math.round( payload.progress ) ) + '%', 'busy' );
			}
		}, cleanup );
		addHookAction( 'FILE_DROP_AFTER_UPLOAD', namespace + '/drop-after-upload', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				container.classList.remove( 'is-dragging' );
				setStatus( __( 'Ready', 'floppy' ) );
				reloadCurrentPanel();
			}
		}, cleanup );
		addHookAction( 'FILE_DROP_UPLOAD_FAILED', namespace + '/drop-upload-failed', function ( payload ) {
			if ( payloadMatchesWindow( payload ) ) {
				container.classList.remove( 'is-dragging' );
				setStatus( __( 'Upload failed', 'floppy' ), 'error' );
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

		return function () {
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
		if ( desktop && typeof desktop.openSettings === 'function' ) {
			desktop.openSettings( { tab: 'floppy', source: OWNER } );
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
			return '<button type="button" class="' + ( visibility === key ? 'is-active' : '' ) + '" data-os-visibility="' + escapeHtml( key ) + '">' + escapeHtml( OS_VISIBILITY_LABELS[ key ] ) + '</button>';
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
		visibleFileItems().forEach( function ( item ) {
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
				{ slug: 'floppy/shared', label: __( 'Floppy Shared Files', 'floppy' ), panel: 'shared' },
				{ slug: 'floppy/sync', label: __( 'Floppy Sync Feed', 'floppy' ), panel: 'sync' },
				{ slug: 'floppy/upload', label: __( 'Upload to Floppy', 'floppy' ), panel: 'files', upload: true },
				{ slug: 'floppy/devices', label: __( 'Show Floppy Devices', 'floppy' ), panel: 'devices' },
				{ slug: 'floppy/diagnostics', label: __( 'Run Floppy Diagnostics', 'floppy' ), panel: 'diagnostics' },
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
				{ id: 'floppy-shared', icon: 'dashicons-groups', label: __( 'Shared', 'floppy' ), panel: 'shared' },
				{ id: 'floppy-sync-status', icon: 'dashicons-update', label: __( 'Sync status', 'floppy' ), panel: 'sync' }
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
