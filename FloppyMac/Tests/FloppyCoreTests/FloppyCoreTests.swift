import Foundation
import Testing
@testable import FloppyCore

@Test func approvalURLContainsExpectedParameters() throws {
    let url = FloppyAPIClient.approvalURL(siteURL: URL(string: "https://example.com")!, state: "abc", deviceName: "Studio Mac")
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

    #expect(url.absoluteString.hasPrefix("https://example.com/wp-admin/admin.php"))
    #expect(items["page"] == "floppy")
    #expect(items["floppy-device-approval"] == "1")
    #expect(items["state"] == "abc")
    #expect(items["callback"] == "floppy://device-approved")
}

@Test func applicationPasswordURLContainsExpectedParameters() throws {
    let url = FloppyAPIClient.applicationPasswordAuthorizationURL(
        siteURL: URL(string: "https://example.com")!,
        authorizationURL: URL(string: "https://example.com/wp-admin/authorize-application.php")!,
        state: "abc",
        deviceName: "Studio Mac"
    )
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

    #expect(url.absoluteString.hasPrefix("https://example.com/wp-admin/authorize-application.php"))
    #expect(items["app_name"] == "Floppy for Mac - Studio Mac")
    #expect(items["success_url"] == "floppy://wordpress-authorized?state=abc")
    #expect(items["reject_url"] == "floppy://wordpress-rejected?state=abc")
}

@Test func wordpressPluginRoutesUseCoreRestPluginIdentifiers() throws {
    #expect(FloppyAPIClient.wordpressPluginPath(for: "floppy/floppy.php") == "plugins/floppy/floppy")
    #expect(FloppyAPIClient.wordpressPluginPath(for: "hello.php") == "plugins/hello")

    let url = FloppyAPIClient.wordPressURL(
        siteURL: URL(string: "http://localhost:8892")!,
        path: FloppyAPIClient.wordpressPluginPath(for: "floppy/floppy.php")
    )

    #expect(url.absoluteString == "http://localhost:8892/wp-json/wp/v2/plugins/floppy/floppy")
}

@Test func parsesApplicationPasswordCallback() throws {
    let url = URL(string: "floppy://wordpress-authorized?state=abc&site_url=https%3A%2F%2Fexample.com&user_login=admin&password=abcdEFGH1234")!
    let credential = try FloppyAPIClient.parseApplicationPasswordCallback(url)

    #expect(credential.siteURL.absoluteString == "https://example.com")
    #expect(credential.userLogin == "admin")
    #expect(credential.password == "abcdEFGH1234")
    #expect(credential.state == "abc")
    #expect(credential.basicAuthorizationHeader.hasPrefix("Basic "))
}

@Test func rejectsDuplicateCallbackParameters() throws {
    let url = URL(string: "floppy://wordpress-authorized?state=abc&state=def&site_url=https%3A%2F%2Fexample.com&user_login=admin&password=abcd")!

    do {
        _ = try FloppyAPIClient.parseApplicationPasswordCallback(url)
        Issue.record("Expected duplicate state parameter to be rejected.")
    } catch FloppyAPIError.duplicateCallbackParameter(let name) {
        #expect(name == "state")
    } catch {
        Issue.record("Expected duplicate parameter error, got \(error).")
    }
}

@Test func rejectsRawTokenApprovalCallbackByDefault() throws {
    let url = URL(string: "floppy://device-approved?site=https%3A%2F%2Fexample.com&device_uuid=dev-1&token=flp_secret&scope=files%3Aread%2Cfiles%3Awrite%2Csync&state=abc")!
    do {
        _ = try FloppyAPIClient.parseApprovalCallback(url)
        Issue.record("Expected raw device-token callbacks to be rejected by default.")
    } catch FloppyAPIError.invalidResponse {
    } catch {
        Issue.record("Expected invalid response, got \(error).")
    }
}

@Test func parsesDeviceCodeApprovalCallback() throws {
    let url = URL(string: "floppy://device-approved?site=https%3A%2F%2Fexample.com&code=flc_abc123&state=abc")!
    let approval = try FloppyAPIClient.parseApprovalCallback(url)

    #expect(approval.siteURL.absoluteString == "https://example.com")
    #expect(approval.exchangeCode == "flc_abc123")
    #expect(approval.requiresCodeExchange == true)
    #expect(approval.state == "abc")
}

@Test func decodesItem() throws {
    let json = """
    {
      "kind": "file",
      "id": 12,
      "uuid": "file-uuid",
      "attachment_id": 44,
      "owner_id": 1,
      "parent_id": 0,
      "parent_uuid": "",
      "name": "hello.txt",
      "mime_type": "text/plain",
      "size_bytes": 5,
      "content_hash": "abc",
      "content_version": "cv",
      "metadata_version": "mv",
      "status": "active",
      "visibility": "private",
      "download_url": "https://example.com/wp-json/floppy/v1/files/12/download",
      "created_at_gmt": "2026-05-22 00:00:00",
      "updated_at_gmt": "2026-05-22 00:00:00"
    }
    """.data(using: .utf8)!

    let item = try JSONDecoder.floppy.decode(FloppyItem.self, from: json)
    #expect(item.kind == .file)
    #expect(item.name == "hello.txt")
    #expect(item.parentUUID == "")
    #expect(item.downloadURL?.path.contains("/floppy/v1/files/12/download") == true)
}

@Test func decodesUploadSession() throws {
    let json = """
    {
      "session_uuid": "session-uuid",
      "received_bytes": 0,
      "chunk_size": 8388608,
      "operation": "replace",
      "expires_at_gmt": "2026-05-23 00:00:00"
    }
    """.data(using: .utf8)!

    let session = try JSONDecoder.floppy.decode(FloppyUploadSession.self, from: json)
    #expect(session.sessionUUID == "session-uuid")
    #expect(session.chunkSize == 8_388_608)
    #expect(session.operation == "replace")
}

