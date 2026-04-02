import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appModel = AppModel.shared
    private var reviewWindowController: ReviewWindowController?
    private var settingsWindowController: NSWindowController?
    private var statusItem: NSStatusItem?
    private lazy var serviceProvider = SelectedTextServiceProvider(
        appModel: appModel,
        presentReviewWindow: { [weak self] in
            self?.showReviewWindow()
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
        configureStatusItem()

        if appModel.needsProviderSetup {
            appModel.settingsStatusMessage = "Finish provider setup once, then RightClick AI can stay in the menu bar."
            showSettingsWindow(nil)
        } else {
            appModel.statusMessage = "RightClick AI is running in the background. Use the menu bar item or the selected-text service."
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showReviewWindow()
        }

        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc(showReviewWindow:)
    func showReviewWindow(_ sender: Any? = nil) {
        if reviewWindowController == nil {
            reviewWindowController = ReviewWindowController(appModel: appModel)
        }

        presentWindow(reviewWindowController)
    }

    @objc(showSettingsWindow:)
    func showSettingsWindow(_ sender: Any? = nil) {
        if settingsWindowController == nil {
            settingsWindowController = makeSettingsWindowController()
        }

        presentWindow(settingsWindowController)
    }

    @objc(importClipboardAndShowReview:)
    func importClipboardAndShowReview(_ sender: Any? = nil) {
        appModel.importClipboardText()
        showReviewWindow(sender)
    }

    @objc(openActionsFolder:)
    func openActionsFolder(_ sender: Any? = nil) {
        appModel.openActionsDirectory()
    }

    @objc(quitApplication:)
    func quitApplication(_ sender: Any? = nil) {
        NSApp.terminate(sender)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "RightClick AI")
            button.toolTip = "RightClick AI"
        }

        let menu = NSMenu()
        menu.addItem(menuItem(title: "Open Review", action: #selector(showReviewWindow(_:))))
        menu.addItem(menuItem(title: "Open Settings", action: #selector(showSettingsWindow(_:))))
        menu.addItem(menuItem(title: "Use Clipboard", action: #selector(importClipboardAndShowReview(_:))))
        menu.addItem(menuItem(title: "Open Actions Folder", action: #selector(openActionsFolder(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit RightClick AI", action: #selector(quitApplication(_:))))

        item.menu = menu
        statusItem = item
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func makeSettingsWindowController() -> NSWindowController {
        let hostingController = NSHostingController(rootView: SettingsView(model: appModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "RightClick AI Settings"
        window.setContentSize(NSSize(width: 700, height: 880))
        window.minSize = NSSize(width: 640, height: 760)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        return NSWindowController(window: window)
    }

    private func presentWindow(_ windowController: NSWindowController?) {
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
