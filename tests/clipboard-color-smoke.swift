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
        let pasteboard = NSPasteboard.withUniqueName()
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
        testMissingColorAssetsFallBackToHex(manager: manager, historyStore: historyStore, pasteboard: pasteboard)
        print("Clipboard color smoke passed.")
    }

    private static func testColorCaptureAndRestore(manager: ClipboardManager, pasteboard: NSPasteboard) {
        let sourceColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        guard let colorData = sourceColor.pasteboardPropertyList(forType: .color) as? Data else {
            fail("Expected source color data to be encodable for the pasteboard.")
        }

        pasteboard.clearContents()
        pasteboard.declareTypes([.color], owner: nil)
        guard pasteboard.setData(colorData, forType: .color) else {
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

    private static func testMissingColorAssetsFallBackToHex(
        manager: ClipboardManager,
        historyStore: ClipboardHistoryStore,
        pasteboard: NSPasteboard
    ) {
        let sourceColor = NSColor(srgbRed: 0.8, green: 0.2, blue: 0.4, alpha: 1)
        guard let colorData = sourceColor.pasteboardPropertyList(forType: .color) as? Data else {
            fail("Expected fallback color data to be encodable for the pasteboard.")
        }

        pasteboard.clearContents()
        pasteboard.declareTypes([.color], owner: nil)
        guard pasteboard.setData(colorData, forType: .color) else {
            fail("Expected color to be written to the pasteboard for fallback coverage.")
        }

        guard let item = manager.captureCurrentPasteboard(
            sourceName: "Digital Color Meter",
            sourceBundleIdentifier: "com.apple.DigitalColorMeter"
        ) else {
            fail("Expected color clipboard item to be captured for fallback coverage.")
        }

        guard let assetURL = historyStore.resolvedAssetURL(for: item) else {
            fail("Expected color clipboard item to have a stored asset.")
        }

        try? FileManager.default.removeItem(at: assetURL)

        guard manager.restore(itemID: item.id) != nil else {
            fail("Expected missing color assets to fall back to a hex string restore.")
        }

        guard pasteboard.string(forType: .string) == "#CC3366" else {
            fail("Expected missing color assets to restore their hex-string fallback.")
        }

        let retainedItems = historyStore.deduplicatedAndPruned(try! historyStore.load())
        guard retainedItems.contains(where: { $0.id == item.id }) else {
            fail("Expected color clipboard items with a hex fallback to stay in history even if the asset is missing.")
        }
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
