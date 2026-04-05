import Foundation

struct ClipboardHistoryStore: Codable, Hashable {
    struct RetentionPolicy: Codable, Hashable {
        var maximumItemCount: Int
        var maximumAge: TimeInterval?
        var preserveProtectedItems: Bool
        var maximumVisualItemCount: Int
        var maximumVisualBytes: Int
        var maximumSingleVisualBytes: Int

        init(
            maximumItemCount: Int = 250,
            maximumAge: TimeInterval? = 60 * 60 * 24 * 30,
            preserveProtectedItems: Bool = true,
            maximumVisualItemCount: Int = 48,
            maximumVisualBytes: Int = 160 * 1024 * 1024,
            maximumSingleVisualBytes: Int = 20 * 1024 * 1024
        ) {
            self.maximumItemCount = maximumItemCount
            self.maximumAge = maximumAge
            self.preserveProtectedItems = preserveProtectedItems
            self.maximumVisualItemCount = maximumVisualItemCount
            self.maximumVisualBytes = maximumVisualBytes
            self.maximumSingleVisualBytes = maximumSingleVisualBytes
        }

        static let standard = RetentionPolicy()
    }

    let fileURL: URL
    var retentionPolicy: RetentionPolicy

    init(
        fileURL: URL = Self.defaultFileURL(),
        retentionPolicy: RetentionPolicy = .standard
    ) {
        self.fileURL = fileURL
        self.retentionPolicy = retentionPolicy
    }

    var rootDirectoryURL: URL {
        fileURL.deletingLastPathComponent()
    }

