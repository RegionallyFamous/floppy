import AppKit
import FloppyCore
import Foundation
import SwiftUI

@MainActor
final class FloppyAppModel: ObservableObject {
    @Published var siteURLText: String = ""
    @Published var deviceName: String = Host.current().localizedName ?? "Mac"
    @Published var accounts: [FloppyAccount] = []
    @Published var selectedAccountID: String?
    @Published var items: [FloppyItem] = []
    @Published var health: FloppyHealthSummary?
    @Published var status: String = "Ready"
    @Published var isWorking = false
    @Published var onboardingStep: FloppyOnboardingStep = .idle
    @Published var pluginMainFile: String = "floppy/floppy.php"
    @Published var githubPluginZipURLText: String = "https://github.com/RegionallyFamous/floppy/releases/latest/download/floppy.zip"
    @Published var lastDownloadedPluginZipURL: URL?
    @Published var pendingPluginUploadURL: URL?

    private let tokenStore: FloppyTokenStore = KeychainTokenStore.default()
    private var ledger: LocalLedger?
    private var pendingOnboarding: PendingOnboarding?
    private var onboardingTask: Task<Void, Never>?

    init() {
        Task { await load() }
    }

    func load() async {
        let ledger = LocalLedger()
        self.ledger = ledger
        restorePendingOnboarding()
        accounts = await ledger.accounts()
        selectedAccountID = accounts.first?.id
        FloppyDiagnostics.app.info("Loaded \(self.accounts.count, privacy: .public) account(s) from local ledger")
        await refreshSelectedAccount()
    }

    func startBrowserApproval() {
        onboardingTask?.cancel()

        guard let siteURL = URL.floppySiteURL(from: siteURLText), siteURL.host != nil else {
            status = "Enter a valid WordPress site URL."
            return
        }

        guard siteURL.normalizedScheme == "https" else {
            status = "Use an HTTPS WordPress site URL."
            return
        }

        guard let zipURL = URL.floppySiteURL(from: githubPluginZipURLText) else {
            status = FloppyOnboardingError.githubZipRequired.localizedDescription
            return
        }

        do {
            try validateOnboardingAdvancedFields(zipURL: zipURL)
        } catch {
            status = error.localizedDescription
            onboardingStep = .failed
            return
        }

        let state = UUID().uuidString
        let normalizedSiteURL = siteURL.normalizedForDisplay
        pendingOnboarding = PendingOnboarding(siteURL: normalizedSiteURL, state: state)
        persistPendingOnboarding()
        onboardingStep = .waitingForWordPressAuthorization
        lastDownloadedPluginZipURL = nil
        pendingPluginUploadURL = nil

        onboardingTask = Task {
            do {
                let discoveryClient = FloppyAPIClient(siteURL: normalizedSiteURL)
                let root = try await discoveryClient.wordPressRESTRoot()
                guard let authorizationURL = root.authentication?.applicationPasswords?.endpoints.authorization else {
                    status = "This site does not expose WordPress Application Password authorization over HTTPS."
                    onboardingStep = .failed
                    return
                }

                NSWorkspace.shared.open(FloppyAPIClient.applicationPasswordAuthorizationURL(siteURL: normalizedSiteURL, authorizationURL: authorizationURL, state: state, deviceName: deviceName))
                FloppyDiagnostics.onboarding.info("Opened WordPress authorization for \(FloppyDiagnostics.redactedURL(normalizedSiteURL), privacy: .public)")
                status = "Opened WordPress. Approve Floppy so it can finish the GitHub install."
            } catch is CancellationError {
                status = "Setup cancelled."
                onboardingStep = .idle
            } catch {
                status = error.localizedDescription
                onboardingStep = .failed
            }
        }
    }

    func cancelOnboarding() {
        onboardingTask?.cancel()
        onboardingTask = nil
        pendingOnboarding = nil
        clearPendingOnboarding()
        onboardingStep = .idle
        status = "Setup cancelled."
    }

    func revealDownloadedPluginZip() {
        guard let lastDownloadedPluginZipURL else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([lastDownloadedPluginZipURL])
    }

