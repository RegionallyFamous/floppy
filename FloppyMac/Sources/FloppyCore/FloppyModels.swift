import Foundation

public struct FloppyDiscovery: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let namespace: String
    public let restURL: URL
    public let auth: [String]
    public let desktopMode: Bool
    public let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case version
        case namespace
        case restURL = "rest_url"
        case auth
        case desktopMode = "desktop_mode"
        case isPrivate = "private"
    }
}

public struct FloppyAccount: Codable, Equatable, Identifiable, Sendable {
    public var id: String { siteURL.absoluteString + "#" + userHint }

    public let siteURL: URL
    public let restURL: URL
    public let userHint: String
    public let deviceUUID: String
    public let scope: String
    public var lastCursor: UInt64
    public var connectedAt: Date
    public var lastSyncAt: Date?

    public init(siteURL: URL, restURL: URL, userHint: String, deviceUUID: String, scope: String, lastCursor: UInt64 = 0, connectedAt: Date = Date(), lastSyncAt: Date? = nil) {
        self.siteURL = siteURL
        self.restURL = restURL
        self.userHint = userHint
        self.deviceUUID = deviceUUID
        self.scope = scope
        self.lastCursor = lastCursor
        self.connectedAt = connectedAt
        self.lastSyncAt = lastSyncAt
    }
}

public struct FloppyDeviceApproval: Codable, Equatable, Sendable {
    public let siteURL: URL
    public let deviceUUID: String
    public let token: String
    public let scope: String
    public let state: String
    public let exchangeCode: String?

    public init(siteURL: URL, deviceUUID: String, token: String, scope: String, state: String, exchangeCode: String? = nil) {
        self.siteURL = siteURL
        self.deviceUUID = deviceUUID
        self.token = token
        self.scope = scope
        self.state = state
        self.exchangeCode = exchangeCode
    }

    public var requiresCodeExchange: Bool {
        exchangeCode?.isEmpty == false
    }
}

public struct FloppyDeviceAuthorization: Codable, Equatable, Sendable {
    public let deviceUUID: String
    public let token: String
    public let scope: String

    public init(deviceUUID: String, token: String, scope: String) {
        self.deviceUUID = deviceUUID
        self.token = token
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey {
        case deviceUUID = "device_uuid"
        case token
        case scope
    }
}

public struct WordPressApplicationCredential: Codable, Equatable, Sendable {
    public let siteURL: URL
    public let userLogin: String
    public let password: String
    public let state: String

    public init(siteURL: URL, userLogin: String, password: String, state: String) {
        self.siteURL = siteURL
        self.userLogin = userLogin
        self.password = password
        self.state = state
    }

    public var basicAuthorizationHeader: String {
        let raw = "\(userLogin):\(password)"
        return "Basic \(Data(raw.utf8).base64EncodedString())"
    }
}

public struct WordPressPlugin: Codable, Equatable, Sendable {
    public let plugin: String
    public let status: WordPressPluginStatus
    public let name: String
    public let textdomain: String?

    enum CodingKeys: String, CodingKey {
        case plugin
        case status
        case name
        case textdomain
    }
}

public struct WordPressApplicationPassword: Codable, Equatable, Sendable {
    public let uuid: String
    public let appID: String?
    public let name: String

    enum CodingKeys: String, CodingKey {
        case uuid
        case appID = "app_id"
        case name
    }
}

public enum WordPressPluginStatus: String, Codable, Sendable {
    case inactive
    case active
}

public struct WordPressRESTRoot: Codable, Equatable, Sendable {
    public let authentication: WordPressAuthentication?
}

public struct WordPressAuthentication: Codable, Equatable, Sendable {
    public let applicationPasswords: WordPressApplicationPasswordAuth?

