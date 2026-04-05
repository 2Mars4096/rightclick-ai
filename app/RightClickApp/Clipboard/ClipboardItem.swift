import CryptoKit
import Foundation

enum ClipboardItemKind: String, Codable, CaseIterable, Hashable {
    case text
    case richText
    case html
    case color
    case url
    case fileURL
    case image
    case screenshot
    case unknown

    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .richText:
            return "Rich Text"
        case .html:
            return "HTML"
        case .color:
            return "Color"
        case .url:
            return "URL"
        case .fileURL:
            return "File URL"
        case .image:
            return "Image"
        case .screenshot:
            return "Screenshot"
        case .unknown:
            return "Clipboard Item"
        }
    }

    var isDeferredVisual: Bool {
        switch self {
        case .image, .screenshot:
            return true
        case .text, .richText, .html, .color, .url, .fileURL, .unknown:
            return false
        }
    }

    var isTextual: Bool {
        switch self {
        case .text, .richText, .html, .url, .fileURL, .unknown:
            return true
        case .color, .image, .screenshot:
            return false
        }
    }

    var isDeferredNonText: Bool {
        switch self {
        case .color, .image, .screenshot:
            return true
        case .text, .richText, .html, .url, .fileURL, .unknown:
            return false
        }
    }

    fileprivate func merged(preferredBy other: ClipboardItemKind) -> ClipboardItemKind {
        if self == other {
            return self
        }

        if self == .unknown {
            return other
        }

        if other == .unknown {
            return self
        }

        if self == .text {
            return other
        }

        if other == .text {
            return self
        }

        return other
    }
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: ClipboardItemKind
    let text: String?
    let normalizedText: String
    let assetFingerprint: String?
    let assetRelativePath: String?
    let assetPasteboardType: String?
    let assetByteCount: Int?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let capturedAt: Date
    var lastCapturedAt: Date
    var lastAccessedAt: Date?
    var lastRestoredAt: Date?
    var sourceName: String?
    var sourceBundleIdentifier: String?
    var sourceWindowTitle: String?
    var captureCount: Int
    var restoreCount: Int
    var isPinned: Bool
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        kind: ClipboardItemKind = .text,
        text: String?,
        assetFingerprint: String? = nil,
        assetRelativePath: String? = nil,
        assetPasteboardType: String? = nil,
        assetByteCount: Int? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        sourceName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        sourceWindowTitle: String? = nil,
        capturedAt: Date = .now,
        lastCapturedAt: Date? = nil,
        lastAccessedAt: Date? = nil,
        lastRestoredAt: Date? = nil,
        captureCount: Int = 1,
        restoreCount: Int = 0,
        isPinned: Bool = false,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.normalizedText = ClipboardTextNormalization.normalizeText(text ?? "")
        self.assetFingerprint = ClipboardTextNormalization.normalizeMetadata(assetFingerprint)
        self.assetRelativePath = ClipboardTextNormalization.normalizeMetadata(assetRelativePath)
        self.assetPasteboardType = ClipboardTextNormalization.normalizeMetadata(assetPasteboardType)
        self.assetByteCount = assetByteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.capturedAt = capturedAt
        self.lastCapturedAt = lastCapturedAt ?? capturedAt
        self.lastAccessedAt = lastAccessedAt
        self.lastRestoredAt = lastRestoredAt
        self.sourceName = ClipboardTextNormalization.normalizeMetadata(sourceName)
        self.sourceBundleIdentifier = ClipboardTextNormalization.normalizeMetadata(sourceBundleIdentifier)
        self.sourceWindowTitle = ClipboardTextNormalization.normalizeMetadata(sourceWindowTitle)
        self.captureCount = max(1, captureCount)
        self.restoreCount = max(0, restoreCount)
        self.isPinned = isPinned
        self.isFavorite = isFavorite
    }

    var isProtected: Bool {
        isPinned || isFavorite
    }

    var sortPriority: Int {
        switch (isPinned, isFavorite) {
        case (true, true):
            return 3
        case (true, false):
            return 2
        case (false, true):
            return 1
        case (false, false):
            return 0
        }
    }

    var lastActivityAt: Date {
        lastRestoredAt ?? lastAccessedAt ?? lastCapturedAt
    }

    var canRestore: Bool {
        if prefersAssetRestore {
            return assetRelativePath != nil || canRestoreAsText
        }

        if kind.isTextual {
            return canRestoreAsText
        }

        return assetRelativePath != nil
    }

    var prefersAssetRestore: Bool {
        switch kind {
        case .richText, .html, .color:
            return true
        case .text, .url, .fileURL, .image, .screenshot, .unknown:
            return false
        }
    }

    var canRestoreAsText: Bool {
        guard kind.isTextual else {
            return false
        }

        guard let text else {
            return false
        }

        return ClipboardTextNormalization.hasMeaningfulContent(text)
    }

    var dedupeKey: String {
        if kind.isDeferredVisual || prefersAssetRestore {
            return "visual:\(kind.rawValue):\(assetFingerprint ?? id.uuidString)"
        }

        return "text:\(normalizedText)"
    }

    var previewText: String {
        if kind.isDeferredVisual {
            if let dimensionsDescription {
                return "\(kind.displayName) • \(dimensionsDescription)"
            }

            return kind.displayName
        }

        guard let text, ClipboardTextNormalization.hasMeaningfulContent(text) else {
            return kind.displayName
        }

        return ClipboardTextNormalization.previewText(for: text)
    }

    var dimensionsDescription: String? {
        guard let pixelWidth, let pixelHeight, pixelWidth > 0, pixelHeight > 0 else {
            return nil
        }

        return "\(pixelWidth) × \(pixelHeight)"
    }

    var searchableText: String {
        ClipboardTextNormalization.searchIndex(
            from: [
                kind.displayName,
                text,
                normalizedText,
                assetRelativePath,
                assetPasteboardType,
                dimensionsDescription,
                sourceName,
                sourceBundleIdentifier,
                sourceWindowTitle,
                isPinned ? "pinned" : nil,
                isFavorite ? "favorite" : nil,
                captureCount > 1 ? "duplicate" : nil,
                restoreCount > 0 ? "restored" : nil
            ]
        )
    }

    func merged(with other: ClipboardItem) -> ClipboardItem {
        precondition(dedupeKey == other.dedupeKey, "Merged clipboard items must share a dedupe key.")

        return ClipboardItem(
            id: id,
            kind: kind.merged(preferredBy: other.kind),
            text: other.text ?? text,
            assetFingerprint: other.assetFingerprint ?? assetFingerprint,
            assetRelativePath: other.assetRelativePath ?? assetRelativePath,
            assetPasteboardType: other.assetPasteboardType ?? assetPasteboardType,
            assetByteCount: other.assetByteCount ?? assetByteCount,
            pixelWidth: other.pixelWidth ?? pixelWidth,
            pixelHeight: other.pixelHeight ?? pixelHeight,
            sourceName: other.sourceName ?? sourceName,
            sourceBundleIdentifier: other.sourceBundleIdentifier ?? sourceBundleIdentifier,
            sourceWindowTitle: other.sourceWindowTitle ?? sourceWindowTitle,
            capturedAt: min(capturedAt, other.capturedAt),
            lastCapturedAt: max(lastCapturedAt, other.lastCapturedAt),
            lastAccessedAt: ClipboardItem.maximumDate(lastAccessedAt, other.lastAccessedAt),
            lastRestoredAt: ClipboardItem.maximumDate(lastRestoredAt, other.lastRestoredAt),
            captureCount: captureCount + other.captureCount,
            restoreCount: restoreCount + other.restoreCount,
            isPinned: isPinned || other.isPinned,
            isFavorite: isFavorite || other.isFavorite
        )
    }

    static func sortBefore(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
        if lhs.sortPriority != rhs.sortPriority {
            return lhs.sortPriority > rhs.sortPriority
        }

        if lhs.lastActivityAt != rhs.lastActivityAt {
            return lhs.lastActivityAt > rhs.lastActivityAt
        }

        if lhs.lastCapturedAt != rhs.lastCapturedAt {
            return lhs.lastCapturedAt > rhs.lastCapturedAt
        }

        if lhs.capturedAt != rhs.capturedAt {
            return lhs.capturedAt > rhs.capturedAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func maximumDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }
}

enum ClipboardTextNormalization {
    static func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func normalizeMetadata(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func hasMeaningfulContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func searchIndex(from values: [String?]) -> String {
        let joined = values
            .compactMap { $0 }
            .map { normalizeText($0) }
            .joined(separator: " ")

        return foldForSearch(joined)
    }

    static func foldForSearch(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    static func searchTokens(for query: String) -> [String] {
        foldForSearch(query)
            .split { $0.isWhitespace || $0.isNewline }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func previewText(for text: String, maximumLength: Int = 140) -> String {
        let flattened = normalizeText(text)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        let trimmed = flattened.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumLength else {
            return trimmed
        }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maximumLength)
        return String(trimmed[..<endIndex]) + "…"
    }

    static func stableFingerprint(for value: String) -> String {
        let hash = SHA256.hash(data: Data(value.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func stableFingerprint(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