    func openPluginUploadPage() {
        guard let pendingPluginUploadURL else {
            return
        }

        NSWorkspace.shared.open(pendingPluginUploadURL)
    }

    func handleCallback(_ url: URL) {
        Task {
            do {
                if url.host == "wordpress-rejected" {
                    let rejectedState = try FloppyAPIClient.parseRejectionCallback(url)
                    guard let pendingOnboarding, pendingOnboarding.matches(state: rejectedState) else {
                        status = "Ignored a stale Floppy connection rejection."
                        return
                    }
                    self.pendingOnboarding = nil
                    clearPendingOnboarding()
                    onboardingStep = .failed
                    status = "WordPress connection was cancelled."
                    return
                }

                if url.host == "wordpress-authorized" {
                    let credential = try FloppyAPIClient.parseApplicationPasswordCallback(url)
                    try validatePendingOnboarding(state: credential.state, siteURL: credential.siteURL)
                    await finishApplicationPasswordOnboarding(credential)
                    return
                }

                if url.host == "device-approved" {
                    let approval = try FloppyAPIClient.parseApprovalCallback(url)
                    try validatePendingOnboarding(state: approval.state, siteURL: approval.siteURL)
                    await finishDeviceApproval(approval)
                    return
                }

                throw FloppyAPIError.unsupportedCallback
            } catch {
                status = error.localizedDescription
                onboardingStep = .failed
            }
        }
    }

    private func finishApplicationPasswordOnboarding(_ credential: WordPressApplicationCredential) async {
        let bootstrapClient = FloppyAPIClient(siteURL: credential.siteURL, applicationPassword: credential)
        onboardingStep = .installingPlugin

        do {
            let initialState = try await pluginInstallState(client: bootstrapClient)
            if initialState == .missing {
                try await beginGitHubZipInstall(client: bootstrapClient, credential: credential)
                return
            }

            onboardingStep = .activatingPlugin
            if try await pluginInstallState(client: bootstrapClient) == .inactive {
                _ = try await bootstrapClient.activatePlugin(plugin: pluginMainFile)
            }

            try await completeApplicationPasswordOnboarding(client: bootstrapClient, credential: credential)
        } catch {
            await bootstrapClient.deleteCurrentApplicationPassword()
            status = error.localizedDescription
            onboardingStep = .failed
        }
    }