@Test func replaceFileUsesResumableUploadSession() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("hello.txt")
    try "hello".data(using: .utf8)!.write(to: fileURL)
    var paths: [String] = []
    var chunkBodies: [String] = []
    URLProtocolStub.handler = { request in
        paths.append(request.url?.path ?? "")
        if request.url?.path.hasSuffix("/files/12/replace-sessions") == true {
            return httpJSON(request, status: 201, body: """
            {"session_uuid":"session-uuid","received_bytes":0,"chunk_size":4,"operation":"replace","expires_at_gmt":"2026-05-23 00:00:00"}
            """)
        }
        if request.url?.path.hasSuffix("/upload-sessions/session-uuid/chunk") == true {
            let body = String(data: requestBodyData(request), encoding: .utf8) ?? ""
            chunkBodies.append(body)
            let received = chunkBodies.joined().utf8.count
            return httpJSON(request, body: "{\"received_bytes\":\(received)}")
        }
        if request.url?.path.hasSuffix("/upload-sessions/session-uuid/complete") == true {
            return httpJSON(request, body: sampleItemJSON(id: 12, uuid: "file-uuid", name: "hello.txt", size: 5))
        }
        return httpJSON(request, status: 404, body: "{}")
    }
    defer { URLProtocolStub.handler = nil }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    let client = FloppyAPIClient(siteURL: URL(string: "https://example.com")!, token: "secret", session: URLSession(configuration: configuration))
    let item = try await client.replaceFile(id: 12, at: fileURL, filename: "hello.txt", contentVersion: "cv", mimeType: "text/plain")

    #expect(item.id == 12)
    #expect(paths.contains { $0.hasSuffix("/files/12/replace-sessions") })
    #expect(paths.contains { $0.hasSuffix("/upload-sessions/session-uuid/complete") })
    #expect(!paths.contains { $0.hasSuffix("/files/12/replace") })
    #expect(chunkBodies == ["hell", "o"])
}

@Test func uploadSessionRejectsUnexpectedServerOffsets() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("hello.txt")
    try "hello".data(using: .utf8)!.write(to: fileURL)
    UploadOffsetURLProtocolStub.handler = { request in
        if request.url?.path.hasSuffix("/upload-sessions/session-uuid/chunk") == true {
            return httpJSON(request, body: #"{"received_bytes":3}"#)
        }
        return httpJSON(request, status: 404, body: "{}")
    }
    defer { UploadOffsetURLProtocolStub.handler = nil }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UploadOffsetURLProtocolStub.self]
    let client = FloppyAPIClient(siteURL: URL(string: "https://example.com")!, token: "secret", session: URLSession(configuration: configuration))
    let session = FloppyUploadSession(sessionUUID: "session-uuid", receivedBytes: 0, chunkSize: 4, operation: "upload", expiresAtGMT: "2026-05-23 00:00:00")

    do {
        _ = try await client.uploadChunks(from: fileURL, session: session, totalSize: 5)
        Issue.record("Expected unexpected upload offset to fail.")
    } catch FloppyTransferError.unexpectedUploadOffset(let expected, let actual) {
        #expect(expected == 4)
        #expect(actual == 3)
    } catch {
        Issue.record("Expected unexpected upload offset error, got \(error).")
    }
}

@Test func fileProviderIdentifierCodecUsesStableUUIDs() throws {
    let rawValue = FloppyFileProviderIdentifierCodec.itemIdentifierRawValue(uuid: "file-uuid")

    #expect(rawValue == "floppy:item:file-uuid")
    #expect(FloppyFileProviderIdentifierCodec.itemUUID(from: rawValue) == "file-uuid")
    #expect(FloppyFileProviderIdentifierCodec.legacyItemID(from: "floppy:item:12") == 12)
    #expect(FloppyFileProviderIdentifierCodec.itemUUID(from: "floppy:item:12") == nil)
}

@Test func syncCadenceCoalescesAutomaticAndCacheRefreshWork() throws {
    let cadence = FloppyMacSyncCadence(minimumAutomaticSyncInterval: 20, cacheRefreshTTL: 12)
    let now = Date(timeIntervalSinceReferenceDate: 1_000)

    #expect(cadence.shouldRunAutomaticSync(now: now, lastAutomaticSyncAt: nil, hasAccount: true, isNetworkReachable: true, isWorking: false, isOnboarding: false))
    #expect(!cadence.shouldRunAutomaticSync(now: now, lastAutomaticSyncAt: now.addingTimeInterval(-5), hasAccount: true, isNetworkReachable: true, isWorking: false, isOnboarding: false))
    #expect(!cadence.shouldRunAutomaticSync(now: now, lastAutomaticSyncAt: nil, hasAccount: true, isNetworkReachable: false, isWorking: false, isOnboarding: false))
    #expect(cadence.shouldRefreshCache(now: now, lastRefreshAt: nil, hasAccount: true))
    #expect(!cadence.shouldRefreshCache(now: now, lastRefreshAt: now.addingTimeInterval(-2), hasAccount: true))
}

@Test func diagnosticsStatusRedactsFilenamesAndLocalPaths() throws {
    let homePath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Secret/report.pdf").path
    let redacted = FloppyDiagnostics.redactedStatus("Uploading client-list.csv from \(homePath)")

    #expect(redacted.contains("[redacted-file]"))
    #expect(!redacted.contains("client-list.csv"))
    #expect(!redacted.contains("report.pdf"))
    #expect(!redacted.contains(FileManager.default.homeDirectoryForCurrentUser.path))
}

@Test func enumeratorSignalPlanDeduplicatesWorkingSetAndActiveFolders() throws {
    let plan = FloppyEnumeratorSignalPlan(
        workingSetIdentifier: "working-set",
        activeEnumerators: ["folder-a", "working-set", "", "folder-b", "folder-a"]
    )

    #expect(plan.rawIdentifiers == ["working-set", "folder-a", "folder-b"])
}

