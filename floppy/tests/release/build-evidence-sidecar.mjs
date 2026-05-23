#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

const here = dirname( fileURLToPath( import.meta.url ) );
const repo = resolve( here, '../../..' );
const args = parseArgs( process.argv.slice( 2 ) );
const output = resolve( repo, args.output || 'dist/floppy-release-evidence.json' );
const loadReport = artifact( 'load_report', args[ 'load-report' ] );
const hookAudit = artifact( 'desktop_mode_hook_audit', args[ 'hook-audit' ] );
const syncTorture = artifact( 'sync_torture_report', args[ 'sync-torture' ] );
const privateProbe = artifact( 'private_storage_probe', args[ 'private-probe' ] );
const exportRestore = artifact( 'export_restore_drill', args[ 'export-restore' ] );
const macDiagnostics = artifact( 'mac_diagnostics', args[ 'mac-diagnostics' ] );
const wpDebugBundle = artifact( 'wordpress_debug_bundle', args[ 'wp-debug-bundle' ] );
const signing = artifact( 'signing_notarization', args.signing );

const evidence = {
	format: 'floppy-release-evidence-sidecar-v1',
	generated_at: new Date().toISOString(),
	repository: {
		commit: git( [ 'rev-parse', 'HEAD' ] ),
		branch: git( [ 'rev-parse', '--abbrev-ref', 'HEAD' ] )
	},
	artifacts: [
		loadReport,
		hookAudit,
		syncTorture,
		privateProbe,
		exportRestore,
		macDiagnostics,
		wpDebugBundle,
		signing
	],
	gates: buildGates( loadReport, hookAudit ),
	manual_release_requirements: [
		'100k load-budget report before beta tagging',
		'1M metadata stress report before public beta announcement',
		'sync torture notes from a live WordPress site',
		'private-storage probe matrix for the target host',
		'export/restore drill with checksum verification',
		'matching WordPress and Mac support correlation IDs',
		'signing/notarization proof before distributing the Mac app'
	]
};

mkdirSync( dirname( output ), { recursive: true } );
writeFileSync( output, `${ JSON.stringify( evidence, null, 2 ) }\n` );
console.log( output );

if ( evidence.gates.some( ( gate ) => gate.status === 'fail' ) ) {
	process.exitCode = 1;
}

function artifact( name, relativePath ) {
	if ( ! relativePath ) {
		return {
			name,
			status: 'missing',
			required_for_public_beta: name !== 'signing_notarization'
		};
	}
	const path = resolve( repo, relativePath );
	if ( ! existsSync( path ) ) {
		return {
			name,
			path: relativePath,
			status: 'missing',
			required_for_public_beta: true
		};
	}
	const bytes = readFileSync( path );
	return {
		name,
		path: relativePath,
		status: 'present',
		bytes: statSync( path ).size,
		sha256: createHash( 'sha256' ).update( bytes ).digest( 'hex' ),
		summary: jsonSummary( bytes )
	};
}

function jsonSummary( bytes ) {
	try {
		const parsed = JSON.parse( bytes.toString( 'utf8' ) );
		return {
			format: parsed.format || parsed.harness || '',
			scenario: parsed.scenario || '',
			status: parsed.status || ( Array.isArray( parsed.failures ) && parsed.failures.length ? 'fail' : 'pass' ),
			failures: Array.isArray( parsed.failures ) ? parsed.failures.length : 0
		};
	} catch ( error ) {
		return {
			format: 'text',
			status: 'unparsed'
		};
	}
}

function buildGates( load, audit ) {
	return [
		{
			name: '10k_load_budget',
			status: load.status === 'present' && load.summary.failures === 0 ? 'pass' : 'fail',
			message: load.status === 'present' ? '10k load report attached.' : '10k load report missing.'
		},
		{
			name: 'desktop_mode_hook_audit',
			status: audit.status === 'present' && audit.summary.status === 'pass' ? 'pass' : 'fail',
			message: audit.status === 'present' ? 'Desktop Mode hook audit attached.' : 'Desktop Mode hook audit missing.'
		},
		{
			name: 'manual_beta_evidence',
			status: 'warn',
			message: 'Attach 100k, 1M, sync torture, private probe, export/restore, diagnostics, and signing evidence before public beta.'
		}
	];
}

function git( params ) {
	try {
		return execFileSync( 'git', params, { cwd: repo, encoding: 'utf8' } ).trim();
	} catch ( error ) {
		return '';
	}
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
