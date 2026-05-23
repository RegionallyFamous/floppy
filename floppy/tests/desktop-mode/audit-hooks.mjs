#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname( fileURLToPath( import.meta.url ) );
const repo = resolve( here, '../../..' );
const args = parseArgs( process.argv.slice( 2 ) );
const sourcePath = resolve( repo, args.source || 'floppy/assets/js/desktop-mode.js' );
const format = args.format || 'text';
const source = readFileSync( sourcePath, 'utf8' );

const requiredHooks = [
	'WINDOW_FOCUSED',
	'NATIVE_WINDOW_AFTER_RENDER',
	'NATIVE_WINDOW_BEFORE_CLOSE',
	'FILE_DROP_FILES_DETECTED',
	'FILE_DROP_BEFORE_UPLOAD',
	'FILE_DROP_UPLOAD_STARTED',
	'FILE_DROP_UPLOAD_PROGRESS',
	'FILE_DROP_AFTER_UPLOAD',
	'FILE_DROP_UPLOAD_FAILED',
	'DOCK_TILE_CLASS',
	'DOCK_TILE_ELEMENT',
	'DOCK_TILE_RENDERED',
	'DOCK_TILE_TOOLTIP',
	'DESKTOP_ICON_CLICKED',
	'DESKTOP_ICONS_RENDERED',
	'DESKTOP_ICON_MENU_ITEMS'
];

const requiredApis = [
	'desktop.HOOKS',
	'hooks.addAction',
	'hooks.addFilter',
	'desktop.registerCommand',
	'desktop.registerSettingsTab',
	'desktop.registerTitleBarButton',
	'desktop.files.registerOpener',
	'desktop.getOsSettings',
	'desktop.updateOsSettings',
	'desktop.subscribeOsSettings',
	'desktop.refreshMenu',
	'desktop.openWindow',
	'desktop.broadcast',
	'desktop.icons.setBadge',
	'desktop.dock.setBadge',
	'desktop.taskbar.setBadge'
];

const requiredPanels = [
	'files',
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

const checks = {
	hooks: requiredHooks.map( ( key ) => ( {
		key,
		pass: source.includes( `'${ key }'` ) || source.includes( `"${ key }"` )
	} ) ),
	apis: requiredApis.map( ( api ) => ( {
		api,
		pass: source.includes( api )
	} ) ),
	panels: requiredPanels.map( ( panel ) => ( {
		panel,
		pass: source.includes( `${ panel }:` ) || source.includes( `'${ panel }'` ) || source.includes( `"${ panel }"` )
	} ) ),
	banned: bannedPatterns.map( ( entry ) => ( {
		label: entry.label,
		pass: ! entry.pattern.test( source )
	} ) )
};

const failures = [
	...checks.hooks.filter( ( check ) => ! check.pass ).map( ( check ) => `missing hook ${ check.key }` ),
	...checks.apis.filter( ( check ) => ! check.pass ).map( ( check ) => `missing API ${ check.api }` ),
	...checks.panels.filter( ( check ) => ! check.pass ).map( ( check ) => `missing panel ${ check.panel }` ),
	...checks.banned.filter( ( check ) => ! check.pass ).map( ( check ) => `banned pattern: ${ check.label }` )
];

const report = {
	format: 'floppy-desktop-mode-hook-audit-v1',
	source: sourcePath,
	generated_at: new Date().toISOString(),
	status: failures.length ? 'fail' : 'pass',
	checks,
	failures
};

if ( format === 'json' ) {
	console.log( JSON.stringify( report, null, 2 ) );
} else if ( failures.length ) {
	console.error( 'Desktop Mode hook audit failed:' );
	for ( const failure of failures ) {
		console.error( `- ${ failure }` );
	}
} else {
	console.log( 'Desktop Mode hook audit passed.' );
}

if ( failures.length ) {
	process.exitCode = 1;
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