@Test func diagnosticsBundleV2RedactsCorrelationAndAccountSecrets() throws {
    let account = FloppyAccount(
        siteURL: URL(string: "https://user:password@example.com/wp?token=secret#fragment")!,
        restURL: URL(string: "https://example.com/wp-json/floppy/v1?token=secret")!,
        userHint: "admin@example.com",
        deviceUUID: "device-secret-uuid",
        scope: "files:read,files:write",
        lastCursor: 42
    )
    let bundle = FloppyMacDiagnosticsBundleV2(
        createdAt: "2026-05-22T00:00:00Z",
        support: FloppyDiagnostics.supportCorrelation(account: account, domainIdentifier: "floppy-device-secret-uuid"),
        app: FloppyMacDiagnosticsAppInfo(version: "dev", bundleID: "com.floppy.mac"),
        selectedAccount: FloppyMacDiagnosticsSelectedAccount(account: account, lastSyncAt: ""),
        ledger: FloppyMacDiagnosticsLedgerInfo(
            path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FloppyMac/ledger.sqlite").path,
            accounts: 1,
            items: 0,
            pendingOperations: 0,
            conflicts: 0,
            activeEnumerators: [],
            conflictDiagnostics: .empty(accountID: account.id),
            integrity: .empty(accountID: account.id)
        ),
        domains: [
            [
                "domain_identifier_fingerprint": FloppyDiagnostics.redactedFingerprint("floppy-device-secret-uuid"),
                "account_fingerprint": FloppyDiagnostics.redactedFingerprint(account.id),
                "site_url": FloppyDiagnostics.redactedURL(account.siteURL),
                "rest_url": FloppyDiagnostics.redactedURL(account.restURL),
                "display_name": "Floppy - example.com"
            ]
        ],
        keychain: FloppyMacDiagnosticsKeychainInfo(
            availableForSelectedAccount: true,
            accessGroupConfigured: true,
            dataProtectionKeychain: true,
            interactivePromptsDisabled: true
        ),
        onboarding: FloppyMacDiagnosticsOnboardingInfo(step: "idle", hasPendingState: false, pluginMainFile: "floppy/floppy.php"),
        fileProvider: FloppyFileProviderLifecycleDiagnostic(
            state: .configured,
            message: "ready",
            domainIdentifierFingerprint: FloppyDiagnostics.redactedFingerprint("floppy-device-secret-uuid"),
            displayName: "Floppy - example.com",
            readinessStatus: "ready",
            registeredInLocalRegistry: true,
            keychainTokenAvailable: true,
            ledgerOK: true,
            activeEnumeratorCount: 0
        ),
        lastStatus: "Ready"
    )

    let data = try JSONEncoder.floppy.encode(bundle)
    let json = String(data: data, encoding: .utf8) ?? ""

    #expect(json.contains("\"format\":\"floppy-mac-diagnostics-v2\""))
    #expect(json.contains("correlation_id"))
    #expect(json.contains("device_uuid_fingerprint"))
    #expect(!json.contains("device-secret-uuid"))
    #expect(!json.contains("password"))
    #expect(!json.contains("token=secret"))
    #expect(!json.contains(FileManager.default.homeDirectoryForCurrentUser.path))
}

