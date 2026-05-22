import FileProvider
import FloppyCore
import Foundation

enum FileProviderDomainController {
    static func register(account: FloppyAccount) async throws {
        let record = FloppyDomainRegistry.record(for: account)
        try FloppyDomainRegistry.save(record)

        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(record.domainIdentifier),
            displayName: record.displayName
        )

        if #available(macOS 15.0, *) {
            domain.userInfo = [
                "accountID": record.accountID,
                "siteURL": record.siteURL.absoluteString,
                "restURL": record.restURL.absoluteString
            ]
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSFileProviderManager.add(domain) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    static func remove(account: FloppyAccount) async throws {
        let record = FloppyDomainRegistry.record(for: account)
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(record.domainIdentifier),
            displayName: record.displayName
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSFileProviderManager.remove(domain) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        try FloppyDomainRegistry.remove(domainIdentifier: record.domainIdentifier)
    }
}