    enum CodingKeys: String, CodingKey {
        case applicationPasswords = "application-passwords"
    }
}

public struct WordPressApplicationPasswordAuth: Codable, Equatable, Sendable {
    public let endpoints: WordPressApplicationPasswordEndpoints
}

public struct WordPressApplicationPasswordEndpoints: Codable, Equatable, Sendable {
    public let authorization: URL
}

public enum FloppyItemKind: String, Codable, Sendable {
    case file
    case folder
}

public struct FloppyItem: Codable, Equatable, Identifiable, Sendable {
    public let kind: FloppyItemKind
    public let id: Int64
    public let uuid: String
    public let attachmentID: Int64?
    public let ownerID: Int64
    public let parentID: Int64
    public let parentUUID: String?
    public let name: String
    public let mimeType: String?
    public let sizeBytes: Int64?
    public let contentHash: String?
    public let contentVersion: String?
    public let metadataVersion: String
    public let status: String
    public let visibility: String?
    public let downloadURL: URL?
    public let createdAtGMT: String
    public let updatedAtGMT: String

    enum CodingKeys: String, CodingKey {
        case kind
        case id
        case uuid
        case attachmentID = "attachment_id"
        case ownerID = "owner_id"
        case parentID = "parent_id"
        case parentUUID = "parent_uuid"
        case name
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case contentHash = "content_hash"
        case contentVersion = "content_version"
        case metadataVersion = "metadata_version"
        case status
        case visibility
        case downloadURL = "download_url"
        case createdAtGMT = "created_at_gmt"
        case updatedAtGMT = "updated_at_gmt"
    }

    public init(
        kind: FloppyItemKind,
        id: Int64,
        uuid: String,
        attachmentID: Int64? = nil,
        ownerID: Int64,
        parentID: Int64,
        parentUUID: String? = nil,
        name: String,
        mimeType: String? = nil,
        sizeBytes: Int64? = nil,
        contentHash: String? = nil,
        contentVersion: String? = nil,
        metadataVersion: String,
        status: String,
        visibility: String? = "private",
        downloadURL: URL? = nil,
        createdAtGMT: String,
        updatedAtGMT: String
    ) {
        self.kind = kind
        self.id = id
        self.uuid = uuid
        self.attachmentID = attachmentID
        self.ownerID = ownerID
        self.parentID = parentID
        self.parentUUID = parentUUID
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.contentHash = contentHash
        self.contentVersion = contentVersion
        self.metadataVersion = metadataVersion
        self.status = status
        self.visibility = visibility
        self.downloadURL = downloadURL
        self.createdAtGMT = createdAtGMT
        self.updatedAtGMT = updatedAtGMT
    }
}

public enum FloppyFileProviderIdentifierCodec {
    public static let itemPrefix = "floppy:item:"

    public static func itemIdentifierRawValue(uuid: String) -> String {
        itemPrefix + uuid
    }

    public static func legacyItemIdentifierRawValue(id: Int64) -> String {
        itemPrefix + String(id)
    }

    public static func itemUUID(from rawValue: String) -> String? {
        guard rawValue.hasPrefix(itemPrefix) else {
            return nil
        }

        let suffix = String(rawValue.dropFirst(itemPrefix.count))
        guard !suffix.isEmpty, Int64(suffix) == nil else {
            return nil
        }
        return suffix
    }

    public static func legacyItemID(from rawValue: String) -> Int64? {
        guard rawValue.hasPrefix(itemPrefix) else {
            return nil
        }

        return Int64(rawValue.dropFirst(itemPrefix.count))
    }
}

public struct FloppyListResponse: Codable, Equatable, Sendable {
    public let parentID: Int64
    public let limit: Int
    public let cursor: String?
    public let nextCursor: String?
    public let hasMore: Bool?
    public let items: [FloppyItem]

    enum CodingKeys: String, CodingKey {
        case parentID = "parent_id"
        case limit
        case cursor
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
        case items
    }
}

public struct FloppyChangeFeed: Codable, Equatable, Sendable {
    public let cursor: UInt64
    public let nextCursor: UInt64
    public let hasMore: Bool
    public let events: [FloppyChange]

