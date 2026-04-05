import AppKit
import SwiftUI

struct ReviewWorkspaceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            workspacePicker

            switch model.activeWorkspaceMode {
            case .selection:
                selectionWorkspace
            case .clipboard:
                clipboardWorkspace
            }

            footer
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 640)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("RightClick AI")
                    .font(.title2.weight(.semibold))
                Text(model.activeWorkspaceMode.subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Settings") {
                (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
            }
        }
    }

    private var workspacePicker: some View {
        Picker("Workspace", selection: $model.activeWorkspaceMode) {
            ForEach(WorkspaceMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var selectionWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Selected Text") {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView {
                        Text(model.selectedText.isEmpty ? "No selected text captured yet." : model.selectedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 140)

                    HStack {
                        Button("Use Clipboard In Review") {
                            model.importClipboardText()
                        }

                        Text("Fallback path for apps where Services are unavailable or unreliable.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            HSplitView {
                GroupBox("Action") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Action", selection: $model.selectedActionID) {
                            ForEach(model.availableActions) { action in
                                Text(action.title).tag(action.id)
                            }
                        }

                        Text(model.selectedAction?.subtitle ?? "Choose an action to prepare a review.")
                            .foregroundStyle(.secondary)

                        if model.supportsUserInstruction {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(model.instructionFieldTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                TextField(model.instructionPlaceholder, text: $model.userInstruction, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(2...4)
                            }
                        }

                        HStack {
                            Button("Prepare Review") {
                                model.preparePreview()
                            }
                            .keyboardShortcut(.defaultAction)

                            Button(model.applyButtonTitle) {
                                model.applyPreview()
                            }
                            .disabled(!model.canApplyPreview)

                            Spacer()

                            Button("Reload Actions") {
                                model.reloadActions()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minWidth: 300)

                GroupBox("Review") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let preview = model.preview {
                            Text(preview.title)
                                .font(.headline)

                            Text(preview.summary)
                                .foregroundStyle(.secondary)

                            Divider()
                            previewContent(preview)
                        } else {
                            Text("Prepare a review to load a runtime-backed result.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minWidth: 420)
            }

            GroupBox("Available Direct Services") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("These actions are also installed directly in the Services menu so you can run them without opening this window.")
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 10) {
                        ForEach(model.directServiceActionTitles, id: \.self) { title in
                            ActionChip(title: title)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var clipboardWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                HStack(spacing: 12) {
                    TextField("Search clipboard history", text: $model.clipboardSearchQuery)
                        .textFieldStyle(.roundedBorder)

                    if model.clipboardHotkeyEnabled {
                        Label(model.clipboardHotkeyShortcutLabel, systemImage: "keyboard")
                            .foregroundStyle(.secondary)
                    }

                    Button(model.clipboardManager.isPaused ? "Resume Capture" : "Pause Capture") {
                        model.toggleClipboardPause()
                    }

                    Button("Clear Last") {
                        model.clearMostRecentClipboardItem()
                    }
                    .disabled(model.filteredClipboardItems.isEmpty)

                    Menu("More") {
                        Button("Clear Recent") {
                            model.clearRecentClipboardItems()
                        }
                        Button("Clear All") {
                            model.clearAllClipboardItems()
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            HSplitView {
                GroupBox("History") {
                    if model.filteredClipboardItems.isEmpty {
                        ContentUnavailableView(
                            "Clipboard history is empty",
                            systemImage: "doc.on.clipboard",
                            description: Text("Copy text or images anywhere on your Mac, then use \(model.clipboardHotkeyShortcutLabel) or this window to review it.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(selection: $model.selectedClipboardItemID) {
                            ForEach(model.filteredClipboardItems) { item in
                                ClipboardHistoryRow(item: item)
                                    .tag(item.id)
                                    .contextMenu {
                                        if item.canRestoreAsText {
                                            Button("Use In Review") {
                                                model.useClipboardItemInReview(item.id)
                                            }
                                        }

                                        if item.canOpen {
                                            Button(item.kind == .fileURL ? "Reveal In Finder" : "Open") {
                                                model.openClipboardItem(item.id)
                                            }
                                        }

                                        if item.canRestore {
                                            Button("Restore To Clipboard") {
                                                model.restoreClipboardItem(item.id)
                                            }
                                        }

                                        Divider()

                                        Button(item.isPinned ? "Unpin" : "Pin") {
                                            model.togglePinnedClipboardItem(item.id)
                                        }

                                        Button(item.isFavorite ? "Remove Favorite" : "Favorite") {
                                            model.toggleFavoriteClipboardItem(item.id)
                                        }

                                        Divider()

                                        ForEach(model.compatibleClipboardActions(for: item), id: \.actionID) { compatibility in
                                            if compatibility.isCompatible {
                                                Button("Prepare \(compatibility.actionTitle)") {
                                                    model.prepareClipboardAction(itemID: item.id, actionID: compatibility.actionID)
                                                }
                                            }
                                        }

                                        Divider()

                                        Button("Remove From History") {
                                            model.removeClipboardItem(item.id)
                                        }
                                    }
                            }
                        }
                    }
                }
                .frame(minWidth: 320, idealWidth: 340)

                GroupBox("Selected Clipboard Item") {
                    if let item = model.selectedClipboardItem {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .top, spacing: 12) {
                                    Label(item.kind.displayName, systemImage: clipboardIconName(for: item.kind))
                                        .font(.headline)

                                    Spacer()

                                    if item.isPinned {
                                        ActionChip(title: "Pinned", systemImage: "pin.fill")
                                    }

                                    if item.isFavorite {
                                        ActionChip(title: "Favorite", systemImage: "star.fill")
                                    }
                                }

                                GroupBox("Preview") {
                                    clipboardPreview(for: item)
                                }

                                GroupBox("Details") {
                                    VStack(alignment: .leading, spacing: 10) {
                                        metadataRow("Last Captured", value: ReviewWorkspaceFormatters.timestamp.string(from: item.lastCapturedAt))
                                        metadataRow("Captured", value: ReviewWorkspaceFormatters.timestamp.string(from: item.capturedAt))
                                        metadataRow("Source", value: item.sourceName ?? "Unknown")
                                        if item.kind == .url || item.kind == .fileURL {
                                            metadataRow("References", value: "\(item.restorableURLs.count)")
                                        }
                                        if let dimensions = item.dimensionsDescription {
                                            metadataRow("Dimensions", value: dimensions)
                                        }
                                        if let assetByteCount = item.assetByteCount {
                                            metadataRow("Size", value: ByteCountFormatter.string(fromByteCount: Int64(assetByteCount), countStyle: .file))
                                        }
                                        if let bundleIdentifier = item.sourceBundleIdentifier {
                                            metadataRow("Bundle ID", value: bundleIdentifier)
                                        }
                                        metadataRow("Captures", value: "\(item.captureCount)")
                                        metadataRow("Restores", value: "\(item.restoreCount)")
                                    }
                                    .padding(.vertical, 4)
                                }

                                HStack {
                                    Button("Use In Review") {
                                        model.useSelectedClipboardItemInReview()
                                    }
                                    .disabled(!model.canUseSelectedClipboardItemInReview)

                                    if item.canOpen {
                                        Button(item.kind == .fileURL ? "Reveal In Finder" : "Open") {
                                            model.openSelectedClipboardItem()
                                        }
                                    }

                                    Button("Restore To Clipboard") {
                                        model.restoreSelectedClipboardItem()
                                    }
                                    .disabled(!model.canRestoreSelectedClipboardItem)

                                    Spacer()

                                    Button(item.isPinned ? "Unpin" : "Pin") {
                                        model.togglePinnedClipboardItem(item.id)
                                    }

                                    Button(item.isFavorite ? "Remove Favorite" : "Favorite") {
                                        model.toggleFavoriteClipboardItem(item.id)
                                    }
                                }

                                GroupBox("Run An Action") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        let compatibleActions = model.selectedClipboardCompatibilities.filter { $0.isCompatible }
                                        if compatibleActions.isEmpty {
                                            Text(item.kind.isDeferredVisual
                                                ? "This clipboard item can already be previewed and restored, but AI actions still expect text."
                                                : "No installed text actions are available for this clipboard item yet.")
                                                .foregroundStyle(.secondary)
                                        } else {
                                            ForEach(compatibleActions, id: \.actionID) { compatibility in
                                                Button("Prepare \(compatibility.actionTitle)") {
                                                    model.prepareClipboardAction(compatibility.actionID)
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    } else {
                        ContentUnavailableView(
                            "No clipboard item selected",
                            systemImage: "doc.on.clipboard",
                            description: Text("Choose an item from the history list to preview it, restore it, or run an action.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 440)
            }
        }
    }

    @ViewBuilder
    private func clipboardPreview(for item: ClipboardItem) -> some View {
        if item.kind.isDeferredVisual, let image = model.previewImage(for: item) {
            GeometryReader { proxy in
                let width = max(proxy.size.width - 20, 240)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: width, minHeight: 180, maxHeight: 320)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .frame(minHeight: 200, maxHeight: 340)
        } else {
            if item.kind == .url || item.kind == .fileURL {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(item.restorableURLs.enumerated()), id: \.offset) { _, url in
                        Text(item.kind == .fileURL ? url.path : url.absoluteString)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text(item.text ?? item.normalizedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusBanner(
                message: model.activeWorkspaceMode == .clipboard ? model.clipboardStatusMessage : model.statusMessage,
                tone: model.activeWorkspaceMode == .clipboard ? model.clipboardStatusTone : model.statusTone
            )

            if model.activeWorkspaceMode == .clipboard {
                Text(model.clipboardStateSummary)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Text("Direct Services stay fastest for repeat use. This window is best for guided review and the clipboard fallback.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func previewContent(_ preview: RuntimePreview) -> some View {
        switch preview.content {
        case let .text(value):
            ScrollView {
                Text(value)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }
            .frame(minHeight: 180)
        case let .rewriteDiff(original, rewritten):
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Original") {
                    ScrollView {
                        Text(original)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 120)
                }

                GroupBox("Rewritten") {
                    ScrollView {
                        Text(rewritten)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 120)
                }
            }
        case let .eventDrafts(reason, events):
            VStack(alignment: .leading, spacing: 12) {
                if !reason.isEmpty {
                    Text(reason)
                        .foregroundStyle(.secondary)
                }

                if events.isEmpty {
                    Text("No calendar events were extracted from the selected text.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(events) { event in
                                GroupBox(event.title) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        eventField("When", value: event.allDay ? "\(event.start) to \(event.end) (all day)" : "\(event.start) to \(event.end)")
                                        if !event.location.isEmpty {
                                            eventField("Location", value: event.location)
                                        }
                                        if !event.calendar.isEmpty {
                                            eventField("Calendar", value: event.calendar)
                                        }
                                        if !event.notes.isEmpty {
                                            eventField("Notes", value: event.notes)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 180)
                }

                DisclosureGroup("Technical Details") {
                    Text(preview.proposedOutput)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func eventField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func clipboardIconName(for kind: ClipboardItemKind) -> String {
        switch kind {
        case .text:
            return "doc.text"
        case .url:
            return "link"
        case .fileURL:
            return "doc"
        case .image:
            return "photo"
        case .screenshot:
            return "camera.viewfinder"
        case .unknown:
            return "doc.on.clipboard"
        }
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(item.previewText)
                    .font(.body)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.secondary)
                } else if item.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Text(item.kind.displayName)
                if let sourceName = item.sourceName {
                    Text(sourceName)
                }
                Text(ReviewWorkspaceFormatters.relative.localizedString(for: item.lastCapturedAt, relativeTo: .now))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct StatusBanner: View {
    let message: String
    let tone: StatusTone

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .padding(.top, 1)

            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var iconName: String {
        switch tone {
        case .neutral:
            return "info.circle"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failure:
            return "xmark.octagon.fill"
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral:
            return Color(NSColor.controlBackgroundColor)
        case .success:
            return Color.green.opacity(0.12)
        case .warning:
            return Color.orange.opacity(0.14)
        case .failure:
            return Color.red.opacity(0.12)
        }
    }

    private var iconColor: Color {
        switch tone {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .failure:
            return .red
        }
    }
}

private struct ActionChip: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        Label {
            Text(title)
                .font(.caption.weight(.semibold))
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(Capsule())
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private enum ReviewWorkspaceFormatters {
    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
