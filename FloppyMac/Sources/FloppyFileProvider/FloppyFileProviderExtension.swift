import FileProvider
import Foundation
import FloppyCore
import UniformTypeIdentifiers

final class FloppyFileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private let apiClient: FloppyAPIClient?
    private let configurationError: Error?
    private let ledger: LocalLedger

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        do {
            self.apiClient = try FloppyFileProviderConfiguration.makeAPIClient(for: domain)
            self.configurationError = nil
        } catch {
            self.apiClient = nil
            self.configurationError = error
            FloppyDiagnostics.fileProvider.error("File Provider configuration failed: \(error.localizedDescription, privacy: .public)")
        }
        self.ledger = FloppyFileProviderConfiguration.makeLedger(for: domain)
        super.init()
    }

    func invalidate() {
        Task {
            await ledger.close()
        }
    }

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            if identifier == .rootContainer {
                progress.completedUnitCount = 1
                completionHandler(FloppyFileProviderItem(item: .rootFileProviderItem), nil)
                return
            }

            if let item = await resolveItem(identifier) {
                progress.completedUnitCount = 1
                completionHandler(await fileProviderItem(for: item), nil)
            } else {
                completionHandler(nil, NSFileProviderError(.noSuchItem))
            }
        }
        return progress
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard let apiClient else {
            throw NSFileProviderError(.notAuthenticated)
        }

        if containerItemIdentifier == .workingSet {
            return FloppyFileProviderEnumerator(workingSetWith: apiClient, ledger: ledger)
        }

        Task {
            await ledger.recordActiveEnumerator(containerItemIdentifier.rawValue)
        }

        return FloppyFileProviderEnumerator(containerItemIdentifier: containerItemIdentifier, apiClient: apiClient, ledger: ledger)
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 100)

        guard itemIdentifier.floppyItemUUID != nil || itemIdentifier.floppyLegacyItemID != nil else {
            completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
            return progress
        }

        let task = Task {
            do {
                guard let apiClient else {
                    throw NSFileProviderError(.notAuthenticated)
                }
                guard let item = await resolveItem(itemIdentifier) else {
                    throw NSFileProviderError(.noSuchItem)
                }

                if item.isLocalConflict, let localURL = await ledger.materializedURL(for: item), FileManager.default.fileExists(atPath: localURL.path) {
                    progress.completedUnitCount = 100
                    completionHandler(localURL, await fileProviderItem(for: item), nil)
                    return
                }

                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FloppyFileProvider", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(UUID().uuidString + "-" + item.name)
                try await apiClient.download(file: item, to: destination)
                try await ledger.markMaterialized(item: item, localURL: destination)
                progress.completedUnitCount = 100
                completionHandler(destination, await fileProviderItem(for: item), nil)
            } catch {
                completionHandler(nil, nil, error)
            }
        }

        progress.cancellationHandler = {
            task.cancel()
        }

        return progress
    }

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 100)
        let task = Task {
            do {
                guard let apiClient else {
                    throw NSFileProviderError(.notAuthenticated)
                }
                let parentID = try await resolveParentID(itemTemplate.parentItemIdentifier)
                let item: FloppyItem
                if itemTemplate.contentType == .folder {
                    item = try await apiClient.createFolder(name: itemTemplate.filename, parentID: parentID)
                } else if let url {
                    item = try await apiClient.uploadFile(
                        at: url,
                        filename: itemTemplate.filename,
                        parentID: parentID,
                        mimeType: itemTemplate.contentType?.preferredMIMEType ?? "application/octet-stream"
                    ) { sent, total in
                        progress.completedUnitCount = total > 0 ? min(Int64(99), Int64(Double(sent) / Double(total) * 99.0)) : 0
                    }
                } else {
                    throw NSFileProviderError(.cannotSynchronize)
                }

                try await ledger.upsert(item: item)
                await signalEnumerators()
                progress.completedUnitCount = 100
                completionHandler(await fileProviderItem(for: item), [], false, nil)
            } catch {
                completionHandler(nil, fields, false, error)
            }
        }
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 100)

        guard item.itemIdentifier.floppyItemUUID != nil || item.itemIdentifier.floppyLegacyItemID != nil else {
            completionHandler(nil, changedFields, false, NSFileProviderError(.noSuchItem))
            return progress
        }

        let task = Task {
            do {
                guard let apiClient else {
                    throw NSFileProviderError(.notAuthenticated)
                }
                guard var current = await resolveItem(item.itemIdentifier) else {
                    throw NSFileProviderError(.noSuchItem)
                }

                if changedFields.contains(.filename), current.name != item.filename {
                    current = current.kind == .folder
                        ? try await apiClient.renameFolder(id: current.id, name: item.filename, metadataVersion: version.floppyMetadataVersion)
                        : try await apiClient.renameFile(id: current.id, name: item.filename, metadataVersion: version.floppyMetadataVersion)
                }

                if changedFields.contains(.parentItemIdentifier) {
                    let parentID = try await resolveParentID(item.parentItemIdentifier)
                    if current.parentID != parentID {
                        current = current.kind == .folder
                            ? try await apiClient.moveFolder(id: current.id, parentID: parentID, metadataVersion: current.metadataVersion)
                            : try await apiClient.moveFile(id: current.id, parentID: parentID, metadataVersion: current.metadataVersion)
                    }
                }

                if let newContents, current.kind == .file {
                    do {
                        current = try await apiClient.replaceFile(
                            id: current.id,
                            at: newContents,
                            filename: current.name,
                            contentVersion: version.floppyContentVersion,
                            mimeType: item.contentType?.preferredMIMEType ?? current.mimeType ?? "application/octet-stream"
                        ) { sent, total in
                            progress.completedUnitCount = total > 0 ? min(Int64(99), Int64(Double(sent) / Double(total) * 99.0)) : 0
                        }
                    } catch FloppyAPIError.httpStatus(let status, _) where status == 409 || status == 428 {
                        let conflictItem = try await createLocalConflict(for: current, editedURL: newContents, contentType: item.contentType)
                        try? await refreshParent(parentID: current.parentID, apiClient: apiClient)
                        await signalEnumerators()
                        progress.completedUnitCount = 100
                        completionHandler(await fileProviderItem(for: conflictItem), [], false, nil)
                        return
                    }
                }

                try await ledger.upsert(item: current)
                await signalEnumerators()
                progress.completedUnitCount = 100
                completionHandler(await fileProviderItem(for: current), [], false, nil)
            } catch {
                completionHandler(nil, changedFields, false, error)
            }
        }

        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        guard identifier.floppyItemUUID != nil || identifier.floppyLegacyItemID != nil else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return progress
        }

        let task = Task {
            do {
                guard let item = await resolveItem(identifier) else {
                    throw NSFileProviderError(.cannotSynchronize)
                }

                if item.isLocalConflict {
                    if let localURL = await ledger.materializedURL(for: item) {
                        try? FileManager.default.removeItem(at: localURL)
                    }
                    try await ledger.removeItem(uuid: item.uuid)
                    await signalEnumerators()
                    progress.completedUnitCount = 1
                    completionHandler(nil)
                    return
                }

                guard let apiClient else {
                    throw NSFileProviderError(.notAuthenticated)
                }

                if item.kind == .folder {
                    if options.contains(.recursive) {
                        try await apiClient.deleteFolder(id: item.id, metadataVersion: version.floppyMetadataVersion)
                    } else {
                        try await apiClient.trashFolder(id: item.id, metadataVersion: version.floppyMetadataVersion)
                    }
                } else if options.contains(.recursive) {
                    try await apiClient.deleteFile(id: item.id, metadataVersion: version.floppyMetadataVersion)
                } else {
                    try await apiClient.trashFile(id: item.id, metadataVersion: version.floppyMetadataVersion)
                }
                try await ledger.removeItem(uuid: item.uuid)
                await signalEnumerators()
                progress.completedUnitCount = 1
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }

        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    private func resolveItem(_ identifier: NSFileProviderItemIdentifier) async -> FloppyItem? {
        if let uuid = identifier.floppyItemUUID {
            return await ledger.item(uuid: uuid)
        }
        if let legacyID = identifier.floppyLegacyItemID {
            return await ledger.item(id: legacyID)
        }
        return nil
    }

    private func resolveParentID(_ identifier: NSFileProviderItemIdentifier) async throws -> Int64 {
        if identifier == .rootContainer {
            return 0
        }
        if let uuid = identifier.floppyItemUUID, let parent = await ledger.item(uuid: uuid) {
            return parent.id
        }
        if let legacyID = identifier.floppyLegacyItemID {
            return legacyID
        }
        throw NSFileProviderError(.noSuchItem)
    }

    private func fileProviderItem(for item: FloppyItem) async -> FloppyFileProviderItem {
        FloppyFileProviderItem(item: item, parentItemIdentifier: await parentIdentifier(for: item))
    }

    private func createLocalConflict(for original: FloppyItem, editedURL: URL, contentType: UTType?) async throws -> FloppyItem {
        let uuid = "local-conflict-\(UUID().uuidString)"
        let filename = Self.conflictFilename(for: original.name)
        let localURL = try await ledger.conflictFileURL(uuid: uuid, filename: filename)
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try FileManager.default.copyItem(at: editedURL, to: localURL)

        let size = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? NSNumber)?.int64Value
        let conflictItem = FloppyItem(
            kind: .file,
            id: -Int64(Date().timeIntervalSince1970),
            uuid: uuid,
            attachmentID: nil,
            ownerID: original.ownerID,
            parentID: original.parentID,
            parentUUID: original.parentUUID,
            name: filename,
            mimeType: contentType?.preferredMIMEType ?? original.mimeType ?? "application/octet-stream",
            sizeBytes: size,
            contentHash: nil,
            contentVersion: "local-conflict",
            metadataVersion: "local-conflict",
            status: "active",
            visibility: "private",
            downloadURL: nil,
            createdAtGMT: Self.mysqlDateFormatter.string(from: Date()),
            updatedAtGMT: Self.mysqlDateFormatter.string(from: Date())
        )
        let conflict = FloppyConflict(
            accountID: "",
            itemUUID: conflictItem.uuid,
            message: "Local edit preserved after the server copy changed.",
            displayName: filename,
            parentID: original.parentID,
            parentUUID: original.parentUUID,
            materializedPath: localURL.path,
            originalContentVersion: original.contentVersion,
            state: "open"
        )
        try await ledger.recordConflict(conflict: conflict, item: conflictItem, localURL: localURL)
        return conflictItem
    }

    private func refreshParent(parentID: Int64, apiClient: FloppyAPIClient) async throws {
        let response = try await apiClient.listFiles(parentID: parentID, limit: 100)
        try await ledger.upsert(items: response.items)
    }

    private func signalEnumerators() async {
        guard let manager = NSFileProviderManager(for: domain) else {
            return
        }
        var identifiers = [NSFileProviderItemIdentifier.workingSet]
        identifiers.append(contentsOf: await ledger.activeEnumeratorIdentifiers().map { NSFileProviderItemIdentifier($0) })
        for identifier in identifiers {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    manager.signalEnumerator(for: identifier) { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            } catch {
                FloppyDiagnostics.fileProvider.error("File Provider signal failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func parentIdentifier(for item: FloppyItem) async -> NSFileProviderItemIdentifier {
        guard item.parentID != 0 else {
            return .rootContainer
        }

        if let parentUUID = item.parentUUID, !parentUUID.isEmpty {
            return NSFileProviderItemIdentifier(FloppyFileProviderIdentifierCodec.itemIdentifierRawValue(uuid: parentUUID))
        }

        if let parent = await ledger.item(id: item.parentID) {
            return parent.fileProviderIdentifier
        }

        return NSFileProviderItemIdentifier(FloppyFileProviderIdentifierCodec.legacyItemIdentifierRawValue(id: item.parentID))
    }

    private static func conflictFilename(for name: String) -> String {
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let stamp = conflictDateFormatter.string(from: Date())
        let conflictBase = "\(base) (Floppy conflict \(stamp))"
        return ext.isEmpty ? conflictBase : "\(conflictBase).\(ext)"
    }

    private static let conflictDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    private static let mysqlDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private extension NSFileProviderItemVersion {
    var floppyMetadataVersion: String {
        String(data: metadataVersion, encoding: .utf8) ?? ""
    }

    var floppyContentVersion: String {
        String(data: contentVersion, encoding: .utf8) ?? ""
    }
}
