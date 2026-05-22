import FileProvider
import FloppyCore
import Foundation

enum FileProviderDomainController {
    static func register(account: FloppyAccount) async throws {
        let record = FloppyDomainRegistry.record(for: account)
        try FloppyDomainRegistry.save(record)
        let domainLedger = LocalLedger(appGroupIdentifier: FloppyDomainRegistry.appGroupIdentifier, domainIdentifier: record.domainIdentifier)
        try await domainLedger.upsert(account: account)
        await domainLedger.close()

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
                    FloppyDiagnostics.fileProvider.info("Registered File Provider domain \(record.domainIdentifier, privacy: .public)")
                    continuation.resume()
                }
            }
        }
    }

    static func signal(account: FloppyAccount) async {
        let record = FloppyDomainRegistry.record(for: account)
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(record.domainIdentifier),
            displayName: record.displayName
        )

        guard let manager = NSFileProviderManager(for: domain) else {
            return
        }

        let domainLedger = LocalLedger(appGroupIdentifier: FloppyDomainRegistry.appGroupIdentifier, domainIdentifier: record.domainIdentifier)
		let activeIdentifiers = await domainLedger.activeEnumeratorIdentifiers()
		await domainLedger.close()
		var identifiers = [NSFileProviderItemIdentifier.workingSet]
		identifiers.append(contentsOf: activeIdentifiers.map { NSFileProviderItemIdentifier($0) })

        do {
            for identifier in identifiers {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    manager.signalEnumerator(for: identifier) { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
            FloppyDiagnostics.fileProvider.info("Signaled File Provider working set for \(record.domainIdentifier, privacy: .public)")
        } catch {
            FloppyDiagnostics.fileProvider.error("File Provider signal failed: \(error.localizedDescription, privacy: .public)")
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
                    FloppyDiagnostics.fileProvider.info("Removed File Provider domain \(record.domainIdentifier, privacy: .public)")
                    continuation.resume()
                }
            }
        }

        try FloppyDomainRegistry.remove(domainIdentifier: record.domainIdentifier)
    }
}
