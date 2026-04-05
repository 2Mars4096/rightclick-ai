import Foundation

struct ClipboardActionCompatibility: Codable, Hashable {
    enum Status: String, Codable, Hashable {
        case compatible
        case deferred
        case incompatible
    }

    let actionID: String
    let actionTitle: String
    let itemID: UUID
    let itemKind: ClipboardItemKind
    let status: Status
    let reason: String?

    var isCompatible: Bool {
        status == .compatible
    }

    var isDeferred: Bool {
        status == .deferred
    }

    static func evaluate(action: ActionDescriptor, item: ClipboardItem) -> ClipboardActionCompatibility {
        if item.kind.isDeferredNonText {
            return ClipboardActionCompatibility(
                actionID: action.id,
                actionTitle: action.title,
                itemID: item.id,
                itemKind: item.kind,
                status: .deferred,
                reason: item.kind.isDeferredVisual
                    ? "Visual clipboard items can already be previewed and restored, but AI actions are still text-only."
                    : "\(item.kind.displayName) clipboard items can already be previewed and restored, but AI actions are still text-only."
            )
        }

        guard let text = item.restorableText, ClipboardTextNormalization.hasMeaningfulContent(text) else {
            return ClipboardActionCompatibility(
                actionID: action.id,
                actionTitle: action.title,
                itemID: item.id,
                itemKind: item.kind,
                status: .incompatible,
                reason: "The clipboard item does not contain usable text."
            )
        }

        return ClipboardActionCompatibility(
            actionID: action.id,
            actionTitle: action.title,
            itemID: item.id,
            itemKind: item.kind,
            status: .compatible,
            reason: text.isEmpty ? "The clipboard item does not contain usable text." : nil
        )
    }

    static func evaluate(actionID: String, actionTitle: String, item: ClipboardItem) -> ClipboardActionCompatibility {
        evaluate(
            action: ActionDescriptor(id: actionID, title: actionTitle, subtitle: ""),
            item: item
        )
    }
}

extension ClipboardItem {
    var restorableText: String? {
        guard kind.isTextual else {
            return nil
        }

        return plainTextFallback
    }

    var restorableURLs: [URL] {
        guard let text = restorableText else {
            return []
        }

        let candidates = ClipboardTextNormalization.normalizeText(text)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        switch kind {
        case .url:
            return candidates.compactMap { URL(string: $0) }
        case .fileURL:
            return candidates.map { URL(fileURLWithPath: $0) }
        case .text, .richText, .html, .color, .image, .screenshot, .unknown:
            return []
        }
    }

    var canOpen: Bool {
        switch kind {
        case .url, .fileURL:
            return !restorableURLs.isEmpty
        case .text, .richText, .html, .color, .image, .screenshot, .unknown:
            return false
        }
    }
}