    enum CodingKeys: String, CodingKey {
        case cursor
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
        case events
    }
}

public struct FloppyChange: Codable, Equatable, Identifiable, Sendable {
    public var id: UInt64 { sequence }

    public let sequence: UInt64
    public let eventUUID: String
    public let eventType: String
    public let targetType: String
    public let targetID: Int64
    public let parentID: Int64
    public let parentUUID: String?
    public let metadataVersion: String
    public let contentVersion: String
    public let createdAtGMT: String
    public let payload: [String: FloppyJSONValue]

    enum CodingKeys: String, CodingKey {
        case sequence = "seq"
        case eventUUID = "event_uuid"
        case eventType = "event_type"
        case targetType = "target_type"
        case targetID = "target_id"
        case parentID = "parent_id"
        case parentUUID = "parent_uuid"
        case metadataVersion = "metadata_version"
        case contentVersion = "content_version"
        case createdAtGMT = "created_at_gmt"
        case payload
    }
}

public extension FloppyChange {
    var isDeletion: Bool {
        eventType.contains("deleted") || eventType.contains("trashed")
    }

    var deletedItemUUID: String? {
        if case .string(let uuid)? = payload["uuid"] {
            return uuid
        }
        if case .string(let uuid)? = payload["item_uuid"] {
            return uuid
        }
        if case .object(let object)? = payload["item"], case .string(let uuid)? = object["uuid"] {
            return uuid
        }
        return nil
    }

    var floppyItemPayload: FloppyItem? {
        guard !isDeletion else {
            return nil
        }

        if case .object(let object)? = payload["item"],
           let data = try? JSONEncoder.floppy.encode(object) {
            return try? JSONDecoder.floppy.decode(FloppyItem.self, from: data)
        }

        guard let data = try? JSONEncoder.floppy.encode(payload) else {
            return nil
        }
        return try? JSONDecoder.floppy.decode(FloppyItem.self, from: data)
    }
}

public enum FloppyJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case array([FloppyJSONValue])
    case object([String: FloppyJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int64.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([FloppyJSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: FloppyJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct FloppyHealthSummary: Codable, Equatable, Sendable {
    public let ok: Bool
    public let checks: [String: FloppyHealthCheck]
}

public struct FloppyHealthCheck: Codable, Equatable, Sendable {
    public let ok: Bool
    public let label: String
    public let message: String
}

public struct FloppyDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let deviceUUID: String
    public let userID: Int64
    public let deviceName: String
    public let scope: String
    public let status: String
    public let lastCursor: UInt64
    public let lastError: String?
    public let approvedAtGMT: String
    public let lastSeenAtGMT: String?
    public let lastSyncAtGMT: String?
    public let revokedAtGMT: String?

    enum CodingKeys: String, CodingKey {
        case id
        case deviceUUID = "device_uuid"
        case userID = "user_id"
        case deviceName = "device_name"
        case scope
        case status
        case lastCursor = "last_cursor"
        case lastError = "last_error"
        case approvedAtGMT = "approved_at_gmt"
        case lastSeenAtGMT = "last_seen_at_gmt"
        case lastSyncAtGMT = "last_sync_at_gmt"
        case revokedAtGMT = "revoked_at_gmt"
    }
}

public struct FloppyDeviceList: Codable, Equatable, Sendable {
    public let devices: [FloppyDevice]
}

public struct FloppyUploadSession: Codable, Equatable, Sendable {
    public let sessionUUID: String
    public let receivedBytes: Int64
    public let chunkSize: Int
    public let expiresAtGMT: String

    enum CodingKeys: String, CodingKey {
        case sessionUUID = "session_uuid"
        case receivedBytes = "received_bytes"
        case chunkSize = "chunk_size"
        case expiresAtGMT = "expires_at_gmt"
    }
}

public struct FloppyUploadProgress: Codable, Equatable, Sendable {
    public let receivedBytes: Int64

    enum CodingKeys: String, CodingKey {
        case receivedBytes = "received_bytes"
    }
}
