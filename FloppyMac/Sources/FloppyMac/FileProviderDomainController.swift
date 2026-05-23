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
        let signalPlan = FloppyEnumeratorSignalPlan(
            workingSetIdentifier: NSFileProviderItemIdentifier.workingSet.rawValue,
            activeEnumerators: activeIdentifiers
        )

        do {
            for identifier in signalPlan.rawIdentifiers.map({ NSFileProviderItemIdentifier($0) }) {
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
            FloppyDiagnostics.fileProvider.info("Signaled \(signalPlan.rawIdentifiers.count, privacy: .public) File Provider enumerator(s) for \(record.domainIdentifier, privacy: .public)")
        } catch {
            FloppyDiagnostics.fileProvider.error("File Provider signal failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func reconcile(account: FloppyAccount) async throws {
        let keychainAvailable = (try? KeychainTokenStore.default().load(accountID: account.id)) != nil
        let diagnostic = await lifecycleDiagnostic(account: account, keychainAvailable: keychainAvailable)

        switch diagnostic.state {
        case .configured:
            return
        case .nativeFolderNotReady:
            throw FileProviderFolderError.notReady(readiness())
        case .missingToken, .revokedToken:
            throw FileProviderFolderError.missingToken
        case .registryMissing, .domainUnavailable, .unconfigured:
            try await register(account: account, strict: true)
        case .needsLedgerRepair, .materializationStuck:
            throw FileProviderFolderError.ledgerNeedsRepair
        case .serverUnreachable, .reconnectFailed:
            try await register(account: account, strict: false)
        }
    }

    static func lifecycleDiagnostic(account: FloppyAccount?, keychainAvailable: Bool) async -> FloppyFileProviderLifecycleDiagnostic {
        guard let account else {
            let readiness = readiness()
            return FloppyFileProviderLifecycleDiagnostic(
                state: .unconfigured,
                message: "No Floppy account is selected.",
                domainIdentifierFingerprint: "",
                displayName: "",
                readinessStatus: readiness.status.rawValue,
                registeredInLocalRegistry: false,
                keychainTokenAvailable: false,
                ledgerOK: true,
                activeEnumeratorCount: 0
            )
        }

        let record = FloppyDomainRegistry.record(for: account)
        let readiness = readiness()
        let registeredInLocalRegistry = (try? FloppyDomainRegistry.load(domainIdentifier: record.domainIdentifier)) != nil
        let registeredInSystem = NSFileProviderManager(for: NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(record.domainIdentifier),
            displayName: record.displayName
        )) != nil
        let domainLedger = LocalLedger(appGroupIdentifier: FloppyDomainRegistry.appGroupIdentifier, domainIdentifier: record.domainIdentifier)
        let integrity = await domainLedger.integrityReport(accountID: account.id)
        let activeEnumeratorIdentifiers = await domainLedger.activeEnumeratorIdentifiers()
        let activeEnumeratorCount = activeEnumeratorIdentifiers.count
        await domainLedger.close()

        let state: FloppyFileProviderLifecycleState
        let message: String
        if !readiness.isReady {
            state = .nativeFolderNotReady
            message = readiness.message
        } else if !keychainAvailable {
            state = .missingToken
            message = "Reconnect this site to create a new Keychain token."
        } else if !registeredInLocalRegistry {
            state = .registryMissing
            message = "The File Provider domain is not present in Floppy's local registry."
        } else if !registeredInSystem {
            state = .domainUnavailable
            message = "macOS does not currently expose the registered Floppy File Provider domain."
        } else if !integrity.ok {
            state = .needsLedgerRepair
            message = "The File Provider ledger needs repair before it can be trusted."
        } else {
            state = .configured
            message = "The File Provider domain is configured and ready for Finder sync."
        }

        return FloppyFileProviderLifecycleDiagnostic(
            state: state,
            message: message,
            domainIdentifierFingerprint: FloppyDiagnostics.redactedFingerprint(record.domainIdentifier),
            displayName: record.displayName,
            readinessStatus: readiness.status.rawValue,
            registeredInLocalRegistry: registeredInLocalRegistry,
            keychainTokenAvailable: keychainAvailable,
            ledgerOK: integrity.ok,
            activeEnumeratorCount: activeEnumeratorCount
        )
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
    case ledgerNeedsRepair
    case missingToken

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The native Floppy Finder folder is not available yet. Build and run the Xcode app with the File Provider extension, then reconnect this site."
        case .notReady(let readiness):
            readiness.message
        case .helperUnavailable:
            "macOS could not start the Floppy Finder helper. Open FloppyMac.xcodeproj, set a signing Team for both the app and File Provider extension, then build and run the FloppyMac scheme."
        case .ledgerNeedsRepair:
            "The Floppy Finder ledger needs repair before native sync can continue."
        case .missingToken:
            "Reconnect this WordPress site so Floppy can refresh the scoped device token in Keychain."
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