@Test func diagnosticsBundleV3IncludesSyncConflictMaterializationAndReleaseFields() throws {
    let account = FloppyAccount(
        siteURL: URL(string: "https://user:password@example.com/wp?token=secret#fragment")!,
        restURL: URL(string: "https://example.com/wp-json/floppy/v1?token=secret")!,
        userHint: "admin@example.com",
        deviceUUID: "device-secret-uuid",
        scope: "files:read,files:write",
        lastCursor: 42
    )
    let decision = FloppyRecoveryDecision(
        state: .conflict,
        message: "Resolve conflicts.",
        actions: [.resolveConflicts, .retrySync]
    )
    let bundle = FloppyMacDiagnosticsBundleV3(
        createdAt: "2026-05-22T00:00:00Z",
        support: FloppyDiagnostics.supportCorrelation(account: account, domainIdentifier: "floppy-device-secret-uuid"),
        app: FloppyMacDiagnosticsAppInfo(version: "dev", bundleID: "com.floppy.mac"),
        selectedAccount: FloppyMacDiagnosticsSelectedAccount(account: account, lastSyncAt: "2026-05-22T01:00:00Z"),
        ledger: FloppyMacDiagnosticsLedgerInfo(
            path: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FloppyMac/ledger.sqlite").path,
            accounts: 1,
            items: 2,
            pendingOperations: 1,
            conflicts: 1,
            activeEnumerators: ["floppy:item:folder-uuid"],
            conflictDiagnostics: FloppyLedgerConflictDiagnostics(
                accountFingerprint: FloppyDiagnostics.redactedFingerprint(account.id),
                totalCount: 1,
                openCount: 1,
                resolvedCount: 0,
                materializedOpenCount: 1,
                missingMaterializedOpenCount: 0,
                missingItemRecordCount: 0,
                reasons: [FloppyConflictReasonCount(reason: "HTTP 409", count: 1)]
            ),
            integrity: .empty(accountID: account.id)
        ),
        domains: [],
        keychain: FloppyMacDiagnosticsKeychainInfo(
            availableForSelectedAccount: true,
            accessGroupConfigured: true,
            dataProtectionKeychain: true,
            interactivePromptsDisabled: true
        ),
        onboarding: FloppyMacDiagnosticsOnboardingInfo(step: "idle", hasPendingState: false, pluginMainFile: "floppy/floppy.php"),
        fileProvider: FloppyFileProviderLifecycleDiagnostic(
            state: .configured,
            message: "ready",
            domainIdentifierFingerprint: FloppyDiagnostics.redactedFingerprint("floppy-device-secret-uuid"),
            displayName: "Floppy - example.com",
            readinessStatus: "ready",
            registeredInLocalRegistry: true,
            keychainTokenAvailable: true,
            ledgerOK: true,
            activeEnumeratorCount: 1
        ),
        finderSync: FloppyMacDiagnosticsFinderSyncInfo(
            decision: decision,
            pendingOperations: 1,
            openConflicts: 1,
            activeEnumerators: 1,
            lastCursor: "42",
            lastSyncAt: "2026-05-22T01:00:00Z"
        ),
        conflictCenter: FloppyMacDiagnosticsConflictCenterInfo(
            summary: FloppyConflictCenterSummary(total: 1, open: 1, resolved: 0, missingLocalCopies: 0),
            recent: []
        ),
        materialization: FloppyMacDiagnosticsMaterializationInfo(retries: 2, checksumFailures: 1, partialFileQuarantineCount: 1, lastFailure: "checksum mismatch"),
        versionRestores: FloppyMacDiagnosticsVersionRestoreInfo(supportedByServer: "unknown", restoresAttempted: 0),
        releaseBuild: FloppyReleaseBuildIdentity(version: "0.1.0", build: "1", bundleID: "com.floppy.mac", appGroupIdentifier: "group.com.floppy.mac", executablePath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Floppy.app/Contents/MacOS/Floppy").path, isSwiftPMBundle: false),
        releaseEvidence: FloppyReleaseEvidenceSummary(passed: 8, warnings: 0, failed: 0, skipped: 0, readyForPublicBeta: true),
        serverHealth: FloppyMacDiagnosticsServerHealthInfo(checkedAt: "2026-05-22T01:00:00Z", ok: false, failedChecks: 1, lastError: "Uploading secret.pdf failed"),
        nativeRuntime: FloppyMacDiagnosticsNativeRuntimeInfo(launchAtLogin: "Enabled", backgroundSyncEnabled: true, networkReachable: true, lastAutomaticSyncAt: "2026-05-22T01:00:00Z", lastRefreshAt: "2026-05-22T01:00:00Z", lastSyncTrigger: "Background sync", lastSyncError: "Could not upload private.csv", syncInProgress: false, openConflicts: 1, pendingTransfers: 1),
        lastStatus: "Ready"
    )

    let data = try JSONEncoder.floppy.encode(bundle)
    let json = String(data: data, encoding: .utf8) ?? ""

    #expect(json.contains("\"format\":\"floppy-mac-diagnostics-v3\""))
    #expect(json.contains("finder_sync"))
    #expect(json.contains("conflict_center"))
    #expect(json.contains("checksum_failures"))
    #expect(json.contains("version_restores"))
    #expect(json.contains("release_build"))
    #expect(json.contains("release_evidence"))
    #expect(json.contains("native_runtime"))
    #expect(json.contains("server_health"))
    #expect(json.contains("pending_transfers"))
    #expect(!json.contains("device-secret-uuid"))
    #expect(!json.contains("password"))
    #expect(!json.contains("token=secret"))
    #expect(!json.contains("secret.pdf"))
    #expect(!json.contains("private.csv"))
    #expect(!json.contains(FileManager.default.homeDirectoryForCurrentUser.path))
}

@Test func recoveryPlannerMapsDeterministicStatesToActions() throws {
    let noAccount = FloppyRecoveryPlanner.decision(for: FloppyRecoveryContext(
        lifecycleState: .unconfigured,
        hasSelectedAccount: false,
        keychainTokenAvailable: false
    ))
    #expect(noAccount.state == .unconfigured)
    #expect(noAccount.actions == [.connectAccount])

    let revoked = FloppyRecoveryPlanner.decision(for: FloppyRecoveryContext(
        lifecycleState: .revokedToken,
        hasSelectedAccount: true,
        keychainTokenAvailable: false
    ))
    #expect(revoked.state == .authNeeded)
    #expect(revoked.actions.contains(.reconnectSite))

    let corruptLedger = FloppyRecoveryPlanner.decision(for: FloppyRecoveryContext(
        lifecycleState: .needsLedgerRepair,
        hasSelectedAccount: true,
        keychainTokenAvailable: true,
        materializationIssueCount: 1
    ))
    #expect(corruptLedger.state == .repairNeeded)
    #expect(corruptLedger.actions.contains(.repairLedger))

    let unreachable = FloppyRecoveryPlanner.decision(for: FloppyRecoveryContext(
        lifecycleState: .configured,
        hasSelectedAccount: true,
        keychainTokenAvailable: true,
        serverReachable: false,
        lastError: "Server unreachable."
    ))
    #expect(unreachable.state == .offline)
    #expect(unreachable.actions.contains(.waitForNetwork))

    let current = FloppyRecoveryPlanner.decision(for: FloppyRecoveryContext(
        lifecycleState: .configured,
        hasSelectedAccount: true,
        keychainTokenAvailable: true
    ))
    #expect(current.state == .current)
    #expect(current.actions.isEmpty)
}

@Test func downloadOriginPolicyRejectsForeignHosts() throws {
    let policy = FloppyDownloadOriginPolicy(
        siteURL: URL(string: "https://example.com")!,
        restURL: URL(string: "https://example.com/wp-json/floppy/v1")!
    )

    try policy.validate(URL(string: "https://example.com/wp-json/floppy/v1/files/12/download")!)

    do {
        try policy.validate(URL(string: "https://evil.example/file")!)
        Issue.record("Expected foreign host to be rejected.")
    } catch FloppyDownloadSecurityError.untrustedDownloadURL {
    } catch {
        Issue.record("Expected untrusted download URL error, got \(error).")
    }
}

@Test func validatesGitHubReleaseZipURLs() throws {
    try FloppyGitHubZipValidator.validateReleaseAssetURL(URL(string: "https://github.com/RegionallyFamous/floppy/releases/latest/download/floppy.zip")!)

    do {
        try FloppyGitHubZipValidator.validateReleaseAssetURL(URL(string: "https://example.com/floppy.zip")!)
        Issue.record("Expected non-GitHub ZIP URL to be rejected.")
    } catch FloppyDownloadSecurityError.invalidGitHubReleaseURL {
    } catch {
        Issue.record("Expected invalid GitHub release URL error, got \(error).")
    }
}

@Test func validatesPluginZipContents() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let zipURL = directory.appendingPathComponent("floppy.zip")
    try makeTestZip(entries: ["floppy/", "floppy/floppy.php", "floppy/readme.txt"]).write(to: zipURL)

    let result = try FloppyGitHubZipValidator.validateDownloadedPluginZip(at: zipURL, mainPluginFile: "floppy/floppy.php")
    #expect(result.rootDirectory == "floppy")
    #expect(result.entryCount == 2)
}