    private func beginGitHubZipInstall(client: FloppyAPIClient, credential: WordPressApplicationCredential) async throws {
        guard let zipURL = URL.floppySiteURL(from: githubPluginZipURLText) else {
            throw FloppyOnboardingError.githubZipRequired
        }
        try validateOnboardingAdvancedFields(zipURL: zipURL)

        onboardingStep = .waitingForManualGitHubInstall
        status = "Downloading the GitHub plugin ZIP."

        let localZip = try await downloadPluginZip(from: zipURL)
        lastDownloadedPluginZipURL = localZip
        pendingPluginUploadURL = credential.siteURL.pluginUploadURL
        NSWorkspace.shared.activateFileViewerSelecting([localZip])
        NSWorkspace.shared.open(credential.siteURL.pluginUploadURL)
        status = "Install the revealed ZIP in WordPress. Floppy will continue after it appears."

        let deadline = Date().addingTimeInterval(10 * 60)
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 3_000_000_000)
            let state = try await pluginInstallState(client: client)
            if state == .inactive {
                onboardingStep = .activatingPlugin
                _ = try await client.activatePlugin(plugin: pluginMainFile)
            }
            if try await pluginInstallState(client: client) == .active {
                try await completeApplicationPasswordOnboarding(client: client, credential: credential)
                return
            }
        }

        await client.deleteCurrentApplicationPassword()
        throw FloppyOnboardingError.githubInstallTimedOut
    }

    private func completeApplicationPasswordOnboarding(client: FloppyAPIClient, credential: WordPressApplicationCredential) async throws {
        onboardingStep = .creatingDeviceToken
        let discovery = try await client.discover()
        let device = try await client.authorizeDevice(deviceName: deviceName)
        await client.deleteCurrentApplicationPassword()

        let account = FloppyAccount(
            siteURL: credential.siteURL,
            restURL: discovery.restURL,
            userHint: credential.userLogin,
            deviceUUID: device.deviceUUID,
            scope: device.scope
        )
        try await saveConnectedAccount(account: account, token: device.token)
        pendingOnboarding = nil
        clearPendingOnboarding()
        pendingPluginUploadURL = nil
        onboardingTask = nil
        onboardingStep = .connected
        status = "GitHub plugin installed and connected \(credential.siteURL.host ?? credential.siteURL.absoluteString)."
    }

    private func downloadPluginZip(from url: URL) async throws -> URL {
        try FloppyGitHubZipValidator.validateReleaseAssetURL(url)

        let request = URLRequest(url: url)
        let (temporaryURL, response) = try await URLSession.shared.download(for: request, delegate: FloppyGitHubZipRedirectDelegate())
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FloppyOnboardingError.githubZipDownloadFailed
        }
        if let finalURL = response.url {
            try FloppyGitHubZipValidator.validateDownloadURL(finalURL)
        }
        try validateGitHubZipResponse(http)

        let downloads = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("FloppyMac", isDirectory: true)
            .appendingPathComponent("PluginZips", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let filename = url.lastPathComponent.isEmpty ? "floppy.zip" : url.lastPathComponent
        let destination = downloads.appendingPathComponent("\(UUID().uuidString)-\(filename)")
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        do {
            let result = try FloppyGitHubZipValidator.validateDownloadedPluginZip(at: destination, mainPluginFile: pluginMainFile)
            FloppyDiagnostics.onboarding.info("Validated GitHub ZIP root \(result.rootDirectory, privacy: .public) with \(result.entryCount, privacy: .public) entries")
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    private func finishDeviceApproval(_ approval: FloppyDeviceApproval) async {
        do {
            let discoveryClient = FloppyAPIClient(siteURL: approval.siteURL)
            let discovery = try await discoveryClient.discover()
            let device: FloppyDeviceAuthorization
            if let exchangeCode = approval.exchangeCode {
                device = try await FloppyAPIClient(siteURL: approval.siteURL, restURL: discovery.restURL).exchangeDeviceCode(code: exchangeCode, state: approval.state)
            } else {
                device = FloppyDeviceAuthorization(deviceUUID: approval.deviceUUID, token: approval.token, scope: approval.scope)
            }
            let account = FloppyAccount(
                siteURL: approval.siteURL,
                restURL: discovery.restURL,
                userHint: "wordpress-user",
                deviceUUID: device.deviceUUID,
                scope: device.scope
            )
            try await saveConnectedAccount(account: account, token: device.token)
            pendingOnboarding = nil
            clearPendingOnboarding()
            onboardingStep = .connected
            status = "Connected to \(approval.siteURL.host ?? approval.siteURL.absoluteString)."
        } catch {
            status = error.localizedDescription
            onboardingStep = .failed
        }
    }

    private func saveConnectedAccount(account: FloppyAccount, token: String) async throws {
        try tokenStore.save(token: token, accountID: account.id)
        try tokenStore.save(token: token, accountID: FloppyDomainRegistry.domainIdentifier(for: account))
        try await ledger?.upsert(account: account)
        try await FileProviderDomainController.register(account: account)
        accounts = await ledger?.accounts() ?? []
        selectedAccountID = account.id
        await refreshSelectedAccount()
        FloppyDiagnostics.app.info("Saved connected account for \(FloppyDiagnostics.redactedURL(account.siteURL), privacy: .public)")
    }

    private func pluginInstallState(client: FloppyAPIClient) async throws -> PluginInstallState {
        do {
            let plugin = try await client.getPlugin(plugin: pluginMainFile)
            return plugin.status == .active ? .active : .inactive
        } catch FloppyAPIError.httpStatus(let status, _) where status == 404 {
            return .missing
        }
    }

    private func validatePendingOnboarding(state: String, siteURL: URL) throws {
        guard let pendingOnboarding else {
            throw FloppyAPIError.unsupportedCallback
        }
        guard pendingOnboarding.matches(state: state), pendingOnboarding.matches(siteURL: siteURL) else {
            throw FloppyAPIError.unsupportedCallback
        }
        guard !pendingOnboarding.isExpired else {
            throw FloppyAPIError.unsupportedCallback
        }
    }

    func refreshSelectedAccount() async {
        guard let account = selectedAccount else {
            items = []
            health = nil
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let client = try client(for: account)
            let list = try await client.listFiles()
            try await ledger?.merge(items: list.items, accountID: account.id)
            items = list.items
            status = "Loaded \(list.items.count) items."
        } catch {
            status = error.localizedDescription
            items = await ledger?.items(accountID: account.id) ?? []
        }
    }

    func syncSelectedAccount() async {
        guard let account = selectedAccount else {
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let client = try client(for: account)
            let changes = try await client.syncChanges(cursor: account.lastCursor)
            try await ledger?.apply(changes: changes.events, accountID: account.id)
            try await ledger?.record(changeFeed: changes, accountID: account.id)
            accounts = await ledger?.accounts() ?? accounts
            items = await ledger?.items(accountID: account.id) ?? items
            await FileProviderDomainController.signal(account: account)
            status = "Synced \(changes.events.count) changes. Cursor \(changes.nextCursor)."
        } catch {
            status = error.localizedDescription
        }
    }

    func loadHealth() async {
        guard let account = selectedAccount else {
            return
        }

        do {
            health = try await client(for: account).health()
            status = health?.ok == true ? "Server health passed." : "Server needs attention."
        } catch {
            status = error.localizedDescription
        }
    }

    func exportDiagnostics() {
        Task {
            do {
                let url = try await makeDiagnosticsBundle()
                NSWorkspace.shared.activateFileViewerSelecting([url])
                status = "Diagnostics exported."
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func makeDiagnosticsBundle() async throws -> URL {
        let account = selectedAccount
        let accountID = account?.id
        let keychainAvailable: Bool
        if let accountID {
            keychainAvailable = ( try? tokenStore.load(accountID: accountID) ) != nil
        } else {
            keychainAvailable = false
        }

        let bundle: [String: Any] = [
            "format": "floppy-mac-diagnostics-v1",
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "app": [
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
                "bundle_id": Bundle.main.bundleIdentifier ?? "unknown"
            ],
            "selected_account": [
                "id": accountID ?? "",
                "site_url": FloppyDiagnostics.redactedURL(account?.siteURL),
                "rest_url": FloppyDiagnostics.redactedURL(account?.restURL),
                "device_uuid": account?.deviceUUID ?? "",
                "scope": account?.scope ?? "",
                "last_cursor": account.map { String($0.lastCursor) } ?? "0",
                "last_sync_at": account?.lastSyncAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
            ],
            "ledger": [
                "path": ledger?.fileURL.path ?? "",
                "accounts": accounts.count,
                "items": items.count,
                "pending_operations": await ledger?.pendingOperationCount(accountID: accountID) ?? 0,
                "conflicts": await ledger?.conflictCount(accountID: accountID) ?? 0,
                "active_enumerators": await ledger?.activeEnumeratorIdentifiers() ?? []
            ],
            "domains": (try? FloppyDomainRegistry.summaries()) ?? [],
            "keychain": [
                "available_for_selected_account": keychainAvailable,
                "access_group_configured": KeychainTokenStore.defaultAccessGroup() != nil
            ],
            "onboarding": [
                "step": String(describing: onboardingStep),
                "has_pending_state": pendingOnboarding != nil,
                "plugin_main_file": pluginMainFile
            ],
            "last_status": status
        ]

        let data = try JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted, .sortedKeys])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FloppyDiagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("floppy-mac-diagnostics-\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: url, options: [.atomic])
        return url
    }

    func disconnectSelectedAccount() {
        guard let account = selectedAccount else {
            return
        }

        Task {
            isWorking = true
            defer { isWorking = false }

            var revokeError: Error?
            do {
                let client = try client(for: account)
                try await client.revokeDevice(deviceUUID: account.deviceUUID)
                FloppyDiagnostics.app.info("Revoked device token for \(FloppyDiagnostics.redactedURL(account.siteURL), privacy: .public)")
            } catch {
                revokeError = error
                FloppyDiagnostics.app.error("Server device revoke failed: \(error.localizedDescription, privacy: .public)")
            }

            do {
                try tokenStore.delete(accountID: account.id)
                try? await FileProviderDomainController.remove(account: account)
                try? tokenStore.delete(accountID: FloppyDomainRegistry.domainIdentifier(for: account))
                try await ledger?.removeAccount(id: account.id)
                accounts = await ledger?.accounts() ?? []
                selectedAccountID = accounts.first?.id
                await refreshSelectedAccount()
                if let revokeError {
                    status = "Disconnected locally. Server revoke failed: \(revokeError.localizedDescription)"
                } else {
                    status = "Revoked and disconnected \(account.siteURL.host ?? account.siteURL.absoluteString)."
                }
            } catch {
                status = error.localizedDescription
            }
        }
    }

    var selectedAccount: FloppyAccount? {
        accounts.first { $0.id == selectedAccountID }
    }

    private func client(for account: FloppyAccount) throws -> FloppyAPIClient {
        guard let token = try tokenStore.load(accountID: account.id) else {
            throw FloppyAPIError.missingToken
        }
        return FloppyAPIClient(siteURL: account.siteURL, restURL: account.restURL, token: token)
    }

    func resetAdvancedOnboardingFields() {
        githubPluginZipURLText = "https://github.com/RegionallyFamous/floppy/releases/latest/download/floppy.zip"
        pluginMainFile = "floppy/floppy.php"
        deviceName = Host.current().localizedName ?? "Mac"
        status = "Advanced setup fields reset."
    }

    private func validateOnboardingAdvancedFields(zipURL: URL) throws {
        try FloppyGitHubZipValidator.validateReleaseAssetURL(zipURL)

        let normalizedMainFile = FloppyGitHubZipValidator.normalizePluginPath(pluginMainFile)
        guard !normalizedMainFile.isEmpty, normalizedMainFile.hasSuffix(".php"), normalizedMainFile.contains("/") else {
            throw FloppyOnboardingError.pluginMainFileRequired
        }
        pluginMainFile = normalizedMainFile

        deviceName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if deviceName.isEmpty {
            deviceName = Host.current().localizedName ?? "Mac"
        }
    }

    private func validateGitHubZipResponse(_ response: HTTPURLResponse) throws {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/html") || contentType.contains("application/json") {
            throw FloppyOnboardingError.githubZipDownloadFailed
        }
    }

    private func persistPendingOnboarding() {
        guard let pendingOnboarding,
              let data = try? JSONEncoder.floppy.encode(pendingOnboarding) else {
            return
        }
        UserDefaults.standard.set(data, forKey: PendingOnboarding.defaultsKey)
    }

    private func restorePendingOnboarding() {
        guard
            let data = UserDefaults.standard.data(forKey: PendingOnboarding.defaultsKey),
            let pending = try? JSONDecoder.floppy.decode(PendingOnboarding.self, from: data),
            !pending.isExpired
        else {
            clearPendingOnboarding()
            return
        }

        pendingOnboarding = pending
        siteURLText = pending.siteURL.absoluteString
        onboardingStep = .waitingForWordPressAuthorization
        status = "Restored an in-progress WordPress approval."
    }

    private func clearPendingOnboarding() {
        UserDefaults.standard.removeObject(forKey: PendingOnboarding.defaultsKey)
    }
}

private enum PluginInstallState: Equatable {
    case missing
    case inactive
    case active
}

enum FloppyOnboardingStep: Equatable {
    case idle
    case waitingForWordPressAuthorization
    case installingPlugin
    case waitingForManualGitHubInstall
    case activatingPlugin
    case creatingDeviceToken
    case connected
    case failed
}

extension FloppyOnboardingStep {
    var title: String {
        switch self {
        case .idle:
            "Ready"
        case .waitingForWordPressAuthorization:
            "Approve in WordPress"
        case .installingPlugin:
            "Prepare GitHub ZIP"
        case .waitingForManualGitHubInstall:
            "Install ZIP"
        case .activatingPlugin:
            "Activate Plugin"
        case .creatingDeviceToken:
            "Secure Device"
        case .connected:
            "Connected"
        case .failed:
            "Needs Attention"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            "Enter your site and GitHub ZIP URL."
        case .waitingForWordPressAuthorization:
            "WordPress is asking you to approve a temporary Application Password."
        case .installingPlugin:
            "Floppy is preparing the plugin ZIP for upload."
        case .waitingForManualGitHubInstall:
            "Install the revealed ZIP in the WordPress upload screen."
        case .activatingPlugin:
            "Floppy found the plugin and is activating it."
        case .creatingDeviceToken:
            "Floppy is replacing the temporary credential with a scoped device token."
        case .connected:
            "This Mac can now sync through the Floppy REST API."
        case .failed:
            "Review the status message and try again."
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "circle"
        case .waitingForWordPressAuthorization:
            "safari"
        case .installingPlugin:
            "arrow.down.doc"
        case .waitingForManualGitHubInstall:
            "shippingbox"
        case .activatingPlugin:
            "powerplug"
        case .creatingDeviceToken:
            "key"
        case .connected:
            "checkmark.seal"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var isActiveSetupStep: Bool {
        switch self {
        case .waitingForWordPressAuthorization, .installingPlugin, .waitingForManualGitHubInstall, .activatingPlugin, .creatingDeviceToken:
            true
        default:
            false
        }
    }
}

enum FloppyOnboardingError: LocalizedError {
    case githubZipRequired
    case githubZipDownloadFailed
    case githubInstallTimedOut
    case pluginMainFileRequired

    var errorDescription: String? {
        switch self {
        case .githubZipRequired:
            "Enter an HTTPS GitHub release ZIP URL for the plugin."
        case .githubZipDownloadFailed:
            "Could not download the GitHub plugin ZIP."
        case .githubInstallTimedOut:
            "Timed out waiting for the GitHub plugin ZIP to be installed in WordPress."
        case .pluginMainFileRequired:
            "Enter the plugin main file inside the ZIP, for example floppy/floppy.php."
        }
    }
}

private struct PendingOnboarding: Codable {
    static let defaultsKey = "FloppyPendingOnboarding"

    let siteURL: URL
    let state: String
    let expiresAt: Date

    init(siteURL: URL, state: String, expiresAt: Date = Date().addingTimeInterval(10 * 60)) {
        self.siteURL = siteURL
        self.state = state
        self.expiresAt = expiresAt
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    func matches(state: String) -> Bool {
        self.state == state
    }

    func matches(siteURL: URL) -> Bool {
        self.siteURL.normalizedForDisplay.absoluteString == siteURL.normalizedForDisplay.absoluteString
    }
}

private extension URL {
    static func floppySiteURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if URLComponents(string: trimmed)?.scheme == nil {
            return URL(string: "https://\(trimmed)")?.normalizedForDisplay
        }

        return URL(string: trimmed)?.normalizedForDisplay
    }

    var normalizedScheme: String {
        (URLComponents(url: self, resolvingAgainstBaseURL: false)?.scheme ?? "https").lowercased()
    }

    var normalizedForDisplay: URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false) ?? URLComponents()
        if components.scheme == nil {
            components.scheme = "https"
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return components.url ?? self
    }

    var pluginUploadURL: URL {
        var components = URLComponents(url: appendingPathComponent("wp-admin/plugin-install.php"), resolvingAgainstBaseURL: false) ?? URLComponents()
        components.queryItems = [URLQueryItem(name: "tab", value: "upload")]
        return components.url ?? self
    }
}
