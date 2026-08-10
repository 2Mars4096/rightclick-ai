import AppKit
import SwiftUI

@MainActor
final class ReviewWindowController: NSWindowController {
    init(appModel: AppModel) {
        let hostingController = NSHostingController(rootView: ReviewWorkspaceView(model: appModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "RightClick AI"
        window.setContentSize(NSSize(width: 940, height: 700))
        window.minSize = NSSize(width: 840, height: 620)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
