import Foundation

public enum FloppyDownloadSecurityError: Error, Equatable, LocalizedError {
    case insecureDownloadURL(URL)
    case untrustedDownloadURL(URL)
    case invalidGitHubReleaseURL(URL)
    case invalidZipArchive
    case zipArchiveTooLarge(Int64)
    case unsafeZipEntry(String)
    case missingPluginMainFile(String)
    case unexpectedPluginRoot(String)

    public var errorDescription: String? {
        switch self {
        case .insecureDownloadURL:
            "Download URLs must use HTTPS unless they point at localhost for development."
        case .untrustedDownloadURL(let url):
            "Rejected download from untrusted origin: \(FloppyDiagnostics.redactedURL(url))."
        case .invalidGitHubReleaseURL:
            "Enter an HTTPS GitHub release asset ZIP URL."
        case .invalidZipArchive:
            "The downloaded file is not a valid ZIP archive."
        case .zipArchiveTooLarge(let bytes):
            "The downloaded ZIP is too large (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))."
        case .unsafeZipEntry(let entry):
            "The ZIP contains an unsafe path: \(entry)."
        case .missingPluginMainFile(let path):
            "The ZIP does not contain \(path)."
        case .unexpectedPluginRoot(let root):
            "The ZIP contents are not rooted in \(root)/."
        }
    }
}

public struct FloppyDownloadOriginPolicy: Sendable {
    private let trustedOrigins: Set<Origin>

    public init(siteURL: URL, restURL: URL) {
        self.trustedOrigins = Set([Origin(url: siteURL), Origin(url: restURL)].compactMap { $0 })
    }

    public init(allowedURLs: [URL]) {
        self.trustedOrigins = Set(allowedURLs.compactMap(Origin.init(url:)))
    }

    public func validate(_ url: URL) throws {
        guard let origin = Origin(url: url), trustedOrigins.contains(origin) else {
            throw FloppyDownloadSecurityError.untrustedDownloadURL(url)
        }

        if origin.scheme != "https", !origin.isLocalDevelopmentHTTP {
            throw FloppyDownloadSecurityError.insecureDownloadURL(url)
        }
    }

    public func validate(response: URLResponse) throws {
        guard let url = response.url else {
            return
        }
        try validate(url)
    }

    public func allows(_ url: URL) -> Bool {
        (try? validate(url)) != nil
    }

    private struct Origin: Hashable, Sendable {
        let scheme: String
        let host: String
        let port: Int?

        init?(url: URL) {
            guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
                return nil
            }

            self.scheme = scheme
            self.host = host
            self.port = url.port
        }

        var isLocalDevelopmentHTTP: Bool {
            scheme == "http" && (host == "localhost" || host == "127.0.0.1" || host == "::1")
        }
    }
}

public final class FloppyDownloadRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let policy: FloppyDownloadOriginPolicy

    public init(policy: FloppyDownloadOriginPolicy) {
        self.policy = policy
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, policy.allows(url) else {
            FloppyDiagnostics.api.warning("Rejected redirect to \(FloppyDiagnostics.redactedURL(request.url), privacy: .public)")
            completionHandler(nil)
            return
        }

        completionHandler(request)
    }
}

public final class FloppyGitHubZipRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public override init() {}

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, FloppyGitHubZipValidator.allowsDownloadURL(url) else {
            FloppyDiagnostics.onboarding.warning("Rejected GitHub ZIP redirect to \(FloppyDiagnostics.redactedURL(request.url), privacy: .public)")
            completionHandler(nil)
            return
        }

        completionHandler(request)
    }
}

public struct FloppyPluginZipValidationResult: Equatable, Sendable {
    public let entryCount: Int
    public let rootDirectory: String
    public let sizeBytes: Int64
}

public enum FloppyGitHubZipValidator {
    public static let maximumPluginZipBytes: Int64 = 100 * 1024 * 1024

