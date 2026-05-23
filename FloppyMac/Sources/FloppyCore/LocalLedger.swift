import Foundation
import SQLite3

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

public struct FloppyUploadTransferSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String { sessionUUID }

    public let accountID: String
    public let sessionUUID: String
    public let operation: String
    public let itemUUID: String?
    public let fileID: Int64?
    public let localPath: String
    public let totalSize: Int64
    public let offset: Int64
    public let chunkSize: Int
    public let expiresAtGMT: String
    public let idempotencyKey: String
    public let updatedAt: Date

    public init(
        accountID: String,
        sessionUUID: String,
        operation: String,
        itemUUID: String? = nil,
        fileID: Int64? = nil,
        localPath: String,
        totalSize: Int64,
        offset: Int64,
        chunkSize: Int = 8_388_608,
        expiresAtGMT: String = "",
        idempotencyKey: String,
        updatedAt: Date = Date()
    ) {
        self.accountID = accountID
        self.sessionUUID = sessionUUID
        self.operation = operation
        self.itemUUID = itemUUID
        self.fileID = fileID
        self.localPath = localPath
        self.totalSize = totalSize
        self.offset = offset
        self.chunkSize = chunkSize
        self.expiresAtGMT = expiresAtGMT
        self.idempotencyKey = idempotencyKey
        self.updatedAt = updatedAt
    }
}

public struct FloppyStoragePolicySummary: Codable, Equatable, Sendable {
    public let accountFingerprint: String
    public let onlineOnly: Int
    public let availableOffline: Int
    public let excluded: Int
    public let materializedBytes: Int64
    public let missingAvailableOffline: Int

    public init(
        accountFingerprint: String,
        onlineOnly: Int,
        availableOffline: Int,
        excluded: Int,
        materializedBytes: Int64,
        missingAvailableOffline: Int
    ) {
        self.accountFingerprint = accountFingerprint
        self.onlineOnly = onlineOnly
        self.availableOffline = availableOffline
        self.excluded = excluded
        self.materializedBytes = materializedBytes
        self.missingAvailableOffline = missingAvailableOffline
    }

    public static func empty(accountID: String? = nil) -> FloppyStoragePolicySummary {
        FloppyStoragePolicySummary(
            accountFingerprint: FloppyDiagnostics.redactedFingerprint(accountID),
            onlineOnly: 0,
            availableOffline: 0,
            excluded: 0,
            materializedBytes: 0,
            missingAvailableOffline: 0
        )
    }

    enum CodingKeys: String, CodingKey {
        case accountFingerprint = "account_fingerprint"
        case onlineOnly = "online_only"
        case availableOffline = "available_offline"
        case excluded
        case materializedBytes = "materialized_bytes"
        case missingAvailableOffline = "missing_available_offline"
    }
}

public struct FloppyConflict: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let accountID: String
    public let itemUUID: String
    public let message: String
    public let displayName: String?
    public let parentID: Int64?
    public let parentUUID: String?
    public let materializedPath: String?
    public let originalContentVersion: String?
    public let state: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        accountID: String,
        itemUUID: String,
        message: String,
        displayName: String? = nil,
        parentID: Int64? = nil,
        parentUUID: String? = nil,
        materializedPath: String? = nil,
        originalContentVersion: String? = nil,
        state: String? = "open",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountID = accountID
        self.itemUUID = itemUUID
        self.message = message
        self.displayName = displayName
        self.parentID = parentID
        self.parentUUID = parentUUID
        self.materializedPath = materializedPath
        self.originalContentVersion = originalContentVersion
        self.state = state
        self.createdAt = createdAt
    }
}

public struct FloppyConflictReasonCount: Codable, Equatable, Sendable {
    public let reason: String
    public let count: Int

    public init(reason: String, count: Int) {
        self.reason = reason
        self.count = count
    }
}

public struct FloppyLedgerConflictDiagnostics: Codable, Equatable, Sendable {
    public let accountFingerprint: String
    public let totalCount: Int
    public let openCount: Int
    public let resolvedCount: Int
    public let materializedOpenCount: Int
    public let missingMaterializedOpenCount: Int
    public let missingItemRecordCount: Int
    public let reasons: [FloppyConflictReasonCount]

    public init(
        accountFingerprint: String,
        totalCount: Int,
        openCount: Int,
        resolvedCount: Int,
        materializedOpenCount: Int,
        missingMaterializedOpenCount: Int,
        missingItemRecordCount: Int,
        reasons: [FloppyConflictReasonCount]
    ) {
        self.accountFingerprint = accountFingerprint
        self.totalCount = totalCount
        self.openCount = openCount
        self.resolvedCount = resolvedCount
        self.materializedOpenCount = materializedOpenCount
        self.missingMaterializedOpenCount = missingMaterializedOpenCount
        self.missingItemRecordCount = missingItemRecordCount
        self.reasons = reasons
    }

    public static func empty(accountID: String? = nil) -> FloppyLedgerConflictDiagnostics {
        FloppyLedgerConflictDiagnostics(
            accountFingerprint: FloppyDiagnostics.redactedFingerprint(accountID),
            totalCount: 0,
            openCount: 0,
            resolvedCount: 0,
            materializedOpenCount: 0,
            missingMaterializedOpenCount: 0,
            missingItemRecordCount: 0,
            reasons: []
        )
    }

    enum CodingKeys: String, CodingKey {
        case accountFingerprint = "account_fingerprint"
        case totalCount = "total_count"
        case openCount = "open_count"
        case resolvedCount = "resolved_count"
        case materializedOpenCount = "materialized_open_count"
        case missingMaterializedOpenCount = "missing_materialized_open_count"
        case missingItemRecordCount = "missing_item_record_count"
        case reasons
    }
}

public struct FloppyLedgerIntegrityIssue: Codable, Equatable, Sendable {
    public let code: String
    public let severity: String
    public let count: Int
    public let message: String

    public init(code: String, severity: String, count: Int, message: String) {
        self.code = code
        self.severity = severity
        self.count = count
        self.message = message
    }
}

public struct FloppyLedgerIntegrityCounts: Codable, Equatable, Sendable {
    public let accounts: Int
    public let items: Int
    public let pendingOperations: Int
    public let conflicts: Int
    public let materializedItems: Int
    public let missingMaterializedItems: Int
    public let activeEnumerators: Int

    public init(
        accounts: Int,
        items: Int,
        pendingOperations: Int,
        conflicts: Int,
        materializedItems: Int,
        missingMaterializedItems: Int,
        activeEnumerators: Int
    ) {
        self.accounts = accounts
        self.items = items
        self.pendingOperations = pendingOperations
        self.conflicts = conflicts
        self.materializedItems = materializedItems
        self.missingMaterializedItems = missingMaterializedItems
        self.activeEnumerators = activeEnumerators
    }

    enum CodingKeys: String, CodingKey {
        case accounts
        case items
        case pendingOperations = "pending_operations"
        case conflicts
        case materializedItems = "materialized_items"
        case missingMaterializedItems = "missing_materialized_items"
        case activeEnumerators = "active_enumerators"
    }
}