@Test func sqliteLedgerMigratesLegacyJSONSnapshot() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let account = FloppyAccount(
        siteURL: URL(string: "https://example.com")!,
        restURL: URL(string: "https://example.com/wp-json/floppy/v1")!,
        userHint: "admin",
        deviceUUID: "device-uuid",
        scope: "files:read"
    )
    let item = sampleItem(uuid: "file-uuid", id: 12, name: "hello.txt")
    let snapshot = FloppyLedgerSnapshot(accounts: [account], itemsByAccount: [account.id: [item.uuid: item]])
    try JSONEncoder.floppy.encode(snapshot).write(to: directory.appendingPathComponent("ledger.json"))

    let ledger = LocalLedger(fileURL: directory.appendingPathComponent("ledger.sqlite"))
    let accounts = await ledger.accounts()
    let migratedItems = await ledger.items(accountID: account.id)
    await ledger.close()

    #expect(accounts == [account])
    #expect(migratedItems == [item])
}

@Test func sqliteLedgerStoresLocalConflictItemsAndActiveEnumerators() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let account = FloppyAccount(
        siteURL: URL(string: "https://example.com")!,
        restURL: URL(string: "https://example.com/wp-json/floppy/v1")!,
        userHint: "admin",
        deviceUUID: "device-uuid",
        scope: "files:read,files:write"
    )
    let ledger = LocalLedger(fileURL: directory.appendingPathComponent("ledger.sqlite"))
    try await ledger.upsert(account: account)

    let conflictItem = sampleItem(uuid: "local-conflict-\(UUID().uuidString)", id: 0, name: "hello (Floppy conflict 2026-05-22 10.00.00).txt")
    let materializedURL = try await ledger.conflictFileURL(uuid: conflictItem.uuid, filename: conflictItem.name)
    try "edited".data(using: .utf8)!.write(to: materializedURL)
    let conflict = FloppyConflict(
        accountID: "",
        itemUUID: conflictItem.uuid,
        message: "Server copy changed before Finder edit uploaded.",
        displayName: conflictItem.name,
        parentID: conflictItem.parentID,
        parentUUID: conflictItem.parentUUID,
        materializedPath: materializedURL.path,
        originalContentVersion: "cv"
    )

    try await ledger.recordConflict(conflict: conflict, item: conflictItem, localURL: materializedURL, accountID: account.id)
    await ledger.recordActiveEnumerator("floppy:item:folder-uuid")
    let storedConflict = await ledger.item(uuid: conflictItem.uuid, accountID: account.id)
    let conflictCount = await ledger.conflictCount(accountID: account.id)
    let activeEnumerators = await ledger.activeEnumeratorIdentifiers()
    let storedURL = await ledger.materializedURL(for: conflictItem, accountID: account.id)
    await ledger.close()

    #expect(storedConflict?.uuid == conflictItem.uuid)
    #expect(conflictCount == 1)
    #expect(activeEnumerators == ["floppy:item:folder-uuid"])
    #expect(storedURL?.path == materializedURL.path)
}

@Test func sqliteLedgerPersistsResumableUploadSessions() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let account = FloppyAccount(
        siteURL: URL(string: "https://example.com")!,
        restURL: URL(string: "https://example.com/wp-json/floppy/v1")!,
        userHint: "admin",
        deviceUUID: "device-uuid",
        scope: "files:read,files:write"
    )
    let ledger = LocalLedger(fileURL: directory.appendingPathComponent("ledger.sqlite"))
    try await ledger.upsert(account: account)

    let transfer = FloppyUploadTransferSession(
        accountID: account.id,
        sessionUUID: "session-uuid",
        operation: "replace",
        itemUUID: "file-uuid",
        fileID: 12,
        localPath: directory.appendingPathComponent("hello.txt").path,
        totalSize: 1024,
        offset: 0,
        chunkSize: 256,
        expiresAtGMT: "2026-05-23 00:00:00",
        idempotencyKey: "session-uuid-0"
    )

    try await ledger.saveUploadTransferSession(transfer)
    try await ledger.updateUploadTransferSession(sessionUUID: transfer.sessionUUID, offset: 512, accountID: account.id)
    let stored = await ledger.uploadTransferSessions(accountID: account.id)
    try await ledger.removeUploadTransferSession(sessionUUID: transfer.sessionUUID, accountID: account.id)
    let removed = await ledger.uploadTransferSessions(accountID: account.id)
    await ledger.close()

    #expect(stored.count == 1)
    #expect(stored[0].sessionUUID == transfer.sessionUUID)
    #expect(stored[0].operation == "replace")
    #expect(stored[0].offset == 512)
    #expect(stored[0].chunkSize == 256)
    #expect(stored[0].expiresAtGMT == "2026-05-23 00:00:00")
    #expect(stored[0].idempotencyKey == "session-uuid-0")
    #expect(removed.isEmpty)
}

