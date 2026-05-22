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

@Test func fileProviderIdentifierCodecUsesStableUUIDs() throws {
    let rawValue = FloppyFileProviderIdentifierCodec.itemIdentifierRawValue(uuid: "file-uuid")

    #expect(rawValue == "floppy:item:file-uuid")
    #expect(FloppyFileProviderIdentifierCodec.itemUUID(from: rawValue) == "file-uuid")
    #expect(FloppyFileProviderIdentifierCodec.legacyItemID(from: "floppy:item:12") == 12)
    #expect(FloppyFileProviderIdentifierCodec.itemUUID(from: "floppy:item:12") == nil)
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
