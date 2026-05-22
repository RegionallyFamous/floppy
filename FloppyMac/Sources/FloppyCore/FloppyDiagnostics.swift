import Foundation
import OSLog

public enum FloppyDiagnostics {
    public static let subsystem = "com.floppy.mac"

    public static let api = Logger(subsystem: subsystem, category: "api")
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let fileProvider = Logger(subsystem: subsystem, category: "file-provider")
    public static let ledger = Logger(subsystem: subsystem, category: "ledger")
    public static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
    public static let packaging = Logger(subsystem: subsystem, category: "packaging")

    public static func redactedURL(_ url: URL?) -> String {
        guard let url else {
            return "(none)"
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "\(url.scheme ?? "url")://\(url.host ?? "unknown")"
    }
}
