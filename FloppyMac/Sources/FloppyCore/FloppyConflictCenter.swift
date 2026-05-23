import Foundation

public enum FloppyConflictCenterAction: String, Codable, CaseIterable, Sendable {
    case openLocalCopy = "open_local_copy"
    case revealLocalCopy = "reveal_local_copy"
    case openServerCopy = "open_server_copy"
    case refreshServerCopy = "refresh_server_copy"
    case retryUpload = "retry_upload"
    case keepBoth = "keep_both"
    case discardLocalCopy = "discard_local_copy"
    case markResolved = "mark_resolved"

    public var legacyServerAction: String {
        switch self {
        case .discardLocalCopy:
            "discard"
        case .keepBoth:
            "keep"
        case .retryUpload:
            "retry"
        case .markResolved:
            "resolve"
        default:
            rawValue
        }
    }
}

public struct FloppyConflictCenterItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let accountFingerprint: String
    public let itemUUID: String
    public let displayName: String
    public let reason: String
    public let state: String
    public let parentID: Int64?
    public let parentUUID: String?
    public let materializedPath: String
    public let materializedFileExists: Bool
    public let originalContentVersionFingerprint: String
    public let createdAt: Date
    public let availableActions: [FloppyConflictCenterAction]

    public init(
        id: String,
        accountFingerprint: String,
        itemUUID: String,
        displayName: String,
        reason: String,
        state: String,
        parentID: Int64?,
        parentUUID: String?,
        materializedPath: String,
        materializedFileExists: Bool,
        originalContentVersionFingerprint: String,
        createdAt: Date,
        availableActions: [FloppyConflictCenterAction]
    ) {
        self.id = id
        self.accountFingerprint = accountFingerprint
        self.itemUUID = itemUUID
        self.displayName = displayName
        self.reason = reason
        self.state = state
        self.parentID = parentID
        self.parentUUID = parentUUID
        self.materializedPath = FloppyDiagnostics.redactedFilePath(materializedPath)
        self.materializedFileExists = materializedFileExists
        self.originalContentVersionFingerprint = originalContentVersionFingerprint
        self.createdAt = createdAt
        self.availableActions = availableActions
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountFingerprint = "account_fingerprint"
        case itemUUID = "item_uuid"
        case displayName = "display_name"
        case reason
        case state
        case parentID = "parent_id"
        case parentUUID = "parent_uuid"
        case materializedPath = "materialized_path"
        case materializedFileExists = "materialized_file_exists"
        case originalContentVersionFingerprint = "original_content_version_fingerprint"
        case createdAt = "created_at"
        case availableActions = "available_actions"
    }
}

public struct FloppyConflictCenterSummary: Codable, Equatable, Sendable {
    public let total: Int
    public let open: Int
    public let resolved: Int
    public let missingLocalCopies: Int
    public let availableActions: [FloppyConflictCenterAction]

    public init(
        total: Int,
        open: Int,
        resolved: Int,
        missingLocalCopies: Int,
        availableActions: [FloppyConflictCenterAction] = FloppyConflictCenterAction.allCases
    ) {
        self.total = total
        self.open = open
        self.resolved = resolved
        self.missingLocalCopies = missingLocalCopies
        self.availableActions = availableActions
    }

    public static var empty: FloppyConflictCenterSummary {
        FloppyConflictCenterSummary(total: 0, open: 0, resolved: 0, missingLocalCopies: 0)
    }

    enum CodingKeys: String, CodingKey {
        case total
        case open
        case resolved
        case missingLocalCopies = "missing_local_copies"
        case availableActions = "available_actions"
    }
}

public struct FloppyConflictActionRequest: Codable, Equatable, Sendable {
    public let action: FloppyConflictCenterAction
    public let localItemUUID: String?
    public let baseContentVersion: String?

    public init(action: FloppyConflictCenterAction, localItemUUID: String? = nil, baseContentVersion: String? = nil) {
        self.action = action
        self.localItemUUID = localItemUUID
        self.baseContentVersion = baseContentVersion
    }

    enum CodingKeys: String, CodingKey {
        case action
        case localItemUUID = "local_item_uuid"
        case baseContentVersion = "base_content_version"
    }
}

