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
            FloppyMenuBarIcon()
                .frame(width: 18, height: 18)
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
