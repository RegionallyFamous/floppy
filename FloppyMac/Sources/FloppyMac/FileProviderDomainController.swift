import FileProvider
import FloppyCore
import Foundation

enum FileProviderDomainController {
    static func readiness() -> FloppyNativeFolderReadiness {
        FloppyNativeFolderReadiness.current()
    }

    static func register(account: FloppyAccount, strict: Bool = false) async throws {
        let record = FloppyDomainRegistry.record(for: account)
        try FloppyDomainRegistry.save(record)
        let domainLedger = LocalLedger(appGroupIdentifier: FloppyDomainRegistry.appGroupIdentifier, domainIdentifier: record.domainIdentifier)
        try await domainLedger.upsert(account: account)
        await domainLedger.close()

        let readiness = readiness()
        guard readiness.isReady else {
            FloppyDiagnostics.fileProvider.error("File Provider registration skipped: \(readiness.message, privacy: .public)")
            if strict {
                throw FileProviderFolderError.notReady(readiness)
            }
            return
        }

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

        do {
            try await addFileProviderDomain(domain, timeout: 5)
            FloppyDiagnostics.fileProvider.info("Registered File Provider domain \(record.domainIdentifier, privacy: .public)")
        } catch {
            FloppyDiagnostics.fileProvider.error("File Provider domain registration skipped: \(error.localizedDescription, privacy: .public)")
            if strict {
                throw FileProviderFolderError.helperUnavailable(error)
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

    static func userVisibleRootURL(account: FloppyAccount) async throws -> URL {
        let readiness = readiness()
        guard readiness.isReady else {
            throw FileProviderFolderError.notReady(readiness)
        }

        let record = FloppyDomainRegistry.record(for: account)
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(record.domainIdentifier),
            displayName: record.displayName
        )

        guard let manager = NSFileProviderManager(for: domain) else {
            throw FileProviderFolderError.unavailable
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            manager.getUserVisibleURL(for: .rootContainer) { url, error in
                if let error {
                    continuation.resume(throwing: FileProviderFolderError.helperUnavailable(error))
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: FileProviderFolderError.unavailable)
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
                    FloppyDiagnostics.fileProvider.info("Removed File Provider domain \(record.domainIdentifier, privacy: .public)")
                    continuation.resume()
                }
            }
        }

        try FloppyDomainRegistry.remove(domainIdentifier: record.domainIdentifier)
    }

    private static func addFileProviderDomain(_ domain: NSFileProviderDomain, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = FileProviderRegistrationContinuationGate()
            NSFileProviderManager.add(domain) { error in
                if let error {
                    gate.resume(continuation, with: .failure(error))
                } else {
                    gate.resume(continuation, with: .success(()))
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                gate.resume(continuation, with: .failure(FileProviderDomainRegistrationError.timedOut))
            }
        }
    }
}

private final class FileProviderRegistrationContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<Void, Error>, with result: Result<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else {
            return
        }

        didResume = true
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private enum FileProviderFolderError: LocalizedError {
    case unavailable
    case notReady(FloppyNativeFolderReadiness)
    case helperUnavailable(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The native Floppy Finder folder is not available yet. Build and run the Xcode app with the File Provider extension, then reconnect this site."
        case .notReady(let readiness):
            readiness.message
        case .helperUnavailable:
            "macOS could not start the Floppy Finder helper. Open FloppyMac.xcodeproj, set a signing Team for both the app and File Provider extension, then build and run the FloppyMac scheme."
        }
    }
}

private enum FileProviderDomainRegistrationError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "Timed out waiting for File Provider registration."
        }
    }
}
