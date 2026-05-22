import FileProvider
import Foundation
import FloppyCore
import UniformTypeIdentifiers

final class FloppyFileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private let apiClient: FloppyAPIClient
    private let ledger: LocalLedger

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        self.apiClient = (try? FloppyFileProviderConfiguration.makeAPIClient(for: domain))
            ?? FloppyAPIClient(siteURL: URL(string: "https://invalid.local")!)
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

            guard let itemID = identifier.floppyItemID else {
                completionHandler(nil, NSFileProviderError(.noSuchItem))
                return
            }

            if let item = await ledger.item(id: itemID) {
                progress.completedUnitCount = 1
                completionHandler(FloppyFileProviderItem(item: item), nil)
            } else {
                completionHandler(nil, NSFileProviderError(.noSuchItem))
            }
        }
        return progress
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
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

        guard let itemID = itemIdentifier.floppyItemID else {
            completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
            return progress
        }

        let task = Task {
            do {
                guard let item = await ledger.item(id: itemID) else {
                    throw NSFileProviderError(.noSuchItem)
                }

                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FloppyFileProvider", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(UUID().uuidString + "-" + item.name)
                try await apiClient.download(file: item, to: destination)
                try await ledger.markMaterialized(item: item, localURL: destination)
                progress.completedUnitCount = 100
                completionHandler(destination, FloppyFileProviderItem(item: item), nil)
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
                let parentID = itemTemplate.parentItemIdentifier == .rootContainer ? 0 : (itemTemplate.parentItemIdentifier.floppyItemID ?? 0)
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
                completionHandler(FloppyFileProviderItem(item: item), [], false, nil)
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

        guard let itemID = item.itemIdentifier.floppyItemID else {
            completionHandler(nil, changedFields, false, NSFileProviderError(.noSuchItem))
            return progress
        }

        let task = Task {
            do {
                guard var current = await ledger.item(id: itemID) else {
                    throw NSFileProviderError(.noSuchItem)
                }

                if changedFields.contains(.filename), current.name != item.filename {
                    current = try await apiClient.renameFile(id: current.id, name: item.filename, metadataVersion: version.floppyMetadataVersion)
                }

                if changedFields.contains(.parentItemIdentifier) {
                    let parentID = item.parentItemIdentifier == .rootContainer ? 0 : (item.parentItemIdentifier.floppyItemID ?? 0)
                    if current.parentID != parentID {
                        current = try await apiClient.moveFile(id: current.id, parentID: parentID, metadataVersion: current.metadataVersion)
                    }
                }

                if let newContents {
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
                completionHandler(FloppyFileProviderItem(item: current), [], false, nil)
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

        guard let itemID = identifier.floppyItemID else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return progress
        }

        let task = Task {
            do {
                guard let item = await ledger.item(id: itemID), item.kind == .file else {
                    throw NSFileProviderError(.cannotSynchronize)
                }

                if options.contains(.recursive) {
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
}

private extension NSFileProviderItemVersion {
    var floppyMetadataVersion: String {
        String(data: metadataVersion, encoding: .utf8) ?? ""
    }

    var floppyContentVersion: String {
        String(data: contentVersion, encoding: .utf8) ?? ""
    }
}
