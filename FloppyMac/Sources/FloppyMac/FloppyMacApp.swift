import AppKit
import SwiftUI

@main
struct FloppyMacApp: App {
    @NSApplicationDelegateAdaptor(FloppyAppDelegate.self) private var appDelegate
    @StateObject private var model: FloppyAppModel

    init() {
        let model = FloppyAppModel()
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            HStack(spacing: 5) {
                FloppyMenuBarIcon()
                    .frame(width: 16, height: 16)
                Text("Floppy")
                    .font(.system(size: 12, weight: .semibold))
            }
            .accessibilityLabel("Floppy")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

final class FloppyAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { @MainActor in
                FloppyURLRouter.shared.open(url)
            }
        }
    }
}

@MainActor
final class FloppyURLRouter {
    static let shared = FloppyURLRouter()

    private var handler: ((URL) -> Void)?
    private var pendingURLs: [URL] = []

    func setHandler(_ handler: @escaping (URL) -> Void) {
        self.handler = handler
        let urls = pendingURLs
        pendingURLs.removeAll()
        urls.forEach(handler)
    }

    func open(_ url: URL) {
        guard let handler else {
            pendingURLs.append(url)
            return
        }

        handler(url)
    }
}
