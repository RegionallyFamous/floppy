import CryptoKit
import Foundation
import OSLog

public enum FloppyDiagnostics {
    public static let subsystem = "com.floppy.mac"

    public static let api = Logger(subsystem: subsystem, category: "api")
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let fileProvider = Logger(subsystem: subsystem, category: "file-provider")
    public static let ledger = Logger(subsystem: subsystem, category: "ledger")
    public static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
    public static let packaging = Logger(subsystem: subsystem, category: "packaging")

    public static func redactedURL(_ url: URL?) -> String {
        guard let url else {
            return "(none)"
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "\(url.scheme ?? "url")://\(url.host ?? "unknown")"
    }

    public static func redactedFilePath(_ path: String?) -> String {
        guard let path, !path.isEmpty else {
            return "(none)"
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~/" + path.dropFirst(home.count + 1)
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    public static func redactedFingerprint(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return ""
        }

        let digest = SHA256.hash(data: Data(value.utf8))
        return "sha256:" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public static func supportCorrelation(
        account: FloppyAccount?,
        domainIdentifier: String?,
        createdAt: Date = Date()
    ) -> FloppySupportCorrelation {
        let accountID = account?.id ?? ""
        let seed = [
            account?.siteURL.normalizedForDiagnostics ?? "",
            account?.restURL.normalizedForDiagnostics ?? "",
            account?.userHint ?? "",
            account?.deviceUUID ?? "",
            domainIdentifier ?? ""
        ].joined(separator: "|")

        return FloppySupportCorrelation(
            correlationID: "floppy-" + redactedFingerprint(seed).replacingOccurrences(of: "sha256:", with: ""),
            accountFingerprint: redactedFingerprint(accountID),
            siteFingerprint: redactedFingerprint(account?.siteURL.normalizedForDiagnostics),
            restFingerprint: redactedFingerprint(account?.restURL.normalizedForDiagnostics),
            deviceFingerprint: redactedFingerprint(account?.deviceUUID),
            domainFingerprint: redactedFingerprint(domainIdentifier),
            redactionVersion: "v2-sha256-prefix-16"
        )
    }
}

public struct FloppySupportCorrelation: Codable, Equatable, Sendable {
    public let correlationID: String
    public let accountFingerprint: String
    public let siteFingerprint: String
    public let restFingerprint: String
    public let deviceFingerprint: String
    public let domainFingerprint: String
    public let redactionVersion: String

    public init(
        correlationID: String,
        accountFingerprint: String,
        siteFingerprint: String,
        restFingerprint: String,
        deviceFingerprint: String,
        domainFingerprint: String,
        redactionVersion: String
    ) {
        self.correlationID = correlationID
        self.accountFingerprint = accountFingerprint
        self.siteFingerprint = siteFingerprint
        self.restFingerprint = restFingerprint
        self.deviceFingerprint = deviceFingerprint
        self.domainFingerprint = domainFingerprint
        self.redactionVersion = redactionVersion
    }

    enum CodingKeys: String, CodingKey {
        case correlationID = "correlation_id"
        case accountFingerprint = "account_fingerprint"
        case siteFingerprint = "site_fingerprint"
        case restFingerprint = "rest_fingerprint"
        case deviceFingerprint = "device_fingerprint"
        case domainFingerprint = "domain_fingerprint"
        case redactionVersion = "redaction_version"
    }
}

public struct FloppyEnumeratorSignalPlan: Equatable, Sendable {
    public let rawIdentifiers: [String]

    public init(workingSetIdentifier: String, activeEnumerators: [String]) {
        var seen = Set<String>()
        var identifiers: [String] = []
        for candidate in [workingSetIdentifier] + activeEnumerators {
            guard !candidate.isEmpty, !seen.contains(candidate) else {
                continue
            }
            seen.insert(candidate)
            identifiers.append(candidate)
        }
        self.rawIdentifiers = identifiers
    }
}

public enum FloppyFileProviderLifecycleState: String, Codable, Sendable {
    case unconfigured
    case nativeFolderNotReady = "native_folder_not_ready"
    case missingToken = "missing_token"
    case registryMissing = "registry_missing"
    case needsLedgerRepair = "needs_ledger_repair"
    case serverUnreachable = "server_unreachable"
    case reconnectFailed = "reconnect_failed"
    case revokedToken = "revoked_token"
    case domainUnavailable = "domain_unavailable"
    case materializationStuck = "materialization_stuck"
    case configured
}

public struct FloppyFileProviderLifecycleDiagnostic: Codable, Equatable, Sendable {
    public let state: FloppyFileProviderLifecycleState
    public let message: String
    public let domainIdentifierFingerprint: String
    public let displayName: String
    public let readinessStatus: String
    public let registeredInLocalRegistry: Bool
    public let keychainTokenAvailable: Bool
    public let ledgerOK: Bool
    public let activeEnumeratorCount: Int

    public init(
        state: FloppyFileProviderLifecycleState,
        message: String,
        domainIdentifierFingerprint: String,
        displayName: String,
        readinessStatus: String,
        registeredInLocalRegistry: Bool,
        keychainTokenAvailable: Bool,
        ledgerOK: Bool,
        activeEnumeratorCount: Int
    ) {
        self.state = state
        self.message = message
        self.domainIdentifierFingerprint = domainIdentifierFingerprint
        self.displayName = displayName
        self.readinessStatus = readinessStatus
        self.registeredInLocalRegistry = registeredInLocalRegistry
        self.keychainTokenAvailable = keychainTokenAvailable
        self.ledgerOK = ledgerOK
        self.activeEnumeratorCount = activeEnumeratorCount
    }

    enum CodingKeys: String, CodingKey {
        case state
        case message
        case domainIdentifierFingerprint = "domain_identifier_fingerprint"
        case displayName = "display_name"
        case readinessStatus = "readiness_status"
        case registeredInLocalRegistry = "registered_in_local_registry"
        case keychainTokenAvailable = "keychain_token_available"
        case ledgerOK = "ledger_ok"
        case activeEnumeratorCount = "active_enumerator_count"
    }
}

private extension URL {
    var normalizedForDiagnostics: String {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? absoluteString
    }
}
