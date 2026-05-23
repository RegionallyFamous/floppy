import FileProvider
import Foundation
import FloppyCore

final class FloppyFileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private enum Scope {
        case folder(NSFileProviderItemIdentifier)
        case workingSet
    }

    private let scope: Scope
    private let apiClient: FloppyAPIClient
    private let ledger: LocalLedger

    init(containerItemIdentifier: NSFileProviderItemIdentifier, apiClient: FloppyAPIClient, ledger: LocalLedger) {
        self.scope = .folder(containerItemIdentifier)
        self.apiClient = apiClient
        self.ledger = ledger
    }

    init(workingSetWith apiClient: FloppyAPIClient, ledger: LocalLedger) {
        self.scope = .workingSet
        self.apiClient = apiClient
        self.ledger = ledger
    }

    func invalidate() {
        Task {
            await ledger.removeActiveEnumerator(identifier)
        }
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        Task {
            do {
                switch scope {
                case .folder(let containerItemIdentifier):
                    let parentID = try await resolveParentID(containerItemIdentifier)
                    let cursor = page.floppyToken ?? ""
                    let response = try await apiClient.listFiles(parentID: parentID, cursor: cursor, limit: 100)
                    try await ledger.upsert(items: response.items)
                    observer.didEnumerate(await fileProviderItems(for: response.items))
                    observer.finishEnumerating(upTo: response.hasMore == true ? response.nextCursor.map(NSFileProviderPage.init(floppyToken:)) : nil)

                case .workingSet:
                    let cursor = UInt64(page.floppyToken ?? "0") ?? 0
                    let response = try await apiClient.syncChanges(cursor: cursor, limit: 250)
                    let items = response.events.compactMap(\.floppyItemPayload)
                    try await ledger.upsert(items: items)
                    observer.didEnumerate(await fileProviderItems(for: items))
                    observer.finishEnumerating(upTo: response.hasMore ? NSFileProviderPage(floppyToken: String(response.nextCursor)) : nil)
                }
            } catch {
                observer.finishEnumeratingWithError(FloppyFileProviderErrorMapper.fileProviderError(for: error))
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        Task {
            do {
                let cursor = UInt64(syncAnchor.floppyToken ?? "0") ?? 0
                let response = try await apiClient.syncChanges(cursor: cursor, limit: 500)
                try await ledger.apply(changes: response.events)
                try await ledger.record(changeFeed: response)

                let updatedItems = await fileProviderItems(for: response.events.compactMap(\.floppyItemPayload))
                let deletedIdentifiers = response.events
                    .filter(\.isDeletion)
                    .map { change -> NSFileProviderItemIdentifier in
                        if let uuid = change.deletedItemUUID {
                            return NSFileProviderItemIdentifier(FloppyFileProviderIdentifierCodec.itemIdentifierRawValue(uuid: uuid))
                        }
                        return NSFileProviderItemIdentifier(FloppyFileProviderIdentifierCodec.legacyItemIdentifierRawValue(id: change.targetID))
                    }

                observer.didUpdate(updatedItems)
                observer.didDeleteItems(withIdentifiers: deletedIdentifiers)
                observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(floppyToken: String(response.nextCursor)), moreComing: response.hasMore)
            } catch {
                observer.finishEnumeratingWithError(FloppyFileProviderErrorMapper.fileProviderError(for: error))
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        Task {
            completionHandler(await ledger.currentSyncAnchor().map(NSFileProviderSyncAnchor.init(floppyToken:)))
        }
    }

    private var identifier: String {
        switch scope {
        case .folder(let itemIdentifier):
            itemIdentifier.rawValue
        case .workingSet:
            NSFileProviderItemIdentifier.workingSet.rawValue
        }
    }

    private func resolveParentID(_ identifier: NSFileProviderItemIdentifier) async throws -> Int64 {
        if identifier == .rootContainer {
            return 0
        }
        if let uuid = identifier.floppyItemUUID, let parent = await ledger.item(uuid: uuid) {
            return parent.id
        }
        if let legacyID = identifier.floppyLegacyItemID {
            return legacyID
        }
        throw NSFileProviderError(.noSuchItem)
    }

    private func fileProviderItems(for items: [FloppyItem]) async -> [FloppyFileProviderItem] {
        var providerItems: [FloppyFileProviderItem] = []
        providerItems.reserveCapacity(items.count)
        for item in items {
            providerItems.append(FloppyFileProviderItem(item: item, parentItemIdentifier: await parentIdentifier(for: item)))
        }
        return providerItems
    }

    private func parentIdentifier(for item: FloppyItem) async -> NSFileProviderItemIdentifier {
        guard item.parentID != 0 else {
            return .rootContainer
        }

        if let parentUUID = item.parentUUID, !parentUUID.isEmpty {
            return NSFileProviderItemIdentifier(FloppyFileProviderIdentifierCodec.itemIdentifierRawValue(uuid: parentUUID))
        }

        if let parent = await ledger.item(id: item.parentID) {
            return parent.fileProviderIdentifier
        }

        return NSFileProviderItemIdentifier(FloppyFileProviderIdentifierCodec.legacyItemIdentifierRawValue(id: item.parentID))
    }
}

private extension NSFileProviderPage {
    init(floppyToken: String) {
        self.init(floppyToken.data(using: .utf8) ?? Data())
    }

    var floppyToken: String? {
        rawValue.isEmpty ? nil : String(data: rawValue, encoding: .utf8)
    }
}

private extension NSFileProviderSyncAnchor {
    init(floppyToken: String) {
        self.init(floppyToken.data(using: .utf8) ?? Data())
    }

    var floppyToken: String? {
        rawValue.isEmpty ? nil : String(data: rawValue, encoding: .utf8)
    }
}
