import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ClipboardManager: ObservableObject {
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
    nonisolated(unsafe) private var monitoringTimer: Timer?
    private var lastObservedPasteboardChangeCount: Int?

    init(
        historyStore: ClipboardHistoryStore = ClipboardHistoryStore(),
        privacyPolicy: ClipboardPrivacyPolicy = .standard,
        pasteboard: NSPasteboard = .general,
        monitoringInterval: TimeInterval = 0.5
    ) {
        self.historyStore = historyStore
        self.privacyPolicy = privacyPolicy
        self.pasteboard = pasteboard
        self.monitoringInterval = monitoringInterval

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
        items.filter { $0.canRestoreAsText }
    }

    func startMonitoring() {
        guard !isMonitoring else {
            return
        }

        lastObservedPasteboardChangeCount = pasteboard.changeCount
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
        guard !kind.isDeferredVisual else {
            lastErrorMessage = nil
            statusMessage = "\(kind.displayName) clipboard items are deferred for a later fast-follow."
            return nil
        }

        guard ClipboardTextNormalization.hasMeaningfulContent(text) else {
            lastErrorMessage = nil
            statusMessage = "Clipboard text was empty."
            return nil
        }

        let privacyDecision = privacyPolicy.decision(
            for: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceWindowTitle: sourceWindowTitle,
            isSensitiveSource: isSensitiveSource
        )

        guard privacyDecision.allowsCapture else {
            lastErrorMessage = nil
            statusMessage = privacyDecision.reason ?? "Clipboard capture was suppressed."
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
        let snapshot = snapshot(from: pasteboard)
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
        case let .deferred(kind):
            lastErrorMessage = nil
            statusMessage = "\(kind.displayName) clipboard items are deferred for a later fast-follow."
            return nil
        case .unsupported:
            lastErrorMessage = nil
            statusMessage = "The clipboard does not contain text yet."
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
            return
        }

        let currentChangeCount = pasteboard.changeCount
        guard lastObservedPasteboardChangeCount != currentChangeCount else {
            return
        }

        _ = captureCurrentPasteboard()
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
        case deferred(kind: ClipboardItemKind)
        case unsupported
    }

    private func snapshot(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
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

        if hasImageLikeContents(in: pasteboard) {
            return .deferred(kind: .image)
        }

        return .unsupported
    }

    private func hasImageLikeContents(in pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else {
            return false
        }

        return types.contains { type in
            guard let utType = UTType(type.rawValue) else {
                return false
            }

            return utType.conforms(to: .image)
        }
    }
}