public struct FloppyLedgerIntegrityReport: Codable, Equatable, Sendable {
    public let accountFingerprint: String
    public let ok: Bool
    public let counts: FloppyLedgerIntegrityCounts
    public let issues: [FloppyLedgerIntegrityIssue]

    public init(
        accountFingerprint: String,
        ok: Bool,
        counts: FloppyLedgerIntegrityCounts,
        issues: [FloppyLedgerIntegrityIssue]
    ) {
        self.accountFingerprint = accountFingerprint
        self.ok = ok
        self.counts = counts
        self.issues = issues
    }

    public static func empty(accountID: String? = nil) -> FloppyLedgerIntegrityReport {
        FloppyLedgerIntegrityReport(
            accountFingerprint: FloppyDiagnostics.redactedFingerprint(accountID),
            ok: true,
            counts: FloppyLedgerIntegrityCounts(
                accounts: 0,
                items: 0,
                pendingOperations: 0,
                conflicts: 0,
                materializedItems: 0,
                missingMaterializedItems: 0,
                activeEnumerators: 0
            ),
            issues: []
        )
    }

    enum CodingKeys: String, CodingKey {
        case accountFingerprint = "account_fingerprint"
        case ok
        case counts
        case issues
    }
}

public enum LocalLedgerError: Error, LocalizedError {
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message):
            "SQLite ledger failed: \(message)"
        }
    }
}

