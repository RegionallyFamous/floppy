import AppKit
import SwiftUI

@MainActor
final class FloppyStatusItemController: NSObject {
    static let shared = FloppyStatusItemController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private weak var model: FloppyAppModel?

    func install(model: FloppyAppModel) {
        self.model = model
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }

        guard let button = statusItem?.button else {
            return
        }

        button.image = makeStatusImage()
        button.imagePosition = .imageOnly
        button.toolTip = "Floppy"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Floppy")
        button.setAccessibilityHelp("Open Floppy sync status")

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.contentViewController = NSHostingController(rootView: MenuBarView(model: model))
        self.popover = popover
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu(from: sender)
            return
        }

        togglePopover(sender)
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func showStatusMenu(from sender: NSStatusBarButton) {
        popover?.performClose(sender)

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem("Open Floppy Folder", action: #selector(openFolderFromMenu), keyEquivalent: "o", enabled: model?.selectedAccount != nil))
        menu.addItem(menuItem("Sync Now", action: #selector(syncNowFromMenu), keyEquivalent: "r", enabled: model?.selectedAccount != nil && model?.isWorking == false))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings...", action: #selector(openSettingsFromMenu), keyEquivalent: ",", enabled: true))
        menu.addItem(menuItem("Quit Floppy", action: #selector(quitFromMenu), keyEquivalent: "q", enabled: true))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    private func menuItem(_ title: String, action: Selector, keyEquivalent: String, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc
    private func openFolderFromMenu() {
        model?.openNativeFolder()
    }

    @objc
    private func syncNowFromMenu() {
        Task { @MainActor [weak self] in
            await self?.model?.syncSelectedAccount()
        }
    }

    @objc
    private func openSettingsFromMenu() {
        model?.openSettingsWindow()
    }

    @objc
    private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func makeStatusImage() -> NSImage {
        if let image = Bundle.main.image(forResource: "FloppyMenuBarTemplate") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setFill()
            FloppyStatusItemController.drawFallbackIcon(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawFallbackIcon(in rect: CGRect) {
        let scale = min(rect.width, rect.height) / 18
        let origin = CGPoint(x: rect.midX - 9 * scale, y: rect.midY - 9 * scale)

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        let path = NSBezierPath()
        path.move(to: point(3.0, 1.7))
        path.line(to: point(12.8, 1.7))
        path.line(to: point(16.3, 5.2))
        path.line(to: point(16.3, 15.1))
        path.curve(to: point(15.1, 16.3), controlPoint1: point(16.3, 15.8), controlPoint2: point(15.8, 16.3))
        path.line(to: point(2.9, 16.3))
        path.curve(to: point(1.7, 15.1), controlPoint1: point(2.2, 16.3), controlPoint2: point(1.7, 15.8))
        path.line(to: point(1.7, 3.0))
        path.curve(to: point(3.0, 1.7), controlPoint1: point(1.7, 2.3), controlPoint2: point(2.3, 1.7))
        path.close()
        path.fill()
    }
}