public struct FloppyServerConflict: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let item: FloppyItem?
    public let localItemUUID: String?
    public let reason: String
    public let state: String
    public let createdAtGMT: String?
    public let updatedAtGMT: String?

    public init(
        id: String,
        item: FloppyItem? = nil,
        localItemUUID: String? = nil,
        reason: String,
        state: String,
        createdAtGMT: String? = nil,
        updatedAtGMT: String? = nil
    ) {
        self.id = id
        self.item = item
        self.localItemUUID = localItemUUID
        self.reason = reason
        self.state = state
        self.createdAtGMT = createdAtGMT
        self.updatedAtGMT = updatedAtGMT
    }

    enum CodingKeys: String, CodingKey {
        case id
        case conflictUUID = "conflict_uuid"
        case item
        case serverFile = "server_file"
        case localItemUUID = "local_item_uuid"
        case reason
        case state
        case status
        case createdAtGMT = "created_at_gmt"
        case updatedAtGMT = "updated_at_gmt"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let conflictUUID = try container.decodeIfPresent(String.self, forKey: .conflictUUID)
        if let conflictUUID, !conflictUUID.isEmpty {
            id = conflictUUID
        } else if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let numericID = try? container.decode(Int64.self, forKey: .id) {
            id = String(numericID)
        } else {
            id = ""
        }
        let decodedItem = try container.decodeIfPresent(FloppyItem.self, forKey: .item)
        let decodedServerFile = try container.decodeIfPresent(FloppyItem.self, forKey: .serverFile)
        item = decodedItem ?? decodedServerFile
        localItemUUID = try container.decodeIfPresent(String.self, forKey: .localItemUUID)
        let decodedReason = try container.decodeIfPresent(String.self, forKey: .reason)
        let decodedState = try container.decodeIfPresent(String.self, forKey: .state)
        let decodedStatus = try container.decodeIfPresent(String.self, forKey: .status)
        reason = decodedReason ?? "conflict"
        state = decodedState ?? decodedStatus ?? "open"
        createdAtGMT = try container.decodeIfPresent(String.self, forKey: .createdAtGMT)
        updatedAtGMT = try container.decodeIfPresent(String.self, forKey: .updatedAtGMT)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(item, forKey: .item)
        try container.encodeIfPresent(localItemUUID, forKey: .localItemUUID)
        try container.encode(reason, forKey: .reason)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(createdAtGMT, forKey: .createdAtGMT)
        try container.encodeIfPresent(updatedAtGMT, forKey: .updatedAtGMT)
    }
}

public struct FloppyServerConflictListResponse: Codable, Equatable, Sendable {
    public let conflicts: [FloppyServerConflict]
    public let nextCursor: String?
    public let hasMore: Bool

    public init(conflicts: [FloppyServerConflict], nextCursor: String? = nil, hasMore: Bool = false) {
        self.conflicts = conflicts
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }

    enum CodingKeys: String, CodingKey {
        case conflicts
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conflicts = try container.decodeIfPresent([FloppyServerConflict].self, forKey: .conflicts) ?? []
        if let stringCursor = try? container.decodeIfPresent(String.self, forKey: .nextCursor) {
            nextCursor = stringCursor
        } else if let numericCursor = try? container.decodeIfPresent(Int64.self, forKey: .nextCursor) {
            nextCursor = numericCursor > 0 ? String(numericCursor) : nil
        } else {
            nextCursor = nil
        }
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conflicts, forKey: .conflicts)
        try container.encodeIfPresent(nextCursor, forKey: .nextCursor)
        try container.encode(hasMore, forKey: .hasMore)
    }
}

public struct FloppyConflictActionResponse: Codable, Equatable, Sendable {
    public let conflict: FloppyServerConflict
    public let canonicalItem: FloppyItem?

    public init(conflict: FloppyServerConflict, canonicalItem: FloppyItem? = nil) {
        self.conflict = conflict
        self.canonicalItem = canonicalItem
    }

    enum CodingKeys: String, CodingKey {
        case conflict
        case canonicalItem = "canonical_item"
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if let conflict = try container.decodeIfPresent(FloppyServerConflict.self, forKey: .conflict) {
                self.conflict = conflict
                self.canonicalItem = try container.decodeIfPresent(FloppyItem.self, forKey: .canonicalItem)
                return
            }
        }

        let conflict = try FloppyServerConflict(from: decoder)
        self.conflict = conflict
        self.canonicalItem = conflict.item
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conflict, forKey: .conflict)
        try container.encodeIfPresent(canonicalItem, forKey: .canonicalItem)
    }
}

public enum FloppyConflictCenterPresenter {
    public static func item(from conflict: FloppyConflict, localFileExists: Bool) -> FloppyConflictCenterItem {
        let isResolved = conflict.state == "resolved"
        var actions: [FloppyConflictCenterAction] = isResolved ? [.openServerCopy] : [.openServerCopy, .refreshServerCopy, .markResolved]
        if localFileExists {
            actions.insert(contentsOf: [.openLocalCopy, .revealLocalCopy, .retryUpload, .keepBoth, .discardLocalCopy], at: 0)
        }

        return FloppyConflictCenterItem(
            id: conflict.id.uuidString,
            accountFingerprint: FloppyDiagnostics.redactedFingerprint(conflict.accountID),
            itemUUID: conflict.itemUUID,
            displayName: conflict.displayName?.isEmpty == false ? conflict.displayName! : conflict.itemUUID,
            reason: conflict.message,
            state: conflict.state ?? "open",
            parentID: conflict.parentID,
            parentUUID: conflict.parentUUID?.isEmpty == false ? conflict.parentUUID : nil,
            materializedPath: conflict.materializedPath ?? "",
            materializedFileExists: localFileExists,
            originalContentVersionFingerprint: FloppyDiagnostics.redactedFingerprint(conflict.originalContentVersion),
            createdAt: conflict.createdAt,
            availableActions: actions
        )
    }
}
