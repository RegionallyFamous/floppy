#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname( fileURLToPath( import.meta.url ) );
const repo = resolve( here, '../../..' );
const args = parseArgs( process.argv.slice( 2 ) );
const sourcePath = resolve( repo, args.source || 'floppy/assets/js/desktop-mode.js' );
const format = args.format || 'text';
const source = readFileSync( sourcePath, 'utf8' );

const requiredHooks = [
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

const fallbackDropHooks = [
	'FILE_DROP_FILES_DETECTED',
	'FILE_DROP_BEFORE_UPLOAD',
	'FILE_DROP_UPLOAD_STARTED',
	'FILE_DROP_UPLOAD_PROGRESS',
	'FILE_DROP_AFTER_UPLOAD',
	'FILE_DROP_UPLOAD_FAILED'
];

const hookNames = {
	WINDOW_REOPENED: 'desktop-mode.window.reopened',
	WINDOW_FOCUSED: 'desktop-mode.window.focused',
	WINDOW_CONTENT_LOADED: 'desktop-mode.window.content-loaded',
	WINDOW_CLOSING: 'desktop-mode.window.closing',
	WINDOW_CLOSED: 'desktop-mode.window.closed',
	NATIVE_WINDOW_AFTER_RENDER: 'desktop-mode.native-window.after-render',
	NATIVE_WINDOW_BEFORE_CLOSE: 'desktop-mode.native-window.before-close',
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
	DESKTOP_ICON_MENU_ITEMS: 'desktop-mode.desktop-icon.menu-items'
};

const requiredCommands = [
	'floppy/open',
	'floppy/recents',
	'floppy/trash',
	'floppy/shared',
	'floppy/conflicts',
	'floppy/versions',
	'floppy/sync',
	'floppy/upload',
	'floppy/devices',
	'floppy/diagnostics',
	'floppy/jobs',
	'floppy/evidence',
	'floppy/settings'
];

const requiredPanels = [
	'files',
	'recents',
	'trash',
	'shared',
	'conflicts',
	'versions',
	'sync',
	'devices',
	'diagnostics',
	'jobs',
	'evidence',
	'settings'
];

const bannedPatterns = [
	{ label: 'legacy wp-desktop hook namespace', pattern: /wp-desktop/ },
	{ label: 'legacy native-window global', pattern: /wpDesktopNativeWindows/ },
	{ label: 'private widget storage key', pattern: /desktop-mode-widgets/ },
	{ label: 'host shell MutationObserver', pattern: /MutationObserver/ },
	{ label: 'shadow DOM monkeypatch', pattern: /attachShadow/ },
	{ label: 'private Desktop Mode window selector', pattern: /\.desktop-mode-window/ },
	{ label: 'parallel localStorage state', pattern: /localStorage/ }
];

const execution = executeDesktopModeScript( source );
const checks = {
	hooks: requiredHooks.map( ( key ) => ( {
		key,
		name: hookNames[ key ],
		pass: execution.hookRegistrations.some( ( registration ) => registration.key === key )
	} ) ),
	fallbackDropHooks: fallbackDropHooks.map( ( key ) => ( {
		key,
		name: hookNames[ key ],
		pass: execution.hookRegistrations.some( ( registration ) => registration.key === key )
	} ) ),
	commands: requiredCommands.map( ( slug ) => ( {
		slug,
		pass: execution.commands.some( ( command ) => command.slug === slug )
	} ) ),
	panels: requiredPanels.map( ( panel ) => ( {
		panel,
		pass: source.includes( `${ panel }:` ) || source.includes( `'${ panel }'` ) || source.includes( `"${ panel }"` )
	} ) ),
	apis: [
		{ api: 'desktop.HOOKS', pass: source.includes( 'desktop.HOOKS' ) },
		{ api: 'desktop.openOsSettings', pass: source.includes( 'desktop.openOsSettings' ) },
		{ api: 'desktop.dragManager.registerDropTarget', pass: execution.dropTargets.length > 0 },
		{ api: 'desktop.registerSettingsTab', pass: execution.settingsTabs.length > 0 },
		{ api: 'desktop.registerTitleBarButton', pass: execution.titleBarButtons.length >= 4 },
		{ api: 'desktop.files.registerOpener', pass: execution.fileOpeners.length > 0 },
		{ api: 'desktop.broadcast', pass: execution.broadcasts.length > 0 || source.includes( 'desktop.broadcast' ) },
		{ api: 'desktop.icons.setBadge', pass: execution.iconBadges.length > 0 || source.includes( 'desktop.icons.setBadge' ) },
		{ api: 'desktop.dock.setBadge', pass: execution.dockBadges.length > 0 || source.includes( 'desktop.dock.setBadge' ) },
		{ api: 'desktop.taskbar.setBadge', pass: execution.taskbarBadges.length > 0 || source.includes( 'desktop.taskbar.setBadge' ) }
	],
	accessibility: [
		{ label: 'sidebar exposes a navigation label', pass: /<aside class="floppy-sidebar" aria-label=/.test( source ) },
		{ label: 'panel navigation buttons have explicit button type', pass: /<button type="button" class="floppy-nav/.test( source ) },
		{ label: 'app status updates are announced politely', pass: /data-floppy-status aria-live="polite" aria-atomic="true"/.test( source ) },
		{ label: 'loading panel is a live status region', pass: /floppy-loading-panel" role="status" aria-live="polite" aria-atomic="true"/.test( source ) },
		{ label: 'inline panel errors use an alert role', pass: /floppy-error-state" role="alert"/.test( source ) },
		{ label: 'file search has an accessible label', pass: /<label class="floppy-search"><span class="screen-reader-text">[\s\S]*data-file-search/.test( source ) },
		{ label: 'select all is bounded to rendered rows', pass: /visibleFileItems\(\)\.slice\( 0, FILE_RENDER_LIMIT \)/.test( source ) },
		{ label: 'selectable rows are explicit', pass: /data-selectable-row="1"/.test( source ) },
		{ label: 'recovery rows carry mode semantics', pass: /data-recovery-mode=/.test( source ) },
		{ label: 'trash rows restore before opening', pass: /mode === 'trash'/.test( source ) && /data-action="restore-item"/.test( source ) && /getAttribute\( 'data-recovery-mode' \) === 'trash'/.test( source ) && /restoreItem\( itemByKey/.test( source ) }
	],
	asyncRaces: [
		{ label: 'panel error handlers are request-token guarded', pass: /function showPanelError/.test( source ) && ( source.match( /\.catch\( showPanelError\( token \) \)/g ) || [] ).length >= 8 }
	],
	cleanup: [
		{ label: 'native window returned cleanup function', pass: typeof execution.windowCleanup === 'function' },
		{ label: 'registered drop target has deregister callback', pass: execution.dropDeregistered > 0 },
		{ label: 'window hook actions cleaned up', pass: execution.removedActions > 0 },
		{ label: 'window hook filters cleaned up', pass: execution.removedFilters > 0 },
		{ label: 'native window DOM listeners cleaned up', pass: execution.addedDomListeners > 0 && execution.removedDomListeners === execution.addedDomListeners },
		{ label: 'native window cleanup is idempotent', pass: execution.cleanupIdempotent }
	],
	banned: bannedPatterns.map( ( entry ) => ( {
		label: entry.label,
		pass: ! entry.pattern.test( source )
	} ) )
};

const failures = [
	...checks.hooks.filter( ( check ) => ! check.pass ).map( ( check ) => `missing executed hook ${ check.key }` ),
	...checks.fallbackDropHooks.filter( ( check ) => ! check.pass ).map( ( check ) => `missing fallback drop hook ${ check.key }` ),
	...checks.commands.filter( ( check ) => ! check.pass ).map( ( check ) => `missing command ${ check.slug }` ),
	...checks.panels.filter( ( check ) => ! check.pass ).map( ( check ) => `missing panel ${ check.panel }` ),
	...checks.apis.filter( ( check ) => ! check.pass ).map( ( check ) => `missing API ${ check.api }` ),
	...checks.accessibility.filter( ( check ) => ! check.pass ).map( ( check ) => `accessibility failed: ${ check.label }` ),
	...checks.asyncRaces.filter( ( check ) => ! check.pass ).map( ( check ) => `async race failed: ${ check.label }` ),
	...checks.cleanup.filter( ( check ) => ! check.pass ).map( ( check ) => `cleanup failed: ${ check.label }` ),
	...checks.banned.filter( ( check ) => ! check.pass ).map( ( check ) => `banned pattern: ${ check.label }` ),
	...execution.errors.map( ( error ) => `execution error: ${ error }` )
];

const report = {
	format: 'floppy-desktop-mode-executable-audit-v2',
	source: sourcePath,
	generated_at: new Date().toISOString(),
	status: failures.length ? 'fail' : 'pass',
	checks,
	execution: {
		commands: execution.commands.length,
		settings_tabs: execution.settingsTabs.length,
		title_bar_buttons: execution.titleBarButtons.length,
		file_openers: execution.fileOpeners.length,
		drop_targets: execution.dropTargets.length,
		hook_registrations: execution.hookRegistrations.length,
		removed_actions: execution.removedActions,
		removed_filters: execution.removedFilters,
		drop_deregistered: execution.dropDeregistered,
		added_dom_listeners: execution.addedDomListeners,
		removed_dom_listeners: execution.removedDomListeners,
		cleanup_idempotent: execution.cleanupIdempotent
	},
	failures
};

if ( format === 'json' ) {
	console.log( JSON.stringify( report, null, 2 ) );
} else if ( failures.length ) {
	console.error( 'Desktop Mode executable audit failed:' );
	for ( const failure of failures ) {
		console.error( `- ${ failure }` );
	}
} else {
	console.log( 'Desktop Mode executable audit passed.' );
}

if ( failures.length ) {
	process.exitCode = 1;
}

function executeDesktopModeScript( script ) {
	const commands = [];
	const settingsTabs = [];
	const titleBarButtons = [];
	const fileOpeners = [];
	const dropTargets = [];
	const broadcasts = [];
	const iconBadges = [];
	const dockBadges = [];
	const taskbarBadges = [];
	const hookRegistrations = [];
	const errors = [];
	let removedActions = 0;
	let removedFilters = 0;
	let dropDeregistered = 0;
	let addedDomListeners = 0;
	let removedDomListeners = 0;
	let cleanupIdempotent = false;
	let windowCleanup = null;
	const eventStats = {
		added: () => {
			addedDomListeners += 1;
		},
		removed: () => {
			removedDomListeners += 1;
		}
	};

	const hooks = {
		addAction( name, namespace ) {
			hookRegistrations.push( { type: 'action', key: hookKeyForName( name ), name, namespace } );
		},
		addFilter( name, namespace ) {
			hookRegistrations.push( { type: 'filter', key: hookKeyForName( name ), name, namespace } );
		},
		removeAction() {
			removedActions += 1;
		},
		removeFilter() {
			removedFilters += 1;
		},
		applyFilters( _name, value ) {
			return value;
		}
	};

	const desktop = {
		HOOKS: hookNames,
		ready( callback ) {
			callback();
		},
		registerCommand( command ) {
			commands.push( command );
		},
		registerSettingsTab( tab ) {
			settingsTabs.push( tab );
		},
		registerTitleBarButton( button ) {
			titleBarButtons.push( button );
		},
		files: {
			registerOpener( opener ) {
				fileOpeners.push( opener );
			}
		},
		getOsSettings() {
			return { itemVisibility: { 'floppy-drive': 'both' } };
		},
		updateOsSettings() {
			return Promise.resolve();
		},
		subscribeOsSettings() {
			return () => {};
		},
		refreshMenu() {},
		openWindow() {},
		openOsSettings() {},
		broadcast( topic, payload ) {
			broadcasts.push( { topic, payload } );
		},
		subscribe() {
			return () => {};
		},
		notify() {},
		fetch() {
			return Promise.resolve( {
				ok: true,
				json: () => Promise.resolve( { items: [], devices: [], checks: {}, ok: true } )
			} );
		},
		icons: { setBadge: ( id, count ) => iconBadges.push( { id, count } ) },
		dock: { setBadge: ( id, count ) => dockBadges.push( { id, count } ) },
		taskbar: { setBadge: ( id, count ) => taskbarBadges.push( { id, count } ) },
		dragManager: {
			registerDropTarget( target ) {
				dropTargets.push( target );
				return () => {
					dropDeregistered += 1;
				};
			}
		}
	};

	const context = {
		window: {
			floppyDesktopConfig: {
				windowId: 'floppy-drive',
				restUrl: 'https://example.test/wp-json/floppy/v1/',
				nonce: 'test',
				maxFileSize: 1024 * 1024,
				desktopMode: true,
				capabilities: { upload: true, admin: true }
			},
			wp: {
				desktop,
				hooks,
				i18n: { __: ( value ) => value },
				apiFetch: () => Promise.resolve( { items: [], devices: [], checks: {}, ok: true } )
			},
			console,
			setTimeout: ( callback ) => {
				if ( typeof callback === 'function' ) {
					callback();
				}
			},
			FormData: class {},
			Blob,
			URL
		},
		document: makeDocument( eventStats ),
		wp: null,
		console,
		Blob,
		URL,
		FormData: class {}
	};
	context.wp = context.window.wp;
	context.window.window = context.window;
	context.window.document = context.document;

	try {
		vm.runInNewContext( script, context, { filename: sourcePath, timeout: 5000 } );
		const callback = context.window.desktopModeNativeWindows?.[ 'floppy-drive' ];
		if ( typeof callback !== 'function' ) {
			errors.push( 'native window callback was not registered' );
		} else {
			const container = makeElement( 'container', eventStats );
			windowCleanup = callback( container, {
				window: {
					markLoading() {},
					markReady() {}
				}
			} );
			if ( typeof windowCleanup === 'function' ) {
				windowCleanup();
				const afterFirstCleanup = {
					removedActions,
					removedFilters,
					dropDeregistered,
					removedDomListeners
				};
				windowCleanup();
				cleanupIdempotent = removedActions === afterFirstCleanup.removedActions &&
					removedFilters === afterFirstCleanup.removedFilters &&
					dropDeregistered === afterFirstCleanup.dropDeregistered &&
					removedDomListeners === afterFirstCleanup.removedDomListeners;
			}
		}
	} catch ( error ) {
		errors.push( error && error.stack ? error.stack : String( error ) );
	}

	return {
		commands,
		settingsTabs,
		titleBarButtons,
		fileOpeners,
		dropTargets,
		broadcasts,
		iconBadges,
		dockBadges,
		taskbarBadges,
		hookRegistrations,
		removedActions,
		removedFilters,
		dropDeregistered,
		addedDomListeners,
		removedDomListeners,
		cleanupIdempotent,
		windowCleanup,
		errors
	};
}

function makeDocument( eventStats = null ) {
	return {
		readyState: 'complete',
		body: makeElement( 'body', eventStats ),
		addEventListener() {
			if ( eventStats ) {
				eventStats.added();
			}
		},
		removeEventListener() {
			if ( eventStats ) {
				eventStats.removed();
			}
		},
		createElement: ( name ) => makeElement( name, eventStats ),
		querySelector() {
			return null;
		},
		querySelectorAll() {
			return [];
		}
	};
}

function makeElement( name = 'element', eventStats = null ) {
	const children = new Map();
	const classNames = new Set();
	const element = {
		name,
		isConnected: true,
		attributes: {},
		style: {},
		files: [],
		value: '',
		disabled: false,
		classList: {
			add: ( ...values ) => values.forEach( ( value ) => classNames.add( value ) ),
			remove: ( ...values ) => values.forEach( ( value ) => classNames.delete( value ) ),
			toggle: ( value, force ) => {
				if ( force === false ) {
					classNames.delete( value );
					return false;
				}
				classNames.add( value );
				return true;
			},
			contains: ( value ) => classNames.has( value )
		},
		setAttribute( key, value ) {
			element.attributes[ key ] = String( value );
		},
		removeAttribute( key ) {
			delete element.attributes[ key ];
		},
		getAttribute( key ) {
			return element.attributes[ key ] || '';
		},
		appendChild() {},
		remove() {
			element.isConnected = false;
		},
		addEventListener() {
			if ( eventStats ) {
				eventStats.added();
			}
		},
		removeEventListener() {
			if ( eventStats ) {
				eventStats.removed();
			}
		},
		focus() {},
		click() {},
		matches() {
			return false;
		},
		closest() {
			return null;
		},
		querySelector( selector ) {
			if ( ! children.has( selector ) ) {
				children.set( selector, makeElement( selector, eventStats ) );
			}
			return children.get( selector );
		},
		querySelectorAll() {
			return [];
		},
		insertAdjacentHTML() {}
	};
	Object.defineProperty( element, 'innerHTML', {
		get() {
			return element._innerHTML || '';
		},
		set( value ) {
			element._innerHTML = String( value );
		}
	} );
	Object.defineProperty( element, 'textContent', {
		get() {
			return element._textContent || '';
		},
		set( value ) {
			element._textContent = String( value );
		}
	} );
	return element;
}

function hookKeyForName( name ) {
	return Object.keys( hookNames ).find( ( key ) => hookNames[ key ] === name ) || name;
}

function parseArgs( values ) {
	const parsed = {};
	for ( const value of values ) {
		if ( ! value.startsWith( '--' ) ) {
			continue;
		}
		const [ key, raw = '1' ] = value.slice( 2 ).split( '=' );
		parsed[ key ] = raw;
	}
	return parsed;
}
