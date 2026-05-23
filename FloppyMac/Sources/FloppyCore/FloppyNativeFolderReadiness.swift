import Foundation

public enum FloppyNativeFolderReadinessStatus: String, Sendable {
    case ready
    case missingEmbeddedExtension
    case missingAppGroupEntitlement
}

public struct FloppyNativeFolderReadiness: Equatable, Sendable {
    public static let fileProviderExtensionBundleName = "FloppyFileProviderExtension.appex"

    public let status: FloppyNativeFolderReadinessStatus
    public let extensionURL: URL?
    public let appGroupIdentifier: String

    public var isReady: Bool {
        status == .ready
    }

    public var message: String {
        switch status {
        case .ready:
            "Native Finder folder is available."
        case .missingEmbeddedExtension:
            "This Floppy build does not include the Finder helper. Run the signed Xcode app target, not the SwiftPM test bundle."
        case .missingAppGroupEntitlement:
            "The Finder helper needs App Group signing. Open the Xcode project, select a Team for both targets, then build and run FloppyMac again."
        }
    }

    public static func current(bundle: Bundle = .main, fileManager: FileManager = .default) -> FloppyNativeFolderReadiness {
        let appGroupIdentifier = FloppyDomainRegistry.appGroupIdentifier(bundle: bundle)
        let canOpenAppGroup = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil

        return inspect(
            builtInPlugInsURL: bundle.builtInPlugInsURL,
            appGroupIdentifier: appGroupIdentifier,
            hasAppGroupEntitlement: FloppyDomainRegistry.hasAppGroupEntitlement(appGroupIdentifier) || canOpenAppGroup,
            fileExists: { fileManager.fileExists(atPath: $0.path) }
        )
    }

    public static func inspect(
        builtInPlugInsURL: URL?,
        appGroupIdentifier: String,
        hasAppGroupEntitlement: Bool,
        fileExists: (URL) -> Bool
    ) -> FloppyNativeFolderReadiness {
        let extensionURL = builtInPlugInsURL?.appendingPathComponent(fileProviderExtensionBundleName, isDirectory: true)
        guard let extensionURL, fileExists(extensionURL) else {
            return FloppyNativeFolderReadiness(
                status: .missingEmbeddedExtension,
                extensionURL: extensionURL,
                appGroupIdentifier: appGroupIdentifier
            )
        }

        guard hasAppGroupEntitlement else {
            return FloppyNativeFolderReadiness(
                status: .missingAppGroupEntitlement,
                extensionURL: extensionURL,
                appGroupIdentifier: appGroupIdentifier
            )
        }

        return FloppyNativeFolderReadiness(
            status: .ready,
            extensionURL: extensionURL,
            appGroupIdentifier: appGroupIdentifier
        )
    }
}
