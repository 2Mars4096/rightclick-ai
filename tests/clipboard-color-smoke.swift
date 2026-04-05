import AppKit
import Foundation

struct ActionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

@main
@MainActor
struct ClipboardColorSmoke {
    static func main() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RightClickAIClipboardColorSmoke"))
        let buildRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("right-click-color-smoke-\(UUID().uuidString)", isDirectory: true)
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

        testColorCaptureAndRestore(manager: manager, pasteboard: pasteboard)
        print("Clipboard color smoke passed.")
    }

    private static func testColorCaptureAndRestore(manager: ClipboardManager, pasteboard: NSPasteboard) {
        let sourceColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)

        pasteboard.clearContents()
        guard pasteboard.writeObjects([sourceColor]) else {
            fail("Expected color to be written to the pasteboard.")
        }

        guard let item = manager.captureCurrentPasteboard(
            sourceName: "Digital Color Meter",
            sourceBundleIdentifier: "com.apple.DigitalColorMeter"
        ) else {
            fail("Expected color clipboard item to be captured.")
        }

        guard item.kind == .color else {
            fail("Expected color clipboard item kind.")
        }

        guard item.text == "#336699" else {
            fail("Expected color preview text to normalize to #336699.")
        }

        guard item.canRestore else {
            fail("Expected color clipboard item to be restorable.")
        }

        guard manager.restore(itemID: item.id) != nil else {
            fail("Expected color clipboard restore to succeed.")
        }

        guard let restoredColors = pasteboard.readObjects(forClasses: [NSColor.self], options: nil) as? [NSColor],
              let restoredColor = restoredColors.first?.usingColorSpace(.sRGB) else {
            fail("Expected restored color data to be available on the pasteboard.")
        }

        assertNearlyEqual(restoredColor.redComponent, 0.2, label: "red")
        assertNearlyEqual(restoredColor.greenComponent, 0.4, label: "green")
        assertNearlyEqual(restoredColor.blueComponent, 0.6, label: "blue")
    }

    private static func assertNearlyEqual(_ actual: CGFloat, _ expected: CGFloat, label: String) {
        guard abs(actual - expected) < 0.01 else {
            fail("Expected \(label) component \(expected), got \(actual).")
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("\(message)\n", stderr)
        exit(1)
    }
}
