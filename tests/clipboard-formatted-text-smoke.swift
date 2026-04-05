import AppKit
import Foundation

struct ActionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

@main
@MainActor
struct ClipboardFormattedTextSmoke {
    static func main() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RightClickAIClipboardFormattedSmoke"))
        let buildRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("right-click-formatted-smoke-\(UUID().uuidString)", isDirectory: true)
        let historyURL = buildRoot.appendingPathComponent("clipboard-history.json", isDirectory: false)
        let historyStore = ClipboardHistoryStore(fileURL: historyURL)
        let manager = ClipboardManager(
            historyStore: historyStore,
            privacyPolicy: .standard,
            pasteboard: pasteboard,
            monitoringInterval: 60,
            minimumStableMonitoringDuration: 60
        )

        defer {
            try? FileManager.default.removeItem(at: buildRoot)
            pasteboard.clearContents()
        }

        testHTMLCaptureAndRestore(manager: manager, pasteboard: pasteboard)
        testRTFCaptureAndRestore(manager: manager, pasteboard: pasteboard)

        print("Clipboard formatted text smoke passed.")
    }

    private static func testHTMLCaptureAndRestore(manager: ClipboardManager, pasteboard: NSPasteboard) {
        let html = """
        <html><body><p>Hello <strong>Dexter</strong></p><p>Second line</p></body></html>
        """
        let htmlData = Data(html.utf8)

        pasteboard.clearContents()
        pasteboard.setData(htmlData, forType: .html)
        pasteboard.setString("Hello Dexter\nSecond line", forType: .string)

        guard let item = manager.captureCurrentPasteboard(
            sourceName: "Safari",
            sourceBundleIdentifier: "com.apple.Safari"
        ) else {
            fail("Expected HTML clipboard item to be captured.")
        }

        guard item.kind == .html else {
            fail("Expected HTML clipboard item kind.")
        }

        guard item.prefersAssetRestore, item.canRestoreAsText else {
            fail("Expected HTML clipboard item to preserve asset restore and text review.")
        }

        guard manager.restore(itemID: item.id) != nil else {
            fail("Expected HTML clipboard restore to succeed.")
        }

        guard pasteboard.data(forType: .html) != nil else {
            fail("Expected HTML data to be restored to the pasteboard.")
        }
    }

    private static func testRTFCaptureAndRestore(manager: ClipboardManager, pasteboard: NSPasteboard) {
        let attributedString = NSAttributedString(
            string: "Rich Text Example",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )

        guard let rtfData = try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) else {
            fail("Expected RTF data to be generated.")
        }

        pasteboard.clearContents()
        pasteboard.setData(rtfData, forType: .rtf)
        pasteboard.setString("Rich Text Example", forType: .string)

        guard let item = manager.captureCurrentPasteboard(
            sourceName: "TextEdit",
            sourceBundleIdentifier: "com.apple.TextEdit"
        ) else {
            fail("Expected rich text clipboard item to be captured.")
        }

        guard item.kind == .richText else {
            fail("Expected rich text clipboard item kind.")
        }

        guard manager.restore(itemID: item.id) != nil else {
            fail("Expected rich text clipboard restore to succeed.")
        }

        guard pasteboard.data(forType: .rtf) != nil else {
            fail("Expected RTF data to be restored to the pasteboard.")
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("\(message)\n", stderr)
        exit(1)
    }
}
