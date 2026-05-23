import Foundation

public enum FloppyTransferError: Error, Equatable, LocalizedError {
    case checksumMismatch(expected: String, actual: String)
    case retryLimitExceeded(attempts: Int)

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "Downloaded file checksum did not match the server metadata."
        case .retryLimitExceeded(let attempts):
            return "Transfer failed after \(attempts) attempt(s)."
        }
    }
}

public struct FloppyTransferRetryPolicy: Equatable, Sendable {
    public let maximumAttempts: Int
    public let initialDelaySeconds: Double

    public init(maximumAttempts: Int = 3, initialDelaySeconds: Double = 0.25) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.initialDelaySeconds = max(0, initialDelaySeconds)
    }

    public static let `default` = FloppyTransferRetryPolicy()
    public static let singleAttempt = FloppyTransferRetryPolicy(maximumAttempts: 1, initialDelaySeconds: 0)
}

public struct FloppyMaterializationResult: Codable, Equatable, Sendable {
    public let destinationPath: String
    public let retries: Int
    public let checksumValidated: Bool
    public let checksumFailures: Int
    public let partialFileQuarantinePath: String?

    public init(
        destinationPath: String,
        retries: Int,
        checksumValidated: Bool,
        checksumFailures: Int,
        partialFileQuarantinePath: String? = nil
    ) {
        self.destinationPath = FloppyDiagnostics.redactedFilePath(destinationPath)
        self.retries = retries
        self.checksumValidated = checksumValidated
        self.checksumFailures = checksumFailures
        self.partialFileQuarantinePath = partialFileQuarantinePath.map(FloppyDiagnostics.redactedFilePath)
    }

    enum CodingKeys: String, CodingKey {
        case destinationPath = "destination_path"
        case retries
        case checksumValidated = "checksum_validated"
        case checksumFailures = "checksum_failures"
        case partialFileQuarantinePath = "partial_file_quarantine_path"
    }
}

public enum FloppyPartialFileQuarantine {
    public static func quarantineURL(for destination: URL, reason: String, date: Date = Date()) -> URL {
        let directory = destination.deletingLastPathComponent().appendingPathComponent(".floppy-quarantine", isDirectory: true)
        let stamp = String(Int(date.timeIntervalSince1970))
        let safeReason = reason.safePathComponent
        return directory.appendingPathComponent("\(destination.lastPathComponent).\(stamp).\(safeReason)")
    }
}

private extension String {
    var safePathComponent: String {
        replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "-", options: .regularExpression)
    }
}