public actor LocalLedger {
    public nonisolated let fileURL: URL
    private let store: SQLiteLedgerStore

    public init(fileURL: URL = LocalLedger.defaultLedgerURL()) {
        let databaseURL = fileURL.pathExtension == "json" ? fileURL.deletingPathExtension().appendingPathExtension("sqlite") : fileURL
        self.fileURL = databaseURL
        self.store = Self.makeStore(databaseURL: databaseURL, legacyJSONURL: Self.legacyJSONURL(for: databaseURL, explicitURL: fileURL))
    }

    public init(appGroupIdentifier: String, domainIdentifier: String) {
        let base = FloppyDomainRegistry.sharedContainerBaseURL(appGroupIdentifier: appGroupIdentifier)
        let directory = base.appendingPathComponent("FloppyMac", isDirectory: true)
        let name = domainIdentifier.safePathComponent + "-ledger"
        let databaseURL = directory.appendingPathComponent(name + ".sqlite")
        self.fileURL = databaseURL
        self.store = Self.makeStore(databaseURL: databaseURL, legacyJSONURL: directory.appendingPathComponent(name + ".json"))
    }

    public static func defaultLedgerURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FloppyMac", isDirectory: true).appendingPathComponent("ledger.sqlite")
    }

    public func accounts() -> [FloppyAccount] {
        do {
            return try store.accounts()
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading accounts: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func upsert(account: FloppyAccount) throws {
        try store.upsert(account: account)
    }

    public func close() {
        store.close()
    }

    public func removeAccount(id: String) throws {
        try store.removeAccount(id: id)
    }

    public func items(accountID: String) -> [FloppyItem] {
        do {
            return try store.items(accountID: accountID)
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading items: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func merge(items: [FloppyItem], accountID: String) throws {
        try store.transaction {
            for item in items {
                try store.upsert(item: item, accountID: accountID)
            }
        }
    }

    public func upsert(item: FloppyItem, accountID: String? = nil) throws {
        try store.upsert(item: item, accountID: try defaultAccountID(accountID))
    }

    public func upsert(items: [FloppyItem], accountID: String? = nil) throws {
        let resolvedAccountID = try defaultAccountID(accountID)
        try store.transaction {
            for item in items {
                try store.upsert(item: item, accountID: resolvedAccountID)
            }
        }
    }

    public func item(uuid: String, accountID: String? = nil) -> FloppyItem? {
        do {
            return try store.item(uuid: uuid, accountID: accountID)
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading item by uuid: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func item(id: Int64, accountID: String? = nil) -> FloppyItem? {
        do {
            return try store.item(id: id, accountID: accountID)
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading item by id: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func removeItem(uuid: String, accountID: String? = nil) throws {
        try store.removeItem(uuid: uuid, accountID: accountID)
    }

    public func markMaterialized(item: FloppyItem, localURL: URL) throws {
        try store.markMaterialized(item: item, accountID: try defaultAccountID(nil), localURL: localURL)
    }

    public func setStoragePolicy(itemUUID: String, policy: FloppyLocalStoragePolicy, accountID: String? = nil, removeMaterializedCopy: Bool = true) throws {
        try store.setStoragePolicy(
            uuid: itemUUID,
            accountID: try defaultAccountID(accountID),
            policy: policy,
            removeMaterializedCopy: removeMaterializedCopy
        )
    }

    public func storagePolicy(for itemUUID: String, accountID: String? = nil) -> FloppyLocalStoragePolicy {
        do {
            return try store.storagePolicy(uuid: itemUUID, accountID: try defaultAccountID(accountID))
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading storage policy: \(error.localizedDescription, privacy: .public)")
            return .onlineOnly
        }
    }

    public func storagePolicySummary(accountID: String? = nil) -> FloppyStoragePolicySummary {
        do {
            let resolvedAccountID = try defaultAccountID(accountID)
            return try store.storagePolicySummary(accountID: resolvedAccountID)
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading storage policy summary: \(error.localizedDescription, privacy: .public)")
            return .empty(accountID: accountID)
        }
    }

    public func materializedURL(for item: FloppyItem, accountID: String? = nil) -> URL? {
        do {
            return try store.materializedURL(uuid: item.uuid, accountID: try defaultAccountID(accountID))
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading materialized URL: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func conflictFileURL(uuid: String, filename: String) throws -> URL {
        let directory = fileURL.deletingLastPathComponent().appendingPathComponent("Conflicts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(uuid + "-" + filename.safePathComponent)
    }

    public func recordConflict(conflict: FloppyConflict, item: FloppyItem, localURL: URL, accountID: String? = nil) throws {
        let resolvedAccountID = try defaultAccountID(accountID)
        let resolvedConflict = FloppyConflict(
            id: conflict.id,
            accountID: resolvedAccountID,
            itemUUID: conflict.itemUUID,
            message: conflict.message,
            displayName: conflict.displayName,
            parentID: conflict.parentID,
            parentUUID: conflict.parentUUID,
            materializedPath: conflict.materializedPath,
            originalContentVersion: conflict.originalContentVersion,
            state: conflict.state,
            createdAt: conflict.createdAt
        )
        try store.transaction {
            try store.upsert(item: item, accountID: resolvedAccountID)
            try store.markMaterialized(item: item, accountID: resolvedAccountID, localURL: localURL)
            try store.insert(conflict: resolvedConflict)
        }
    }

    public func conflictCount(accountID: String? = nil) -> Int {
        do {
            return try store.conflictCount(accountID: try defaultAccountID(accountID))
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading conflict count: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    public func conflictDiagnostics(accountID: String? = nil) -> FloppyLedgerConflictDiagnostics {
        do {
            let resolvedAccountID = try defaultAccountID(accountID)
            return try store.conflictDiagnostics(accountID: resolvedAccountID)
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading conflict diagnostics: \(error.localizedDescription, privacy: .public)")
            return .empty(accountID: accountID)
        }
    }

    public func conflictCenterItems(accountID: String? = nil, limit: Int = 25) -> [FloppyConflictCenterItem] {
        do {
            let resolvedAccountID = try defaultAccountID(accountID)
            return try store.conflictCenterItems(accountID: resolvedAccountID, limit: limit)
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading conflict center items: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func markConflictResolved(id: UUID, accountID: String? = nil) throws {
        let resolvedAccountID = try defaultAccountID(accountID)
        try store.updateConflictState(id: id, accountID: resolvedAccountID, state: "resolved")
    }

    public func discardLocalConflictCopy(id: UUID, accountID: String? = nil) throws {
        let resolvedAccountID = try defaultAccountID(accountID)
        if let path = try store.conflictMaterializedPath(id: id, accountID: resolvedAccountID), !path.isEmpty {
            try? FileManager.default.removeItem(atPath: path)
        }
        try store.updateConflictState(id: id, accountID: resolvedAccountID, state: "resolved")
    }

    public func integrityReport(accountID: String? = nil) -> FloppyLedgerIntegrityReport {
        do {
            let resolvedAccountID = try defaultAccountID(accountID)
            return try store.integrityReport(accountID: resolvedAccountID)
        } catch {
            FloppyDiagnostics.ledger.error("Failed checking ledger integrity: \(error.localizedDescription, privacy: .public)")
            return .empty(accountID: accountID)
        }
    }

    public func pendingOperationCount(accountID: String? = nil) -> Int {
        do {
            return try store.pendingOperationCount(accountID: try defaultAccountID(accountID))
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading pending operation count: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    public func saveUploadTransferSession(_ session: FloppyUploadTransferSession) throws {
        try store.upsert(uploadTransferSession: session)
    }

    public func updateUploadTransferSession(sessionUUID: String, offset: Int64, accountID: String? = nil) throws {
        try store.updateUploadTransferSession(sessionUUID: sessionUUID, offset: offset, accountID: try defaultAccountID(accountID))
    }

    public func removeUploadTransferSession(sessionUUID: String, accountID: String? = nil) throws {
        try store.removeUploadTransferSession(sessionUUID: sessionUUID, accountID: try defaultAccountID(accountID))
    }

    public func uploadTransferSessions(accountID: String? = nil) -> [FloppyUploadTransferSession] {
        do {
            return try store.uploadTransferSessions(accountID: try defaultAccountID(accountID))
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading resumable upload sessions: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func recordActiveEnumerator(_ identifier: String) {
        do {
            try store.recordActiveEnumerator(identifier)
        } catch {
            FloppyDiagnostics.ledger.error("Failed recording active enumerator: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func removeActiveEnumerator(_ identifier: String) {
        do {
            try store.removeActiveEnumerator(identifier)
        } catch {
            FloppyDiagnostics.ledger.error("Failed removing active enumerator: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func activeEnumeratorIdentifiers() -> [String] {
        do {
            return try store.activeEnumeratorIdentifiers()
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading active enumerators: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func currentSyncAnchor() -> String? {
        accounts().first.map { String($0.lastCursor) }
    }

    public func apply(changes: [FloppyChange], accountID: String? = nil) throws {
        let resolvedAccountID = try defaultAccountID(accountID)
        try store.transaction {
            for change in changes {
                if let item = change.floppyItemPayload {
                    try store.upsert(item: item, accountID: resolvedAccountID)
                }
                if change.isDeletion, let uuid = change.deletedItemUUID {
                    try store.removeItem(uuid: uuid, accountID: resolvedAccountID)
                } else if change.isDeletion {
                    try store.removeItem(id: change.targetID, accountID: resolvedAccountID)
                }
            }

            if let last = changes.last {
                try store.updateAccountSync(accountID: resolvedAccountID, lastCursor: last.sequence, lastSyncAt: Date())
            }
        }
    }

    public func record(changeFeed: FloppyChangeFeed, accountID: String? = nil) throws {
        try store.updateAccountSync(accountID: try defaultAccountID(accountID), lastCursor: changeFeed.nextCursor, lastSyncAt: Date())
    }

    private func defaultAccountID(_ accountID: String?) throws -> String {
        if let accountID {
            return accountID
        }
        return try store.accounts().first?.id ?? "default"
    }

    private static func makeStore(databaseURL: URL, legacyJSONURL: URL?) -> SQLiteLedgerStore {
        do {
            return try SQLiteLedgerStore(databaseURL: databaseURL, legacyJSONURL: legacyJSONURL)
        } catch {
            FloppyDiagnostics.ledger.fault("Unable to open SQLite ledger at \(databaseURL.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }

        let fallbackURL = fallbackLedgerURL(for: databaseURL)
        do {
            FloppyDiagnostics.ledger.error("Using fallback SQLite ledger at \(fallbackURL.path, privacy: .private)")
            return try SQLiteLedgerStore(databaseURL: fallbackURL, legacyJSONURL: nil)
        } catch {
            FloppyDiagnostics.ledger.fault("Unable to open fallback SQLite ledger at \(fallbackURL.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }

        do {
            FloppyDiagnostics.ledger.error("Using in-memory SQLite ledger fallback")
            return try SQLiteLedgerStore.inMemory()
        } catch {
            FloppyDiagnostics.ledger.fault("Unable to open in-memory SQLite ledger: \(error.localizedDescription, privacy: .public)")
            preconditionFailure("Unable to open any Floppy SQLite ledger: \(error.localizedDescription)")
        }
    }

    private static func legacyJSONURL(for databaseURL: URL, explicitURL: URL) -> URL? {
        if explicitURL.pathExtension == "json" {
            return explicitURL
        }
        return databaseURL.deletingPathExtension().appendingPathExtension("json")
    }

    private static func fallbackLedgerURL(for databaseURL: URL) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let name = databaseURL.deletingPathExtension().lastPathComponent.safePathComponent
        return base
            .appendingPathComponent("FloppyMac", isDirectory: true)
            .appendingPathComponent("LedgerFallback", isDirectory: true)
            .appendingPathComponent(name + ".sqlite")
    }
}

private final class SQLiteLedgerStore {
    private let databaseURL: URL
    private let legacyJSONURL: URL?
    private var database: OpaquePointer?

    init(databaseURL: URL, legacyJSONURL: URL?) throws {
        self.databaseURL = databaseURL
        self.legacyJSONURL = legacyJSONURL

        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not allocate SQLite handle"
            if let handle {
                sqlite3_close(handle)
            }
            throw LocalLedgerError.sqlite(message)
        }

        database = handle
        try configureDatabase()
        try migrateLegacyJSONIfNeeded()
    }

    static func inMemory() throws -> SQLiteLedgerStore {
        try SQLiteLedgerStore(inMemoryName: "floppy-ledger")
    }

    private init(inMemoryName: String) throws {
        self.databaseURL = URL(fileURLWithPath: inMemoryName)
        self.legacyJSONURL = nil

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_MEMORY
        guard sqlite3_open_v2(inMemoryName, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not allocate SQLite handle"
            if let handle {
                sqlite3_close(handle)
            }
            throw LocalLedgerError.sqlite(message)
        }

        database = handle
        try configureDatabase()
    }

    private func configureDatabase() throws {
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        try execute("PRAGMA busy_timeout=5000")
        try migrateSchema()
    }

    deinit {
        close()
    }

    func close() {
        guard let database else {
            return
        }

        sqlite3_close(database)
        self.database = nil
    }

    func accounts() throws -> [FloppyAccount] {
        let statement = try prepare("""
            SELECT id, site_url, rest_url, user_hint, device_uuid, scope, last_cursor, connected_at, last_sync_at
            FROM accounts
            ORDER BY connected_at ASC
            """)
        defer { sqlite3_finalize(statement) }

        var accounts: [FloppyAccount] = []
        while try step(statement) == SQLITE_ROW {
            guard
                let siteURL = URL(string: columnText(statement, 1)),
                let restURL = URL(string: columnText(statement, 2))
            else {
                continue
            }

            accounts.append(FloppyAccount(
                siteURL: siteURL,
                restURL: restURL,
                userHint: columnText(statement, 3),
                deviceUUID: columnText(statement, 4),
                scope: columnText(statement, 5),
                lastCursor: UInt64(columnText(statement, 6)) ?? 0,
                connectedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 7)),
                lastSyncAt: sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 8))
            ))
        }
        return accounts
    }

    func upsert(account: FloppyAccount) throws {
        let statement = try prepare("""
            INSERT INTO accounts (id, site_url, rest_url, user_hint, device_uuid, scope, last_cursor, connected_at, last_sync_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                site_url = excluded.site_url,
                rest_url = excluded.rest_url,
                user_hint = excluded.user_hint,
                device_uuid = excluded.device_uuid,
                scope = excluded.scope,
                last_cursor = excluded.last_cursor,
                connected_at = excluded.connected_at,
                last_sync_at = excluded.last_sync_at
            """)
        defer { sqlite3_finalize(statement) }

        bind(account.id, to: statement, at: 1)
        bind(account.siteURL.absoluteString, to: statement, at: 2)
        bind(account.restURL.absoluteString, to: statement, at: 3)
        bind(account.userHint, to: statement, at: 4)
        bind(account.deviceUUID, to: statement, at: 5)
        bind(account.scope, to: statement, at: 6)
        bind(String(account.lastCursor), to: statement, at: 7)
        sqlite3_bind_double(statement, 8, account.connectedAt.timeIntervalSinceReferenceDate)
        bind(account.lastSyncAt?.timeIntervalSinceReferenceDate, to: statement, at: 9)
        try finish(statement)
    }

    func removeAccount(id: String) throws {
        try transaction {
            try execute("DELETE FROM accounts WHERE id = ?", .text(id))
            try execute("DELETE FROM items WHERE account_id = ?", .text(id))
            try execute("DELETE FROM pending_operations WHERE account_id = ?", .text(id))
            try execute("DELETE FROM upload_transfer_sessions WHERE account_id = ?", .text(id))
            try execute("DELETE FROM conflicts WHERE account_id = ?", .text(id))
        }
    }

    func items(accountID: String) throws -> [FloppyItem] {
        let statement = try prepare("""
            SELECT json
            FROM items
            WHERE account_id = ?
            ORDER BY kind DESC, name COLLATE NOCASE ASC
            """)
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        return try decodeItems(from: statement)
    }

    func upsert(item: FloppyItem, accountID: String) throws {
        let data = try JSONEncoder.floppy.encode(item)
        let statement = try prepare("""
            INSERT INTO items (account_id, uuid, stable_id, parent_id, kind, name, json, local_storage_policy, materialized_url, materialized_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, COALESCE((SELECT local_storage_policy FROM items WHERE account_id = ? AND uuid = ?), ?), COALESCE((SELECT materialized_url FROM items WHERE account_id = ? AND uuid = ?), NULL), COALESCE((SELECT materialized_at FROM items WHERE account_id = ? AND uuid = ?), NULL))
            ON CONFLICT(account_id, uuid) DO UPDATE SET
                stable_id = excluded.stable_id,
                parent_id = excluded.parent_id,
                kind = excluded.kind,
                name = excluded.name,
                json = excluded.json
            """)
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        bind(item.uuid, to: statement, at: 2)
        sqlite3_bind_int64(statement, 3, item.id)
        sqlite3_bind_int64(statement, 4, item.parentID)
        bind(item.kind.rawValue, to: statement, at: 5)
        bind(item.name, to: statement, at: 6)
        bind(data, to: statement, at: 7)
        bind(accountID, to: statement, at: 8)
        bind(item.uuid, to: statement, at: 9)
        bind(item.storagePolicy?.rawValue ?? FloppyLocalStoragePolicy.onlineOnly.rawValue, to: statement, at: 10)
        bind(accountID, to: statement, at: 11)
        bind(item.uuid, to: statement, at: 12)
        bind(accountID, to: statement, at: 13)
        bind(item.uuid, to: statement, at: 14)
        try finish(statement)
    }

    func item(uuid: String, accountID: String?) throws -> FloppyItem? {
        let statement: OpaquePointer
        if let accountID {
            statement = try prepare("SELECT json FROM items WHERE account_id = ? AND uuid = ? LIMIT 1")
            bind(accountID, to: statement, at: 1)
            bind(uuid, to: statement, at: 2)
        } else {
            statement = try prepare("SELECT json FROM items WHERE uuid = ? ORDER BY account_id ASC LIMIT 1")
            bind(uuid, to: statement, at: 1)
        }
        defer { sqlite3_finalize(statement) }

        return try decodeFirstItem(from: statement)
    }

    func item(id: Int64, accountID: String?) throws -> FloppyItem? {
        let statement: OpaquePointer
        if let accountID {
            statement = try prepare("SELECT json FROM items WHERE account_id = ? AND stable_id = ? LIMIT 1")
            bind(accountID, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, id)
        } else {
            statement = try prepare("SELECT json FROM items WHERE stable_id = ? ORDER BY account_id ASC LIMIT 1")
            sqlite3_bind_int64(statement, 1, id)
        }
        defer { sqlite3_finalize(statement) }

        return try decodeFirstItem(from: statement)
    }

    func removeItem(uuid: String, accountID: String?) throws {
        if let accountID {
            try execute("DELETE FROM items WHERE account_id = ? AND uuid = ?", .text(accountID), .text(uuid))
        } else {
            try execute("DELETE FROM items WHERE uuid = ?", .text(uuid))
        }
    }

    func removeItem(id: Int64, accountID: String?) throws {
        if let accountID {
            let statement = try prepare("DELETE FROM items WHERE account_id = ? AND stable_id = ?")
            defer { sqlite3_finalize(statement) }
            bind(accountID, to: statement, at: 1)
            sqlite3_bind_int64(statement, 2, id)
            try finish(statement)
        } else {
            let statement = try prepare("DELETE FROM items WHERE stable_id = ?")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, id)
            try finish(statement)
        }
    }

    func markMaterialized(item: FloppyItem, accountID: String, localURL: URL) throws {
        try upsert(item: item, accountID: accountID)
        let statement = try prepare("""
            UPDATE items
            SET materialized_url = ?, materialized_at = ?, local_storage_policy = ?
            WHERE account_id = ? AND uuid = ?
            """)
        defer { sqlite3_finalize(statement) }

        bind(localURL.path, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, Date().timeIntervalSinceReferenceDate)
        bind(FloppyLocalStoragePolicy.availableOffline.rawValue, to: statement, at: 3)
        bind(accountID, to: statement, at: 4)
        bind(item.uuid, to: statement, at: 5)
        try finish(statement)
    }

    func setStoragePolicy(uuid: String, accountID: String, policy: FloppyLocalStoragePolicy, removeMaterializedCopy: Bool) throws {
        var existingMaterializedPath: String?
        if policy != .availableOffline {
            existingMaterializedPath = try materializedPath(uuid: uuid, accountID: accountID)
        }

        if removeMaterializedCopy, let existingMaterializedPath, !existingMaterializedPath.isEmpty {
            try? FileManager.default.removeItem(atPath: existingMaterializedPath)
        }

        let statement = try prepare("""
            UPDATE items
            SET local_storage_policy = ?,
                materialized_url = CASE WHEN ? THEN NULL ELSE materialized_url END,
                materialized_at = CASE WHEN ? THEN NULL ELSE materialized_at END
            WHERE account_id = ? AND uuid = ?
            """)
        defer { sqlite3_finalize(statement) }

        let clearMaterialized = policy != .availableOffline
        bind(policy.rawValue, to: statement, at: 1)
        sqlite3_bind_int(statement, 2, clearMaterialized ? 1 : 0)
        sqlite3_bind_int(statement, 3, clearMaterialized ? 1 : 0)
        bind(accountID, to: statement, at: 4)
        bind(uuid, to: statement, at: 5)
        try finish(statement)
    }

    func storagePolicy(uuid: String, accountID: String) throws -> FloppyLocalStoragePolicy {
        let statement = try prepare("SELECT local_storage_policy FROM items WHERE account_id = ? AND uuid = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        bind(uuid, to: statement, at: 2)
        guard try step(statement) == SQLITE_ROW else {
            return .onlineOnly
        }
        return FloppyLocalStoragePolicy(rawValue: columnText(statement, 0)) ?? .onlineOnly
    }

    func storagePolicySummary(accountID: String) throws -> FloppyStoragePolicySummary {
        let counts = try countRowsByStoragePolicy(accountID: accountID)
        let materializedRows = try materializedPolicyRows(accountID: accountID)
        var materializedBytes: Int64 = 0
        var missingAvailableOffline = 0
        for row in materializedRows {
            guard row.policy == .availableOffline else {
                continue
            }
            guard !row.path.isEmpty, FileManager.default.fileExists(atPath: row.path) else {
                missingAvailableOffline += 1
                continue
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: row.path)[.size] as? NSNumber)?.int64Value ?? 0
            materializedBytes += size
        }

        return FloppyStoragePolicySummary(
            accountFingerprint: FloppyDiagnostics.redactedFingerprint(accountID),
            onlineOnly: counts[.onlineOnly, default: 0],
            availableOffline: counts[.availableOffline, default: 0],
            excluded: counts[.excluded, default: 0],
            materializedBytes: materializedBytes,
            missingAvailableOffline: missingAvailableOffline
        )
    }

    func materializedURL(uuid: String, accountID: String) throws -> URL? {
        let statement = try prepare("SELECT materialized_url FROM items WHERE account_id = ? AND uuid = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        bind(uuid, to: statement, at: 2)
        guard try step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) != SQLITE_NULL else {
            return nil
        }
        return URL(fileURLWithPath: columnText(statement, 0))
    }

    private func materializedPath(uuid: String, accountID: String) throws -> String? {
        let statement = try prepare("SELECT materialized_url FROM items WHERE account_id = ? AND uuid = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        bind(uuid, to: statement, at: 2)
        guard try step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) != SQLITE_NULL else {
            return nil
        }
        let path = columnText(statement, 0)
        return path.isEmpty ? nil : path
    }

    func recordActiveEnumerator(_ identifier: String) throws {
        let statement = try prepare("""
            INSERT INTO active_enumerators (identifier, recorded_at)
            VALUES (?, ?)
            ON CONFLICT(identifier) DO UPDATE SET recorded_at = excluded.recorded_at
            """)
        defer { sqlite3_finalize(statement) }

        bind(identifier, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, Date().timeIntervalSinceReferenceDate)
        try finish(statement)
    }

    func removeActiveEnumerator(_ identifier: String) throws {
        try execute("DELETE FROM active_enumerators WHERE identifier = ?", .text(identifier))
    }

    func activeEnumeratorIdentifiers() throws -> [String] {
        let statement = try prepare("SELECT identifier FROM active_enumerators ORDER BY recorded_at DESC")
        defer { sqlite3_finalize(statement) }

        var identifiers: [String] = []
        while try step(statement) == SQLITE_ROW {
            identifiers.append(columnText(statement, 0))
        }
        return identifiers
    }

    func conflictCount(accountID: String) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM conflicts WHERE account_id = ? AND state != 'resolved'")
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        guard try step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func conflictDiagnostics(accountID: String) throws -> FloppyLedgerConflictDiagnostics {
        let totalCount = try scalarInt("SELECT COUNT(*) FROM conflicts WHERE account_id = ?", .text(accountID))
        let openCount = try scalarInt("SELECT COUNT(*) FROM conflicts WHERE account_id = ? AND state != 'resolved'", .text(accountID))
        let resolvedCount = try scalarInt("SELECT COUNT(*) FROM conflicts WHERE account_id = ? AND state = 'resolved'", .text(accountID))
        let materializedPaths = try nonEmptyStrings(
            sql: "SELECT materialized_path FROM conflicts WHERE account_id = ? AND state != 'resolved' AND materialized_path != ''",
            bindings: [.text(accountID)]
        )
        let missingMaterializedOpenCount = materializedPaths.filter { !FileManager.default.fileExists(atPath: $0) }.count
        let missingItemRecordCount = try scalarInt("""
            SELECT COUNT(*)
            FROM conflicts c
            LEFT JOIN items i ON i.account_id = c.account_id AND i.uuid = c.item_uuid
            WHERE c.account_id = ? AND c.state != 'resolved' AND i.uuid IS NULL
            """, .text(accountID))
        let reasons = try conflictReasonCounts(accountID: accountID)

        return FloppyLedgerConflictDiagnostics(
            accountFingerprint: FloppyDiagnostics.redactedFingerprint(accountID),
            totalCount: totalCount,
            openCount: openCount,
            resolvedCount: resolvedCount,
            materializedOpenCount: materializedPaths.count,
            missingMaterializedOpenCount: missingMaterializedOpenCount,
            missingItemRecordCount: missingItemRecordCount,
            reasons: reasons
        )
    }

    func conflictCenterItems(accountID: String, limit: Int) throws -> [FloppyConflictCenterItem] {
        let statement = try prepare("""
            SELECT id, account_id, item_uuid, message, display_name, parent_id, parent_uuid, materialized_path, original_content_version, state, created_at
            FROM conflicts
            WHERE account_id = ?
            ORDER BY
                CASE WHEN state = 'resolved' THEN 1 ELSE 0 END ASC,
                created_at DESC
            LIMIT ?
            """)
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        sqlite3_bind_int(statement, 2, Int32(max(1, min(limit, 100))))

        var items: [FloppyConflictCenterItem] = []
        while try step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: columnText(statement, 0)) else {
                continue
            }
            let materializedPath = columnText(statement, 7)
            let conflict = FloppyConflict(
                id: id,
                accountID: columnText(statement, 1),
                itemUUID: columnText(statement, 2),
                message: columnText(statement, 3),
                displayName: columnText(statement, 4),
                parentID: sqlite3_column_int64(statement, 5),
                parentUUID: columnText(statement, 6),
                materializedPath: materializedPath,
                originalContentVersion: columnText(statement, 8),
                state: columnText(statement, 9),
                createdAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 10))
            )
            items.append(FloppyConflictCenterPresenter.item(
                from: conflict,
                localFileExists: !materializedPath.isEmpty && FileManager.default.fileExists(atPath: materializedPath)
            ))
        }
        return items
    }

    func updateConflictState(id: UUID, accountID: String, state: String) throws {
        let statement = try prepare("""
            UPDATE conflicts
            SET state = ?
            WHERE id = ? AND account_id = ?
            """)
        defer { sqlite3_finalize(statement) }

        bind(state, to: statement, at: 1)
        bind(id.uuidString, to: statement, at: 2)
        bind(accountID, to: statement, at: 3)
        try finish(statement)
    }

    func conflictMaterializedPath(id: UUID, accountID: String) throws -> String? {
        let statement = try prepare("""
            SELECT materialized_path
            FROM conflicts
            WHERE id = ? AND account_id = ?
            LIMIT 1
            """)
        defer { sqlite3_finalize(statement) }

        bind(id.uuidString, to: statement, at: 1)
        bind(accountID, to: statement, at: 2)
        guard try step(statement) == SQLITE_ROW else {
            return nil
        }
        let path = columnText(statement, 0)
        return path.isEmpty ? nil : path
    }

    func integrityReport(accountID: String) throws -> FloppyLedgerIntegrityReport {
        let accountCount = try scalarInt("SELECT COUNT(*) FROM accounts WHERE id = ?", .text(accountID))
        let itemCount = try scalarInt("SELECT COUNT(*) FROM items WHERE account_id = ?", .text(accountID))
        let pendingCount = try scalarInt("SELECT COUNT(*) FROM pending_operations WHERE account_id = ?", .text(accountID))
        let conflictCount = try scalarInt("SELECT COUNT(*) FROM conflicts WHERE account_id = ?", .text(accountID))
        let materializedPaths = try nonEmptyStrings(
            sql: "SELECT materialized_url FROM items WHERE account_id = ? AND materialized_url IS NOT NULL AND materialized_url != ''",
            bindings: [.text(accountID)]
        )
        let missingMaterializedItems = materializedPaths.filter { !FileManager.default.fileExists(atPath: $0) }.count
        let conflictDiagnostics = try conflictDiagnostics(accountID: accountID)
        let activeEnumeratorCount = try scalarInt("SELECT COUNT(*) FROM active_enumerators")

        var issues: [FloppyLedgerIntegrityIssue] = []
        if accountCount == 0 {
            issues.append(FloppyLedgerIntegrityIssue(
                code: "missing_account",
                severity: "error",
                count: 1,
                message: "The selected account is not present in the local ledger."
            ))
        }
        if missingMaterializedItems > 0 {
            issues.append(FloppyLedgerIntegrityIssue(
                code: "missing_materialized_files",
                severity: "warning",
                count: missingMaterializedItems,
                message: "One or more materialized Finder files no longer exists on disk."
            ))
        }
        if conflictDiagnostics.missingMaterializedOpenCount > 0 {
            issues.append(FloppyLedgerIntegrityIssue(
                code: "missing_conflict_files",
                severity: "error",
                count: conflictDiagnostics.missingMaterializedOpenCount,
                message: "One or more open conflict copies is missing from local disk."
            ))
        }
        if conflictDiagnostics.missingItemRecordCount > 0 {
            issues.append(FloppyLedgerIntegrityIssue(
                code: "conflict_missing_item_record",
                severity: "error",
                count: conflictDiagnostics.missingItemRecordCount,
                message: "One or more open conflicts does not have a matching local item row."
            ))
        }

        return FloppyLedgerIntegrityReport(
            accountFingerprint: FloppyDiagnostics.redactedFingerprint(accountID),
            ok: issues.isEmpty,
            counts: FloppyLedgerIntegrityCounts(
                accounts: accountCount,
                items: itemCount,
                pendingOperations: pendingCount,
                conflicts: conflictCount,
                materializedItems: materializedPaths.count,
                missingMaterializedItems: missingMaterializedItems,
                activeEnumerators: activeEnumeratorCount
            ),
            issues: issues
        )
    }

    func pendingOperationCount(accountID: String) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM pending_operations WHERE account_id = ?")
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        guard try step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func upsert(uploadTransferSession session: FloppyUploadTransferSession) throws {
        let statement = try prepare("""
            INSERT OR REPLACE INTO upload_transfer_sessions (session_uuid, account_id, operation, item_uuid, file_id, local_path, total_size, offset, chunk_size, expires_at_gmt, idempotency_key, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }

        bind(session.sessionUUID, to: statement, at: 1)
        bind(session.accountID, to: statement, at: 2)
        bind(session.operation, to: statement, at: 3)
        bind(session.itemUUID, to: statement, at: 4)
        if let fileID = session.fileID {
            sqlite3_bind_int64(statement, 5, fileID)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        bind(session.localPath, to: statement, at: 6)
        sqlite3_bind_int64(statement, 7, session.totalSize)
        sqlite3_bind_int64(statement, 8, session.offset)
        sqlite3_bind_int(statement, 9, Int32(session.chunkSize))
        bind(session.expiresAtGMT, to: statement, at: 10)
        bind(session.idempotencyKey, to: statement, at: 11)
        sqlite3_bind_double(statement, 12, session.updatedAt.timeIntervalSinceReferenceDate)
        try finish(statement)
    }

    func updateUploadTransferSession(sessionUUID: String, offset: Int64, accountID: String) throws {
        try execute(
            "UPDATE upload_transfer_sessions SET offset = ?, updated_at = ? WHERE session_uuid = ? AND account_id = ?",
            .int(offset),
            .double(Date().timeIntervalSinceReferenceDate),
            .text(sessionUUID),
            .text(accountID)
        )
    }

    func removeUploadTransferSession(sessionUUID: String, accountID: String) throws {
        try execute("DELETE FROM upload_transfer_sessions WHERE session_uuid = ? AND account_id = ?", .text(sessionUUID), .text(accountID))
    }

    func uploadTransferSessions(accountID: String) throws -> [FloppyUploadTransferSession] {
        let statement = try prepare("""
            SELECT session_uuid, account_id, operation, item_uuid, file_id, local_path, total_size, offset, chunk_size, expires_at_gmt, idempotency_key, updated_at
            FROM upload_transfer_sessions
            WHERE account_id = ?
            ORDER BY updated_at DESC
            """)
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        var sessions: [FloppyUploadTransferSession] = []
        while try step(statement) == SQLITE_ROW {
            let fileID: Int64? = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 4)
            sessions.append(FloppyUploadTransferSession(
                accountID: columnText(statement, 1),
                sessionUUID: columnText(statement, 0),
                operation: columnText(statement, 2),
                itemUUID: columnText(statement, 3).isEmpty ? nil : columnText(statement, 3),
                fileID: fileID,
                localPath: columnText(statement, 5),
                totalSize: sqlite3_column_int64(statement, 6),
                offset: sqlite3_column_int64(statement, 7),
                chunkSize: Int(sqlite3_column_int(statement, 8)),
                expiresAtGMT: columnText(statement, 9),
                idempotencyKey: columnText(statement, 10),
                updatedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 11))
            ))
        }

        return sessions
    }

    func updateAccountSync(accountID: String, lastCursor: UInt64, lastSyncAt: Date) throws {
        let statement = try prepare("""
            UPDATE accounts
            SET last_cursor = ?, last_sync_at = ?
            WHERE id = ?
            """)
        defer { sqlite3_finalize(statement) }

        bind(String(lastCursor), to: statement, at: 1)
        sqlite3_bind_double(statement, 2, lastSyncAt.timeIntervalSinceReferenceDate)
        bind(accountID, to: statement, at: 3)
        try finish(statement)
    }

    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func migrateSchema() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at REAL NOT NULL
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS accounts (
                id TEXT PRIMARY KEY,
                site_url TEXT NOT NULL,
                rest_url TEXT NOT NULL,
                user_hint TEXT NOT NULL,
                device_uuid TEXT NOT NULL,
                scope TEXT NOT NULL,
                last_cursor TEXT NOT NULL DEFAULT '0',
                connected_at REAL NOT NULL,
                last_sync_at REAL
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS items (
                account_id TEXT NOT NULL,
                uuid TEXT NOT NULL,
                stable_id INTEGER NOT NULL,
                parent_id INTEGER NOT NULL,
                kind TEXT NOT NULL,
                name TEXT NOT NULL,
                json BLOB NOT NULL,
                local_storage_policy TEXT NOT NULL DEFAULT 'online_only',
                materialized_url TEXT,
                materialized_at REAL,
                PRIMARY KEY (account_id, uuid)
            )
            """)
        try addColumnIfMissing(table: "items", column: "local_storage_policy", definition: "local_storage_policy TEXT NOT NULL DEFAULT 'online_only'")
        try execute("CREATE INDEX IF NOT EXISTS items_account_stable_id ON items (account_id, stable_id)")
        try execute("CREATE INDEX IF NOT EXISTS items_account_parent_id ON items (account_id, parent_id)")
        try execute("CREATE INDEX IF NOT EXISTS items_account_storage_policy ON items (account_id, local_storage_policy)")
        try execute("""
            CREATE TABLE IF NOT EXISTS pending_operations (
                id TEXT PRIMARY KEY,
                account_id TEXT NOT NULL,
                operation TEXT NOT NULL,
                created_at REAL NOT NULL
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS upload_transfer_sessions (
                session_uuid TEXT PRIMARY KEY,
                account_id TEXT NOT NULL,
                operation TEXT NOT NULL,
                item_uuid TEXT,
                file_id INTEGER,
                local_path TEXT NOT NULL,
                total_size INTEGER NOT NULL,
                offset INTEGER NOT NULL,
                chunk_size INTEGER NOT NULL DEFAULT 8388608,
                expires_at_gmt TEXT NOT NULL DEFAULT '',
                idempotency_key TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
            """)
        try addColumnIfMissing(table: "upload_transfer_sessions", column: "chunk_size", definition: "chunk_size INTEGER NOT NULL DEFAULT 8388608")
        try addColumnIfMissing(table: "upload_transfer_sessions", column: "expires_at_gmt", definition: "expires_at_gmt TEXT NOT NULL DEFAULT ''")
        try execute("CREATE INDEX IF NOT EXISTS upload_transfer_sessions_account ON upload_transfer_sessions (account_id, updated_at)")
        try execute("""
            CREATE TABLE IF NOT EXISTS conflicts (
                id TEXT PRIMARY KEY,
                account_id TEXT NOT NULL,
                item_uuid TEXT NOT NULL,
                message TEXT NOT NULL,
                display_name TEXT NOT NULL DEFAULT '',
                parent_id INTEGER NOT NULL DEFAULT 0,
                parent_uuid TEXT NOT NULL DEFAULT '',
                materialized_path TEXT NOT NULL DEFAULT '',
                original_content_version TEXT NOT NULL DEFAULT '',
                state TEXT NOT NULL DEFAULT 'open',
                created_at REAL NOT NULL
            )
            """)
        try addColumnIfMissing(table: "conflicts", column: "display_name", definition: "display_name TEXT NOT NULL DEFAULT ''")
        try addColumnIfMissing(table: "conflicts", column: "parent_id", definition: "parent_id INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(table: "conflicts", column: "parent_uuid", definition: "parent_uuid TEXT NOT NULL DEFAULT ''")
        try addColumnIfMissing(table: "conflicts", column: "materialized_path", definition: "materialized_path TEXT NOT NULL DEFAULT ''")
        try addColumnIfMissing(table: "conflicts", column: "original_content_version", definition: "original_content_version TEXT NOT NULL DEFAULT ''")
        try addColumnIfMissing(table: "conflicts", column: "state", definition: "state TEXT NOT NULL DEFAULT 'open'")
        try execute("""
            CREATE TABLE IF NOT EXISTS active_enumerators (
                identifier TEXT PRIMARY KEY,
                recorded_at REAL NOT NULL
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """)
        try execute("""
            INSERT OR IGNORE INTO schema_migrations (version, applied_at)
            VALUES (1, ?)
            """, .double(Date().timeIntervalSinceReferenceDate))
    }

    private func addColumnIfMissing(table: String, column: String, definition: String) throws {
        guard try !columnNames(in: table).contains(column) else {
            return
        }

        try execute("ALTER TABLE \(table) ADD COLUMN \(definition)")
    }

    private func columnNames(in table: String) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }

        var names = Set<String>()
        while try step(statement) == SQLITE_ROW {
            names.insert(columnText(statement, 1))
        }
        return names
    }

    private func migrateLegacyJSONIfNeeded() throws {
        guard
            try accountCount() == 0,
            let legacyJSONURL,
            FileManager.default.fileExists(atPath: legacyJSONURL.path)
        else {
            return
        }

        let snapshot = try Self.loadJSONSnapshot(from: legacyJSONURL)
        try transaction {
            for account in snapshot.accounts {
                try upsert(account: account)
            }
            for (accountID, itemsByUUID) in snapshot.itemsByAccount {
                for item in itemsByUUID.values {
                    try upsert(item: item, accountID: accountID)
                }
            }
            for operation in snapshot.pendingOperations {
                try insert(operation: operation)
            }
            for conflict in snapshot.conflicts {
                try insert(conflict: conflict)
            }
            try execute("INSERT OR REPLACE INTO metadata (key, value) VALUES ('migrated_from_json', ?)", .text(legacyJSONURL.path))
        }

        FloppyDiagnostics.ledger.info("Migrated JSON ledger into SQLite at \(self.databaseURL.path, privacy: .private)")
    }

    private func accountCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM accounts")
        defer { sqlite3_finalize(statement) }

        guard try step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func insert(operation: FloppyPendingOperation) throws {
        let statement = try prepare("""
            INSERT OR REPLACE INTO pending_operations (id, account_id, operation, created_at)
            VALUES (?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }

        bind(operation.id.uuidString, to: statement, at: 1)
        bind(operation.accountID, to: statement, at: 2)
        bind(operation.operation, to: statement, at: 3)
        sqlite3_bind_double(statement, 4, operation.createdAt.timeIntervalSinceReferenceDate)
        try finish(statement)
    }

    func insert(conflict: FloppyConflict) throws {
        let statement = try prepare("""
            INSERT OR REPLACE INTO conflicts (id, account_id, item_uuid, message, display_name, parent_id, parent_uuid, materialized_path, original_content_version, state, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }

        bind(conflict.id.uuidString, to: statement, at: 1)
        bind(conflict.accountID, to: statement, at: 2)
        bind(conflict.itemUUID, to: statement, at: 3)
        bind(conflict.message, to: statement, at: 4)
        bind(conflict.displayName ?? "", to: statement, at: 5)
        sqlite3_bind_int64(statement, 6, conflict.parentID ?? 0)
        bind(conflict.parentUUID ?? "", to: statement, at: 7)
        bind(conflict.materializedPath ?? "", to: statement, at: 8)
        bind(conflict.originalContentVersion ?? "", to: statement, at: 9)
        bind(conflict.state ?? "open", to: statement, at: 10)
        sqlite3_bind_double(statement, 11, conflict.createdAt.timeIntervalSinceReferenceDate)
        try finish(statement)
    }

    private func decodeItems(from statement: OpaquePointer?) throws -> [FloppyItem] {
        var items: [FloppyItem] = []
        while try step(statement) == SQLITE_ROW {
            let data = columnData(statement, 0)
            items.append(try JSONDecoder.floppy.decode(FloppyItem.self, from: data))
        }
        return items
    }

    private func decodeFirstItem(from statement: OpaquePointer?) throws -> FloppyItem? {
        guard try step(statement) == SQLITE_ROW else {
            return nil
        }

        return try JSONDecoder.floppy.decode(FloppyItem.self, from: columnData(statement, 0))
    }

    private func scalarInt(_ sql: String, _ bindings: SQLiteBinding...) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        for (offset, binding) in bindings.enumerated() {
            bind(binding, to: statement, at: Int32(offset + 1))
        }

        guard try step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func nonEmptyStrings(sql: String, bindings: [SQLiteBinding]) throws -> [String] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        for (offset, binding) in bindings.enumerated() {
            bind(binding, to: statement, at: Int32(offset + 1))
        }

        var values: [String] = []
        while try step(statement) == SQLITE_ROW {
            let value = columnText(statement, 0)
            if !value.isEmpty {
                values.append(value)
            }
        }
        return values
    }

    private func conflictReasonCounts(accountID: String) throws -> [FloppyConflictReasonCount] {
        let statement = try prepare("""
            SELECT message, COUNT(*)
            FROM conflicts
            WHERE account_id = ? AND state != 'resolved'
            GROUP BY message
            ORDER BY COUNT(*) DESC, message COLLATE NOCASE ASC
            LIMIT 5
            """)
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        var reasons: [FloppyConflictReasonCount] = []
        while try step(statement) == SQLITE_ROW {
            reasons.append(FloppyConflictReasonCount(
                reason: columnText(statement, 0),
                count: Int(sqlite3_column_int64(statement, 1))
            ))
        }
        return reasons
    }

    private func countRowsByStoragePolicy(accountID: String) throws -> [FloppyLocalStoragePolicy: Int] {
        let statement = try prepare("""
            SELECT local_storage_policy, COUNT(*)
            FROM items
            WHERE account_id = ?
            GROUP BY local_storage_policy
            """)
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        var counts: [FloppyLocalStoragePolicy: Int] = [:]
        while try step(statement) == SQLITE_ROW {
            let policy = FloppyLocalStoragePolicy(rawValue: columnText(statement, 0)) ?? .onlineOnly
            counts[policy] = Int(sqlite3_column_int64(statement, 1))
        }
        return counts
    }

    private func materializedPolicyRows(accountID: String) throws -> [(policy: FloppyLocalStoragePolicy, path: String)] {
        let statement = try prepare("""
            SELECT local_storage_policy, COALESCE(materialized_url, '')
            FROM items
            WHERE account_id = ?
            """)
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        var rows: [(policy: FloppyLocalStoragePolicy, path: String)] = []
        while try step(statement) == SQLITE_ROW {
            rows.append((
                policy: FloppyLocalStoragePolicy(rawValue: columnText(statement, 0)) ?? .onlineOnly,
                path: columnText(statement, 1)
            ))
        }
        return rows
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(try requireDatabase(), sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LocalLedgerError.sqlite(lastErrorMessage)
        }
        return statement
    }

    private func execute(_ sql: String, _ bindings: SQLiteBinding...) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        for (offset, binding) in bindings.enumerated() {
            bind(binding, to: statement, at: Int32(offset + 1))
        }

        try finish(statement)
    }

    @discardableResult
    private func step(_ statement: OpaquePointer?) throws -> Int32 {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else {
            throw LocalLedgerError.sqlite(lastErrorMessage)
        }
        return result
    }

    private func finish(_ statement: OpaquePointer?) throws {
        while true {
            let result = try step(statement)
            if result == SQLITE_DONE {
                return
            }
        }
    }

    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func bind(_ value: String?, to statement: OpaquePointer?, at index: Int32) {
        if let value {
            bind(value, to: statement, at: index)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ value: Data, to statement: OpaquePointer?, at index: Int32) {
        _ = value.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(value.count), sqliteTransient)
        }
    }

    private func bind(_ value: Double?, to statement: OpaquePointer?, at index: Int32) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ binding: SQLiteBinding, to statement: OpaquePointer?, at index: Int32) {
        switch binding {
        case .text(let value):
            bind(value, to: statement, at: index)
        case .double(let value):
            sqlite3_bind_double(statement, index, value)
        case .int(let value):
            sqlite3_bind_int64(statement, index, value)
        }
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: text)
    }

    private func columnData(_ statement: OpaquePointer?, _ index: Int32) -> Data {
        guard let blob = sqlite3_column_blob(statement, index) else {
            return Data()
        }
        return Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func requireDatabase() throws -> OpaquePointer {
        guard let database else {
            throw LocalLedgerError.sqlite("database is closed")
        }
        return database
    }

    private var lastErrorMessage: String {
        guard let database else {
            return "database is closed"
        }
        return String(cString: sqlite3_errmsg(database))
    }

    private static func loadJSONSnapshot(from url: URL) throws -> FloppyLedgerSnapshot {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.floppy.decode(FloppyLedgerSnapshot.self, from: data)
    }
}

private enum SQLiteBinding {
    case text(String)
    case double(Double)
    case int(Int64)
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension String {
    var safePathComponent: String {
        replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "-", options: .regularExpression)
    }
}
