import Foundation
import CryptoKit

public enum FloppyAPIError: Error, Equatable, LocalizedError {
    case invalidSiteURL
    case invalidResponse
    case httpStatus(Int, String)
    case missingToken
    case unsupportedCallback
    case duplicateCallbackParameter(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSiteURL:
            "Enter a valid WordPress site URL."
        case .invalidResponse:
            "Floppy returned an invalid response."
        case .httpStatus(let status, let message):
            "Floppy request failed with HTTP \(status): \(message)"
        case .missingToken:
            "No device token is stored for this Floppy account. Reconnect the site once to create a new Keychain token."
        case .unsupportedCallback:
            "The approval callback was not a Floppy device approval URL."
        case .duplicateCallbackParameter(let name):
            "The approval callback contained duplicate \(name) parameters."
        }
    }
}

public struct FloppyAPIClient: Sendable {
    public let siteURL: URL
    public let restURL: URL
    public let token: String?
    public let session: URLSession
    private let authorizationHeader: String?

    public init(siteURL: URL, restURL: URL? = nil, token: String? = nil, session: URLSession = .shared) {
        self.siteURL = siteURL.normalizedSiteURL()
        self.restURL = restURL ?? self.siteURL.appendingPathComponent("wp-json/floppy/v1")
        self.token = token
        self.session = session
        self.authorizationHeader = token.map { "Bearer \($0)" }
    }

    public init(siteURL: URL, restURL: URL? = nil, applicationPassword: WordPressApplicationCredential, session: URLSession = .shared) {
        self.siteURL = siteURL.normalizedSiteURL()
        self.restURL = restURL ?? self.siteURL.appendingPathComponent("wp-json/floppy/v1")
        self.token = nil
        self.session = session
        self.authorizationHeader = applicationPassword.basicAuthorizationHeader
    }

    public static func discoveryURL(for siteURL: URL) -> URL {
        siteURL.normalizedSiteURL().appendingPathComponent("wp-json/floppy/v1/discovery")
    }