    var assetsDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("clipboard-assets", isDirectory: true)
    }

    static func defaultFileURL() -> URL {
        let fileManager = FileManager.default
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "RightClickApp"

        return supportDirectory
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("clipboard-history.json", isDirectory: false)
    }

    func load() throws -> [ClipboardItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(ClipboardHistorySnapshot.self, from: data)
        return snapshot.items
    }

    func save(_ items: [ClipboardItem]) throws {
        let snapshot = ClipboardHistorySnapshot(
            schemaVersion: 1,
            savedAt: .now,
            items: items
        )

        let directoryURL = rootDirectoryURL
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try pruneUnreferencedAssets(referencedRelativePaths: Set(items.compactMap(\.assetRelativePath)))
    }

    func saveVisualAsset(data: Data, itemID: UUID, fileExtension: String = "png") throws -> String {
        try saveAsset(data: data, itemID: itemID, fileExtension: fileExtension)
    }

    func saveAsset(data: Data, itemID: UUID, fileExtension: String) throws -> String {
        try FileManager.default.createDirectory(at: assetsDirectoryURL, withIntermediateDirectories: true)
        let filename = "\(itemID.uuidString.lowercased()).\(fileExtension)"
        let assetURL = assetsDirectoryURL.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: assetURL, options: .atomic)
        return "clipboard-assets/\(filename)"
    }

    func resolvedAssetURL(for item: ClipboardItem) -> URL? {
        guard let assetRelativePath = item.assetRelativePath else {
            return nil
        }

        return rootDirectoryURL.appendingPathComponent(assetRelativePath, isDirectory: false)
    }

    func deduplicated(_ items: [ClipboardItem]) -> [ClipboardItem] {
        let merged = items.reduce(into: [String: ClipboardItem]()) { partialResult, item in
            let key = item.dedupeKey
            if let existing = partialResult[key] {
                partialResult[key] = existing.merged(with: item)
            } else {
                partialResult[key] = item
            }
        }

        return merged.values.sorted(by: ClipboardItem.sortBefore)
    }

    func pruned(_ items: [ClipboardItem], now: Date = .now) -> [ClipboardItem] {
        let deduplicatedItems = deduplicated(items)
        let availableItems = pruneMissingAssets(deduplicatedItems)
        let ageLimitedItems = pruneByAge(availableItems, now: now)
        return pruneByCount(ageLimitedItems)
    }

    func deduplicatedAndPruned(_ items: [ClipboardItem], now: Date = .now) -> [ClipboardItem] {
        pruned(items, now: now)
    }

    func allowsVisualCapture(byteCount: Int) -> Bool {
        let maximumSingleVisualBytes = retentionPolicy.maximumSingleVisualBytes
        guard maximumSingleVisualBytes > 0 else {
            return true
        }

        return byteCount <= maximumSingleVisualBytes
    }

    private func pruneByAge(_ items: [ClipboardItem], now: Date) -> [ClipboardItem] {
        guard let maximumAge = retentionPolicy.maximumAge, maximumAge > 0 else {
            return items
        }

        let cutoff = now.addingTimeInterval(-maximumAge)
        return items.filter { item in
            if retentionPolicy.preserveProtectedItems, item.isProtected {
                return true
            }

            return item.lastActivityAt >= cutoff
        }
    }

    private func pruneByCount(_ items: [ClipboardItem]) -> [ClipboardItem] {
        let maximumItemCount = max(1, retentionPolicy.maximumItemCount)
        guard items.count > maximumItemCount else {
            return pruneByVisualLimits(items)
        }

        guard retentionPolicy.preserveProtectedItems else {
            return Array(items.prefix(maximumItemCount))
        }

        var prunedItems = items
        var index = prunedItems.count - 1

        while prunedItems.count > maximumItemCount, index >= 0 {
            if prunedItems[index].isProtected {
                index -= 1
                continue
            }

            prunedItems.remove(at: index)
            index -= 1
        }

        return pruneByVisualLimits(prunedItems.sorted(by: ClipboardItem.sortBefore))
    }

    private func pruneMissingAssets(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter { item in
            let requiresAsset = item.kind.isDeferredVisual || (item.prefersAssetRestore && !item.canRestoreAsText)
            guard requiresAsset else {
                return true
            }

            guard let assetURL = resolvedAssetURL(for: item) else {
                return false
            }

            return FileManager.default.fileExists(atPath: assetURL.path)
        }
    }

    private func pruneUnreferencedAssets(referencedRelativePaths: Set<String>) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: assetsDirectoryURL.path) else {
            return
        }

        let assetFiles = try fileManager.contentsOfDirectory(at: assetsDirectoryURL, includingPropertiesForKeys: nil)
        let referencedAssetNames = Set(
            referencedRelativePaths.compactMap { relativePath in
                URL(fileURLWithPath: relativePath).lastPathComponent
            }
        )

        for assetFile in assetFiles where !referencedAssetNames.contains(assetFile.lastPathComponent) {
            try? fileManager.removeItem(at: assetFile)
        }
    }

    private func pruneByVisualLimits(_ items: [ClipboardItem]) -> [ClipboardItem] {
        let visualItemLimit = max(1, retentionPolicy.maximumVisualItemCount)
        let visualByteLimit = max(0, retentionPolicy.maximumVisualBytes)

        guard visualItemLimit > 0 || visualByteLimit > 0 else {
            return items
        }

        var prunedItems = items

        func visualItems(in items: [ClipboardItem]) -> [ClipboardItem] {
            items.filter(\.kind.isDeferredVisual)
        }

        func visualBytes(in items: [ClipboardItem]) -> Int {
            visualItems(in: items).reduce(0) { partialResult, item in
                partialResult + max(0, item.assetByteCount ?? 0)
            }
        }

        func exceedsVisualLimits(_ items: [ClipboardItem]) -> Bool {
            let visualItemsCount = visualItems(in: items).count
            if visualItemsCount > visualItemLimit {
                return true
            }

            if visualByteLimit > 0, visualBytes(in: items) > visualByteLimit {
                return true
            }

            return false
        }

        while exceedsVisualLimits(prunedItems) {
            guard let removalIndex = prunedItems.indices.reversed().first(where: { index in
                let item = prunedItems[index]
                guard item.kind.isDeferredVisual else {
                    return false
                }

                if retentionPolicy.preserveProtectedItems, item.isProtected {
                    return false
                }

                return true
            }) else {
                break
            }

            prunedItems.remove(at: removalIndex)
        }

        return prunedItems.sorted(by: ClipboardItem.sortBefore)
    }
}

private struct ClipboardHistorySnapshot: Codable {
    var schemaVersion: Int
    var savedAt: Date
    var items: [ClipboardItem]
}
