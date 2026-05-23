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
        self.lastStatus = FloppyDiagnostics.redactedStatus(lastStatus)
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

public struct FloppyMacDiagnosticsBundleV3: Codable, Equatable, Sendable {
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
    public let finderSync: FloppyMacDiagnosticsFinderSyncInfo
    public let conflictCenter: FloppyMacDiagnosticsConflictCenterInfo
    public let materialization: FloppyMacDiagnosticsMaterializationInfo
    public let versionRestores: FloppyMacDiagnosticsVersionRestoreInfo
    public let releaseBuild: FloppyReleaseBuildIdentity
    public let releaseEvidence: FloppyReleaseEvidenceSummary
    public let serverHealth: FloppyMacDiagnosticsServerHealthInfo
    public let nativeRuntime: FloppyMacDiagnosticsNativeRuntimeInfo
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
        finderSync: FloppyMacDiagnosticsFinderSyncInfo,
        conflictCenter: FloppyMacDiagnosticsConflictCenterInfo,
        materialization: FloppyMacDiagnosticsMaterializationInfo,
        versionRestores: FloppyMacDiagnosticsVersionRestoreInfo,
        releaseBuild: FloppyReleaseBuildIdentity,
        releaseEvidence: FloppyReleaseEvidenceSummary,
        serverHealth: FloppyMacDiagnosticsServerHealthInfo = .empty,
        nativeRuntime: FloppyMacDiagnosticsNativeRuntimeInfo = .empty,
        lastStatus: String
    ) {
        self.format = "floppy-mac-diagnostics-v3"
        self.createdAt = createdAt
        self.support = support
        self.app = app
        self.selectedAccount = selectedAccount
        self.ledger = ledger
        self.domains = domains
        self.keychain = keychain
        self.onboarding = onboarding
        self.fileProvider = fileProvider
        self.finderSync = finderSync
        self.conflictCenter = conflictCenter
        self.materialization = materialization
        self.versionRestores = versionRestores
        self.releaseBuild = releaseBuild
        self.releaseEvidence = releaseEvidence
        self.serverHealth = serverHealth
        self.nativeRuntime = nativeRuntime
        self.lastStatus = FloppyDiagnostics.redactedStatus(lastStatus)
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
        case finderSync = "finder_sync"
        case conflictCenter = "conflict_center"
        case materialization
        case versionRestores = "version_restores"
        case releaseBuild = "release_build"
        case releaseEvidence = "release_evidence"
        case serverHealth = "server_health"
        case nativeRuntime = "native_runtime"
        case lastStatus = "last_status"
    }
}

