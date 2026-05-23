import Foundation

public struct FloppyMacDiagnosticsBundleV2: Codable, Equatable, Sendable {
    public let format: String
    public let createdAt: String
    public let support: FloppySupportCorrelation
    public let app: FloppyMacDiagnosticsAppInfo
    public let selectedAccount: FloppyMacDiagnosticsSelectedAccount
    public let ledger: FloppyMacDiagnosticsLedgerInfo
    public let domains: [[String: String]]
    public let keychain: FloppyMacDiagnosticsKeychainInfo
    public let onboarding: FloppyMacDiagnosticsOnboardingInfo
    public let fileProvider: FloppyFileProviderLifecycleDiagnostic
    public let lastStatus: String

    public init(
        createdAt: String,
        support: FloppySupportCorrelation,
        app: FloppyMacDiagnosticsAppInfo,
        selectedAccount: FloppyMacDiagnosticsSelectedAccount,
        ledger: FloppyMacDiagnosticsLedgerInfo,
        domains: [[String: String]],
        keychain: FloppyMacDiagnosticsKeychainInfo,
        onboarding: FloppyMacDiagnosticsOnboardingInfo,
        fileProvider: FloppyFileProviderLifecycleDiagnostic,
        lastStatus: String
    ) {
        self.format = "floppy-mac-diagnostics-v2"
        self.createdAt = createdAt
        self.support = support
        self.app = app
        self.selectedAccount = selectedAccount
        self.ledger = ledger
        self.domains = domains
        self.keychain = keychain
        self.onboarding = onboarding
        self.fileProvider = fileProvider
        self.lastStatus = lastStatus
    }

    enum CodingKeys: String, CodingKey {
        case format
        case createdAt = "created_at"
        case support
        case app
        case selectedAccount = "selected_account"
        case ledger
        case domains
        case keychain
        case onboarding
        case fileProvider = "file_provider"
        case lastStatus = "last_status"
    }
}

public struct FloppyMacDiagnosticsAppInfo: Codable, Equatable, Sendable {
    public let version: String
    public let bundleID: String

    public init(version: String, bundleID: String) {
        self.version = version
        self.bundleID = bundleID
    }

    enum CodingKeys: String, CodingKey {
        case version
        case bundleID = "bundle_id"
    }
}

public struct FloppyMacDiagnosticsSelectedAccount: Codable, Equatable, Sendable {
    public let accountFingerprint: String
    public let siteURL: String
    public let restURL: String
    public let deviceUUIDFingerprint: String
    public let scope: String
    public let lastCursor: String
    public let lastSyncAt: String

    public init(account: FloppyAccount?, lastSyncAt: String) {
        self.accountFingerprint = FloppyDiagnostics.redactedFingerprint(account?.id)
        self.siteURL = FloppyDiagnostics.redactedURL(account?.siteURL)
        self.restURL = FloppyDiagnostics.redactedURL(account?.restURL)
        self.deviceUUIDFingerprint = FloppyDiagnostics.redactedFingerprint(account?.deviceUUID)
        self.scope = account?.scope ?? ""
        self.lastCursor = account.map { String($0.lastCursor) } ?? "0"
        self.lastSyncAt = lastSyncAt
    }

    enum CodingKeys: String, CodingKey {
        case accountFingerprint = "account_fingerprint"
        case siteURL = "site_url"
        case restURL = "rest_url"
        case deviceUUIDFingerprint = "device_uuid_fingerprint"
        case scope
        case lastCursor = "last_cursor"
        case lastSyncAt = "last_sync_at"
    }
}

public struct FloppyMacDiagnosticsLedgerInfo: Codable, Equatable, Sendable {
    public let path: String
    public let accounts: Int
    public let items: Int
    public let pendingOperations: Int
    public let conflicts: Int
    public let activeEnumerators: [String]
    public let conflictDiagnostics: FloppyLedgerConflictDiagnostics
    public let integrity: FloppyLedgerIntegrityReport

    public init(
        path: String,
        accounts: Int,
        items: Int,
        pendingOperations: Int,
        conflicts: Int,
        activeEnumerators: [String],
        conflictDiagnostics: FloppyLedgerConflictDiagnostics,
        integrity: FloppyLedgerIntegrityReport
    ) {
        self.path = FloppyDiagnostics.redactedFilePath(path)
        self.accounts = accounts
        self.items = items
        self.pendingOperations = pendingOperations
        self.conflicts = conflicts
        self.activeEnumerators = activeEnumerators
        self.conflictDiagnostics = conflictDiagnostics
        self.integrity = integrity
    }

    enum CodingKeys: String, CodingKey {
        case path
        case accounts
        case items
        case pendingOperations = "pending_operations"
        case conflicts
        case activeEnumerators = "active_enumerators"
        case conflictDiagnostics = "conflict_diagnostics"
        case integrity
    }
}

public struct FloppyMacDiagnosticsKeychainInfo: Codable, Equatable, Sendable {
    public let availableForSelectedAccount: Bool
    public let accessGroupConfigured: Bool
    public let dataProtectionKeychain: Bool
    public let interactivePromptsDisabled: Bool

    public init(
        availableForSelectedAccount: Bool,
        accessGroupConfigured: Bool,
        dataProtectionKeychain: Bool,
        interactivePromptsDisabled: Bool
    ) {
        self.availableForSelectedAccount = availableForSelectedAccount
        self.accessGroupConfigured = accessGroupConfigured
        self.dataProtectionKeychain = dataProtectionKeychain
        self.interactivePromptsDisabled = interactivePromptsDisabled
    }

    enum CodingKeys: String, CodingKey {
        case availableForSelectedAccount = "available_for_selected_account"
        case accessGroupConfigured = "access_group_configured"
        case dataProtectionKeychain = "data_protection_keychain"
        case interactivePromptsDisabled = "interactive_prompts_disabled"
    }
}

public struct FloppyMacDiagnosticsOnboardingInfo: Codable, Equatable, Sendable {
    public let step: String
    public let hasPendingState: Bool
    public let pluginMainFile: String

    public init(step: String, hasPendingState: Bool, pluginMainFile: String) {
        self.step = step
        self.hasPendingState = hasPendingState
        self.pluginMainFile = pluginMainFile
    }

    enum CodingKeys: String, CodingKey {
        case step
        case hasPendingState = "has_pending_state"
        case pluginMainFile = "plugin_main_file"
    }
}
