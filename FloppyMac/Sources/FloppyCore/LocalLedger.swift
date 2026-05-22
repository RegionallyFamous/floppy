import Foundation

public struct FloppyLedgerSnapshot: Codable, Equatable, Sendable {
    public var accounts: [FloppyAccount]
    public var itemsByAccount: [String: [String: FloppyItem]]
    public var pendingOperations: [FloppyPendingOperation]
    public var conflicts: [FloppyConflict]

    public init(accounts: [FloppyAccount] = [], itemsByAccount: [String: [String: FloppyItem]] = [:], pendingOperations: [FloppyPendingOperation] = [], conflicts: [FloppyConflict] = []) {
        self.accounts = accounts
        self.itemsByAccount = itemsByAccount
        self.pendingOperations = pendingOperations
        self.conflicts = conflicts
    }
}

public struct FloppyPendingOperation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let accountID: String
    public let operation: String
    public let createdAt: Date

    public init(id: UUID = UUID(), accountID: String, operation: String, createdAt: Date = Date()) {
        self.id = id
        self.accountID = accountID
        self.operation = operation
        self.createdAt = createdAt
    }
}

public struct FloppyConflict: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let accountID: String
    public let itemUUID: String
    public let message: String
    public let createdAt: Date

    public init(id: UUID = UUID(), accountID: String, itemUUID: String, message: String, createdAt: Date = Date()) {
        self.id = id
        self.accountID = accountID
        self.itemUUID = itemUUID
        self.message = message
        self.createdAt = createdAt
    }
}

public actor LocalLedger {
    public let fileURL: URL
    private var snapshot: FloppyLedgerSnapshot

    public init(fileURL: URL = LocalLedger.defaultLedgerURL()) {
        self.fileURL = fileURL
        self.snapshot = (try? Self.load(from: fileURL)) ?? FloppyLedgerSnapshot()
    }

    public init(appGroupIdentifier: String, domainIdentifier: String) {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fileURL = base
            .appendingPathComponent("FloppyMac", isDirectory: true)
            .appendingPathComponent(domainIdentifier.safePathComponent + "-ledger.json")
        self.snapshot = (try? Self.load(from: fileURL)) ?? FloppyLedgerSnapshot()
    }

    public static func defaultLedgerURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FloppyMac", isDirectory: true).appendingPathComponent("ledger.json")
    }

    public func accounts() -> [FloppyAccount] {
        snapshot.accounts
    }

    public func upsert(account: FloppyAccount) throws {
        if let index = snapshot.accounts.firstIndex(where: { $0.id == account.id }) {
            snapshot.accounts[index] = account
        } else {
            snapshot.accounts.append(account)
        }
        try save()
    }

    public func close() {}

    public func removeAccount(id: String) throws {
        snapshot.accounts.removeAll { $0.id == id }
        snapshot.itemsByAccount.removeValue(forKey: id)
        snapshot.pendingOperations.removeAll { $0.accountID == id }
        snapshot.conflicts.removeAll { $0.accountID == id }
        try save()
    }

    public func items(accountID: String) -> [FloppyItem] {
        Array(snapshot.itemsByAccount[accountID, default: [:]].values)
    }

    public func merge(items: [FloppyItem], accountID: String) throws {
        var existing = snapshot.itemsByAccount[accountID, default: [:]]
        for item in items {
            existing[item.uuid] = item
        }
        snapshot.itemsByAccount[accountID] = existing
        try save()
    }

    public func upsert(item: FloppyItem, accountID: String? = nil) throws {
        let accountID = accountID ?? snapshot.accounts.first?.id ?? "default"
        var existing = snapshot.itemsByAccount[accountID, default: [:]]
        existing[item.uuid] = item
        snapshot.itemsByAccount[accountID] = existing
        try save()
    }

    public func upsert(items: [FloppyItem], accountID: String? = nil) throws {
        let accountID = accountID ?? snapshot.accounts.first?.id ?? "default"
        var existing = snapshot.itemsByAccount[accountID, default: [:]]
        for item in items {
            existing[item.uuid] = item
        }
        snapshot.itemsByAccount[accountID] = existing
        try save()
    }

    public func item(uuid: String, accountID: String? = nil) -> FloppyItem? {
        if let accountID {
            return snapshot.itemsByAccount[accountID]?[uuid]
        }
        for items in snapshot.itemsByAccount.values {
            if let item = items[uuid] {
                return item
            }
        }
        return nil
    }

    public func item(id: Int64, accountID: String? = nil) -> FloppyItem? {
        if let accountID {
            return snapshot.itemsByAccount[accountID]?.values.first { $0.id == id }
        }
        for items in snapshot.itemsByAccount.values {
            if let item = items.values.first(where: { $0.id == id }) {
                return item
            }
        }
        return nil
    }

    public func removeItem(uuid: String, accountID: String? = nil) throws {
        if let accountID {
            snapshot.itemsByAccount[accountID]?.removeValue(forKey: uuid)
        } else {
            for key in snapshot.itemsByAccount.keys {
                snapshot.itemsByAccount[key]?.removeValue(forKey: uuid)
            }
        }
        try save()
    }

    public func markMaterialized(item: FloppyItem, localURL: URL) throws {
        try upsert(item: item)
    }

    public func recordActiveEnumerator(_ identifier: String) {}

    public func removeActiveEnumerator(_ identifier: String) {}

    public func currentSyncAnchor() -> String? {
        snapshot.accounts.first.map { String($0.lastCursor) }
    }

    public func apply(changes: [FloppyChange], accountID: String? = nil) throws {
        let accountID = accountID ?? snapshot.accounts.first?.id ?? "default"
        var existing = snapshot.itemsByAccount[accountID, default: [:]]
        for change in changes {
            if let itemValue = change.payload["item"], case .object(let object) = itemValue,
               let data = try? JSONEncoder.floppy.encode(object),
               let item = try? JSONDecoder.floppy.decode(FloppyItem.self, from: data) {
                existing[item.uuid] = item
            }
            if change.eventType.contains("deleted"),
               case .string(let uuid)? = change.payload["uuid"] {
                existing.removeValue(forKey: uuid)
            }
        }
        snapshot.itemsByAccount[accountID] = existing
        if let last = changes.last, let index = snapshot.accounts.firstIndex(where: { $0.id == accountID }) {
            snapshot.accounts[index].lastCursor = last.sequence
            snapshot.accounts[index].lastSyncAt = Date()
        }
        try save()
    }

    public func record(changeFeed: FloppyChangeFeed, accountID: String) throws {
        guard let index = snapshot.accounts.firstIndex(where: { $0.id == accountID }) else {
            return
        }
        snapshot.accounts[index].lastCursor = changeFeed.nextCursor
        snapshot.accounts[index].lastSyncAt = Date()
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.floppy.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func load(from url: URL) throws -> FloppyLedgerSnapshot {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.floppy.decode(FloppyLedgerSnapshot.self, from: data)
    }
}

private extension String {
    var safePathComponent: String {
        replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "-", options: .regularExpression)
    }
}
