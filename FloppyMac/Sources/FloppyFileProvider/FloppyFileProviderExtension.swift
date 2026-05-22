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
                    let data = try Data(contentsOf: url)
                    item = try await apiClient.upload(data: data, filename: itemTemplate.filename, parentID: parentID, mimeType: itemTemplate.contentType?.preferredMIMEType ?? "application/octet-stream")
                } else {
                    throw NSFileProviderError(.cannotSynchronize)
                }

                try await ledger.upsert(item: item)
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
                    let data = try Data(contentsOf: newContents)
                    current = try await apiClient.replaceFile(
                        id: current.id,
                        data: data,
                        filename: current.name,
                        contentVersion: version.floppyContentVersion,
                        mimeType: item.contentType?.preferredMIMEType ?? current.mimeType ?? "application/octet-stream"
                    )
                }

                try await ledger.upsert(item: current)
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
                guard let apiClient else {
                    throw NSFileProviderError(.notAuthenticated)
                }
                guard let item = await resolveItem(identifier) else {
                    throw NSFileProviderError(.cannotSynchronize)
                }

                if item.kind == .folder {
                    if options.contains(.recursive) {
                        try await apiClient.deleteFolder(id: item.id)
                    } else {
                        try await apiClient.trashFolder(id: item.id, metadataVersion: version.floppyMetadataVersion)
                    }
                } else if options.contains(.recursive) {
                    try await apiClient.deleteFile(id: item.id)
                } else {
                    try await apiClient.trashFile(id: item.id, metadataVersion: version.floppyMetadataVersion)
                }
                try await ledger.removeItem(uuid: item.uuid)
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

    private func parentIdentifier(for item: FloppyItem) async -> NSFileProviderItemIdentifier {
        guard item.parentID != 0 else {
            return .rootContainer
        }

        if let parent = await ledger.item(id: item.parentID) {
            return parent.fileProviderIdentifier
        }

        return NSFileProviderItemIdentifier(FloppyFileProviderIdentifierCodec.legacyItemIdentifierRawValue(id: item.parentID))
    }
}

private extension NSFileProviderItemVersion {
    var floppyMetadataVersion: String {
        String(data: metadataVersion, encoding: .utf8) ?? ""
    }

    var floppyContentVersion: String {
        String(data: contentVersion, encoding: .utf8) ?? ""
    }
}
