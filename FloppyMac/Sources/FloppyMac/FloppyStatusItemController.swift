import AppKit
import Combine
import SwiftUI

@MainActor
final class FloppyStatusItemController: NSObject {
    static let shared = FloppyStatusItemController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var modelObservation: AnyCancellable?
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
        updateStatusItemPresentation()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.contentViewController = NSHostingController(rootView: MenuBarView(model: model))
        self.popover = popover

        modelObservation = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusItemPresentation()
            }
        }
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
        let statusItem = NSMenuItem(title: statusSummary, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())
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

    private func updateStatusItemPresentation() {
        guard let button = statusItem?.button else {
            return
        }

        let summary = statusSummary
        button.toolTip = "Floppy: \(summary)"
        button.setAccessibilityLabel("Floppy")
        button.setAccessibilityValue(summary)
        button.setAccessibilityHelp("Open Floppy sync status. \(summary)")
    }

    private var statusSummary: String {
        guard let model else {
            return "Not running"
        }

        guard let account = model.selectedAccount else {
            return model.onboardingStep.title
        }

        let host = account.siteURL.host ?? "Connected site"
        if model.isWorking {
            return "\(host), syncing"
        }

        if !model.isNetworkReachable {
            return "\(host), offline"
        }

        if model.openConflictCount > 0 {
            return "\(host), \(model.openConflictCount) conflict\(model.openConflictCount == 1 ? "" : "s") need attention"
        }

        if model.pendingTransferCount > 0 {
            return "\(host), \(model.pendingTransferCount) interrupted transfer\(model.pendingTransferCount == 1 ? "" : "s") preserved"
        }

        if let lastSyncAt = account.lastSyncAt {
            return "\(host), synced \(lastSyncAt.formatted(date: .omitted, time: .shortened))"
        }

        return "\(host), \(model.nativeFolderStatusText)"
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
        path.lineWidth = 1.9 * scale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: point(2.4, 14.2))
        path.line(to: point(5.5, 3.9))
        path.line(to: point(8.6, 14.2))
        path.move(to: point(3.5, 10.5))
        path.line(to: point(7.5, 10.5))
        path.move(to: point(15.6, 4.1))
        path.line(to: point(12.5, 14.1))
        path.stroke()

        NSBezierPath(ovalIn: CGRect(x: point(10.6, 7.6).x - 0.85 * scale, y: point(10.6, 7.6).y - 0.85 * scale, width: 1.7 * scale, height: 1.7 * scale)).fill()
        NSBezierPath(ovalIn: CGRect(x: point(10.6, 12.0).x - 0.85 * scale, y: point(10.6, 12.0).y - 0.85 * scale, width: 1.7 * scale, height: 1.7 * scale)).fill()
    }
}