    private static let allowedDownloadHosts: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",
        "github-releases.githubusercontent.com"
    ]

    public static func validateReleaseAssetURL(_ url: URL) throws {
        guard
            url.scheme?.lowercased() == "https",
            url.host?.lowercased() == "github.com",
            url.path.lowercased().contains("/releases/"),
            url.path.lowercased().hasSuffix(".zip")
        else {
            throw FloppyDownloadSecurityError.invalidGitHubReleaseURL(url)
        }
    }

    public static func validateDownloadURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), allowedDownloadHosts.contains(host) else {
            throw FloppyDownloadSecurityError.untrustedDownloadURL(url)
        }
    }

    public static func allowsDownloadURL(_ url: URL) -> Bool {
        (try? validateDownloadURL(url)) != nil
    }

    public static func validateDownloadedPluginZip(at url: URL, mainPluginFile: String) throws -> FloppyPluginZipValidationResult {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size <= maximumPluginZipBytes else {
            throw FloppyDownloadSecurityError.zipArchiveTooLarge(size)
        }

        let entries = try FloppyZipCentralDirectory.entries(in: url)
            .filter { !$0.isDirectory }
            .filter { !$0.path.hasPrefix("__MACOSX/") && !$0.path.hasSuffix("/.DS_Store") && $0.path != ".DS_Store" }

        guard !entries.isEmpty else {
            throw FloppyDownloadSecurityError.invalidZipArchive
        }

        let normalizedMainFile = normalizePluginPath(mainPluginFile)
        guard entries.contains(where: { $0.path == normalizedMainFile }) else {
            throw FloppyDownloadSecurityError.missingPluginMainFile(normalizedMainFile)
        }

        let expectedRoot = String(normalizedMainFile.split(separator: "/", omittingEmptySubsequences: true).first ?? "")
        guard !expectedRoot.isEmpty else {
            throw FloppyDownloadSecurityError.missingPluginMainFile(normalizedMainFile)
        }

        for entry in entries {
            guard entry.path == expectedRoot || entry.path.hasPrefix(expectedRoot + "/") else {
                throw FloppyDownloadSecurityError.unexpectedPluginRoot(expectedRoot)
            }
        }

        return FloppyPluginZipValidationResult(entryCount: entries.count, rootDirectory: expectedRoot, sizeBytes: size)
    }

    public static func normalizePluginPath(_ path: String) -> String {
        path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }
}

private struct FloppyZipEntry {
    let path: String

    var isDirectory: Bool {
        path.hasSuffix("/")
    }
}

private enum FloppyZipCentralDirectory {
    static func entries(in url: URL) throws -> [FloppyZipEntry] {
        let data = try Data(contentsOf: url)
        guard data.count >= 22, data.starts(with: [0x50, 0x4b]) else {
            throw FloppyDownloadSecurityError.invalidZipArchive
        }

        let eocdOffset = try endOfCentralDirectoryOffset(in: data)
        let entryCount = Int(data.littleEndianUInt16(at: eocdOffset + 10))
        let centralDirectoryOffset = Int(data.littleEndianUInt32(at: eocdOffset + 16))

        guard centralDirectoryOffset >= 0, centralDirectoryOffset < data.count else {
            throw FloppyDownloadSecurityError.invalidZipArchive
        }

        var offset = centralDirectoryOffset
        var entries: [FloppyZipEntry] = []
        entries.reserveCapacity(entryCount)

        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, data.littleEndianUInt32(at: offset) == 0x02014b50 else {
                throw FloppyDownloadSecurityError.invalidZipArchive
            }

            let filenameLength = Int(data.littleEndianUInt16(at: offset + 28))
            let extraLength = Int(data.littleEndianUInt16(at: offset + 30))
            let commentLength = Int(data.littleEndianUInt16(at: offset + 32))
            let nameStart = offset + 46
            let nameEnd = nameStart + filenameLength
            guard nameEnd <= data.count else {
                throw FloppyDownloadSecurityError.invalidZipArchive
            }

            guard let path = String(data: data[nameStart..<nameEnd], encoding: .utf8) else {
                throw FloppyDownloadSecurityError.invalidZipArchive
            }
            let normalizedPath = try validate(entryPath: path)
            entries.append(FloppyZipEntry(path: normalizedPath))

            offset = nameEnd + extraLength + commentLength
            guard offset <= data.count else {
                throw FloppyDownloadSecurityError.invalidZipArchive
            }
        }

        return entries
    }

    private static func endOfCentralDirectoryOffset(in data: Data) throws -> Int {
        let minimumOffset = max(0, data.count - 65_557)
        guard data.count >= 22 else {
            throw FloppyDownloadSecurityError.invalidZipArchive
        }

        var offset = data.count - 22
        while offset >= minimumOffset {
            if data.littleEndianUInt32(at: offset) == 0x06054b50 {
                return offset
            }
            offset -= 1
        }

        throw FloppyDownloadSecurityError.invalidZipArchive
    }

    private static func validate(entryPath path: String) throws -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else {
            throw FloppyDownloadSecurityError.unsafeZipEntry(path)
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains("") || normalized.hasSuffix("/") else {
            throw FloppyDownloadSecurityError.unsafeZipEntry(path)
        }

        return normalized
    }
}

private extension Data {
    func littleEndianUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else {
            return 0
        }

        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else {
            return 0
        }

        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