public struct FloppyMacDiagnosticsBundleV4: Codable, Equatable, Sendable {
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
    public let finderSync: FloppyMacDiagnosticsFinderSyncInfo
    public let storagePolicy: FloppyMacDiagnosticsStoragePolicyInfo
    public let transferQueue: FloppyMacDiagnosticsTransferQueueInfo
    public let reauth: FloppyMacDiagnosticsReauthInfo
    public let conflictCenter: FloppyMacDiagnosticsConflictCenterInfo
    public let materialization: FloppyMacDiagnosticsMaterializationInfo
    public let versionRestores: FloppyMacDiagnosticsVersionRestoreInfo
    public let releaseBuild: FloppyReleaseBuildIdentity
    public let releaseEvidence: FloppyReleaseEvidenceSummary
    public let serverHealth: FloppyMacDiagnosticsServerHealthInfo
    public let nativeRuntime: FloppyMacDiagnosticsNativeRuntimeInfo
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
        finderSync: FloppyMacDiagnosticsFinderSyncInfo,
        storagePolicy: FloppyMacDiagnosticsStoragePolicyInfo,
        transferQueue: FloppyMacDiagnosticsTransferQueueInfo,
        reauth: FloppyMacDiagnosticsReauthInfo,
        conflictCenter: FloppyMacDiagnosticsConflictCenterInfo,
        materialization: FloppyMacDiagnosticsMaterializationInfo,
        versionRestores: FloppyMacDiagnosticsVersionRestoreInfo,
        releaseBuild: FloppyReleaseBuildIdentity,
        releaseEvidence: FloppyReleaseEvidenceSummary,
        serverHealth: FloppyMacDiagnosticsServerHealthInfo = .empty,
        nativeRuntime: FloppyMacDiagnosticsNativeRuntimeInfo = .empty,
        lastStatus: String
    ) {
        self.format = "floppy-mac-diagnostics-v4"
        self.createdAt = createdAt
        self.support = support
        self.app = app
        self.selectedAccount = selectedAccount
        self.ledger = ledger
        self.domains = domains
        self.keychain = keychain
        self.onboarding = onboarding
        self.fileProvider = fileProvider
        self.finderSync = finderSync
        self.storagePolicy = storagePolicy
        self.transferQueue = transferQueue
        self.reauth = reauth
        self.conflictCenter = conflictCenter
        self.materialization = materialization
        self.versionRestores = versionRestores
        self.releaseBuild = releaseBuild
        self.releaseEvidence = releaseEvidence
        self.serverHealth = serverHealth
        self.nativeRuntime = nativeRuntime
        self.lastStatus = FloppyDiagnostics.redactedStatus(lastStatus)
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
        case finderSync = "finder_sync"
        case storagePolicy = "storage_policy"
        case transferQueue = "transfer_queue"
        case reauth
        case conflictCenter = "conflict_center"
        case materialization
        case versionRestores = "version_restores"
        case releaseBuild = "release_build"
        case releaseEvidence = "release_evidence"
        case serverHealth = "server_health"
        case nativeRuntime = "native_runtime"
        case lastStatus = "last_status"
    }
}

public struct FloppyMacDiagnosticsFinderSyncInfo: Codable, Equatable, Sendable {
    public let state: FloppyFinderSyncState
    public let message: String
    public let recoveryActions: [FloppyFileProviderRecoveryAction]
    public let pendingOperations: Int
    public let openConflicts: Int
    public let activeEnumerators: Int
    public let lastCursor: String
    public let lastSyncAt: String

    public init(
        decision: FloppyRecoveryDecision,
        pendingOperations: Int,
        openConflicts: Int,
        activeEnumerators: Int,
        lastCursor: String,
        lastSyncAt: String
    ) {
        self.state = decision.state
        self.message = decision.message
        self.recoveryActions = decision.actions
        self.pendingOperations = pendingOperations
        self.openConflicts = openConflicts
        self.activeEnumerators = activeEnumerators
        self.lastCursor = lastCursor
        self.lastSyncAt = lastSyncAt
    }

    enum CodingKeys: String, CodingKey {
        case state
        case message
        case recoveryActions = "recovery_actions"
        case pendingOperations = "pending_operations"
        case openConflicts = "open_conflicts"
        case activeEnumerators = "active_enumerators"
        case lastCursor = "last_cursor"
        case lastSyncAt = "last_sync_at"
    }
}

public struct FloppyMacDiagnosticsStoragePolicyInfo: Codable, Equatable, Sendable {
    public let summary: FloppyStoragePolicySummary
    public let defaultPolicy: FloppyLocalStoragePolicy
    public let supportedPolicies: [FloppyLocalStoragePolicy]
    public let finderActions: [FloppyFileProviderRecoveryAction]

    public init(
        summary: FloppyStoragePolicySummary,
        defaultPolicy: FloppyLocalStoragePolicy = .onlineOnly,
        supportedPolicies: [FloppyLocalStoragePolicy] = FloppyLocalStoragePolicy.allCases,
        finderActions: [FloppyFileProviderRecoveryAction] = [.makeAvailableOffline, .makeOnlineOnly, .freeStorage, .excludeFromThisMac, .includeOnThisMac]
    ) {
        self.summary = summary
        self.defaultPolicy = defaultPolicy
        self.supportedPolicies = supportedPolicies
        self.finderActions = finderActions
    }

