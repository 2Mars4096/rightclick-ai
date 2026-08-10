import AppKit
import Foundation

struct ActionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

@MainActor
@main
struct ClipboardMonitoringSmoke {
    static func main() throws {
        let fileManager = FileManager.default
        let buildRoot = fileManager.temporaryDirectory
            .appendingPathComponent("right-click-clipboard-monitoring-\(UUID().uuidString)", isDirectory: true)
        let historyFileURL = buildRoot.appendingPathComponent("clipboard-history.json", isDirectory: false)
        let sourcePDFURL = buildRoot.appendingPathComponent("incoming/paper.pdf", isDirectory: false)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RightClickAIClipboardMonitoringSmoke.\(UUID().uuidString)"))

        try fileManager.createDirectory(at: buildRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: sourcePDFURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("%PDF-1.4\nmock\n".utf8).write(to: sourcePDFURL)

        defer {
            pasteboard.clearContents()
            try? fileManager.removeItem(at: buildRoot)
        }

        let manager = ClipboardManager(
            historyStore: ClipboardHistoryStore(fileURL: historyFileURL),
            pasteboard: pasteboard,
            monitoringInterval: 0.05,
            minimumStableMonitoringDuration: 0.15
        )
        manager.startMonitoring()
        defer {
            manager.stopMonitoring()
        }

        pasteboard.clearContents()
        let pdfPasteboardItem = NSPasteboardItem()
        guard pdfPasteboardItem.setString(sourcePDFURL.absoluteString, forType: .fileURL),
              pasteboard.writeObjects([pdfPasteboardItem]) else {
            print("Clipboard monitoring smoke skipped: the macOS pasteboard server is unavailable in this test environment.")
            return
        }
        wait(0.3)

        let bibTeX = """
        @article{smith2026example,
          title={An Example Paper},
          author={Smith, Jane},
          year={2026}
        }
        """
        pasteboard.clearContents()
        guard pasteboard.setString(bibTeX, forType: .string) else {
            fail("Expected the test pasteboard to accept the BibTeX text.")
        }
        wait(0.3)

        guard manager.items.contains(where: { item in
            item.kind == .fileURL && item.restorableURLs.contains(sourcePDFURL)
        }) else {
            fail("Expected the monitored clipboard history to capture the copied PDF file reference.")
        }

        guard manager.items.contains(where: { item in
            item.kind == .text && (item.text?.contains("@article{smith2026example") == true)
        }) else {
            fail("Expected the monitored clipboard history to capture the copied BibTeX entry.")
        }

        print("Clipboard monitoring smoke passed.")
    }

    private static func wait(_ duration: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }

    private static func fail(_ message: String) -> Never {
        fputs("\(message)\n", stderr)
        exit(1)
    }
}