    public static func approvalURL(siteURL: URL, state: String, deviceName: String, callbackScheme: String = "floppy") -> URL {
        var components = URLComponents(url: siteURL.normalizedSiteURL().appendingPathComponent("wp-admin/admin.php"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page", value: "floppy"),
            URLQueryItem(name: "floppy-device-approval", value: "1"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "device_name", value: deviceName),
            URLQueryItem(name: "callback", value: "\(callbackScheme)://device-approved")
        ]
        return components.url!
    }

    public static func applicationPasswordAuthorizationURL(siteURL: URL, authorizationURL: URL? = nil, state: String, deviceName: String, appID: UUID = UUID(uuidString: "B6AFA1D8-2E47-4E4C-93E6-1B8786C43D8E")!, callbackScheme: String = "floppy") -> URL {
        let baseURL = authorizationURL ?? siteURL.normalizedSiteURL().appendingPathComponent("wp-admin/authorize-application.php")
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "app_name", value: "Floppy for Mac - \(deviceName)"),
            URLQueryItem(name: "app_id", value: appID.uuidString.lowercased()),
            URLQueryItem(name: "success_url", value: "\(callbackScheme)://wordpress-authorized?state=\(state)"),
            URLQueryItem(name: "reject_url", value: "\(callbackScheme)://wordpress-rejected?state=\(state)")
        ]
        return components.url!
    }

    public func discover() async throws -> FloppyDiscovery {
        try await request(path: "discovery", requiresToken: false)
    }

    public func health() async throws -> FloppyHealthSummary {
        try await request(path: "health")
    }

    public func listFiles(parentID: Int64 = 0, cursor: String = "", afterID: Int64 = 0, limit: Int = 100) async throws -> FloppyListResponse {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "parent_id", value: String(parentID)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if !cursor.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor))
        } else if afterID > 0 {
            components.queryItems?.append(URLQueryItem(name: "after_id", value: String(afterID)))
        }
        return try await request(path: "files?\(components.percentEncodedQuery ?? "")")
    }

    public func syncChanges(cursor: UInt64 = 0, limit: Int = 250) async throws -> FloppyChangeFeed {
        try await request(path: "sync/changes?cursor=\(cursor)&limit=\(limit)")
    }

    public func devices() async throws -> FloppyDeviceList {
        try await request(path: "devices")
    }

    public func listConflicts(cursor: String = "", limit: Int = 100) async throws -> FloppyServerConflictListResponse {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if !cursor.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await request(path: "conflicts?\(components.percentEncodedQuery ?? "")")
    }

    public func applyConflictAction(conflictID: String, request actionRequest: FloppyConflictActionRequest) async throws -> FloppyConflictActionResponse {
        do {
            return try await request(path: "conflicts/\(conflictID)/actions", method: "POST", body: actionRequest)
        } catch FloppyAPIError.httpStatus(let status, _) where status == 404 || status == 405 {
            struct LegacyBody: Encodable {
                let action: String
            }

            let legacy: FloppyServerConflict = try await request(
                path: "conflicts/\(conflictID)/resolve",
                method: "POST",
                body: LegacyBody(action: actionRequest.action.legacyServerAction)
            )
            return FloppyConflictActionResponse(conflict: legacy, canonicalItem: legacy.item)
        }
    }

    public func revokeDevice(deviceUUID: String) async throws {
        do {
            let _: EmptyResponse = try await request(path: "devices/\(deviceUUID)/revoke", method: "POST", body: EmptyRequestBody())
        } catch FloppyAPIError.httpStatus(let status, _) where status == 404 || status == 405 {
            FloppyDiagnostics.api.info("Falling back to DELETE device revoke route for \(deviceUUID, privacy: .private)")
            let request = try makeRequest(path: "devices/\(deviceUUID)", method: "DELETE")
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
        }
    }

    public func authorizeDevice(deviceName: String) async throws -> FloppyDeviceAuthorization {
        struct Body: Encodable {
            let deviceName: String

            enum CodingKeys: String, CodingKey {
                case deviceName = "device_name"
            }
        }

        return try await request(path: "devices/authorize", method: "POST", body: Body(deviceName: deviceName))
    }

    public func exchangeDeviceCode(code: String, state: String) async throws -> FloppyDeviceAuthorization {
        struct Body: Encodable {
            let code: String
            let state: String
        }

        return try await request(path: "devices/exchange", method: "POST", body: Body(code: code, state: state), requiresToken: false)
    }

    public func wordPressRESTRoot() async throws -> WordPressRESTRoot {
        var request = URLRequest(url: siteURL.appendingPathComponent("wp-json"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("FloppyMac/0.1", forHTTPHeaderField: "User-Agent")
        return try await decode(session.data(for: request))
    }

    public func getPlugin(plugin: String) async throws -> WordPressPlugin {
        try await wordpressRequest(path: Self.wordpressPluginPath(for: plugin), method: "GET")
    }

    public func installPlugin(slug: String, status: WordPressPluginStatus = .active) async throws -> WordPressPlugin {
        struct Body: Encodable {
            let slug: String
            let status: WordPressPluginStatus
        }

        return try await wordpressRequest(path: "plugins", method: "POST", body: Body(slug: slug, status: status))
    }

    public func activatePlugin(plugin: String) async throws -> WordPressPlugin {
        struct Body: Encodable {
            let status: WordPressPluginStatus = .active
        }

        return try await wordpressRequest(path: Self.wordpressPluginPath(for: plugin), method: "POST", body: Body())
    }

    public func deleteCurrentApplicationPassword() async {
        do {
            let password: WordPressApplicationPassword = try await wordpressRequest(path: "users/me/application-passwords/introspect", method: "GET")
            let request = try makeWordPressRequest(path: "users/me/application-passwords/\(password.uuid)", method: "DELETE")
            _ = try? await session.data(for: request)
        } catch {
            return
        }
    }

    public func createFolder(name: String, parentID: Int64 = 0) async throws -> FloppyItem {
        struct Body: Encodable {
            let name: String
            let parentID: Int64

            enum CodingKeys: String, CodingKey {
                case name
                case parentID = "parent_id"
            }
        }

        return try await request(path: "folders", method: "POST", body: Body(name: name, parentID: parentID))
    }

    public func renameFile(id: Int64, name: String, metadataVersion: String) async throws -> FloppyItem {
        struct Body: Encodable {
            let name: String
            let metadataVersion: String

            enum CodingKeys: String, CodingKey {
                case name
                case metadataVersion = "metadata_version"
            }
        }

        return try await request(path: "files/\(id)/rename", method: "POST", body: Body(name: name, metadataVersion: metadataVersion))
    }

    public func moveFile(id: Int64, parentID: Int64, metadataVersion: String) async throws -> FloppyItem {
        struct Body: Encodable {
            let parentID: Int64
            let metadataVersion: String

            enum CodingKeys: String, CodingKey {
                case parentID = "parent_id"
                case metadataVersion = "metadata_version"
            }
        }

        return try await request(path: "files/\(id)/move", method: "POST", body: Body(parentID: parentID, metadataVersion: metadataVersion))
    }

    public func renameFolder(id: Int64, name: String, metadataVersion: String) async throws -> FloppyItem {
        struct Body: Encodable {
            let name: String
            let metadataVersion: String

            enum CodingKeys: String, CodingKey {
                case name
                case metadataVersion = "metadata_version"
            }
        }

        return try await request(path: "folders/\(id)/rename", method: "POST", body: Body(name: name, metadataVersion: metadataVersion))
    }

    public func moveFolder(id: Int64, parentID: Int64, metadataVersion: String) async throws -> FloppyItem {
        struct Body: Encodable {
            let parentID: Int64
            let metadataVersion: String

            enum CodingKeys: String, CodingKey {
                case parentID = "parent_id"
                case metadataVersion = "metadata_version"
            }
        }

        return try await request(path: "folders/\(id)/move", method: "POST", body: Body(parentID: parentID, metadataVersion: metadataVersion))
    }

    public func trashFile(id: Int64, metadataVersion: String) async throws {
        struct Body: Encodable {
            let metadataVersion: String

            enum CodingKeys: String, CodingKey {
                case metadataVersion = "metadata_version"
            }
        }

        let _: EmptyResponse = try await request(path: "files/\(id)/trash", method: "POST", body: Body(metadataVersion: metadataVersion))
    }

    public func trashFolder(id: Int64, metadataVersion: String) async throws {
        struct Body: Encodable {
            let metadataVersion: String

            enum CodingKeys: String, CodingKey {
                case metadataVersion = "metadata_version"
            }
        }

        let _: EmptyResponse = try await request(path: "folders/\(id)/trash", method: "POST", body: Body(metadataVersion: metadataVersion))
    }

    public func deleteFile(id: Int64, metadataVersion: String) async throws {
        struct Body: Encodable {
            let metadataVersion: String

            enum CodingKeys: String, CodingKey {
                case metadataVersion = "metadata_version"
            }
        }

        let _: EmptyResponse = try await request(path: "files/\(id)", method: "DELETE", body: Body(metadataVersion: metadataVersion))
    }

    public func deleteFolder(id: Int64, metadataVersion: String) async throws {
        struct Body: Encodable {
            let metadataVersion: String

            enum CodingKeys: String, CodingKey {
                case metadataVersion = "metadata_version"
            }
        }

        let _: EmptyResponse = try await request(path: "folders/\(id)", method: "DELETE", body: Body(metadataVersion: metadataVersion))
    }

    public func listFileVersions(fileID: Int64, afterID: Int64 = 0, limit: Int = 50) async throws -> FloppyFileVersionListResponse {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if afterID > 0 {
            components.queryItems?.append(URLQueryItem(name: "after_id", value: String(afterID)))
        }
        return try await request(path: "files/\(fileID)/versions?\(components.percentEncodedQuery ?? "")")
    }

    public func restoreFileVersion(fileID: Int64, versionID: Int64, contentVersion: String) async throws -> FloppyItem {
        struct Body: Encodable {
            let contentVersion: String

            enum CodingKeys: String, CodingKey {
                case contentVersion = "content_version"
            }
        }

        return try await request(
            path: "files/\(fileID)/versions/\(versionID)/restore",
            method: "POST",
            body: Body(contentVersion: contentVersion)
        )
    }

    public func upload(data: Data, filename: String, parentID: Int64 = 0, mimeType: String = "application/octet-stream") async throws -> FloppyItem {
        let boundary = "FloppyBoundary-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartField(name: "parent_id", value: String(parentID), boundary: boundary)
        body.appendMultipartFile(name: "file", filename: filename, mimeType: mimeType, data: data, boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = try makeRequest(path: "upload", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        return try await decode(session.data(for: request))
    }

    public func createUploadSession(
        filename: String,
        parentID: Int64 = 0,
        totalSize: Int64,
        contentHash: String,
        mimeType: String = "application/octet-stream"
    ) async throws -> FloppyUploadSession {
        struct Body: Encodable {
            let filename: String
            let parentID: Int64
            let totalSize: Int64
            let contentHash: String
            let mimeType: String

            enum CodingKeys: String, CodingKey {
                case filename
                case parentID = "parent_id"
                case totalSize = "total_size"
                case contentHash = "content_hash"
                case mimeType = "mime_type"
            }
        }

        return try await request(
            path: "upload-sessions",
            method: "POST",
            body: Body(filename: filename, parentID: parentID, totalSize: totalSize, contentHash: contentHash, mimeType: mimeType)
        )
    }

    public func createReplaceSession(
        fileID: Int64,
        contentVersion: String,
        totalSize: Int64,
        contentHash: String,
        mimeType: String = "application/octet-stream"
    ) async throws -> FloppyUploadSession {
        struct Body: Encodable {
            let contentVersion: String
            let totalSize: Int64
            let contentHash: String
            let mimeType: String

            enum CodingKeys: String, CodingKey {
                case contentVersion = "content_version"
                case totalSize = "total_size"
                case contentHash = "content_hash"
                case mimeType = "mime_type"
            }
        }

        return try await request(
            path: "files/\(fileID)/replace-sessions",
            method: "POST",
            body: Body(contentVersion: contentVersion, totalSize: totalSize, contentHash: contentHash, mimeType: mimeType)
        )
    }

    public func uploadFile(
        at fileURL: URL,
        filename: String,
        parentID: Int64 = 0,
        mimeType: String = "application/octet-stream",
        progressHandler: ((Int64, Int64) -> Void)? = nil
    ) async throws -> FloppyItem {
        let totalSize = try Self.fileSize(for: fileURL)
        let uploadSession = try await createUploadSession(
            filename: filename,
            parentID: parentID,
            totalSize: totalSize,
            contentHash: try Self.sha256HexDigest(for: fileURL),
            mimeType: mimeType
        )

        return try await uploadChunks(from: fileURL, session: uploadSession, totalSize: totalSize, progressHandler: progressHandler)
    }

    public func replaceFile(
        id: Int64,
        at fileURL: URL,
        filename: String,
        contentVersion: String,
        mimeType: String = "application/octet-stream",
        progressHandler: ((Int64, Int64) -> Void)? = nil
    ) async throws -> FloppyItem {
        let totalSize = try Self.fileSize(for: fileURL)
        let uploadSession = try await createReplaceSession(
            fileID: id,
            contentVersion: contentVersion,
            totalSize: totalSize,
            contentHash: try Self.sha256HexDigest(for: fileURL),
            mimeType: mimeType
        )

        return try await uploadChunks(from: fileURL, session: uploadSession, totalSize: totalSize, progressHandler: progressHandler)
    }

    public func uploadChunks(
        from fileURL: URL,
        session uploadSession: FloppyUploadSession,
        totalSize: Int64,
        progressHandler: ((Int64, Int64) -> Void)? = nil,
        progressRecorder: ((Int64) async -> Void)? = nil
    ) async throws -> FloppyItem {
        let chunkSize = max(1, uploadSession.chunkSize)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var offset = uploadSession.receivedBytes
        try handle.seek(toOffset: UInt64(offset))
        while offset < totalSize {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: min(chunkSize, Int(totalSize - offset))), !chunk.isEmpty else {
                break
            }
            let response = try await appendUploadChunkWithRetry(
                sessionUUID: uploadSession.sessionUUID,
                chunk: chunk,
                offset: offset,
                idempotencyKey: "\(uploadSession.sessionUUID)-\(offset)"
            )
            let expectedOffset = offset + Int64(chunk.count)
            guard response.receivedBytes == expectedOffset else {
                throw FloppyTransferError.unexpectedUploadOffset(expected: expectedOffset, actual: response.receivedBytes)
            }
            offset = expectedOffset
            progressHandler?(offset, totalSize)
            if let progressRecorder {
                await progressRecorder(offset)
            }
        }

        return try await completeUploadSession(sessionUUID: uploadSession.sessionUUID)
    }

    private func appendUploadChunk(sessionUUID: String, chunk: Data, offset: Int64) async throws -> FloppyUploadProgress {
        var request = try makeRequest(path: "upload-sessions/\(sessionUUID)/chunk", method: "POST")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(offset), forHTTPHeaderField: "X-Floppy-Offset")
        request.httpBody = chunk
        return try await decode(session.data(for: request))
    }

    private func appendUploadChunkWithRetry(sessionUUID: String, chunk: Data, offset: Int64, idempotencyKey: String, retryPolicy: FloppyTransferRetryPolicy = .default) async throws -> FloppyUploadProgress {
        var attempt = 0
        var lastError: Error?
        while attempt < retryPolicy.maximumAttempts {
            try Task.checkCancellation()
            attempt += 1
            do {
                return try await appendUploadChunk(sessionUUID: sessionUUID, chunk: chunk, offset: offset, idempotencyKey: idempotencyKey)
            } catch FloppyAPIError.httpStatus(let status, _) where status == 409 || status == 428 {
                throw FloppyAPIError.httpStatus(status, "Upload offset requires reconciliation before retrying.")
            } catch FloppyAPIError.httpStatus(let status, _) where status == 429 || status >= 500 {
                lastError = FloppyAPIError.httpStatus(status, "Chunk upload retryable server response.")
            } catch {
                lastError = error
            }

            if attempt < retryPolicy.maximumAttempts, retryPolicy.initialDelaySeconds > 0 {
                let delay = UInt64(retryPolicy.initialDelaySeconds * Double(NSEC_PER_SEC) * pow(2.0, Double(attempt - 1)))
                try await Task.sleep(nanoseconds: delay)
            }
        }

        if let lastError {
            throw lastError
        }
        throw FloppyTransferError.retryLimitExceeded(attempts: attempt)
    }

    private func appendUploadChunk(sessionUUID: String, chunk: Data, offset: Int64, idempotencyKey: String) async throws -> FloppyUploadProgress {
        var request = try makeRequest(path: "upload-sessions/\(sessionUUID)/chunk", method: "POST")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(offset), forHTTPHeaderField: "X-Floppy-Offset")
        request.setValue(idempotencyKey, forHTTPHeaderField: "X-Floppy-Idempotency-Key")
        request.httpBody = chunk
        return try await decode(session.data(for: request))
    }

    public func completeUploadSession(sessionUUID: String) async throws -> FloppyItem {
        return try await request(path: "upload-sessions/\(sessionUUID)/complete", method: "POST", body: EmptyRequestBody())
    }

    public func replaceFile(id: Int64, data: Data, filename: String, contentVersion: String, mimeType: String = "application/octet-stream") async throws -> FloppyItem {
        let boundary = "FloppyBoundary-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartField(name: "content_version", value: contentVersion, boundary: boundary)
        body.appendMultipartFile(name: "file", filename: filename, mimeType: mimeType, data: data, boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = try makeRequest(path: "files/\(id)/replace", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        return try await decode(session.data(for: request))
    }

    public func download(file: FloppyItem, to url: URL) async throws {
        _ = try await downloadValidated(file: file, to: url)
    }

    public func download(version: FloppyFileVersion, to url: URL) async throws {
        guard let downloadURL = version.downloadURL else {
            throw FloppyAPIError.invalidResponse
        }

        _ = try await downloadRemoteFile(
            downloadURL: downloadURL,
            expectedHash: version.contentHash,
            to: url,
            retryPolicy: .default
        )
    }

    @discardableResult
    public func downloadValidated(
        file: FloppyItem,
        to url: URL,
        retryPolicy: FloppyTransferRetryPolicy = .default
    ) async throws -> FloppyMaterializationResult {
        var attempt = 0
        var checksumFailures = 0
        var lastError: Error?
        var lastQuarantineURL: URL?

        while attempt < retryPolicy.maximumAttempts {
            try Task.checkCancellation()
            attempt += 1
            do {
                let result = try await downloadOnce(file: file, to: url, attempt: attempt)
                return FloppyMaterializationResult(
                    destinationPath: result.destination.path,
                    retries: attempt - 1,
                    checksumValidated: result.checksumValidated,
                    checksumFailures: checksumFailures,
                    partialFileQuarantinePath: lastQuarantineURL?.path
                )
            } catch FloppyTransferError.checksumMismatch(let expected, let actual) {
                checksumFailures += 1
                lastError = FloppyTransferError.checksumMismatch(expected: expected, actual: actual)
                lastQuarantineURL = FloppyPartialFileQuarantine.quarantineURL(for: url, reason: "checksum")
            } catch {
                lastError = error
            }

            if attempt < retryPolicy.maximumAttempts, retryPolicy.initialDelaySeconds > 0 {
                let delay = UInt64(retryPolicy.initialDelaySeconds * Double(NSEC_PER_SEC) * pow(2.0, Double(attempt - 1)))
                try await Task.sleep(nanoseconds: delay)
            }
        }

        if let lastError {
            throw lastError
        }
        throw FloppyTransferError.retryLimitExceeded(attempts: attempt)
    }

    private func downloadOnce(file: FloppyItem, to url: URL, attempt: Int) async throws -> (destination: URL, checksumValidated: Bool) {
        guard let downloadURL = file.downloadURL else {
            throw FloppyAPIError.invalidResponse
        }

        return try await downloadRemoteFile(downloadURL: downloadURL, expectedHash: file.contentHash, to: url, attempt: attempt)
    }

    private func downloadRemoteFile(
        downloadURL: URL,
        expectedHash: String?,
        to url: URL,
        retryPolicy: FloppyTransferRetryPolicy
    ) async throws -> (destination: URL, checksumValidated: Bool) {
        var attempt = 0
        var lastError: Error?
        while attempt < retryPolicy.maximumAttempts {
            attempt += 1
            do {
                return try await downloadRemoteFile(downloadURL: downloadURL, expectedHash: expectedHash, to: url, attempt: attempt)
            } catch {
                lastError = error
                if attempt < retryPolicy.maximumAttempts, retryPolicy.initialDelaySeconds > 0 {
                    let delay = UInt64(retryPolicy.initialDelaySeconds * Double(NSEC_PER_SEC) * pow(2.0, Double(attempt - 1)))
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }
        if let lastError {
            throw lastError
        }
        throw FloppyTransferError.retryLimitExceeded(attempts: attempt)
    }

    private func downloadRemoteFile(downloadURL: URL, expectedHash: String?, to url: URL, attempt: Int) async throws -> (destination: URL, checksumValidated: Bool) {
        var request = URLRequest(url: downloadURL)
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        let policy = FloppyDownloadOriginPolicy(siteURL: siteURL, restURL: restURL)
        try policy.validate(downloadURL)

        let (temporaryURL, response) = try await session.download(for: request, delegate: FloppyDownloadRedirectDelegate(policy: policy))
        try policy.validate(response: response)
        try validate(response: response, data: Data())
        let checksumValidated: Bool
        if let expectedHash, !expectedHash.isEmpty {
            let actualHash = try Self.sha256HexDigest(for: temporaryURL)
            guard actualHash.caseInsensitiveCompare(expectedHash) == .orderedSame else {
                let quarantineURL = FloppyPartialFileQuarantine.quarantineURL(for: url, reason: "checksum-\(attempt)")
                try FileManager.default.createDirectory(at: quarantineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: quarantineURL)
                try? FileManager.default.moveItem(at: temporaryURL, to: quarantineURL)
                FloppyDiagnostics.api.error("Downloaded checksum mismatch for \(FloppyDiagnostics.redactedFilePath(url.path), privacy: .public)")
                throw FloppyTransferError.checksumMismatch(expected: expectedHash, actual: actualHash)
            }
            checksumValidated = true
        } else {
            checksumValidated = false
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: url)
        return (url, checksumValidated)
    }

    public func request<Response: Decodable, Body: Encodable>(path: String, method: String = "GET", body: Body? = Optional<Data>.none, requiresToken: Bool = true) async throws -> Response {
        var request = try makeRequest(path: path, method: method, requiresToken: requiresToken)
        if let body {
            request.httpBody = try JSONEncoder.floppy.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return try await decode(session.data(for: request))
    }

    private func wordpressRequest<Response: Decodable, Body: Encodable>(path: String, method: String = "GET", body: Body? = Optional<Data>.none) async throws -> Response {
        var request = try makeWordPressRequest(path: path, method: method)
        if let body {
            request.httpBody = try JSONEncoder.floppy.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return try await decode(session.data(for: request))
    }

    private func wordpressRequest<Response: Decodable>(path: String, method: String = "GET") async throws -> Response {
        let request = try makeWordPressRequest(path: path, method: method)
        return try await decode(session.data(for: request))
    }

    public func request<Response: Decodable>(path: String, requiresToken: Bool = true) async throws -> Response {
        var request = try makeRequest(path: path, method: "GET", requiresToken: requiresToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await decode(session.data(for: request))
    }

    private func makeRequest(path: String, method: String, requiresToken: Bool = true) throws -> URLRequest {
        if requiresToken, authorizationHeader == nil {
            throw FloppyAPIError.missingToken
        }

        let url = restURL.appendingFloppyAPIPath(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("FloppyMac/0.1", forHTTPHeaderField: "User-Agent")
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func makeWordPressRequest(path: String, method: String) throws -> URLRequest {
        if authorizationHeader == nil {
            throw FloppyAPIError.missingToken
        }

        let url = Self.wordPressURL(siteURL: siteURL, path: path)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("FloppyMac/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func wordpressPluginPath(for plugin: String) -> String {
        let normalizedPlugin = plugin.hasSuffix(".php") ? String(plugin.dropLast(4)) : plugin
        let encodedPlugin = normalizedPlugin
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { percentEncodeWordPressPathComponent(String($0)) }
            .joined(separator: "/")
        return "plugins/\(encodedPlugin)"
    }

    static func wordPressURL(siteURL: URL, path: String) -> URL {
        var components = URLComponents(url: siteURL.appendingPathComponent("wp-json/wp/v2"), resolvingAgainstBaseURL: false)!
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedPath = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { percentEncodeWordPressPathComponent(String($0)) }
            .joined(separator: "/")
        components.percentEncodedPath = "/" + [basePath, encodedPath].filter { !$0.isEmpty }.joined(separator: "/")
        return components.url ?? siteURL.appendingPathComponent("wp-json/wp/v2").appendingPathComponent(path)
    }

    private static func percentEncodeWordPressPathComponent(_ component: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~%")
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }

    private func decode<Response: Decodable>(_ result: (Data, URLResponse)) async throws -> Response {
        let (data, response) = result
        try validate(response: response, data: data)
        return try JSONDecoder.floppy.decode(Response.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw FloppyAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw FloppyAPIError.httpStatus(http.statusCode, message)
        }
    }

    public static func sha256HexDigest(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func fileSize(for fileURL: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fallbackSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? fallbackSize
    }
}

private extension URL {
    func appendingFloppyAPIPath(_ path: String) -> URL {
        let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var url = self
        let route = pieces.first.map(String.init) ?? ""
        if !route.isEmpty {
            for component in route.split(separator: "/") {
                if component == ".." {
                    url.deleteLastPathComponent()
                } else if component != "." {
                    url.appendPathComponent(String(component))
                }
            }
        }
        if pieces.count == 2,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.percentEncodedQuery = String(pieces[1])
            return components.url ?? url
        }
        return url
    }
}

public struct EmptyResponse: Codable, Equatable, Sendable {}
public struct EmptyRequestBody: Codable, Equatable, Sendable {}

extension FloppyAPIClient {
    public static func parseApplicationPasswordCallback(_ url: URL) throws -> WordPressApplicationCredential {
        guard url.scheme == "floppy", url.host == "wordpress-authorized" else {
            throw FloppyAPIError.unsupportedCallback
        }

        let items = try uniqueQueryItems(url)
        guard
            let site = items["site_url"].flatMap(URL.init(string:)),
            let userLogin = items["user_login"],
            let password = items["password"],
            let state = items["state"]
        else {
            throw FloppyAPIError.invalidResponse
        }

        return WordPressApplicationCredential(siteURL: site, userLogin: userLogin, password: password, state: state)
    }

    public static func parseRejectionCallback(_ url: URL) throws -> String {
        guard url.scheme == "floppy", url.host == "wordpress-rejected" else {
            throw FloppyAPIError.unsupportedCallback
        }

        return try uniqueQueryItems(url)["state"] ?? ""
    }

    public static func parseApprovalCallback(_ url: URL) throws -> FloppyDeviceApproval {
        guard url.scheme == "floppy", url.host == "device-approved" else {
            throw FloppyAPIError.unsupportedCallback
        }

        let items = try uniqueQueryItems(url)

        guard let site = items["site"].flatMap(URL.init(string:)) else {
            throw FloppyAPIError.invalidResponse
        }

        if let code = items["code"], !code.isEmpty {
            return FloppyDeviceApproval(siteURL: site, deviceUUID: "", token: "", scope: "", state: items["state"] ?? "", exchangeCode: code)
        }

        guard ProcessInfo.processInfo.environment["FLOPPY_ALLOW_RAW_DEVICE_TOKEN_CALLBACK"] == "1" else {
            throw FloppyAPIError.invalidResponse
        }

        guard let deviceUUID = items["device_uuid"], let token = items["token"], let scope = items["scope"] else {
            throw FloppyAPIError.invalidResponse
        }

        return FloppyDeviceApproval(siteURL: site, deviceUUID: deviceUUID, token: token, scope: scope, state: items["state"] ?? "")
    }

    private static func uniqueQueryItems(_ url: URL) throws -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            if items[item.name] != nil {
                throw FloppyAPIError.duplicateCallbackParameter(item.name)
            }
            items[item.name] = item.value ?? ""
        }
        return items
    }
}

extension Data {
    fileprivate mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    fileprivate mutating func appendMultipartFile(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}

extension URL {
    fileprivate func normalizedSiteURL() -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false) ?? URLComponents()
        if components.scheme == nil {
            components.scheme = "https"
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return components.url ?? self
    }
}

public extension JSONDecoder {
    static let floppy: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
}

public extension JSONEncoder {
    static let floppy: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()
}