@Test func sqliteLedgerReportsIntegrityAndConflictDiagnostics() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let account = FloppyAccount(
        siteURL: URL(string: "https://example.com")!,
        restURL: URL(string: "https://example.com/wp-json/floppy/v1")!,
        userHint: "admin",
        deviceUUID: "device-uuid",
        scope: "files:read,files:write"
    )
    let ledger = LocalLedger(fileURL: directory.appendingPathComponent("ledger.sqlite"))
    try await ledger.upsert(account: account)

    let item = sampleItem(uuid: "file-uuid", id: 12, name: "hello.txt")
    let missingMaterializedURL = directory.appendingPathComponent("missing-materialized.txt")
    try await ledger.markMaterialized(item: item, localURL: missingMaterializedURL)

    let missingConflictURL = directory.appendingPathComponent("missing-conflict.txt")
    let conflictItem = sampleItem(uuid: "local-conflict-\(UUID().uuidString)", id: -1, name: "hello (Floppy conflict 2026-05-22 10.00.00).txt")
    let conflict = FloppyConflict(
        accountID: "",
        itemUUID: conflictItem.uuid,
        message: "HTTP 409 while replacing a stale Finder edit.",
        displayName: conflictItem.name,
        parentID: conflictItem.parentID,
        parentUUID: conflictItem.parentUUID,
        materializedPath: missingConflictURL.path,
        originalContentVersion: "cv"
    )
    try await ledger.recordConflict(conflict: conflict, item: conflictItem, localURL: missingConflictURL, accountID: account.id)
    await ledger.recordActiveEnumerator("floppy:item:folder-uuid")

    let conflictDiagnostics = await ledger.conflictDiagnostics(accountID: account.id)
    let integrity = await ledger.integrityReport(accountID: account.id)
    await ledger.close()

    #expect(conflictDiagnostics.openCount == 1)
    #expect(conflictDiagnostics.missingMaterializedOpenCount == 1)
    #expect(conflictDiagnostics.reasons.first?.reason == "HTTP 409 while replacing a stale Finder edit.")
    #expect(integrity.ok == false)
    #expect(integrity.counts.items == 2)
    #expect(integrity.counts.activeEnumerators == 1)
    #expect(integrity.issues.contains { $0.code == "missing_materialized_files" })
    #expect(integrity.issues.contains { $0.code == "missing_conflict_files" })
}

@Test func sqliteLedgerListsConflictCenterItemsAndResolvesLocalConflicts() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let account = FloppyAccount(
        siteURL: URL(string: "https://example.com")!,
        restURL: URL(string: "https://example.com/wp-json/floppy/v1")!,
        userHint: "admin",
        deviceUUID: "device-uuid",
        scope: "files:read,files:write"
    )
    let ledger = LocalLedger(fileURL: directory.appendingPathComponent("ledger.sqlite"))
    try await ledger.upsert(account: account)

    let conflictItem = sampleItem(uuid: "local-conflict-\(UUID().uuidString)", id: -1, name: "hello conflict.txt")
    let materializedURL = try await ledger.conflictFileURL(uuid: conflictItem.uuid, filename: conflictItem.name)
    try "edited".data(using: .utf8)!.write(to: materializedURL)
    let conflictID = UUID()
    let conflict = FloppyConflict(
        id: conflictID,
        accountID: "",
        itemUUID: conflictItem.uuid,
        message: "HTTP 428 while replacing a stale Finder edit.",
        displayName: conflictItem.name,
        parentID: conflictItem.parentID,
        parentUUID: conflictItem.parentUUID,
        materializedPath: materializedURL.path,
        originalContentVersion: "server-secret-version",
        state: "open"
    )

    try await ledger.recordConflict(conflict: conflict, item: conflictItem, localURL: materializedURL, accountID: account.id)
    let centerItems = await ledger.conflictCenterItems(accountID: account.id)
    #expect(centerItems.count == 1)
    #expect(centerItems[0].displayName == "hello conflict.txt")
    #expect(centerItems[0].materializedFileExists)
    #expect(centerItems[0].availableActions.contains(.retryUpload))
    #expect(centerItems[0].availableActions.contains(.discardLocalCopy))
    #expect(!centerItems[0].originalContentVersionFingerprint.contains("server-secret-version"))

    try await ledger.discardLocalConflictCopy(id: conflictID, accountID: account.id)
    let resolved = await ledger.conflictDiagnostics(accountID: account.id)
    await ledger.close()

    #expect(resolved.openCount == 0)
    #expect(resolved.resolvedCount == 1)
    #expect(!FileManager.default.fileExists(atPath: materializedURL.path))
}

@Test func conflictApiHelpersUseFutureCompatibleRoutes() async throws {
    var requested: [(method: String, path: String, body: String)] = []
    ConflictURLProtocolStub.handler = { request in
        requested.append((
            method: request.httpMethod ?? "",
            path: request.url?.path ?? "",
            body: String(data: requestBodyData(request), encoding: .utf8) ?? ""
        ))
        if request.url?.path.hasSuffix("/conflicts") == true {
            return httpJSON(request, body: #"{"conflicts":[],"next_cursor":null,"has_more":false}"#)
        }
        if request.url?.path.hasSuffix("/conflicts/conflict-1/actions") == true {
            return httpJSON(request, body: #"{"conflict":{"id":"conflict-1","reason":"stale","state":"resolved"}}"#)
        }
        return httpJSON(request, status: 404, body: "{}")
    }
    defer { ConflictURLProtocolStub.handler = nil }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ConflictURLProtocolStub.self]
    let client = FloppyAPIClient(siteURL: URL(string: "https://example.com")!, token: "secret", session: URLSession(configuration: configuration))

    let conflicts = try await client.listConflicts(cursor: "cursor-1", limit: 20)
    let response = try await client.applyConflictAction(conflictID: "conflict-1", request: FloppyConflictActionRequest(action: .markResolved))

    #expect(conflicts.conflicts.isEmpty)
    #expect(response.conflict.state == "resolved")
    #expect(requested.contains { $0.method == "GET" && $0.path.hasSuffix("/conflicts") })
    #expect(requested.contains { $0.method == "POST" && $0.path.hasSuffix("/conflicts/conflict-1/actions") && $0.body.contains("mark_resolved") })
}

@Test func conflictApiHelpersDecodeCurrentWordPressShapeAndFallbackRoute() async throws {
    var requested: [(method: String, path: String, body: String)] = []
    let serverItem = sampleItemJSON(id: 12, uuid: "file-uuid", name: "hello.txt", size: 5)
    CurrentConflictURLProtocolStub.handler = { request in
        requested.append((
            method: request.httpMethod ?? "",
            path: request.url?.path ?? "",
            body: String(data: requestBodyData(request), encoding: .utf8) ?? ""
        ))
        if request.url?.path.hasSuffix("/conflicts") == true {
            return httpJSON(request, body: """
            {"conflicts":[{"id":7,"conflict_uuid":"conflict-uuid","status":"open","reason":"stale_content","server_file":\(serverItem)}],"next_cursor":0,"has_more":false}
            """)
        }
        if request.url?.path.hasSuffix("/conflicts/conflict-uuid/actions") == true {
            return httpJSON(request, status: 404, body: "{}")
        }
        if request.url?.path.hasSuffix("/conflicts/conflict-uuid/resolve") == true {
            return httpJSON(request, body: """
            {"id":7,"conflict_uuid":"conflict-uuid","status":"resolved","reason":"stale_content","server_file":\(serverItem)}
            """)
        }
        return httpJSON(request, status: 404, body: "{}")
    }
    defer { CurrentConflictURLProtocolStub.handler = nil }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CurrentConflictURLProtocolStub.self]
    let client = FloppyAPIClient(siteURL: URL(string: "https://example.com")!, token: "secret", session: URLSession(configuration: configuration))

    let conflicts = try await client.listConflicts(limit: 20)
    let response = try await client.applyConflictAction(conflictID: "conflict-uuid", request: FloppyConflictActionRequest(action: .markResolved))

    #expect(conflicts.conflicts.first?.id == "conflict-uuid")
    #expect(conflicts.conflicts.first?.state == "open")
    #expect(conflicts.conflicts.first?.item?.uuid == "file-uuid")
    #expect(response.conflict.state == "resolved")
    #expect(requested.contains { $0.method == "POST" && $0.path.hasSuffix("/conflicts/conflict-uuid/resolve") && $0.body.contains("resolve") })
}

