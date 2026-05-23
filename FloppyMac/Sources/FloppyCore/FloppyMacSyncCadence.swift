import Foundation

public struct FloppyMacSyncCadence: Equatable, Sendable {
    public let minimumAutomaticSyncInterval: TimeInterval
    public let cacheRefreshTTL: TimeInterval

    public init(minimumAutomaticSyncInterval: TimeInterval = 20, cacheRefreshTTL: TimeInterval = 12) {
        self.minimumAutomaticSyncInterval = max(0, minimumAutomaticSyncInterval)
        self.cacheRefreshTTL = max(0, cacheRefreshTTL)
    }

    public static let standard = FloppyMacSyncCadence()

    public func shouldRunAutomaticSync(
        now: Date,
        lastAutomaticSyncAt: Date?,
        hasAccount: Bool,
        isNetworkReachable: Bool,
        isWorking: Bool,
        isOnboarding: Bool
    ) -> Bool {
        guard hasAccount, isNetworkReachable, !isWorking, !isOnboarding else {
            return false
        }

        guard let lastAutomaticSyncAt else {
            return true
        }

        return now.timeIntervalSince(lastAutomaticSyncAt) >= minimumAutomaticSyncInterval
    }

    public func shouldRefreshCache(now: Date, lastRefreshAt: Date?, hasAccount: Bool) -> Bool {
        guard hasAccount else {
            return false
        }

        guard let lastRefreshAt else {
            return true
        }

        return now.timeIntervalSince(lastRefreshAt) >= cacheRefreshTTL
    }
}
