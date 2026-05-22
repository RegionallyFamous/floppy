import FileProvider
import Foundation
import FloppyCore
import UniformTypeIdentifiers

final class FloppyFileProviderItem: NSObject, NSFileProviderItem {
    let item: FloppyItem
    private let resolvedParentItemIdentifier: NSFileProviderItemIdentifier?

    init(item: FloppyItem, parentItemIdentifier: NSFileProviderItemIdentifier? = nil) {
        self.item = item
        self.resolvedParentItemIdentifier = parentItemIdentifier
        super.init()
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        item.fileProviderIdentifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        resolvedParentItemIdentifier ?? item.parentFileProviderIdentifier ?? .rootContainer
    }

    var filename: String {
        item.name.isEmpty ? "Floppy" : item.name
    }

    var contentType: UTType {
        if item.kind == .folder {
            return .folder
        }
        if let mimeType = item.mimeType, let type = UTType(mimeType: mimeType) {
            return type
        }
        return .data
    }

    var capabilities: NSFileProviderItemCapabilities {
        var capabilities: NSFileProviderItemCapabilities = [.allowsReading]
        if item.status == "active" {
            capabilities.insert(.allowsWriting)
            capabilities.insert(.allowsRenaming)
            capabilities.insert(.allowsReparenting)
            capabilities.insert(.allowsTrashing)
            capabilities.insert(.allowsDeleting)
        }
        if item.kind == .folder {
            capabilities.insert(.allowsAddingSubItems)
        }
        return capabilities
    }

    var documentSize: NSNumber? {
        item.sizeBytes.map(NSNumber.init(value:))
    }

    var creationDate: Date? {
        item.createdAt
    }

    var contentModificationDate: Date? {
        item.updatedAt
    }

    var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(
            contentVersion: (item.contentVersion ?? item.metadataVersion).data(using: .utf8) ?? Data(),
            metadataVersion: item.metadataVersion.data(using: .utf8) ?? Data()
        )
    }
}

extension FloppyItem {
    static var rootFileProviderItem: FloppyItem {
        FloppyItem(
            kind: .folder,
            id: 0,
            uuid: "root",
            ownerID: 0,
            parentID: 0,
            name: "Floppy",
            metadataVersion: "root",
            status: "active",
            createdAtGMT: "",
            updatedAtGMT: ""
        )
    }

    var fileProviderIdentifier: NSFileProviderItemIdentifier {
        id == 0 ? .rootContainer : NSFileProviderItemIdentifier(FloppyFileProviderIdentifierCodec.itemIdentifierRawValue(uuid: uuid))
    }

    var parentFileProviderIdentifier: NSFileProviderItemIdentifier? {
        if let parentUUID, !parentUUID.isEmpty {
            return NSFileProviderItemIdentifier(FloppyFileProviderIdentifierCodec.itemIdentifierRawValue(uuid: parentUUID))
        }
        return parentID == 0 ? nil : NSFileProviderItemIdentifier(FloppyFileProviderIdentifierCodec.legacyItemIdentifierRawValue(id: parentID))
    }

    var createdAt: Date? {
        Self.dateFormatter.date(from: createdAtGMT)
    }

    var updatedAt: Date? {
        Self.dateFormatter.date(from: updatedAtGMT)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

extension NSFileProviderItemIdentifier {
    var floppyItemUUID: String? {
        FloppyFileProviderIdentifierCodec.itemUUID(from: rawValue)
    }

    var floppyLegacyItemID: Int64? {
        FloppyFileProviderIdentifierCodec.legacyItemID(from: rawValue)
    }
}
