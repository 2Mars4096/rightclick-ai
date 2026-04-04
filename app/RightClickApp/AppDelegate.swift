import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let appModel = AppModel.shared
    private var reviewWindowController: ReviewWindowController?
    private var settingsWindowController: NSWindowController?
    private var statusItem: NSStatusItem?
    private var clipboardHistoryMenuItem: NSMenuItem?
    private var pauseClipboardMenuItem: NSMenuItem?
    private var clearLastClipboardMenuItem: NSMenuItem?
    private var clipboardStatusMenuItem: NSMenuItem?
    private var hotKeyController: GlobalHotKeyController?
    private var cancellables: Set<AnyCancellable> = []
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

        appModel.startClipboardMonitoringIfNeeded()
        configureStatusItem()
        configureHotKey()
        observeAppState()

        if appModel.needsProviderSetup {
            appModel.settingsStatusMessage = "Finish provider setup once, then RightClick AI can stay in the menu bar."
            appModel.settingsStatusTone = .warning
            showSettingsWindow(nil)
        } else {
            appModel.statusMessage = "RightClick AI is running in the background. Use Services, the hotkey, or the menu bar item."
            appModel.statusTone = .success
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showClipboardHistory()
        }

        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatusMenuState()
    }

    @objc(showReviewWindow:)
    func showReviewWindow(_ sender: Any? = nil) {
        appModel.showSelectedTextWorkspace()

        if reviewWindowController == nil {
            reviewWindowController = ReviewWindowController(appModel: appModel)
        }

        presentWindow(reviewWindowController)
    }

    @objc(showClipboardHistory:)
    func showClipboardHistory(_ sender: Any? = nil) {
        appModel.showClipboardWorkspace()

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

    @objc(toggleClipboardCapture:)
    func toggleClipboardCapture(_ sender: Any? = nil) {
        appModel.toggleClipboardPause()
        refreshStatusMenuState()
    }

    @objc(clearMostRecentClipboardItem:)
    func clearMostRecentClipboardItem(_ sender: Any? = nil) {
        appModel.clearMostRecentClipboardItem()
        refreshStatusMenuState()
    }

    @objc(openActionsFolder:)
    func openActionsFolder(_ sender: Any? = nil) {
        appModel.openActionsDirectory()
    }

    @objc(quitApplication:)
    func quitApplication(_ sender: Any? = nil) {
        NSApp.terminate(sender)
    }

    @objc(handleClipboardHotKeyPreferenceDidChange:)
    func handleClipboardHotKeyPreferenceDidChange(_ notification: Notification) {
        refreshHotKeyRegistration()
        refreshStatusMenuState()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "RightClick AI")
            button.toolTip = "RightClick AI"
        }

        let menu = NSMenu()
        menu.delegate = self

        clipboardHistoryMenuItem = menuItem(title: "Open Clipboard History", action: #selector(showClipboardHistory(_:)))
        menu.addItem(clipboardHistoryMenuItem!)
        menu.addItem(menuItem(title: "Open Selected Text Review", action: #selector(showReviewWindow(_:))))
        menu.addItem(menuItem(title: "Use Current Clipboard In Review", action: #selector(importClipboardAndShowReview(_:))))
        menu.addItem(.separator())

        pauseClipboardMenuItem = menuItem(title: "Pause Clipboard Capture", action: #selector(toggleClipboardCapture(_:)))
        menu.addItem(pauseClipboardMenuItem!)

        clearLastClipboardMenuItem = menuItem(title: "Clear Last Clipboard Item", action: #selector(clearMostRecentClipboardItem(_:)))
        menu.addItem(clearLastClipboardMenuItem!)

        clipboardStatusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        clipboardStatusMenuItem?.isEnabled = false
        if let clipboardStatusMenuItem {
            menu.addItem(clipboardStatusMenuItem)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Open Settings", action: #selector(showSettingsWindow(_:))))
        menu.addItem(menuItem(title: "Open Actions Folder", action: #selector(openActionsFolder(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit RightClick AI", action: #selector(quitApplication(_:))))

        item.menu = menu
        statusItem = item
        refreshStatusMenuState()
    }

    private func configureHotKey() {
        hotKeyController = GlobalHotKeyController(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ) { [weak self] in
            self?.showClipboardHistory()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipboardHotKeyPreferenceDidChange(_:)),
            name: .rightClickClipboardHotKeyPreferenceDidChange,
            object: appModel
        )

        refreshHotKeyRegistration()
    }

    private func observeAppState() {
        appModel.clipboardManager.$isPaused
            .sink { [weak self] _ in
                self?.refreshStatusMenuState()
            }
            .store(in: &cancellables)

        appModel.clipboardManager.$items
            .sink { [weak self] _ in
                self?.refreshStatusMenuState()
            }
            .store(in: &cancellables)
    }

    private func refreshHotKeyRegistration() {
        if appModel.clipboardHotkeyEnabled {
            hotKeyController?.register()
        } else {
            hotKeyController?.unregister()
        }
    }

    private func refreshStatusMenuState() {
        let historyTitle = appModel.clipboardHotkeyEnabled
            ? "Open Clipboard History (\(appModel.clipboardHotkeyShortcutLabel))"
            : "Open Clipboard History"

        clipboardHistoryMenuItem?.title = historyTitle
        pauseClipboardMenuItem?.title = appModel.clipboardManager.isPaused
            ? "Resume Clipboard Capture"
            : "Pause Clipboard Capture"
        clearLastClipboardMenuItem?.isEnabled = !appModel.clipboardManager.items.isEmpty
        clipboardStatusMenuItem?.title = appModel.clipboardStateSummary
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
        window.setContentSize(NSSize(width: 720, height: 860))
        window.minSize = NSSize(width: 680, height: 760)
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

private final class GlobalHotKeyController {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let hotKeyID = EventHotKeyID(signature: 0x52434149, id: 1)
    private let handler: () -> Void
    private var eventHandler: EventHandlerRef?
    private var registeredHotKey: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
        installEventHandlerIfNeeded()
    }

    deinit {
        unregister()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register() {
        guard registeredHotKey == nil else {
            return
        }

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )

        if status != noErr {
            registeredHotKey = nil
        }
    }

    func unregister() {
        guard let registeredHotKey else {
            return
        }

        UnregisterEventHotKey(registeredHotKey)
        self.registeredHotKey = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else {
                    return noErr
                }

                let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
                var eventHotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventHotKeyID
                )

                guard status == noErr else {
                    return status
                }

                if eventHotKeyID.signature == controller.hotKeyID.signature,
                   eventHotKeyID.id == controller.hotKeyID.id {
                    controller.handler()
                }

                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
    }
}
