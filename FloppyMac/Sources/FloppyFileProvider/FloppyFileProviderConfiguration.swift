import FileProvider
import Foundation
import FloppyCore

enum FloppyFileProviderConfiguration {
    static let appGroupIdentifier = FloppyDomainRegistry.appGroupIdentifier
    static let tokenService = "com.floppy.mac.token"

    static func makeAPIClient(for domain: NSFileProviderDomain) throws -> FloppyAPIClient {
        let userInfo: [AnyHashable: Any]
        if #available(macOS 15.0, *) {
            userInfo = domain.userInfo ?? [:]
        } else {
            userInfo = [:]
        }

        let registryRecord: FloppyDomainRecord?
        do {
            registryRecord = try FloppyDomainRegistry.load(domainIdentifier: domain.identifier.rawValue)
        } catch {
            registryRecord = nil
            FloppyDiagnostics.fileProvider.error("File Provider domain registry lookup failed: \(error.localizedDescription, privacy: .public)")
        }
        let accountID = (userInfo["accountID"] as? String) ?? registryRecord?.accountID ?? domain.identifier.rawValue
        guard let siteURL = (userInfo["siteURL"] as? String).flatMap(URL.init(string:)) ?? registryRecord?.siteURL else {
            throw FloppyAPIError.invalidSiteURL
        }

        let restURL = (userInfo["restURL"] as? String).flatMap(URL.init(string:)) ?? registryRecord?.restURL
        let token = try KeychainTokenStore.default(service: tokenService).load(accountID: accountID)
        return FloppyAPIClient(siteURL: siteURL, restURL: restURL, token: token)
    }

    static func makeLedger(for domain: NSFileProviderDomain) -> LocalLedger {
        LocalLedger(appGroupIdentifier: appGroupIdentifier, domainIdentifier: domain.identifier.rawValue)
    }
}