    public static var empty: FloppyMacDiagnosticsStoragePolicyInfo {
        FloppyMacDiagnosticsStoragePolicyInfo(summary: .empty())
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case defaultPolicy = "default_policy"
        case supportedPolicies = "supported_policies"
        case finderActions = "finder_actions"
    }
}

public struct FloppyMacDiagnosticsTransferQueueInfo: Codable, Equatable, Sendable {
    public let pendingOperations: Int
    public let resumableSessions: Int
    public let uploadSessions: Int
    public let replacementSessions: Int
    public let hasInterruptedWork: Bool

    public init(pendingOperations: Int, sessions: [FloppyUploadTransferSession]) {
        self.pendingOperations = pendingOperations
        self.resumableSessions = sessions.count
        self.uploadSessions = sessions.filter { $0.operation == "upload" || $0.operation == "create" }.count
        self.replacementSessions = sessions.filter { $0.operation == "replace" }.count
        self.hasInterruptedWork = pendingOperations > 0 || !sessions.isEmpty
    }

    public static let empty = FloppyMacDiagnosticsTransferQueueInfo(pendingOperations: 0, sessions: [])

    enum CodingKeys: String, CodingKey {
        case pendingOperations = "pending_operations"
        case resumableSessions = "resumable_sessions"
        case uploadSessions = "upload_sessions"
        case replacementSessions = "replacement_sessions"
        case hasInterruptedWork = "has_interrupted_work"
    }
}

public struct FloppyMacDiagnosticsReauthInfo: Codable, Equatable, Sendable {
    public let required: Bool
    public let reason: String
    public let keychainTokenAvailable: Bool
    public let reconnectOnlyWhenRevokedOrMissing: Bool
    public let lastAuthError: String

    public init(required: Bool, reason: String, keychainTokenAvailable: Bool, lastAuthError: String = "") {
        self.required = required
        self.reason = FloppyDiagnostics.redactedStatus(reason)
        self.keychainTokenAvailable = keychainTokenAvailable
        self.reconnectOnlyWhenRevokedOrMissing = true
        self.lastAuthError = FloppyDiagnostics.redactedStatus(lastAuthError)
    }

    public static let empty = FloppyMacDiagnosticsReauthInfo(required: false, reason: "", keychainTokenAvailable: false)

    enum CodingKeys: String, CodingKey {
        case required
        case reason
        case keychainTokenAvailable = "keychain_token_available"
        case reconnectOnlyWhenRevokedOrMissing = "reconnect_only_when_revoked_or_missing"
        case lastAuthError = "last_auth_error"
    }
}

public struct FloppyMacDiagnosticsConflictCenterInfo: Codable, Equatable, Sendable {
    public let summary: FloppyConflictCenterSummary
    public let recent: [FloppyConflictCenterItem]

    public init(summary: FloppyConflictCenterSummary, recent: [FloppyConflictCenterItem]) {
        self.summary = summary
        self.recent = recent
    }

    public static var empty: FloppyMacDiagnosticsConflictCenterInfo {
        FloppyMacDiagnosticsConflictCenterInfo(summary: .empty, recent: [])
    }
}

public struct FloppyMacDiagnosticsMaterializationInfo: Codable, Equatable, Sendable {
    public let retries: Int
    public let checksumFailures: Int
    public let partialFileQuarantineCount: Int
    public let lastFailure: String

    public init(retries: Int = 0, checksumFailures: Int = 0, partialFileQuarantineCount: Int = 0, lastFailure: String = "") {
        self.retries = retries
        self.checksumFailures = checksumFailures
        self.partialFileQuarantineCount = partialFileQuarantineCount
        self.lastFailure = lastFailure
    }

    enum CodingKeys: String, CodingKey {
        case retries
        case checksumFailures = "checksum_failures"
        case partialFileQuarantineCount = "partial_file_quarantine_count"
        case lastFailure = "last_failure"
    }
}

