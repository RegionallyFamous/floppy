import Foundation

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
            "No device token is stored for this Floppy account."
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

    public func listFiles(parentID: Int64 = 0, afterID: Int64 = 0, limit: Int = 100) async throws -> FloppyListResponse {
        try await request(path: "files?parent_id=\(parentID)&after_id=\(afterID)&limit=\(limit)")
    }

    public func syncChanges(cursor: UInt64 = 0, limit: Int = 250) async throws -> FloppyChangeFeed {
        try await request(path: "sync/changes?cursor=\(cursor)&limit=\(limit)")
    }

    public func devices() async throws -> FloppyDeviceList {
        try await request(path: "devices")
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

    public func wordPressRESTRoot() async throws -> WordPressRESTRoot {
        var request = URLRequest(url: siteURL.appendingPathComponent("wp-json"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("FloppyMac/0.1", forHTTPHeaderField: "User-Agent")
        return try await decode(session.data(for: request))
    }

    public func getPlugin(plugin: String) async throws -> WordPressPlugin {
        try await wordpressRequest(path: "plugins/\(plugin)", method: "GET")
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

        return try await wordpressRequest(path: "plugins/\(plugin)", method: "POST", body: Body())
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

    public func trashFile(id: Int64, metadataVersion: String) async throws {
        struct Body: Encodable {
            let metadataVersion: String

            enum CodingKeys: String, CodingKey {
                case metadataVersion = "metadata_version"
            }
        }

        let _: EmptyResponse = try await request(path: "files/\(id)/trash", method: "POST", body: Body(metadataVersion: metadataVersion))
    }

    public func deleteFile(id: Int64) async throws {
        let request = try makeRequest(path: "files/\(id)", method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
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
        guard let downloadURL = file.downloadURL else {
            throw FloppyAPIError.invalidResponse
        }

        var request = URLRequest(url: downloadURL)
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        let (temporaryURL, response) = try await session.download(for: request)
        try validate(response: response, data: Data())
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: url)
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

        var url = siteURL.appendingPathComponent("wp-json/wp/v2")
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }

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

        guard
            let site = items["site"].flatMap(URL.init(string:)),
            let deviceUUID = items["device_uuid"],
            let token = items["token"],
            let scope = items["scope"]
        else {
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
