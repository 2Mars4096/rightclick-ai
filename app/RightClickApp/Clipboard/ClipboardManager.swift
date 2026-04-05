import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ClipboardManager: ObservableObject {
    private struct PendingClipboardObservation {
        let changeCount: Int
        let firstObservedAt: Date
        let sourceName: String?
        let sourceBundleIdentifier: String?
        let sourceWindowTitle: String?
        let isSensitiveSource: Bool
    }

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var isPaused = false
    @Published private(set) var pauseReason: String?
    @Published private(set) var statusMessage = "Clipboard history is ready."
    @Published private(set) var lastErrorMessage: String?

    private let historyStore: ClipboardHistoryStore
    private var privacyPolicy: ClipboardPrivacyPolicy
    private let pasteboard: NSPasteboard
    private let monitoringInterval: TimeInterval
    private let minimumStableMonitoringDuration: TimeInterval
    nonisolated(unsafe) private var monitoringTimer: Timer?
    private var lastObservedPasteboardChangeCount: Int?
    private var pendingObservation: PendingClipboardObservation?

    init(
        historyStore: ClipboardHistoryStore = ClipboardHistoryStore(),
        privacyPolicy: ClipboardPrivacyPolicy = .standard,
        pasteboard: NSPasteboard = .general,
        monitoringInterval: TimeInterval = 0.5,
        minimumStableMonitoringDuration: TimeInterval = 1.5
    ) {
        self.historyStore = historyStore
        self.privacyPolicy = privacyPolicy
        self.pasteboard = pasteboard
        self.monitoringInterval = monitoringInterval
        self.minimumStableMonitoringDuration = minimumStableMonitoringDuration

        reloadHistory()
    }

    deinit {
        monitoringTimer?.invalidate()
    }

    var pinnedItems: [ClipboardItem] {
        items.filter { $0.isPinned }
    }

    var favoriteItems: [ClipboardItem] {
        items.filter { $0.isFavorite && !$0.isPinned }
    }

    var restoreableItems: [ClipboardItem] {
        items.filter { $0.canRestore }
    }

    func startMonitoring() {
        guard !isMonitoring else {
            return
        }

        lastObservedPasteboardChangeCount = pasteboard.changeCount
        pendingObservation = nil
        let timer = Timer(timeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPasteboardIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitoringTimer = timer

        isMonitoring = true
        statusMessage = "Clipboard monitoring started."
    }

    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        isMonitoring = false
        lastObservedPasteboardChangeCount = nil
        pendingObservation = nil
        statusMessage = "Clipboard monitoring stopped."
    }

    func pause(reason: String? = nil) {
        isPaused = true
        pauseReason = ClipboardTextNormalization.normalizeMetadata(reason)
        statusMessage = pauseReason.map { "Clipboard capture paused: \($0)." } ?? "Clipboard capture paused."
    }

    func resume() {
        isPaused = false
        pauseReason = nil
        lastObservedPasteboardChangeCount = pasteboard.changeCount
        pendingObservation = nil
        statusMessage = "Clipboard capture resumed."
    }

    func reloadHistory() {
        do {
            let loadedItems = try historyStore.load()
            let sanitizedItems = historyStore.deduplicatedAndPruned(loadedItems)
            items = sanitizedItems
            lastErrorMessage = nil
            statusMessage = loadedItems.isEmpty
                ? "Clipboard history loaded with no saved items."
                : "Loaded \(sanitizedItems.count) clipboard item(s) from disk."

            if sanitizedItems != loadedItems {
                persistHistory()
            }
        } catch {
            items = []
            lastErrorMessage = error.localizedDescription
            statusMessage = "Clipboard history could not be loaded."
        }
    }

    func updatePrivacyPolicy(_ policy: ClipboardPrivacyPolicy) {
        privacyPolicy = policy
    }

    func search(query: String) -> [ClipboardItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        let tokens = ClipboardTextNormalization.searchTokens(for: trimmedQuery)
        guard !tokens.isEmpty else {
            return items
        }

        return items.filter { item in
            let haystack = item.searchableText
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    func item(withID itemID: ClipboardItem.ID) -> ClipboardItem? {
        items.first { $0.id == itemID }
    }

    @discardableResult
    func capture(text: String, kind: ClipboardItemKind = .text, sourceName: String? = nil, sourceBundleIdentifier: String? = nil, sourceWindowTitle: String? = nil, isSensitiveSource: Bool = false) -> ClipboardItem? {
        guard ClipboardTextNormalization.hasMeaningfulContent(text) else {
            lastErrorMessage = nil
            statusMessage = "Clipboard text was empty."
            return nil
        }

        guard allowCapture(
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceWindowTitle: sourceWindowTitle,
            isSensitiveSource: isSensitiveSource
        ) else {
            return nil
        }

        let capturedItem = ClipboardItem(
            kind: kind,
            text: text,
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceWindowTitle: sourceWindowTitle
        )

        return ingestCapturedItem(capturedItem, sourceLabel: sourceName ?? kind.displayName)
    }

    @discardableResult
    func captureCurrentPasteboard(
        sourceName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        sourceWindowTitle: String? = nil,
        isSensitiveSource: Bool = false
    ) -> ClipboardItem? {
        let snapshot = snapshot(
            from: pasteboard,
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier
        )
        lastObservedPasteboardChangeCount = pasteboard.changeCount

        switch snapshot {
        case let .text(kind, text):
            return capture(
                text: text,
                kind: kind,
                sourceName: sourceName,
                sourceBundleIdentifier: sourceBundleIdentifier,
                sourceWindowTitle: sourceWindowTitle,
                isSensitiveSource: isSensitiveSource
            )
        case let .visual(kind, data, byteCount, pixelWidth, pixelHeight):
            return captureVisual(
                data: data,
                kind: kind,
                byteCount: byteCount,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                sourceName: sourceName,
                sourceBundleIdentifier: sourceBundleIdentifier,
                sourceWindowTitle: sourceWindowTitle,
                isSensitiveSource: isSensitiveSource
            )
        case .unsupported:
            lastErrorMessage = nil
            statusMessage = "The clipboard does not contain supported content yet."
            return nil
        }
    }

    @discardableResult
    func restore(itemID: ClipboardItem.ID) -> ClipboardItem? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            lastErrorMessage = "Clipboard item was not found."
            statusMessage = lastErrorMessage ?? "Clipboard item was not found."
            return nil
        }

        let item = items[index]
        if item.kind.isTextual {
            guard let text = item.restorableText, ClipboardTextNormalization.hasMeaningfulContent(text) else {
                lastErrorMessage = nil
                statusMessage = "\(item.kind.displayName) clipboard items cannot be restored yet."
                return nil
            }

            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            lastObservedPasteboardChangeCount = pasteboard.changeCount

            let restoredItem = recordRestore(on: item)
            items[index] = restoredItem
            reconcileAndPersistHistory()

            lastErrorMessage = nil
            statusMessage = "Restored \(item.kind.displayName.lowercased()) content to the clipboard."
            return restoredItem
        }

        guard let assetURL = historyStore.resolvedAssetURL(for: item),
              let assetData = try? Data(contentsOf: assetURL) else {
            lastErrorMessage = nil
            statusMessage = "\(item.kind.displayName) clipboard data is unavailable."
            return nil
        }

        pasteboard.clearContents()
        var didRestore = pasteboard.setData(assetData, forType: .png)
        if !didRestore, let image = NSImage(data: assetData) {
            didRestore = pasteboard.writeObjects([image])
        }

        guard didRestore else {
            lastErrorMessage = nil
            statusMessage = "Could not restore \(item.kind.displayName.lowercased()) content to the clipboard."
            return nil
        }

        lastObservedPasteboardChangeCount = pasteboard.changeCount

        let restoredItem = recordRestore(on: item)
        items[index] = restoredItem
        reconcileAndPersistHistory()

        lastErrorMessage = nil
        statusMessage = "Restored \(item.kind.displayName.lowercased()) content to the clipboard."
        return restoredItem
    }

    func previewImage(for itemID: ClipboardItem.ID) -> NSImage? {
        guard let item = item(withID: itemID),
              let assetURL = historyStore.resolvedAssetURL(for: item) else {
            return nil
        }

        return NSImage(contentsOf: assetURL)
    }

    @discardableResult
    func setPinned(_ isPinned: Bool, for itemID: ClipboardItem.ID) -> ClipboardItem? {
        updateItem(itemID: itemID) { item in
            item.isPinned = isPinned
        }
    }

    @discardableResult
    func setFavorite(_ isFavorite: Bool, for itemID: ClipboardItem.ID) -> ClipboardItem? {
        updateItem(itemID: itemID) { item in
            item.isFavorite = isFavorite
        }
    }

    @discardableResult
    func clearRecent() -> [ClipboardItem] {
        let removedItems = items.filter { !$0.isProtected }
        guard !removedItems.isEmpty else {
            lastErrorMessage = nil
            statusMessage = "There were no recent clipboard items to clear."
            return []
        }

        items.removeAll { !$0.isProtected }
        persistHistory()
        lastErrorMessage = nil
        statusMessage = "Cleared \(removedItems.count) recent clipboard item(s)."
        return removedItems
    }

    @discardableResult
    func clearAll() -> [ClipboardItem] {
        let removedItems = items
        guard !removedItems.isEmpty else {
            lastErrorMessage = nil
            statusMessage = "Clipboard history was already empty."
            return []
        }

        items.removeAll()
        persistHistory()
        lastErrorMessage = nil
        statusMessage = "Cleared all clipboard history."
        return removedItems
    }

    @discardableResult
    func clearMostRecent() -> ClipboardItem? {
        guard let itemToRemove = items.max(by: { $0.lastCapturedAt < $1.lastCapturedAt }) else {
            lastErrorMessage = nil
            statusMessage = "Clipboard history was already empty."
            return nil
        }

        return remove(itemID: itemToRemove.id, reason: "Removed the most recent clipboard item.")
    }

    @discardableResult
    func remove(itemID: ClipboardItem.ID, reason: String? = nil) -> ClipboardItem? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            lastErrorMessage = "Clipboard item was not found."
            statusMessage = lastErrorMessage ?? "Clipboard item was not found."
            return nil
        }

        let removedItem = items.remove(at: index)
        persistHistory()
        lastErrorMessage = nil
        statusMessage = reason ?? "Removed a clipboard item from history."
        return removedItem
    }

    func compatibility(for action: ActionDescriptor, itemID: ClipboardItem.ID) -> ClipboardActionCompatibility? {
        guard let item = item(withID: itemID) else {
            return nil
        }

        return ClipboardActionCompatibility.evaluate(action: action, item: item)
    }

    func compatibilities(for actions: [ActionDescriptor], itemID: ClipboardItem.ID) -> [ClipboardActionCompatibility] {
        guard let item = item(withID: itemID) else {
            return []
        }

        return actions.map { ClipboardActionCompatibility.evaluate(action: $0, item: item) }
    }

    private func pollPasteboardIfNeeded() {
        if isPaused {
            lastObservedPasteboardChangeCount = pasteboard.changeCount
            pendingObservation = nil
            return
        }

        let currentChangeCount = pasteboard.changeCount
        if let pendingObservation {
            if pendingObservation.changeCount == currentChangeCount {
                let stableDuration = Date.now.timeIntervalSince(pendingObservation.firstObservedAt)
                guard stableDuration >= minimumStableMonitoringDuration else {
                    return
                }

                _ = captureCurrentPasteboard(
                    sourceName: pendingObservation.sourceName,
                    sourceBundleIdentifier: pendingObservation.sourceBundleIdentifier,
                    sourceWindowTitle: pendingObservation.sourceWindowTitle,
                    isSensitiveSource: pendingObservation.isSensitiveSource
                )
                self.pendingObservation = nil
                return
            }

            self.pendingObservation = makePendingObservation(changeCount: currentChangeCount)
            return
        }

        guard lastObservedPasteboardChangeCount != currentChangeCount else {
            return
        }

        pendingObservation = makePendingObservation(changeCount: currentChangeCount)
    }

    private func ingestCapturedItem(_ candidate: ClipboardItem, sourceLabel: String) -> ClipboardItem? {
        let priorCount = items.count
        let hadMatchingItem = items.contains { $0.dedupeKey == candidate.dedupeKey }

        var updatedItems = items
        updatedItems.append(candidate)
        updatedItems = historyStore.deduplicatedAndPruned(updatedItems)
        items = updatedItems

        persistHistory()
        lastErrorMessage = nil
        statusMessage = hadMatchingItem
            ? "Updated the existing \(sourceLabel.lowercased()) clipboard item."
            : "Captured \(sourceLabel.lowercased()) into clipboard history."

        if items.count == priorCount && !hadMatchingItem {
            statusMessage = "Captured \(sourceLabel.lowercased()) into clipboard history."
        }

        return items.first { $0.dedupeKey == candidate.dedupeKey }
    }

    private func updateItem(itemID: ClipboardItem.ID, mutate: (inout ClipboardItem) -> Void) -> ClipboardItem? {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            lastErrorMessage = "Clipboard item was not found."
            statusMessage = lastErrorMessage ?? "Clipboard item was not found."
            return nil
        }

        mutate(&items[index])
        reconcileAndPersistHistory()
        lastErrorMessage = nil
        return items.first(where: { $0.id == itemID })
    }

    private func recordRestore(on item: ClipboardItem) -> ClipboardItem {
        var restoredItem = item
        restoredItem.lastAccessedAt = .now
        restoredItem.lastRestoredAt = .now
        restoredItem.restoreCount += 1
        return restoredItem
    }

    private func reconcileAndPersistHistory() {
        items = historyStore.deduplicatedAndPruned(items)
        persistHistory()
    }

    private func persistHistory() {
        do {
            try historyStore.save(items)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    private enum ClipboardSnapshot {
        case text(kind: ClipboardItemKind, text: String)
        case visual(kind: ClipboardItemKind, data: Data, byteCount: Int, pixelWidth: Int?, pixelHeight: Int?)
        case unsupported
    }

    private func snapshot(
        from pasteboard: NSPasteboard,
        sourceName: String?,
        sourceBundleIdentifier: String?
    ) -> ClipboardSnapshot {
        if let string = pasteboard.string(forType: .string),
           ClipboardTextNormalization.hasMeaningfulContent(string) {
            return .text(kind: .text, text: string)
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let kind: ClipboardItemKind = urls.allSatisfy { $0.isFileURL } ? .fileURL : .url
            let text = urls
                .map { kind == .fileURL ? $0.path : $0.absoluteString }
                .joined(separator: "\n")
            return .text(kind: kind, text: text)
        }

        if let visualSnapshot = visualSnapshot(
            from: pasteboard,
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier
        ) {
            return visualSnapshot
        }

        return .unsupported
    }

    private func allowCapture(
        sourceName: String?,
        sourceBundleIdentifier: String?,
        sourceWindowTitle: String?,
        isSensitiveSource: Bool
    ) -> Bool {
        let privacyDecision = privacyPolicy.decision(
            for: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceWindowTitle: sourceWindowTitle,
            isSensitiveSource: isSensitiveSource
        )

        guard privacyDecision.allowsCapture else {
            lastErrorMessage = nil
            statusMessage = privacyDecision.reason ?? "Clipboard capture was suppressed."
            return false
        }

        return true
    }

    @discardableResult
    private func captureVisual(
        data: Data,
        kind: ClipboardItemKind,
        byteCount: Int,
        pixelWidth: Int?,
        pixelHeight: Int?,
        sourceName: String?,
        sourceBundleIdentifier: String?,
        sourceWindowTitle: String?,
        isSensitiveSource: Bool
    ) -> ClipboardItem? {
        guard allowCapture(
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceWindowTitle: sourceWindowTitle,
            isSensitiveSource: isSensitiveSource
        ) else {
            return nil
        }

        guard historyStore.allowsVisualCapture(byteCount: byteCount) else {
            lastErrorMessage = nil
            statusMessage = "Skipped \(kind.displayName.lowercased()) clipboard data larger than \(ByteCountFormatter.string(fromByteCount: Int64(historyStore.retentionPolicy.maximumSingleVisualBytes), countStyle: .file))."
            return nil
        }

        let itemID = UUID()

        do {
            let assetRelativePath = try historyStore.saveVisualAsset(data: data, itemID: itemID)
            let candidate = ClipboardItem(
                id: itemID,
                kind: kind,
                text: nil,
                assetFingerprint: ClipboardTextNormalization.stableFingerprint(for: data),
                assetRelativePath: assetRelativePath,
                assetByteCount: byteCount,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                sourceName: sourceName,
                sourceBundleIdentifier: sourceBundleIdentifier,
                sourceWindowTitle: sourceWindowTitle
            )

            return ingestCapturedItem(candidate, sourceLabel: sourceName ?? kind.displayName)
        } catch {
            lastErrorMessage = error.localizedDescription
            statusMessage = "Could not store \(kind.displayName.lowercased()) clipboard data."
            return nil
        }
    }

    private func visualSnapshot(
        from pasteboard: NSPasteboard,
        sourceName: String?,
        sourceBundleIdentifier: String?
    ) -> ClipboardSnapshot? {
        guard let imageData = bestVisualData(from: pasteboard),
              let image = NSImage(data: imageData) else {
            return nil
        }

        let kind = visualKind(sourceName: sourceName, sourceBundleIdentifier: sourceBundleIdentifier)
        let imageSize = pixelSize(for: image)

        return .visual(
            kind: kind,
            data: imageData,
            byteCount: imageData.count,
            pixelWidth: imageSize?.width,
            pixelHeight: imageSize?.height
        )
    }

    private func bestVisualData(from pasteboard: NSPasteboard) -> Data? {
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return pngData
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let pngData = pngData(for: image) {
            return pngData
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let pngData = pngData(for: image) {
            return pngData
        }

        return nil
    }

    private func pngData(for image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRepresentation = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmapRepresentation.representation(using: .png, properties: [:])
    }

    private func pixelSize(for image: NSImage) -> (width: Int, height: Int)? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRepresentation = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let width = bitmapRepresentation.pixelsWide
        let height = bitmapRepresentation.pixelsHigh
        guard width > 0, height > 0 else {
            return nil
        }

        return (width, height)
    }

    private func visualKind(sourceName: String?, sourceBundleIdentifier: String?) -> ClipboardItemKind {
        if sourceBundleIdentifier == "com.apple.screencaptureui" {
            return .screenshot
        }

        if sourceName?.localizedCaseInsensitiveContains("screenshot") == true {
            return .screenshot
        }

        return .image
    }

    private func makePendingObservation(changeCount: Int) -> PendingClipboardObservation {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        return PendingClipboardObservation(
            changeCount: changeCount,
            firstObservedAt: .now,
            sourceName: frontmostApplication?.localizedName,
            sourceBundleIdentifier: frontmostApplication?.bundleIdentifier,
            sourceWindowTitle: nil,
            isSensitiveSource: false
        )
    }
}
