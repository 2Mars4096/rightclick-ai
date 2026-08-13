import AppKit
import SwiftUI

struct ReviewWorkspaceView: View {
    @ObservedObject var model: AppModel
    @State private var showsCombinedInputPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            Group {
                switch model.activeWorkspaceMode {
                case .selection:
                    selectionWorkspace
                case .clipboard:
                    clipboardWorkspace
                case .paper:
                    paperWorkspace
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 840, minHeight: 620)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(Color(nsColor: .systemOrange))
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("RightClick AI")
                    .font(.headline.weight(.semibold))
                Text(model.activeWorkspaceMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            workspacePicker

            Button {
                model.reloadActions()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload installed actions")
            .accessibilityLabel("Reload installed actions")
            .disabled(model.isBusy)

            if #available(macOS 14.0, *) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .accessibilityLabel("Open Settings")
            } else {
                Button {
                    openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .accessibilityLabel("Open Settings")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var workspacePicker: some View {
        Picker("Workspace", selection: $model.activeWorkspaceMode) {
            ForEach(WorkspaceMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 300)
    }

    private var selectionWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Input", systemImage: "selection.pin.in.out")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    if !model.selectedText.isEmpty {
                        Text("\(model.selectedText.count) characters")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                ScrollView {
                    if model.selectedText.isEmpty {
                        ContentUnavailableView(
                            "No text yet",
                            systemImage: "text.cursor",
                            description: Text("Select text and use RightClick AI, or load the current clipboard.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 88)
                    } else {
                        Text(model.selectedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.vertical, 2)
                    }
                }
                .frame(height: 112)

                HStack {
                    Button(model.selectedText.isEmpty ? "Use Clipboard" : "Replace With Clipboard") {
                        model.importClipboardText()
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Text(model.launchSource)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Action")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Action", selection: $model.selectedActionID) {
                        ForEach(model.availableActions) { action in
                            Text(action.title).tag(action.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190, alignment: .leading)
                }

                if model.supportsUserInstruction {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.instructionFieldTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField(model.instructionPlaceholder, text: $model.userInstruction)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(model.selectedAction?.subtitle ?? "Choose an action.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 5)
                }

                if model.isPreparingPreview {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Running action")
                        .padding(.bottom, 4)
                }

                Button(model.runButtonTitle) {
                    model.preparePreview()
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canPreparePreview)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Result", systemImage: "bolt.horizontal.circle")
                        .font(.subheadline.weight(.semibold))

                    if let preview = model.preview {
                        Text(preview.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if model.isApplyingPreview {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Applying reviewed result")
                    } else if model.preview != nil {
                        Button(model.applyButtonTitle) {
                            model.applyPreview()
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(!model.canApplyPreview)
                    }
                }

                if model.isPreparingPreview {
                    ContentUnavailableView(
                        "Working…",
                        systemImage: "bolt.horizontal.circle",
                        description: Text("The window stays responsive while \(model.selectedAction?.title ?? "the action") runs.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let preview = model.preview {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(preview.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()
                        previewContent(preview)
                    }
                } else {
                    ContentUnavailableView(
                        "Ready",
                        systemImage: "bolt.horizontal.circle",
                        description: Text("Choose an action and run it. Direct Services remain the fastest path for repeat work.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(model.isApplyingPreview)
    }

    private var paperWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Selected PDF", systemImage: "doc.richtext")
                    .font(.subheadline.weight(.semibold))

                if let pdfURL = model.selectedPaperPDFURL {
                    Text(pdfURL.lastPathComponent)
                        .font(.body.weight(.medium))
                    Text(pdfURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    ContentUnavailableView(
                        "No paper selected",
                        systemImage: "doc",
                        description: Text("Right-click one PDF in Finder and choose Open Paper & Notes.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 90)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Google Scholar BibTeX", systemImage: "text.quote")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text("Required for a new paper")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $model.paperBibTeXDraft)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .frame(minHeight: 190)
                    .disabled(model.isIngestingPaper)

                if let proposal = model.selectedPaperDraftProposal {
                    VStack(alignment: .leading, spacing: 6) {
                        metadataRow("Citation Key", value: proposal.citationKey)
                        metadataRow("Title", value: proposal.paperTitle)
                        metadataRow("Paper Page", value: proposal.destinationPageURL.path)
                        metadataRow("Canonical PDF", value: proposal.destinationPDFURL.path)
                    }
                }

                Text(model.paperDraftStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label(model.paperIngestionModelSummary, systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Paper ingestion model. Change it in Settings.")

                    Toggle("Keep original PDF", isOn: $model.keepSourcePaperPDF)
                        .toggleStyle(.checkbox)
                        .disabled(model.isIngestingPaper)

                    Spacer()

                    if model.isIngestingPaper {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Ingesting paper with Codex")
                    }

                    Button(model.isIngestingPaper ? "Ingesting…" : "Ingest with Codex") {
                        model.ingestSelectedPaperWithCodex()
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canIngestSelectedPaperWithCodex)
                }

                if !model.paperIngestionOutput.isEmpty {
                    Divider()
                    ScrollView {
                        Text(model.paperIngestionOutput)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var legacySelectionWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Selected Text") {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView {
                        Text(model.selectedText.isEmpty ? "No selected text captured yet." : model.selectedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                    .frame(height: 128)

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

            HStack(alignment: .top, spacing: 16) {
                GroupBox("Action") {
                    VStack(alignment: .leading, spacing: 12) {
                        if !model.coreActions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ActionTier.core.sectionTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                FlowLayout(spacing: 8) {
                                    ForEach(model.coreActions) { action in
                                        Button {
                                            model.selectedActionID = action.id
                                        } label: {
                                            SelectableActionChip(
                                                title: action.title,
                                                isSelected: model.selectedActionID == action.id
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                Text(ActionTier.core.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

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

                        actionButtonRow
                    }
                    .padding(.vertical, 4)
                }
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 390, alignment: .topLeading)

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
                .frame(minWidth: 420, maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            GroupBox("Available Direct Services") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("These actions are also installed directly in the Services menu so you can run them without opening this window.")
                        .foregroundStyle(.secondary)

                    if !model.coreActions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ActionTier.core.sectionTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            FlowLayout(spacing: 10) {
                                ForEach(model.coreActions) { action in
                                    ActionChip(title: action.title)
                                }
                            }
                        }
                    }

                    if !model.utilityActions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ActionTier.utility.sectionTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            FlowLayout(spacing: 10) {
                                ForEach(model.utilityActions) { action in
                                    ActionChip(title: action.title)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var actionButtonRow: some View {
        ViewThatFits(in: .horizontal) {
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

            VStack(alignment: .leading, spacing: 8) {
                Button("Prepare Review") {
                    model.preparePreview()
                }
                .keyboardShortcut(.defaultAction)

                Button(model.applyButtonTitle) {
                    model.applyPreview()
                }
                .disabled(!model.canApplyPreview)

                Button("Reload Actions") {
                    model.reloadActions()
                }
            }
        }
    }

    private var clipboardWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TextField("Search clipboard history", text: $model.clipboardSearchQuery)
                    .textFieldStyle(.roundedBorder)

                if model.clipboardHotkeyEnabled {
                    Label(model.clipboardHotkeyShortcutLabel, systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Menu {
                    Button(model.clipboardManager.isPaused ? "Resume Capture" : "Pause Capture") {
                        model.toggleClipboardPause()
                    }

                    Button("Clear Last") {
                        model.clearMostRecentClipboardItem()
                    }
                    .disabled(model.filteredClipboardItems.isEmpty)

                    Divider()

                    Button("Clear Recent") {
                        model.clearRecentClipboardItems()
                    }

                    Button("Clear All") {
                        model.clearAllClipboardItems()
                    }
                } label: {
                    Label("History", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("History")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        Text("\(model.filteredClipboardItems.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                    Divider()

                    if model.filteredClipboardItems.isEmpty {
                        ContentUnavailableView(
                            "Clipboard history is empty",
                            systemImage: "doc.on.clipboard",
                            description: Text("Copy something, then press \(model.clipboardHotkeyShortcutLabel) to bring it back.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        clipboardHistoryList
                    }
                }
                .frame(minWidth: 300, idealWidth: 330)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.hasMultipleSelectedClipboardItems ? "Selection" : "Preview")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        if model.selectedClipboardItemCount > 0 {
                            Text("\(model.selectedClipboardItemCount) selected")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                    Divider()

                    clipboardSelectionDetail
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
                .frame(minWidth: 430)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var clipboardHistoryList: some View {
        List(selection: $model.selectedClipboardItemIDs) {
            ForEach(model.filteredClipboardItems) { item in
                ClipboardHistoryRow(
                    item: item,
                    isSelected: model.isClipboardItemSelected(item.id),
                    selectOnly: { model.selectOnlyClipboardItem(item.id) },
                    toggleSelection: { model.toggleClipboardItemSelection(item.id) }
                )
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
                                Button("Run \(compatibility.actionTitle)") {
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
        .listStyle(.inset)
    }

    private var legacyClipboardWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        TextField("Search clipboard history", text: $model.clipboardSearchQuery)
                            .textFieldStyle(.roundedBorder)

                        if model.clipboardHotkeyEnabled {
                            Label(model.clipboardHotkeyShortcutLabel, systemImage: "keyboard")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 10) {
                        Button(model.selectedClipboardItemCount > 1 ? "Use Selected In Review" : "Use In Review") {
                            model.useSelectedClipboardItemsInReview()
                        }
                        .disabled(!model.canUseSelectedClipboardItemsInReview)

                        Button("Import Paper") {
                            model.importSelectedClipboardItemsAsPaper()
                        }
                        .disabled(!model.canImportSelectedClipboardItemsAsPaper)

                        Menu("History") {
                            Button(model.clipboardManager.isPaused ? "Resume Capture" : "Pause Capture") {
                                model.toggleClipboardPause()
                            }

                            Button("Clear Last") {
                                model.clearMostRecentClipboardItem()
                            }
                            .disabled(model.filteredClipboardItems.isEmpty)

                            Divider()

                            Button("Clear Recent") {
                                model.clearRecentClipboardItems()
                            }
                            Button("Clear All") {
                                model.clearAllClipboardItems()
                            }
                        }

                        Spacer()
                    }

                    Text("Use the circle toggles in the history list to build a multi-selection for review or paper import.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        List(selection: $model.selectedClipboardItemIDs) {
                            ForEach(model.filteredClipboardItems) { item in
                                ClipboardHistoryRow(
                                    item: item,
                                    isSelected: model.isClipboardItemSelected(item.id),
                                    selectOnly: { model.selectOnlyClipboardItem(item.id) },
                                    toggleSelection: { model.toggleClipboardItemSelection(item.id) }
                                )
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

                GroupBox(model.hasMultipleSelectedClipboardItems ? "Selected Clipboard Items" : "Selected Clipboard Item") {
                    clipboardSelectionDetail
                }
                .frame(minWidth: 440)
            }
        }
    }

    @ViewBuilder
    private var clipboardSelectionDetail: some View {
        if model.hasMultipleSelectedClipboardItems {
            multipleClipboardSelectionDetail
        } else if let item = model.selectedClipboardItem {
            singleClipboardSelectionDetail(for: item)
        } else {
            ContentUnavailableView(
                "No clipboard item selected",
                systemImage: "doc.on.clipboard",
                description: Text("Choose an item from the history list to preview it, restore it, or run an action.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var multipleClipboardSelectionDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.selectedClipboardReviewSummary)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Use Selected In Review") {
                            model.useSelectedClipboardItemsInReview()
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(!model.canUseSelectedClipboardItemsInReview)

                        if model.canImportSelectedClipboardItemsAsPaper {
                            Button("Import Paper") {
                                model.importSelectedClipboardItemsAsPaper()
                            }
                        }

                        Spacer()
                    }
                }

                if model.showsPaperImportControls {
                    paperImportPanel
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Selected Items")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.selectedClipboardItems) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top, spacing: 8) {
                                    Label(item.kind.displayName, systemImage: clipboardIconName(for: item.kind))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    if item.isPinned {
                                        ActionChip(title: "Pinned", systemImage: "pin.fill")
                                    }

                                    if item.isFavorite {
                                        ActionChip(title: "Favorite", systemImage: "star.fill")
                                    }
                                }

                                Text(item.previewText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)

                                Text(item.sourceName ?? "Unknown source")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let lastSelectedItemID = model.selectedClipboardItems.last?.id,
                               lastSelectedItemID != item.id {
                                Divider()
                            }
                        }
                    }
                }

                if let combinedSelectedClipboardText = model.combinedSelectedClipboardText {
                    DisclosureGroup("Combined Input", isExpanded: $showsCombinedInputPreview) {
                        ScrollView {
                            Text(combinedSelectedClipboardText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.top, 8)
                        }
                        .frame(minHeight: 180)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func singleClipboardSelectionDetail(for item: ClipboardItem) -> some View {
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    clipboardPreview(for: item)
                }

                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 10) {
                        metadataRow("Last Captured", value: ReviewWorkspaceFormatters.timestamp.string(from: item.lastCapturedAt))
                        metadataRow("Captured", value: ReviewWorkspaceFormatters.timestamp.string(from: item.capturedAt))
                        metadataRow("Source", value: item.sourceName ?? "Unknown")
                        if item.kind == .url || item.kind == .fileURL {
                            metadataRow("References", value: "\(item.restorableURLs.count)")
                        }
                        if item.kind == .richText || item.kind == .html {
                            metadataRow("Format", value: item.kind.displayName)
                        }
                        if item.kind == .color {
                            metadataRow("Color", value: item.text ?? item.previewText)
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
                    .padding(.top, 10)
                }

                HStack {
                    Button("Use In Review") {
                        model.useSelectedClipboardItemInReview()
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
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

                    let compatibleActions = model.selectedClipboardCompatibilities.filter { $0.isCompatible }
                    if !compatibleActions.isEmpty {
                        Menu("Run Action") {
                            ForEach(compatibleActions, id: \.actionID) { compatibility in
                                Button(compatibility.actionTitle) {
                                    model.prepareClipboardAction(compatibility.actionID)
                                }
                            }
                        }
                    }

                    Spacer()

                    Button {
                        model.togglePinnedClipboardItem(item.id)
                    } label: {
                        Image(systemName: item.isPinned ? "pin.slash" : "pin")
                    }
                    .buttonStyle(.borderless)
                    .help(item.isPinned ? "Unpin" : "Pin")
                    .accessibilityLabel(item.isPinned ? "Unpin clipboard item" : "Pin clipboard item")

                    Button {
                        model.toggleFavoriteClipboardItem(item.id)
                    } label: {
                        Image(systemName: item.isFavorite ? "star.slash" : "star")
                    }
                    .buttonStyle(.borderless)
                    .help(item.isFavorite ? "Remove Favorite" : "Favorite")
                    .accessibilityLabel(item.isFavorite ? "Remove clipboard favorite" : "Favorite clipboard item")
                }

                if model.selectedClipboardCompatibilities.allSatisfy({ !$0.isCompatible }) {
                    Text(item.kind.isDeferredNonText
                        ? "This item can be previewed and restored. AI actions currently require text."
                        : "No installed text actions are available for this item.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.showsPaperImportControls {
                    paperImportPanel
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var paperImportPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Paper Import", systemImage: "doc.badge.plus")
                .font(.caption.weight(.semibold))

            Text(model.paperImportSelectionSummary)
                .foregroundStyle(.secondary)

            if let proposal = model.selectedPaperImportProposal {
                VStack(alignment: .leading, spacing: 8) {
                    metadataRow("Citation Key", value: proposal.citationKey)
                    metadataRow("Title", value: proposal.paperTitle)
                    metadataRow("Source PDF", value: proposal.sourcePDFURL.path)
                    metadataRow("Paper Page", value: proposal.destinationPageURL.path)
                    metadataRow("Canonical PDF", value: proposal.destinationPDFURL.path)
                }

                HStack {
                    Button("Import Paper") {
                        model.importSelectedClipboardItemsAsPaper()
                    }

                    Spacer()

                    if proposal.pageAlreadyExists {
                        ActionChip(title: "Page Exists")
                    }

                    if proposal.destinationPDFAlreadyExists {
                        ActionChip(title: "PDF Exists")
                    }
                }
            } else {
                Button("Import Paper") {
                    model.importSelectedClipboardItemsAsPaper()
                }
                .disabled(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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
        } else if item.kind == .color, let color = model.previewColor(for: item) {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: color))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .frame(height: 180)

                Text(item.text ?? item.previewText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
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
        StatusBanner(
            message: model.activeWorkspaceMode == .clipboard ? model.clipboardStatusMessage : model.statusMessage,
            tone: model.activeWorkspaceMode == .clipboard ? model.clipboardStatusTone : model.statusTone
        )
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
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Original")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(original)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 120)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Rewritten")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(rewritten)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 120)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
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
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(event.title)
                                        .font(.body.weight(.semibold))

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

                                if event.id != events.last?.id {
                                    Divider()
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
        case .richText:
            return "textformat"
        case .html:
            return "chevron.left.slash.chevron.right"
        case .color:
            return "paintpalette"
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

    private func openSettingsWindow() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.showSettingsWindow(nil)
            return
        }

        NSApp.sendAction(#selector(AppDelegate.showSettingsWindow(_:)), to: nil, from: nil)
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let selectOnly: () -> Void
    let toggleSelection: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: toggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Remove this item from the current selection." : "Add this item to the current selection.")
            .accessibilityLabel(isSelected ? "Remove clipboard item from selection" : "Add clipboard item to selection")

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
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: selectOnly)
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
        .padding(.vertical, 8)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            return .clear
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

private struct SelectableActionChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? Color(nsColor: .selectedControlTextColor) : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
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

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Color(nsColor: .selectedControlTextColor))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .systemOrange))
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
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
