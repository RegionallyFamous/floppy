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
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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

    public func pendingOperationCount(accountID: String? = nil) -> Int {
        do {
            return try store.pendingOperationCount(accountID: try defaultAccountID(accountID))
        } catch {
            FloppyDiagnostics.ledger.error("Failed loading pending operation count: \(error.localizedDescription, privacy: .public)")
            return 0
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

    public func record(changeFeed: FloppyChangeFeed, accountID: String) throws {
        try store.updateAccountSync(accountID: accountID, lastCursor: changeFeed.nextCursor, lastSyncAt: Date())
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
            preconditionFailure("Unable to open Floppy SQLite ledger: \(error.localizedDescription)")
        }
    }

    private static func legacyJSONURL(for databaseURL: URL, explicitURL: URL) -> URL? {
        if explicitURL.pathExtension == "json" {
            return explicitURL
        }
        return databaseURL.deletingPathExtension().appendingPathExtension("json")
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
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        try execute("PRAGMA busy_timeout=5000")
        try migrateSchema()
        try migrateLegacyJSONIfNeeded()
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
            INSERT INTO items (account_id, uuid, stable_id, parent_id, kind, name, json, materialized_url, materialized_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, COALESCE((SELECT materialized_url FROM items WHERE account_id = ? AND uuid = ?), NULL), COALESCE((SELECT materialized_at FROM items WHERE account_id = ? AND uuid = ?), NULL))
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
        bind(accountID, to: statement, at: 10)
        bind(item.uuid, to: statement, at: 11)
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
            SET materialized_url = ?, materialized_at = ?
            WHERE account_id = ? AND uuid = ?
            """)
        defer { sqlite3_finalize(statement) }

        bind(localURL.path, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, Date().timeIntervalSinceReferenceDate)
        bind(accountID, to: statement, at: 3)
        bind(item.uuid, to: statement, at: 4)
        try finish(statement)
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

    func pendingOperationCount(accountID: String) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM pending_operations WHERE account_id = ?")
        defer { sqlite3_finalize(statement) }

        bind(accountID, to: statement, at: 1)
        guard try step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
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
                materialized_url TEXT,
                materialized_at REAL,
                PRIMARY KEY (account_id, uuid)
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS items_account_stable_id ON items (account_id, stable_id)")
        try execute("CREATE INDEX IF NOT EXISTS items_account_parent_id ON items (account_id, parent_id)")
        try execute("""
            CREATE TABLE IF NOT EXISTS pending_operations (
                id TEXT PRIMARY KEY,
                account_id TEXT NOT NULL,
                operation TEXT NOT NULL,
                created_at REAL NOT NULL
            )
            """)
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
        try? execute("ALTER TABLE conflicts ADD COLUMN display_name TEXT NOT NULL DEFAULT ''")
        try? execute("ALTER TABLE conflicts ADD COLUMN parent_id INTEGER NOT NULL DEFAULT 0")
        try? execute("ALTER TABLE conflicts ADD COLUMN parent_uuid TEXT NOT NULL DEFAULT ''")
        try? execute("ALTER TABLE conflicts ADD COLUMN materialized_path TEXT NOT NULL DEFAULT ''")
        try? execute("ALTER TABLE conflicts ADD COLUMN original_content_version TEXT NOT NULL DEFAULT ''")
        try? execute("ALTER TABLE conflicts ADD COLUMN state TEXT NOT NULL DEFAULT 'open'")
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
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension String {
    var safePathComponent: String {
        replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "-", options: .regularExpression)
    }
}
