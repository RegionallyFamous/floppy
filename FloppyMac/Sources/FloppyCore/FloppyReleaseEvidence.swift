import Foundation

public enum FloppyReleaseEvidenceStatus: String, Codable, CaseIterable, Sendable {
    case pass
    case warn
    case fail
    case skipped
}

public struct FloppyReleaseEvidenceCheck: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let status: FloppyReleaseEvidenceStatus
    public let message: String
    public let evidence: [String: String]

    public init(id: String, status: FloppyReleaseEvidenceStatus, message: String, evidence: [String: String] = [:]) {
        self.id = id
        self.status = status
        self.message = message
        self.evidence = evidence
    }
}

public struct FloppyReleaseEvidenceSummary: Codable, Equatable, Sendable {
    public let passed: Int
    public let warnings: Int
    public let failed: Int
    public let skipped: Int
    public let readyForPublicBeta: Bool

    public init(checks: [FloppyReleaseEvidenceCheck]) {
        self.passed = checks.filter { $0.status == .pass }.count
        self.warnings = checks.filter { $0.status == .warn }.count
        self.failed = checks.filter { $0.status == .fail }.count
        self.skipped = checks.filter { $0.status == .skipped }.count
        self.readyForPublicBeta = failed == 0 && skipped == 0
    }

    public init(passed: Int, warnings: Int, failed: Int, skipped: Int, readyForPublicBeta: Bool) {
        self.passed = passed
        self.warnings = warnings
        self.failed = failed
        self.skipped = skipped
        self.readyForPublicBeta = readyForPublicBeta
    }

    public static var empty: FloppyReleaseEvidenceSummary {
        FloppyReleaseEvidenceSummary(passed: 0, warnings: 0, failed: 0, skipped: 0, readyForPublicBeta: false)
    }

    enum CodingKeys: String, CodingKey {
        case passed
        case warnings
        case failed
        case skipped
        case readyForPublicBeta = "ready_for_public_beta"
    }
}

public struct FloppyReleaseEvidenceReport: Codable, Equatable, Sendable {
    public let format: String
    public let generatedAt: String
    public let projectPath: String
    public let appPath: String
    public let zipPath: String
    public let summary: FloppyReleaseEvidenceSummary
    public let checks: [FloppyReleaseEvidenceCheck]

    public init(
        generatedAt: String,
        projectPath: String,
        appPath: String = "",
        zipPath: String = "",
        checks: [FloppyReleaseEvidenceCheck]
    ) {
        self.format = "floppy-mac-release-evidence-v1"
        self.generatedAt = generatedAt
        self.projectPath = FloppyDiagnostics.redactedFilePath(projectPath)
        self.appPath = FloppyDiagnostics.redactedFilePath(appPath)
        self.zipPath = FloppyDiagnostics.redactedFilePath(zipPath)
        self.summary = FloppyReleaseEvidenceSummary(checks: checks)
        self.checks = checks
    }

    enum CodingKeys: String, CodingKey {
        case format
        case generatedAt = "generated_at"
        case projectPath = "project_path"
        case appPath = "app_path"
        case zipPath = "zip_path"
        case summary
        case checks
    }
}

public struct FloppyReleaseBuildIdentity: Codable, Equatable, Sendable {
    public let version: String
    public let build: String
    public let bundleID: String
    public let appGroupIdentifier: String
    public let executablePath: String
    public let isSwiftPMBundle: Bool

    public init(
        version: String,
        build: String,
        bundleID: String,
        appGroupIdentifier: String,
        executablePath: String,
        isSwiftPMBundle: Bool
    ) {
        self.version = version
        self.build = build
        self.bundleID = bundleID
        self.appGroupIdentifier = appGroupIdentifier
        self.executablePath = FloppyDiagnostics.redactedFilePath(executablePath)
        self.isSwiftPMBundle = isSwiftPMBundle
    }

    public static func current(bundle: Bundle = .main) -> FloppyReleaseBuildIdentity {
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let executablePath = bundle.executableURL?.path ?? ""
        return FloppyReleaseBuildIdentity(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            bundleID: bundleID,
            appGroupIdentifier: FloppyDomainRegistry.appGroupIdentifier(bundle: bundle),
            executablePath: executablePath,
            isSwiftPMBundle: bundleID == "unknown" || executablePath.contains(".build/")
        )
    }

    enum CodingKeys: String, CodingKey {
        case version
        case build
        case bundleID = "bundle_id"
        case appGroupIdentifier = "app_group_identifier"
        case executablePath = "executable_path"
        case isSwiftPMBundle = "is_swiftpm_bundle"
    }
}