@Test func versionApiHelpersListAndRestoreAuthenticatedVersions() async throws {
    var requested: [(method: String, path: String, body: String)] = []
    VersionURLProtocolStub.handler = { request in
        requested.append((
            method: request.httpMethod ?? "",
            path: request.url?.path ?? "",
            body: String(data: requestBodyData(request), encoding: .utf8) ?? ""
        ))
        if request.url?.path.hasSuffix("/files/12/versions") == true {
            return httpJSON(request, body: """
            {"versions":[{"id":2,"version_uuid":"version-uuid","file_id":12,"file_uuid":"file-uuid","name":"hello.txt","mime_type":"text/plain","size_bytes":5,"content_hash":"abc","content_version":"old-cv","metadata_version":"old-mv","reason":"replace_session","created_by":1,"created_at_gmt":"2026-05-22 00:00:00","download_url":"https://example.com/wp-json/floppy/v1/files/12/versions/2/download"}],"next_cursor":0,"has_more":false}
            """)
        }
        if request.url?.path.hasSuffix("/files/12/versions/2/restore") == true {
            return httpJSON(request, body: sampleItemJSON(id: 12, uuid: "file-uuid", name: "hello.txt", size: 5))
        }
        return httpJSON(request, status: 404, body: "{}")
    }
    defer { VersionURLProtocolStub.handler = nil }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [VersionURLProtocolStub.self]
    let client = FloppyAPIClient(siteURL: URL(string: "https://example.com")!, token: "secret", session: URLSession(configuration: configuration))

    let versions = try await client.listFileVersions(fileID: 12, limit: 10)
    let restored = try await client.restoreFileVersion(fileID: 12, versionID: 2, contentVersion: "cv2")

    #expect(versions.versions.first?.downloadURL?.path.hasSuffix("/files/12/versions/2/download") == true)
    #expect(versions.versions.first?.contentVersion == "old-cv")
    #expect(restored.id == 12)
    #expect(requested.contains { $0.method == "GET" && $0.path.hasSuffix("/files/12/versions") })
    #expect(requested.contains { $0.method == "POST" && $0.path.hasSuffix("/files/12/versions/2/restore") && $0.body.contains("cv2") })
}

@Test func releaseEvidenceSummaryAndReportRedactLocalPaths() throws {
    let checks = [
        FloppyReleaseEvidenceCheck(id: "xcodebuild", status: .pass, message: "ok"),
        FloppyReleaseEvidenceCheck(id: "notary", status: .warn, message: "missing local profile"),
        FloppyReleaseEvidenceCheck(id: "codesign", status: .skipped, message: "no APP_PATH")
    ]
    let report = FloppyReleaseEvidenceReport(
        generatedAt: "2026-05-22T00:00:00Z",
        projectPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/GitHub/floppy/FloppyMac").path,
        appPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Floppy.app").path,
        zipPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Floppy.zip").path,
        checks: checks
    )

    let json = String(data: try JSONEncoder.floppy.encode(report), encoding: .utf8) ?? ""
    #expect(report.summary.passed == 1)
    #expect(report.summary.warnings == 1)
    #expect(report.summary.skipped == 1)
    #expect(!report.summary.readyForPublicBeta)
    #expect(json.contains("floppy-mac-release-evidence-v2"))
    #expect(!json.contains(FileManager.default.homeDirectoryForCurrentUser.path))
}

@Test func materializationResultAndQuarantinePathsAreRedacted() throws {
    let destination = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Floppy/hello.txt")
    let quarantine = FloppyPartialFileQuarantine.quarantineURL(for: destination, reason: "checksum mismatch", date: Date(timeIntervalSince1970: 1_800_000_000))
    let result = FloppyMaterializationResult(
        destinationPath: destination.path,
        retries: 2,
        checksumValidated: true,
        checksumFailures: 1,
        partialFileQuarantinePath: quarantine.path
    )
    let json = String(data: try JSONEncoder.floppy.encode(result), encoding: .utf8) ?? ""

    #expect(quarantine.lastPathComponent.contains("checksum-mismatch"))
    #expect(result.retries == 2)
    #expect(result.checksumFailures == 1)
    #expect(!json.contains(FileManager.default.homeDirectoryForCurrentUser.path))
}

