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
                    let parentID = containerItemIdentifier == .rootContainer ? 0 : (containerItemIdentifier.floppyItemID ?? 0)
                    let afterID = Int64(page.floppyToken ?? "0") ?? 0
                    let response = try await apiClient.listFiles(parentID: parentID, afterID: afterID, limit: 100)
                    try await ledger.upsert(items: response.items)
                    observer.didEnumerate(response.items.map(FloppyFileProviderItem.init(item:)))
                    observer.finishEnumerating(upTo: response.items.count == response.limit ? response.items.last.map { NSFileProviderPage(floppyToken: String($0.id)) } : nil)

                case .workingSet:
                    let cursor = UInt64(page.floppyToken ?? "0") ?? 0
                    let response = try await apiClient.syncChanges(cursor: cursor, limit: 250)
                    let items = response.events.compactMap(\.floppyItem)
                    try await ledger.upsert(items: items)
                    observer.didEnumerate(items.map(FloppyFileProviderItem.init(item:)))
                    observer.finishEnumerating(upTo: response.hasMore ? NSFileProviderPage(floppyToken: String(response.nextCursor)) : nil)
                }
            } catch {
                observer.finishEnumeratingWithError(error.asFileProviderError)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        Task {
            do {
                let cursor = UInt64(syncAnchor.floppyToken ?? "0") ?? 0
                let response = try await apiClient.syncChanges(cursor: cursor, limit: 500)
                try await ledger.apply(changes: response.events)

                let updatedItems = response.events.compactMap(\.floppyItem).map(FloppyFileProviderItem.init(item:))
                let deletedIdentifiers = response.events
                    .filter { $0.eventType.contains("deleted") || $0.eventType.contains("trashed") }
                    .map { NSFileProviderItemIdentifier("floppy:item:\($0.targetID)") }

                observer.didUpdate(updatedItems)
                observer.didDeleteItems(withIdentifiers: deletedIdentifiers)
                observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(floppyToken: String(response.nextCursor)), moreComing: response.hasMore)
            } catch {
                observer.finishEnumeratingWithError(error.asFileProviderError)
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
}

private extension FloppyChange {
    var floppyItem: FloppyItem? {
        guard !eventType.contains("deleted"), !eventType.contains("trashed") else {
            return nil
        }

        let encoded = try? JSONEncoder.floppy.encode(payload)
        return encoded.flatMap { try? JSONDecoder.floppy.decode(FloppyItem.self, from: $0) }
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

private extension Error {
    var asFileProviderError: Error {
        if let fileProviderError = self as? NSFileProviderError {
            return fileProviderError
        }

        if let apiError = self as? FloppyAPIError {
            switch apiError {
            case .missingToken:
                return NSFileProviderError(.notAuthenticated)
            case .httpStatus(let status, _):
                if status == 404 {
                    return NSFileProviderError(.noSuchItem)
                }
                if status == 409 {
                    return NSFileProviderError(.cannotSynchronize)
                }
                if status == 410 {
                    return NSFileProviderError(.syncAnchorExpired)
                }
                if status >= 500 {
                    return NSFileProviderError(.serverUnreachable)
                }
                return NSFileProviderError(.cannotSynchronize)
            default:
                return NSFileProviderError(.cannotSynchronize)
            }
        }

        return self
    }
}
