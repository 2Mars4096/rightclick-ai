import AppKit

@MainActor
final class SelectedTextServiceProvider: NSObject {
    private let appModel: AppModel
    private let presentReviewWindow: () -> Void

    init(appModel: AppModel, presentReviewWindow: @escaping () -> Void) {
        self.appModel = appModel
        self.presentReviewWindow = presentReviewWindow
    }

    @objc(captureSelectedText:userData:error:)
    func captureSelectedText(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let selectedText = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !selectedText.isEmpty else {
            error.pointee = "RightClick AI did not receive any selected text." as NSString
            return
        }

        appModel.acceptSelectedText(selectedText, source: "Selected-Text Service")
        presentReviewWindow()
    }
}
