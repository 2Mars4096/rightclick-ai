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

    @objc(openPaperAndNotes:userData:error:)
    func openPaperAndNotes(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let pdfURLs = selectedFileURLs(from: pasteboard).filter {
            $0.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
        }

        guard pdfURLs.count == 1, let pdfURL = pdfURLs.first else {
            error.pointee = "Select exactly one PDF in Finder." as NSString
            return
        }

        if !appModel.acceptSelectedPaperPDF(pdfURL) {
            presentReviewWindow()
        }
    }

    private func selectedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls
        }

        let legacyFileNamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = pasteboard.propertyList(forType: legacyFileNamesType) as? [String] {
            return paths.map { URL(fileURLWithPath: $0, isDirectory: false) }
        }

        return []
    }
}