public struct FloppyMacDiagnosticsVersionRestoreInfo: Codable, Equatable, Sendable {
    public let supportedByServer: String
    public let restoresAttempted: Int
    public let lastRestoreAt: String
    public let lastError: String

    public init(supportedByServer: String = "unknown", restoresAttempted: Int = 0, lastRestoreAt: String = "", lastError: String = "") {
        self.supportedByServer = supportedByServer
        self.restoresAttempted = restoresAttempted
        self.lastRestoreAt = lastRestoreAt
        self.lastError = lastError
    }

    enum CodingKeys: String, CodingKey {
        case supportedByServer = "supported_by_server"
        case restoresAttempted = "restores_attempted"
        case lastRestoreAt = "last_restore_at"
        case lastError = "last_error"
    }
}

public struct FloppyMacDiagnosticsNativeRuntimeInfo: Codable, Equatable, Sendable {
    public let launchAtLogin: String
    public let backgroundSyncEnabled: Bool
    public let networkReachable: Bool
    public let lastAutomaticSyncAt: String
    public let lastRefreshAt: String
    public let lastSyncTrigger: String
    public let lastSyncError: String
    public let syncInProgress: Bool
    public let openConflicts: Int
    public let pendingTransfers: Int

    public init(
        launchAtLogin: String,
        backgroundSyncEnabled: Bool,
        networkReachable: Bool,
        lastAutomaticSyncAt: String,
        lastRefreshAt: String = "",
        lastSyncTrigger: String = "",
        lastSyncError: String = "",
        syncInProgress: Bool = false,
        openConflicts: Int = 0,
        pendingTransfers: Int = 0
    ) {
        self.launchAtLogin = launchAtLogin
        self.backgroundSyncEnabled = backgroundSyncEnabled
        self.networkReachable = networkReachable
        self.lastAutomaticSyncAt = lastAutomaticSyncAt
        self.lastRefreshAt = lastRefreshAt
        self.lastSyncTrigger = FloppyDiagnostics.redactedStatus(lastSyncTrigger)
        self.lastSyncError = FloppyDiagnostics.redactedStatus(lastSyncError)
        self.syncInProgress = syncInProgress
        self.openConflicts = openConflicts
        self.pendingTransfers = pendingTransfers
    }

    public static let empty = FloppyMacDiagnosticsNativeRuntimeInfo(
        launchAtLogin: "unknown",
        backgroundSyncEnabled: false,
        networkReachable: true,
        lastAutomaticSyncAt: ""
    )

    enum CodingKeys: String, CodingKey {
        case launchAtLogin = "launch_at_login"
        case backgroundSyncEnabled = "background_sync_enabled"
        case networkReachable = "network_reachable"
        case lastAutomaticSyncAt = "last_automatic_sync_at"
        case lastRefreshAt = "last_refresh_at"
        case lastSyncTrigger = "last_sync_trigger"
        case lastSyncError = "last_sync_error"
        case syncInProgress = "sync_in_progress"
        case openConflicts = "open_conflicts"
        case pendingTransfers = "pending_transfers"
    }
}

public struct FloppyMacDiagnosticsServerHealthInfo: Codable, Equatable, Sendable {
    public let checkedAt: String
    public let ok: Bool?
    public let failedChecks: Int
    public let lastError: String

    public init(checkedAt: String, ok: Bool?, failedChecks: Int, lastError: String) {
        self.checkedAt = checkedAt
        self.ok = ok
        self.failedChecks = failedChecks
        self.lastError = FloppyDiagnostics.redactedStatus(lastError)
    }

    public static let empty = FloppyMacDiagnosticsServerHealthInfo(checkedAt: "", ok: nil, failedChecks: 0, lastError: "")

    enum CodingKeys: String, CodingKey {
        case checkedAt = "checked_at"
        case ok
        case failedChecks = "failed_checks"
        case lastError = "last_error"
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
