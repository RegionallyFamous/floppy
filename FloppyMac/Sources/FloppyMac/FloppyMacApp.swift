import AppKit
import SwiftUI

@main
struct FloppyMacApp: App {
    @NSApplicationDelegateAdaptor(FloppyAppDelegate.self) private var appDelegate
    @StateObject private var model: FloppyAppModel

    init() {
        let model = FloppyAppModel()
        _model = StateObject(wrappedValue: model)
        FloppyStatusItemController.shared.install(model: model)
    }

    var body: some Scene {
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
final class FloppySettingsWindowController {
    static let shared = FloppySettingsWindowController()

    private var window: NSWindow?

    func show(model: FloppyAppModel) {
        let window = window ?? makeWindow(model: model)
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow(model: FloppyAppModel) -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: controller)
        window.title = "Floppy Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 560)
        window.setContentSize(NSSize(width: 900, height: 620))
        return window
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
