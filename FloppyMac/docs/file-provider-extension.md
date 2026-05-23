# Floppy File Provider Extension Scaffold

This scaffold adds the macOS replicated File Provider extension surface for Floppy. It intentionally delegates authentication, REST transport, item decoding, sync anchors, and the shared SQLite ledger to `FloppyCore`, which is expected to provide `FloppyAPIClient`, `FloppyItem`, `FloppyChange`, `LocalLedger`, and `TokenStore`.

## Files

- `FloppyMac/Sources/FloppyFileProvider/FloppyFileProviderExtension.swift`: extension principal adopting `NSFileProviderReplicatedExtension` and `NSFileProviderEnumerating`.
- `FloppyMac/Sources/FloppyFileProvider/FloppyFileProviderEnumerator.swift`: folder and working-set enumerators backed by Floppy REST cursors and sync anchors.
- `FloppyMac/Sources/FloppyFileProvider/FloppyItemAdapter.swift`: adapter from `FloppyItem` to `NSFileProviderItem` using stable UUID-backed item identifiers.
- `FloppyMac/Sources/FloppyFileProvider/FloppyFileProviderConfiguration.swift`: shared App Group, Keychain group, API client, and ledger construction.
- `FloppyMac/Extension/Info.plist`: extension metadata and principal class declaration.
- `FloppyMac/Packaging/FloppyMac.entitlements`: Developer ID containing-app entitlements. The menu app is intentionally not sandboxed so it can reveal the user-visible CloudStorage folder in Finder.
- `FloppyMac/Extension/FloppyFileProvider.entitlements`: sandbox, App Group, and Keychain sharing for the File Provider helper.

## Xcode Target Wiring

1. Add a new macOS File Provider extension target to the Floppy Xcode project.
2. Set the extension target bundle identifier, for example `com.floppy.mac.FileProvider`.
3. Add the Swift files under `FloppyMac/Sources/FloppyFileProvider/` to the extension target membership.
4. Set the extension target `Info.plist` to `FloppyMac/Extension/Info.plist`.
5. Set the extension target entitlements file to `FloppyMac/Extension/FloppyFileProvider.entitlements`.
6. Link the extension target against `FileProvider.framework`, `UniformTypeIdentifiers.framework`, and the `FloppyCore` module.
7. Keep the app and extension identifiers aligned:
   - App Group: `$(TeamIdentifierPrefix)com.floppy.mac.sync`
   - Keychain group: `$(AppIdentifierPrefix)com.floppy.mac`
   - Extension bundle ID: `com.floppy.mac.FileProvider`
8. Add the same App Group and Keychain access group to the containing macOS app target.
9. In the app target, register one `NSFileProviderDomain` per connected WordPress site/account after `TokenStore` and `LocalLedger` are initialized for that account.
10. Keep the File Provider extension sandboxed. Keep the containing Developer ID app unsandboxed unless a future Finder-opening path uses security-scoped folder access; a sandboxed menu app cannot reliably reveal its own CloudStorage domain.

## Expected FloppyCore Surface

The extension assumes `FloppyCore` will provide these production APIs or equivalent compatibility shims:

- `TokenStore(accessGroup:)` for reading device tokens from the shared Keychain access group.
- `LocalLedger(appGroupIdentifier:domainIdentifier:)` for App Group SQLite metadata, JSON ledger migration, materialization state, active enumerators, sync anchors, and pending operations.
- `FloppyAPIClient(domainIdentifier:tokenStore:)` for authenticated Floppy REST calls.
- `FloppyItem` with stable `uuid`, optional `parentUUID`, name, content type, size, dates, capability flags, `etag`, `contentVersion`, and `metadataVersion`.
- `FloppyChange` with optional updated `FloppyItem`, deletion state, and deleted item UUID.

The method names used in the scaffold are deliberately direct:

- `rootItem()`
- `item(uuid:)`
- `enumerateFolder(parentID:pageToken:)`
- `enumerateWorkingSet(pageToken:)`
- `enumerateChanges(since:)`
- `downloadItem(uuid:version:progress:)`
- `createItem(parentUUID:filename:typeIdentifier:contents:idempotencyKey:progress:)`
- `modifyItem(uuid:parentUUID:filename:typeIdentifier:changedFields:baseVersion:contents:progress:)`
- `deleteItem(uuid:baseVersion:shouldTrash:)`

If `FloppyCore` lands with different names, keep the File Provider target thin by adding adapters in `FloppyCore` or in a small compatibility file under `FloppyMac/Sources/FloppyFileProvider/`.

## Domain Registration

The containing app owns account sign-in and domain lifecycle. After a user authorizes a WordPress site, the app should:

1. Validate HTTPS and Floppy REST discovery.
2. Register or rotate the macOS device token through Floppy REST.
3. Store the token in `TokenStore`.
4. Create the account row in `LocalLedger`.
5. Add an `NSFileProviderDomain` whose identifier remains stable for the approved device UUID through `FloppyDomainRegistry`.

The extension does not create or remove domains by itself.

## Production Notes

- Add `com.apple.developer.fileprovider.testing-mode` only to a local debug entitlement override if the team needs development-only File Provider reset tooling.
- The containing app must be the signed Xcode app bundle with the extension embedded under `Contents/PlugIns/`. The SwiftPM test app does not include an extension, and macOS will surface that as a helper communication failure if the app tries to open the native folder.
- Keep File Provider item identifiers stable and filename-free: `floppy:item:{uuid}`. Legacy numeric identifiers are accepted only so existing local state can resolve during migration.
- Treat `NSFileProviderPage` and `NSFileProviderSyncAnchor` values as opaque UTF-8 tokens produced by the server.
- Map expired server anchors to `NSFileProviderError.Code.syncAnchorExpired` so macOS can reimport.
- Do not log tokens, Authorization headers, full local paths, or file contents from this target.
- The current implementation logs recoverable API and ledger failures through `FloppyDiagnostics`; the containing app should surface reauth or repair UI when a domain cannot load its account record or token.