@Test func nativeFolderReadinessRequiresEmbeddedExtensionAndAppGroupEntitlement() throws {
    let pluginRoot = URL(fileURLWithPath: "/tmp/FloppyPlugIns", isDirectory: true)
    let extensionURL = pluginRoot.appendingPathComponent(FloppyNativeFolderReadiness.fileProviderExtensionBundleName, isDirectory: true)

    let missingExtension = FloppyNativeFolderReadiness.inspect(
        builtInPlugInsURL: pluginRoot,
        appGroupIdentifier: "TEAMID.com.floppy.mac.sync",
        hasAppGroupEntitlement: true,
        fileExists: { _ in false }
    )
    #expect(missingExtension.status == .missingEmbeddedExtension)
    #expect(!missingExtension.isReady)

    let missingEntitlement = FloppyNativeFolderReadiness.inspect(
        builtInPlugInsURL: pluginRoot,
        appGroupIdentifier: "TEAMID.com.floppy.mac.sync",
        hasAppGroupEntitlement: false,
        fileExists: { $0 == extensionURL }
    )
    #expect(missingEntitlement.status == .missingAppGroupEntitlement)
    #expect(!missingEntitlement.isReady)

    let ready = FloppyNativeFolderReadiness.inspect(
        builtInPlugInsURL: pluginRoot,
        appGroupIdentifier: "TEAMID.com.floppy.mac.sync",
        hasAppGroupEntitlement: true,
        fileExists: { $0 == extensionURL }
    )
    #expect(ready.status == .ready)
    #expect(ready.isReady)
}

private func sampleItem(uuid: String, id: Int64, name: String, parentID: Int64 = 0) -> FloppyItem {
    FloppyItem(
        kind: .file,
        id: id,
        uuid: uuid,
        attachmentID: 44,
        ownerID: 1,
        parentID: parentID,
        name: name,
        mimeType: "text/plain",
        sizeBytes: 5,
        contentHash: "abc",
        contentVersion: "cv",
        metadataVersion: "mv",
        status: "active",
        visibility: "private",
        downloadURL: URL(string: "https://example.com/wp-json/floppy/v1/files/\(id)/download"),
        createdAtGMT: "2026-05-22 00:00:00",
        updatedAtGMT: "2026-05-22 00:00:00"
    )
}

private func sampleItemJSON(id: Int64, uuid: String, name: String, size: Int64) -> String {
    """
    {
      "kind": "file",
      "id": \(id),
      "uuid": "\(uuid)",
      "attachment_id": 44,
      "owner_id": 1,
      "parent_id": 0,
      "parent_uuid": "",
      "name": "\(name)",
      "mime_type": "text/plain",
      "size_bytes": \(size),
      "content_hash": "abc",
      "content_version": "cv2",
      "metadata_version": "mv",
      "status": "active",
      "visibility": "private",
      "download_url": "https://example.com/wp-json/floppy/v1/files/\(id)/download",
      "created_at_gmt": "2026-05-22 00:00:00",
      "updated_at_gmt": "2026-05-22 00:00:00"
    }
    """
}

private func httpJSON(_ request: URLRequest, status: Int = 200, body: String) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(body.utf8))
}

private func requestBodyData(_ request: URLRequest) -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return Data()
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw FloppyAPIError.invalidResponse
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class UploadOffsetURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw FloppyAPIError.invalidResponse
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class ConflictURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw FloppyAPIError.invalidResponse
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class CurrentConflictURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw FloppyAPIError.invalidResponse
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class VersionURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw FloppyAPIError.invalidResponse
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeTestZip(entries: [String]) throws -> Data {
    var archive = Data()
    var centralDirectory = Data()
    var localHeaderOffsets: [UInt32] = []

    for entry in entries {
        localHeaderOffsets.append(UInt32(archive.count))
        let name = Data(entry.utf8)
        archive.appendUInt32LE(0x04034b50)
        archive.appendUInt16LE(20)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt32LE(0)
        archive.appendUInt32LE(0)
        archive.appendUInt32LE(0)
        archive.appendUInt16LE(UInt16(name.count))
        archive.appendUInt16LE(0)
        archive.append(name)
    }

    let centralDirectoryOffset = UInt32(archive.count)
    for (index, entry) in entries.enumerated() {
        let name = Data(entry.utf8)
        centralDirectory.appendUInt32LE(0x02014b50)
        centralDirectory.appendUInt16LE(20)
        centralDirectory.appendUInt16LE(20)
        centralDirectory.appendUInt16LE(0)
        centralDirectory.appendUInt16LE(0)
        centralDirectory.appendUInt16LE(0)
        centralDirectory.appendUInt16LE(0)
        centralDirectory.appendUInt32LE(0)
        centralDirectory.appendUInt32LE(0)
        centralDirectory.appendUInt32LE(0)
        centralDirectory.appendUInt16LE(UInt16(name.count))
        centralDirectory.appendUInt16LE(0)
        centralDirectory.appendUInt16LE(0)
        centralDirectory.appendUInt16LE(0)
        centralDirectory.appendUInt16LE(0)
        centralDirectory.appendUInt32LE(0)
        centralDirectory.appendUInt32LE(localHeaderOffsets[index])
        centralDirectory.append(name)
    }

    archive.append(centralDirectory)
    archive.appendUInt32LE(0x06054b50)
    archive.appendUInt16LE(0)
    archive.appendUInt16LE(0)
    archive.appendUInt16LE(UInt16(entries.count))
    archive.appendUInt16LE(UInt16(entries.count))
    archive.appendUInt32LE(UInt32(centralDirectory.count))
    archive.appendUInt32LE(centralDirectoryOffset)
    archive.appendUInt16LE(0)
    return archive
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0x00ff))
        append(UInt8((value >> 8) & 0x00ff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0x000000ff))
        append(UInt8((value >> 8) & 0x000000ff))
        append(UInt8((value >> 16) & 0x000000ff))
        append(UInt8((value >> 24) & 0x000000ff))
    }
}
