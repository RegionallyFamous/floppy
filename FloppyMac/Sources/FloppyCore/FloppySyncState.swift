import Foundation

public enum FloppyFinderSyncState: String, Codable, CaseIterable, Sendable {
    case unconfigured
    case queued
    case onlineOnly = "online_only"
    case availableOffline = "available_offline"
    case syncing
    case current
    case conflict
    case offline
    case authNeeded = "auth_needed"
    case repairNeeded = "repair_needed"
    case storageBlocked = "storage_blocked"

    public var requiresUserAction: Bool {
        switch self {
        case .unconfigured, .conflict, .authNeeded, .repairNeeded, .storageBlocked:
            return true
        case .queued, .onlineOnly, .availableOffline, .syncing, .current, .offline:
            return false
        }
    }
}

public enum FloppyFileProviderRecoveryAction: String, Codable, CaseIterable, Sendable {
    case connectAccount = "connect_account"
    case openSignedXcodeBuild = "open_signed_xcode_build"
    case reconnectSite = "reconnect_site"
    case registerDomain = "register_domain"
    case repairLedger = "repair_ledger"
    case waitForNetwork = "wait_for_network"
    case retrySync = "retry_sync"
    case freeStorage = "free_storage"
    case makeAvailableOffline = "make_available_offline"
    case makeOnlineOnly = "make_online_only"
    case excludeFromThisMac = "exclude_from_this_mac"
    case includeOnThisMac = "include_on_this_mac"
    case resolveConflicts = "resolve_conflicts"
    case resetDomain = "reset_domain"
}

public struct FloppyRecoveryDecision: Codable, Equatable, Sendable {
    public let state: FloppyFinderSyncState
    public let message: String
    public let actions: [FloppyFileProviderRecoveryAction]

    public init(state: FloppyFinderSyncState, message: String, actions: [FloppyFileProviderRecoveryAction]) {
        self.state = state
        self.message = message
        self.actions = actions
    }
}

public struct FloppyRecoveryContext: Equatable, Sendable {
    public let lifecycleState: FloppyFileProviderLifecycleState
    public let hasSelectedAccount: Bool
    public let keychainTokenAvailable: Bool
    public let serverReachable: Bool
    public let storageBlocked: Bool
    public let isSyncing: Bool
    public let pendingOperationCount: Int
    public let openConflictCount: Int
    public let materializationIssueCount: Int
    public let lastError: String

    public init(
        lifecycleState: FloppyFileProviderLifecycleState,
        hasSelectedAccount: Bool,
        keychainTokenAvailable: Bool,
        serverReachable: Bool = true,
        storageBlocked: Bool = false,
        isSyncing: Bool = false,
        pendingOperationCount: Int = 0,
        openConflictCount: Int = 0,
        materializationIssueCount: Int = 0,
        lastError: String = ""
    ) {
        self.lifecycleState = lifecycleState
        self.hasSelectedAccount = hasSelectedAccount
        self.keychainTokenAvailable = keychainTokenAvailable
        self.serverReachable = serverReachable
        self.storageBlocked = storageBlocked
        self.isSyncing = isSyncing
        self.pendingOperationCount = pendingOperationCount
        self.openConflictCount = openConflictCount
        self.materializationIssueCount = materializationIssueCount
        self.lastError = lastError
    }
}

public enum FloppyRecoveryPlanner {
    public static func decision(for context: FloppyRecoveryContext) -> FloppyRecoveryDecision {
        if !context.hasSelectedAccount || context.lifecycleState == .unconfigured {
            return FloppyRecoveryDecision(
                state: .unconfigured,
                message: "Connect a WordPress site to create the Floppy Finder folder.",
                actions: [.connectAccount]
            )
        }

        if context.lifecycleState == .nativeFolderNotReady {
            return FloppyRecoveryDecision(
                state: .repairNeeded,
                message: "Run the signed Xcode build with the embedded File Provider extension.",
                actions: [.openSignedXcodeBuild]
            )
        }

        if context.lifecycleState == .missingToken || !context.keychainTokenAvailable || context.lifecycleState == .revokedToken {
            return FloppyRecoveryDecision(
                state: .authNeeded,
                message: "Reconnect this site so Floppy can create a fresh scoped device token.",
                actions: [.reconnectSite]
            )
        }

        if context.lifecycleState == .registryMissing || context.lifecycleState == .domainUnavailable {
            return FloppyRecoveryDecision(
                state: .repairNeeded,
                message: "Register the File Provider domain again for this WordPress site.",
                actions: [.registerDomain, .resetDomain]
            )
        }

        if context.lifecycleState == .needsLedgerRepair || context.materializationIssueCount > 0 || context.lifecycleState == .materializationStuck {
            return FloppyRecoveryDecision(
                state: .repairNeeded,
                message: "Repair the local sync ledger before trusting Finder state.",
                actions: [.repairLedger, .retrySync]
            )
        }

        if context.storageBlocked {
            return FloppyRecoveryDecision(
                state: .storageBlocked,
                message: "The connected WordPress site is blocking storage or quota-sensitive sync.",
                actions: [.freeStorage, .retrySync]
            )
        }

        if !context.serverReachable || context.lifecycleState == .serverUnreachable || context.lifecycleState == .reconnectFailed {
            return FloppyRecoveryDecision(
                state: .offline,
                message: context.lastError.isEmpty ? "The WordPress site is currently unreachable." : context.lastError,
                actions: [.waitForNetwork, .retrySync]
            )
        }

        if context.openConflictCount > 0 {
            return FloppyRecoveryDecision(
                state: .conflict,
                message: "Resolve local Finder conflicts before Floppy can report this folder as current.",
                actions: [.resolveConflicts, .retrySync]
            )
        }

        if context.isSyncing {
            return FloppyRecoveryDecision(
                state: .syncing,
                message: "Floppy is applying Finder and WordPress changes.",
                actions: []
            )
        }

        if context.pendingOperationCount > 0 {
            return FloppyRecoveryDecision(
                state: .queued,
                message: "Floppy has queued local changes waiting to sync.",
                actions: [.retrySync]
            )
        }

        return FloppyRecoveryDecision(
            state: .current,
            message: "Finder and WordPress are in sync.",
            actions: []
        )
    }
}
