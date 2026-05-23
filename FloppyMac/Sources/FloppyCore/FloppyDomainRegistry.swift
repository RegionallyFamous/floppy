import Foundation
import Security

public struct FloppyDomainRecord: Codable, Equatable, Sendable {
    public let domainIdentifier: String
    public let accountID: String
    public let siteURL: URL
    public let restURL: URL
    public let displayName: String

    public init(domainIdentifier: String, accountID: String, siteURL: URL, restURL: URL, displayName: String) {
        self.domainIdentifier = domainIdentifier
        self.accountID = accountID
        self.siteURL = siteURL
        self.restURL = restURL
        self.displayName = displayName
    }
}

public enum FloppyDomainRegistry {
    public static let defaultAppGroupIdentifier = "group.com.floppy.mac"

    public static var appGroupIdentifier: String {
        appGroupIdentifier(bundle: .main)
    }

    public static func appGroupIdentifier(bundle: Bundle) -> String {
        guard
            let value = bundle.object(forInfoDictionaryKey: "FloppyAppGroupIdentifier") as? String,
            !value.isEmpty,
            !value.contains("$(")
        else {
            return defaultAppGroupIdentifier
        }

        return value
    }

    public static func domainIdentifier(for account: FloppyAccount) -> String {
        "floppy-\(account.deviceUUID)"
    }

    public static func record(for account: FloppyAccount) -> FloppyDomainRecord {
        FloppyDomainRecord(
            domainIdentifier: domainIdentifier(for: account),
            accountID: account.id,
            siteURL: account.siteURL,
            restURL: account.restURL,
            displayName: "Floppy - \(account.siteURL.host ?? account.siteURL.absoluteString)"
        )
    }

    public static func save(_ record: FloppyDomainRecord) throws {
        var records = try loadAll()
        records[record.domainIdentifier] = record
        try write(records)
    }

    public static func load(domainIdentifier: String) throws -> FloppyDomainRecord? {
        try loadAll()[domainIdentifier]
    }

    public static func remove(domainIdentifier: String) throws {
        var records = try loadAll()
        records.removeValue(forKey: domainIdentifier)
        try write(records)
    }

    public static func summaries() throws -> [[String: String]] {
        try loadAll().values.map { record in
            [
                "domainIdentifier": record.domainIdentifier,
                "accountID": record.accountID,
                "siteURL": FloppyDiagnostics.redactedURL(record.siteURL),
                "restURL": FloppyDiagnostics.redactedURL(record.restURL),
                "displayName": record.displayName
            ]
        }.sorted { ($0["domainIdentifier"] ?? "") < ($1["domainIdentifier"] ?? "") }
    }

    public static func sharedContainerBaseURL(appGroupIdentifier: String = Self.appGroupIdentifier) -> URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return url
        }

        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    private static func loadAll() throws -> [String: FloppyDomainRecord] {
        let url = registryURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.floppy.decode([String: FloppyDomainRecord].self, from: data)
    }

    private static func write(_ records: [String: FloppyDomainRecord]) throws {
        let url = registryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.floppy.encode(records)
        try data.write(to: url, options: [.atomic])
    }

    private static func registryURL() -> URL {
        let base = sharedContainerBaseURL()
        return base.appendingPathComponent("FloppyMac", isDirectory: true).appendingPathComponent("domains.json")
    }

    public static func hasAppGroupEntitlement(_ appGroupIdentifier: String) -> Bool {
        guard
            let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
        else {
            return false
        }

        return (value as? [String])?.contains(appGroupIdentifier) == true
    }
}
