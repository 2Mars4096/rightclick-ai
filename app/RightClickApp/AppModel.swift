import AppKit
import Combine
import Foundation
import ServiceManagement

extension Notification.Name {
    static let rightClickClipboardHotKeyPreferenceDidChange = Notification.Name("RightClickAI.clipboardHotKeyPreferenceDidChange")
}

struct ActionDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String

    var tier: ActionTier {
        switch id {
        case "add-to-calendar", "draft-response", "polish-draft", "explain", "summarize":
            return .core
        default:
            return .utility
        }
    }

    var displayOrder: Int {
        switch id {
        case "add-to-calendar":
            return 0
        case "draft-response":
            return 1
        case "polish-draft":
            return 2
        case "explain":
            return 3
        case "summarize":
            return 4
        case "extract-action-items":
            return 5
        case "rewrite-friendly":
            return 6
        default:
            return 100
        }
    }
}

enum ActionTier: String {
    case core
    case utility

    var sectionTitle: String {
        switch self {
        case .core:
            return "Core Actions"
        case .utility:
            return "More Actions"
        }
    }

    var summary: String {
        switch self {
        case .core:
            return "These are the main daily jobs RightClick AI is optimized for."
        case .utility:
            return "These are useful secondary utilities that stay available without competing with the core jobs."
        }
    }
}

struct RuntimeRequest: Sendable {
    let selectedText: String
    let actionID: String
    let actionTitle: String
    let userInstruction: String?
}

struct RuntimeEventDraft: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: String
    let end: String
    let allDay: Bool
    let location: String
    let notes: String
    let calendar: String
}

enum RuntimePreviewContent: Equatable, Sendable {
    case text(String)
    case rewriteDiff(original: String, rewritten: String)
    case eventDrafts(reason: String, events: [RuntimeEventDraft])
}

struct RuntimePreview: Equatable, Sendable {
    let title: String
    let summary: String
    let proposedOutput: String
    let content: RuntimePreviewContent
}

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case selection
    case clipboard
    case paper

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .selection:
            return "Selection"
        case .clipboard:
            return "Clipboard"
        case .paper:
            return "Paper"
        }
    }

    var subtitle: String {
        switch self {
        case .selection:
            return "Run an AI action on the text you selected in another app."
        case .clipboard:
            return "Search, review, and reuse recent clipboard items with the same action runtime."
        case .paper:
            return "Open an existing paper note or ingest a new PDF with Codex."
        }
    }
}

enum StatusTone: String {
    case neutral
    case success
    case warning
    case failure
}

@MainActor
final class AppModel: ObservableObject {
    private static let runtimeRootDefaultsKey = "rightClick.runtimeRootPath"
    private static let paperKnowledgeBaseRootDefaultsKey = "rightClick.paperKnowledgeBaseRootPath"
    private static let workspaceModeDefaultsKey = "rightClick.workspaceMode"
    private static let clipboardHotkeyEnabledDefaultsKey = "rightClick.clipboardHotkeyEnabled"
    static let defaultRuntimeRootPath = "~/Library/Application Support/RightClickAI"
    static let defaultPaperKnowledgeBaseRootPath = "~/Downloads/local_projects/my-knowledge-base"
    private static let legacyRuntimeRootPath = "~/Library/Application Support/RightClickCalendar"
    private static let legacyVolumePaperKnowledgeBaseRootPath = "/Volumes/data/Dropbox/Projects/my-knowledge-base"
    private static let legacyPaperKnowledgeBaseRootPath = "~/Dropbox/Projects/my-knowledge-base"

    static let shared = AppModel(runtimeBridge: InstalledRuntimeBridge())

    let clipboardManager: ClipboardManager

    @Published var selectedText = "" {
        didSet {
            if selectedText != oldValue {
                invalidatePreparedResult()
            }
        }
    }
    @Published var selectedActionID = "" {
        didSet {
            if selectedActionID != oldValue {
                invalidatePreparedResult()
            }
        }
    }
    @Published var userInstruction = "" {
        didSet {
            if userInstruction != oldValue {
                invalidatePreparedResult()
            }
        }
    }
    @Published var availableActions: [ActionDescriptor]
    @Published var preview: RuntimePreview?
    @Published var statusMessage = "Use the RightClick AI service on selected text to start a run."
    @Published var statusTone: StatusTone = .neutral
    @Published var launchSource = "Manual launch"
    @Published var runtimeSettings = RuntimeSettingsDocument()
    @Published var settingsStatusMessage = "Load or create a runtime settings file from the native Settings window."
    @Published var settingsStatusTone: StatusTone = .neutral
    @Published private(set) var isPreparingPreview = false
    @Published private(set) var isApplyingPreview = false
    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginStatusMessage = "RightClick AI will not start automatically when you log in."
    @Published var launchAtLoginStatusTone: StatusTone = .neutral
    @Published var runtimeRootPath: String {
        didSet {
            UserDefaults.standard.set(runtimeRootPath, forKey: Self.runtimeRootDefaultsKey)
        }
    }
    @Published var paperKnowledgeBaseRootPath: String {
        didSet {
            UserDefaults.standard.set(paperKnowledgeBaseRootPath, forKey: Self.paperKnowledgeBaseRootDefaultsKey)
        }
    }
    @Published var activeWorkspaceMode: WorkspaceMode {
        didSet {
            UserDefaults.standard.set(activeWorkspaceMode.rawValue, forKey: Self.workspaceModeDefaultsKey)
        }
    }
    @Published var clipboardSearchQuery = "" {
        didSet {
            reconcileClipboardSelection()
        }
    }
    @Published var selectedClipboardItemIDs: Set<ClipboardItem.ID> = [] {
        didSet {
            reconcileClipboardSelection()
        }
    }
    @Published var clipboardHotkeyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(clipboardHotkeyEnabled, forKey: Self.clipboardHotkeyEnabledDefaultsKey)
            NotificationCenter.default.post(name: .rightClickClipboardHotKeyPreferenceDidChange, object: self)
        }
    }
    @Published var selectedPaperPDFURL: URL? = nil
    @Published var paperBibTeXDraft = ""
    @Published var keepSourcePaperPDF = false
    @Published private(set) var isIngestingPaper = false
    @Published private(set) var paperIngestionOutput = ""

    private let runtimeBridge: any RuntimeBridge
    private var cancellables: Set<AnyCancellable> = []
    private var previewTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?
    private var paperIngestionTask: Task<Void, Never>?
    private var previewRequestID = UUID()

    convenience init(runtimeBridge: any RuntimeBridge) {
        self.init(runtimeBridge: runtimeBridge, clipboardManager: ClipboardManager())
    }

    init(
        runtimeBridge: any RuntimeBridge,
        clipboardManager: ClipboardManager
    ) {
        self.runtimeBridge = runtimeBridge
        self.clipboardManager = clipboardManager
        runtimeRootPath = Self.initialRuntimeRootPath()
        paperKnowledgeBaseRootPath = Self.initialPaperKnowledgeBaseRootPath()
        activeWorkspaceMode = Self.initialWorkspaceMode()
        clipboardHotkeyEnabled = Self.initialClipboardHotkeyEnabled()
        availableActions = []

        configureClipboardBindings()
        reloadActions(initialLoad: true)
        reloadRuntimeSettings(initialLoad: true)
        refreshLaunchAtLoginStatus(initialLoad: true)
        reconcileClipboardSelection()
    }

    var selectedAction: ActionDescriptor? {
        availableActions.first(where: { $0.id == selectedActionID })
    }

    var runtimeConfiguration: RuntimeConfiguration {
        RuntimeConfiguration(runtimeRootPath: runtimeRootPath)
    }

    var runtimeExecutablePath: String {
        runtimeConfiguration.runtimeExecutablePath
    }

    var runtimeSettingsPath: String {
        runtimeConfiguration.settingsFilePath
    }

    var actionBundleLocation: String {
        runtimeConfiguration.actionsDirectoryPath
    }

    var runtimeKeychainServiceName: String {
        runtimeConfiguration.keychainServiceName
    }

    var paperKnowledgeBaseConfiguration: PaperKnowledgeBaseConfiguration {
        PaperKnowledgeBaseConfiguration(rootPath: paperKnowledgeBaseRootPath)
    }

    var paperKnowledgeBaseExpandedRootPath: String {
        paperKnowledgeBaseConfiguration.expandedRootPath
    }

    var paperKnowledgeBaseContentPapersPath: String {
        paperKnowledgeBaseConfiguration.contentPapersDirectoryURL?.path
            ?? paperKnowledgeBaseExpandedRootPath + "/content/papers"
    }

    var paperKnowledgeBaseStaticPapersPath: String {
        paperKnowledgeBaseConfiguration.staticPapersDirectoryURL?.path
            ?? paperKnowledgeBaseExpandedRootPath + "/static/papers"
    }

    var paperImportAnalysis: ClipboardPaperImportAnalysis {
        ClipboardPaperImportAnalyzer.analyze(
            items: selectedClipboardItems,
            configuration: paperKnowledgeBaseConfiguration
        )
    }

    var selectedPaperImportProposal: ClipboardPaperImportProposal? {
        paperImportAnalysis.proposal
    }

    var canImportSelectedClipboardItemsAsPaper: Bool {
        selectedPaperImportProposal != nil
    }

    var showsPaperImportControls: Bool {
        selectedClipboardItems.contains { item in
            item.paperBibliographyEntry != nil || !item.paperPDFCandidateURLs.isEmpty
        }
    }

    var paperImportSelectionSummary: String {
        paperImportAnalysis.message
    }

    var paperDraftImportAnalysis: ClipboardPaperImportAnalysis {
        guard let selectedPaperPDFURL else {
            return .unavailable("Right-click a PDF in Finder and choose Open Paper & Notes.")
        }

        guard !paperBibTeXDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unavailable("Paste the complete Google Scholar BibTeX entry for this paper.")
        }

        return ClipboardPaperImportAnalyzer.analyze(
            pdfURL: selectedPaperPDFURL,
            bibTeX: paperBibTeXDraft,
            configuration: paperKnowledgeBaseConfiguration
        )
    }

    var selectedPaperDraftProposal: ClipboardPaperImportProposal? {
        paperDraftImportAnalysis.proposal
    }

    var canIngestSelectedPaperWithCodex: Bool {
        selectedPaperDraftProposal != nil && !isIngestingPaper
    }

    var paperDraftStatusMessage: String {
        if isIngestingPaper {
            return "Codex is verifying, skimming, and ingesting the paper. This can take several minutes."
        }

        return paperDraftImportAnalysis.message
    }

    var selectedProviderTitle: String {
        RuntimeProviderOption.title(for: runtimeSettings.provider)
    }

    var directServiceActionTitles: [String] {
        availableActions.map(\.title)
    }

    var coreActions: [ActionDescriptor] {
        availableActions.filter { $0.tier == .core }
    }

    var utilityActions: [ActionDescriptor] {
        availableActions.filter { $0.tier == .utility }
    }

    var filteredClipboardItems: [ClipboardItem] {
        clipboardManager.search(query: clipboardSearchQuery)
    }

    var selectedClipboardItems: [ClipboardItem] {
        let matchingItems = filteredClipboardItems.filter { selectedClipboardItemIDs.contains($0.id) }
        if !matchingItems.isEmpty {
            return matchingItems
        }

        if let firstVisibleItem = filteredClipboardItems.first {
            return [firstVisibleItem]
        }

        return []
    }

    var selectedClipboardItem: ClipboardItem? {
        selectedClipboardItems.first
    }

    var selectedClipboardCompatibilities: [ClipboardActionCompatibility] {
        guard selectedClipboardItems.count == 1,
              let itemID = selectedClipboardItem?.id else {
            return []
        }

        return clipboardManager.compatibilities(for: availableActions, itemID: itemID)
    }

    var clipboardHotkeyShortcutLabel: String {
        "⌃⌥⌘V"
    }

    var clipboardStatusMessage: String {
        clipboardManager.statusMessage
    }

    var clipboardStatusTone: StatusTone {
        if clipboardManager.lastErrorMessage != nil {
            return .failure
        }

        if clipboardManager.isPaused {
            return .warning
        }

        return .neutral
    }

    var clipboardStateSummary: String {
        if clipboardManager.isPaused {
            return clipboardManager.pauseReason.map { "Capture paused: \($0)" } ?? "Capture paused."
        }

        if filteredClipboardItems.isEmpty {
            return "Clipboard history is empty."
        }

        return "Showing \(filteredClipboardItems.count) saved clipboard item(s)."
    }

    var selectedClipboardItemCount: Int {
        selectedClipboardItems.count
    }

    var hasMultipleSelectedClipboardItems: Bool {
        selectedClipboardItems.count > 1
    }

    var combinedSelectedClipboardText: String? {
        ClipboardSelectionComposer.compose(items: selectedClipboardItems)?.text
    }

    var selectedClipboardReviewSummary: String {
        let selectedCount = selectedClipboardItems.count
        guard selectedCount > 0 else {
            return "Choose one or more saved clipboard items to review."
        }

        if canUseSelectedClipboardItemsInReview {
            if selectedCount == 1 {
                return "This clipboard item can be loaded into review."
            }

            return "These \(selectedCount) clipboard items will be combined into one review input."
        }

        return "Only text, rich text, HTML, URLs, and file references can be combined into review right now."
    }

    var canUseSelectedClipboardItemsInReview: Bool {
        guard !selectedClipboardItems.isEmpty else {
            return false
        }

        return combinedSelectedClipboardText != nil
    }

    var canUseSelectedClipboardItemInReview: Bool {
        selectedClipboardItems.count == 1 && canUseSelectedClipboardItemsInReview
    }

    var canRestoreSelectedClipboardItem: Bool {
        selectedClipboardItems.count == 1 && selectedClipboardItem?.canRestore == true
    }

    var canOpenSelectedClipboardItem: Bool {
        selectedClipboardItems.count == 1 && selectedClipboardItem?.canOpen == true
    }

    var needsProviderSetup: Bool {
        switch runtimeSettings.provider {
        case "openai_compatible":
            return runtimeSettings.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "anthropic":
            return runtimeSettings.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "gemini":
            return runtimeSettings.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "custom_command":
            return runtimeSettings.customProviderCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    var canApplyPreview: Bool {
        preview != nil && !isBusy
    }

    var canPreparePreview: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedAction != nil
            && !isBusy
    }

    var isBusy: Bool {
        isPreparingPreview || isApplyingPreview || isIngestingPaper
    }

    var runButtonTitle: String {
        if isPreparingPreview {
            return "Running…"
        }

        return selectedAction.map { "Run \($0.title)" } ?? "Run Action"
    }

    var supportsUserInstruction: Bool {
        guard let selectedAction else {
            return false
        }

        return selectedAction.id != "add-to-calendar"
    }

    var instructionFieldTitle: String {
        switch selectedAction?.id {
        case "draft-response":
            return "Reply Guidance"
        case "polish-draft":
            return "Polish Guidance"
        case "explain":
            return "Explanation Guidance"
        case "rewrite-friendly":
            return "Rewrite Guidance"
        case "extract-action-items":
            return "Extraction Guidance"
        case "summarize":
            return "Summary Guidance"
        default:
            return "Optional Guidance"
        }
    }

    var instructionPlaceholder: String {
        switch selectedAction?.id {
        case "draft-response":
            return "Optional instruction, for example: keep it short and warm."
        case "polish-draft":
            return "Optional instruction, for example: keep my tone but make it tighter."
        case "explain":
            return "Optional instruction, for example: explain this for a beginner."
        case "rewrite-friendly":
            return "Optional instruction, for example: make it friendlier but still direct."
        case "extract-action-items":
            return "Optional instruction, for example: focus only on tasks for me."
        case "summarize":
            return "Optional instruction, for example: focus on risks and decisions."
        default:
            return "Optional instruction."
        }
    }

    var applyButtonTitle: String {
        switch selectedAction?.id {
        case "add-to-calendar":
            return "Create Events"
        case "draft-response":
            return "Copy Draft Reply"
        case "polish-draft":
            return "Copy Polished Draft"
        case "explain":
            return "Copy Explanation"
        case "rewrite-friendly":
            return "Copy Rewrite"
        case "extract-action-items":
            return "Copy Action Items"
        case "summarize":
            return "Copy Summary"
        default:
            return "Apply"
        }
    }

    var notificationDefaultsSummary: String {
        switch (runtimeSettings.notifyOnSuccess, runtimeSettings.notifyOnFailure) {
        case (true, true):
            return "Recommended: notify on both success and failure."
        case (false, true):
            return "Failure-only: keep errors visible but keep success quiet."
        case (true, false):
            return "Success-only: unusual for a utility app, but possible."
        case (false, false):
            return "Silent mode: fastest once the workflow feels routine."
        }
    }

    func acceptSelectedText(_ text: String, source: String) {
        selectedText = text
        userInstruction = ""
        launchSource = source
        preview = nil
        activeWorkspaceMode = .selection

        do {
            let actions = try loadActions()
            if actions.isEmpty {
                setStatus("Captured \(text.count) characters from \(source), but no installed actions were found.", tone: .warning)
            } else {
                setStatus("Captured \(text.count) characters from \(source). Ready to run \(actions.count) action(s).")
            }
        } catch {
            availableActions = []
            selectedActionID = ""
            setStatus(error.localizedDescription, tone: .failure)
        }
    }

    func importClipboardText() {
        let clipboardText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !clipboardText.isEmpty else {
            setStatus("The clipboard does not contain plain text yet.", tone: .warning)
            return
        }

        acceptSelectedText(clipboardText, source: "Clipboard Fallback")
    }

    func showSelectedTextWorkspace() {
        activeWorkspaceMode = .selection
    }

    func showClipboardWorkspace() {
        startClipboardMonitoringIfNeeded()
        activeWorkspaceMode = .clipboard
        reconcileClipboardSelection()

        if filteredClipboardItems.isEmpty {
            setStatus("Clipboard history is ready. Copy text, then use the clipboard workspace or the direct Services.")
        }
    }

    func showPaperWorkspace() {
        activeWorkspaceMode = .paper
    }

    @discardableResult
    func acceptSelectedPaperPDF(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame,
              FileManager.default.fileExists(atPath: standardizedURL.path) else {
            setStatus("RightClick AI needs one existing PDF file.", tone: .warning)
            activeWorkspaceMode = .paper
            return false
        }

        selectedPaperPDFURL = standardizedURL
        paperBibTeXDraft = ""
        paperIngestionOutput = ""
        launchSource = "Finder PDF Service"

        if let match = PaperKnowledgeBaseResolver.match(
            for: standardizedURL,
            configuration: paperKnowledgeBaseConfiguration
        ) {
            openPaperAndNotes(match: match, selectedPDFURL: standardizedURL)
            return true
        }

        activeWorkspaceMode = .paper
        setStatus(
            "No corresponding paper note was found. Paste the Google Scholar BibTeX entry to ingest it with Codex.",
            tone: .warning
        )
        return false
    }

    func ingestSelectedPaperWithCodex() {
        guard let proposal = selectedPaperDraftProposal,
              let knowledgeBaseRoot = paperKnowledgeBaseConfiguration.rootURL else {
            setStatus(paperDraftImportAnalysis.message, tone: .warning)
            return
        }

        paperIngestionTask?.cancel()
        isIngestingPaper = true
        paperIngestionOutput = ""
        setStatus("Codex is ingesting \(proposal.citationKey) with the ingest-paper-kb skill.")

        let request = CodexPaperIngestionRequest(
            proposal: proposal,
            knowledgeBaseRoot: knowledgeBaseRoot,
            keepSourcePDF: keepSourcePaperPDF
        )
        let citationKey = proposal.citationKey

        paperIngestionTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let output = try await CodexPaperIngestionLauncher.run(request)
                guard !Task.isCancelled else {
                    return
                }

                paperIngestionOutput = CodexPaperIngestionLauncher.finalAgentMessage(fromJSONLines: output) ?? output
                isIngestingPaper = false

                if let match = PaperKnowledgeBaseResolver.match(
                    citationKey: citationKey,
                    configuration: paperKnowledgeBaseConfiguration
                ) {
                    selectedPaperPDFURL = match.pdfURL
                    openPaperAndNotes(match: match, selectedPDFURL: match.pdfURL)
                    setStatus("Ingested \(citationKey) and opened its PDF and notes.", tone: .success)
                } else {
                    setStatus(
                        "Codex finished, but no verified paper page was found for \(citationKey). Review the run output below.",
                        tone: .warning
                    )
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                isIngestingPaper = false
                paperIngestionOutput = error.localizedDescription
                setStatus(error.localizedDescription, tone: .failure)
            }
        }
    }

    private func openPaperAndNotes(match: PaperKnowledgeBaseMatch, selectedPDFURL: URL) {
        let openedPDF = NSWorkspace.shared.open(selectedPDFURL)
        let openedNotes = NSWorkspace.shared.open(match.pageURL)
        setStatus(
            openedPDF && openedNotes
                ? "Opened \(match.citationKey) and its notes."
                : "Found \(match.citationKey), but macOS could not open both files.",
            tone: openedPDF && openedNotes ? .success : .warning
        )
    }

    func startClipboardMonitoringIfNeeded() {
        clipboardManager.startMonitoring()
        reconcileClipboardSelection()
    }

    func setClipboardHotkeyEnabled(_ enabled: Bool) {
        guard clipboardHotkeyEnabled != enabled else {
            return
        }

        clipboardHotkeyEnabled = enabled
        setSettingsStatus(
            enabled
                ? "Clipboard history hotkey enabled. Use \(clipboardHotkeyShortcutLabel) to open it quickly."
                : "Clipboard history hotkey disabled.",
            tone: .success
        )
    }

    func toggleClipboardPause() {
        if clipboardManager.isPaused {
            clipboardManager.resume()
        } else {
            clipboardManager.pause(reason: "paused from the RightClick AI menu")
        }

        objectWillChange.send()
    }

    func clearMostRecentClipboardItem() {
        _ = clipboardManager.clearMostRecent()
        reconcileClipboardSelection()
        objectWillChange.send()
    }

    func clearRecentClipboardItems() {
        _ = clipboardManager.clearRecent()
        reconcileClipboardSelection()
        objectWillChange.send()
    }

    func clearAllClipboardItems() {
        _ = clipboardManager.clearAll()
        reconcileClipboardSelection()
        objectWillChange.send()
    }

    func restoreSelectedClipboardItem() {
        guard let item = selectedClipboardItem else {
            setStatus("Choose a clipboard item first.", tone: .warning)
            return
        }

        _ = clipboardManager.restore(itemID: item.id)
        objectWillChange.send()
    }

    func restoreClipboardItem(_ itemID: ClipboardItem.ID) {
        _ = clipboardManager.restore(itemID: itemID)
        objectWillChange.send()
    }

    func openSelectedClipboardItem() {
        guard let item = selectedClipboardItem else {
            setStatus("Choose a clipboard item first.", tone: .warning)
            return
        }

        _ = clipboardManager.open(itemID: item.id)
        objectWillChange.send()
    }

    func openClipboardItem(_ itemID: ClipboardItem.ID) {
        _ = clipboardManager.open(itemID: itemID)
        objectWillChange.send()
    }

    func togglePinnedClipboardItem(_ itemID: ClipboardItem.ID) {
        guard let item = clipboardManager.item(withID: itemID) else {
            return
        }

        _ = clipboardManager.setPinned(!item.isPinned, for: itemID)
        objectWillChange.send()
    }

    func toggleFavoriteClipboardItem(_ itemID: ClipboardItem.ID) {
        guard let item = clipboardManager.item(withID: itemID) else {
            return
        }

        _ = clipboardManager.setFavorite(!item.isFavorite, for: itemID)
        objectWillChange.send()
    }

    func removeClipboardItem(_ itemID: ClipboardItem.ID) {
        _ = clipboardManager.remove(itemID: itemID, reason: "Removed a clipboard item from history.")
        reconcileClipboardSelection()
        objectWillChange.send()
    }

    func isClipboardItemSelected(_ itemID: ClipboardItem.ID) -> Bool {
        selectedClipboardItemIDs.contains(itemID)
    }

    func selectOnlyClipboardItem(_ itemID: ClipboardItem.ID) {
        selectedClipboardItemIDs = [itemID]
        objectWillChange.send()
    }

    func toggleClipboardItemSelection(_ itemID: ClipboardItem.ID) {
        var updatedSelection = selectedClipboardItemIDs
        if updatedSelection.contains(itemID) {
            if updatedSelection.count == 1 {
                return
            }

            updatedSelection.remove(itemID)
        } else {
            updatedSelection.insert(itemID)
        }

        selectedClipboardItemIDs = updatedSelection
        objectWillChange.send()
    }

    func useSelectedClipboardItemsInReview() {
        let items = selectedClipboardItems
        guard !items.isEmpty else {
            setStatus("Choose one or more clipboard items first.", tone: .warning)
            return
        }

        if items.count == 1, let item = items.first {
            routeClipboardItemToReview(itemID: item.id)
            return
        }

        guard let composition = ClipboardSelectionComposer.compose(items: items) else {
            setStatus("Only text, rich text, HTML, URLs, and file references can be combined into review right now.", tone: .warning)
            return
        }

        selectedText = composition.text
        launchSource = "Clipboard History (\(composition.itemCount) items)"
        userInstruction = ""
        preview = nil
        activeWorkspaceMode = .selection
        setStatus("Combined \(composition.itemCount) clipboard items into one review input.", tone: .success)
    }

    func useSelectedClipboardItemInReview() {
        useSelectedClipboardItemsInReview()
    }

    func useClipboardItemInReview(_ itemID: ClipboardItem.ID) {
        routeClipboardItemToReview(itemID: itemID)
    }

    func prepareClipboardAction(_ actionID: String) {
        guard let item = selectedClipboardItem else {
            setStatus("Choose a clipboard item first.", tone: .warning)
            return
        }

        routeClipboardItemToReview(itemID: item.id, actionID: actionID, prepareAfterRouting: true)
    }

    func prepareClipboardAction(itemID: ClipboardItem.ID, actionID: String) {
        routeClipboardItemToReview(itemID: itemID, actionID: actionID, prepareAfterRouting: true)
    }

    func compatibleClipboardActions(for item: ClipboardItem) -> [ClipboardActionCompatibility] {
        clipboardManager.compatibilities(for: availableActions, itemID: item.id)
    }

    func previewImage(for item: ClipboardItem) -> NSImage? {
        clipboardManager.previewImage(for: item.id)
    }

    func previewColor(for item: ClipboardItem) -> NSColor? {
        clipboardManager.previewColor(for: item.id)
    }

    private var normalizedUserInstruction: String? {
        let trimmed = userInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func preparePreview() {
        guard !isBusy else {
            return
        }

        let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            setStatus("No selected text has been captured yet.", tone: .warning)
            preview = nil
            return
        }

        guard let selectedAction else {
            setStatus("Choose an action before preparing review.", tone: .warning)
            preview = nil
            return
        }

        let request = RuntimeRequest(
            selectedText: trimmedText,
            actionID: selectedAction.id,
            actionTitle: selectedAction.title,
            userInstruction: normalizedUserInstruction
        )
        let configuration = runtimeConfiguration
        let bridge = runtimeBridge
        let requestID = UUID()

        previewTask?.cancel()
        previewRequestID = requestID
        preview = nil
        isPreparingPreview = true
        setStatus("Running \(selectedAction.title)…")

        previewTask = Task { [weak self] in
            do {
                let preparedPreview = try await Task.detached(priority: .userInitiated) {
                    try bridge.preparePreview(for: request, configuration: configuration)
                }.value

                guard let self, self.previewRequestID == requestID, !Task.isCancelled else {
                    return
                }

                self.preview = preparedPreview
                self.isPreparingPreview = false
                self.previewTask = nil
                self.setStatus("\(selectedAction.title) is ready to review.", tone: .success)
            } catch {
                guard let self, self.previewRequestID == requestID, !Task.isCancelled else {
                    return
                }

                self.preview = nil
                self.isPreparingPreview = false
                self.previewTask = nil
                self.setStatus(error.localizedDescription, tone: .failure)
            }
        }
    }

    func applyPreview() {
        guard !isBusy else {
            return
        }

        guard let selectedAction else {
            setStatus("Choose an action before applying.", tone: .warning)
            return
        }

        let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            setStatus("No selected text has been captured yet.", tone: .warning)
            return
        }

        guard let preview else {
            setStatus("Prepare a review before applying.", tone: .warning)
            return
        }

        if selectedAction.id == "add-to-calendar" {
            let request = RuntimeRequest(
                selectedText: trimmedText,
                actionID: selectedAction.id,
                actionTitle: selectedAction.title,
                userInstruction: normalizedUserInstruction
            )
            let configuration = runtimeConfiguration
            let bridge = runtimeBridge

            isApplyingPreview = true
            setStatus("Creating the reviewed calendar events…")

            applyTask = Task { [weak self] in
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try bridge.performAction(for: request, preview: preview, configuration: configuration)
                    }.value

                    guard let self else {
                        return
                    }

                    self.isApplyingPreview = false
                    self.applyTask = nil
                    self.setStatus("Created the reviewed calendar events.", tone: .success)
                } catch {
                    guard let self else {
                        return
                    }

                    self.isApplyingPreview = false
                    self.applyTask = nil
                    self.setStatus(error.localizedDescription, tone: .failure)
                }
            }
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(preview.proposedOutput, forType: .string) else {
            setStatus("The result is ready, but macOS did not accept it on the clipboard. Try copying it from the result view.", tone: .failure)
            return
        }
        setStatus("Copied \(selectedAction.title) output to the clipboard.", tone: .success)
    }

    private func invalidatePreparedResult() {
        previewRequestID = UUID()
        previewTask?.cancel()
        previewTask = nil
        isPreparingPreview = false
        preview = nil
    }

    func reloadActions(initialLoad: Bool = false) {
        do {
            let actions = try loadActions()
            if actions.isEmpty {
                setStatus("No installed actions were found at \(actionBundleLocation).", tone: .warning)
            } else if initialLoad {
                setStatus("Loaded \(actions.count) action(s) from \(runtimeExecutablePath).")
            } else {
                setStatus("Reloaded \(actions.count) action(s) from \(runtimeExecutablePath).")
            }
        } catch {
            availableActions = []
            selectedActionID = ""
            preview = nil
            setStatus(error.localizedDescription, tone: .failure)
        }
    }

    func resetRuntimeRootPath() {
        runtimeRootPath = Self.defaultRuntimeRootPath
        reloadActions()
        reloadRuntimeSettings()
    }

    func resetPaperKnowledgeBaseRootPath() {
        paperKnowledgeBaseRootPath = Self.defaultPaperKnowledgeBaseRootPath
        setSettingsStatus("Restored the default paper knowledge base root.", tone: .success)
    }

    func openRuntimeSettingsFile() {
        let url = URL(fileURLWithPath: runtimeSettingsPath)
        guard FileManager.default.fileExists(atPath: runtimeSettingsPath) else {
            setStatus("No runtime settings file exists at \(runtimeSettingsPath). Install the runtime first.", tone: .failure)
            return
        }

        NSWorkspace.shared.open(url)
    }

    func openRuntimeRootDirectory() {
        let path = (runtimeRootPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            setStatus("The runtime root does not exist yet at \(path). Install the runtime first.", tone: .failure)
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func openActionsDirectory() {
        let path = actionBundleLocation
        guard FileManager.default.fileExists(atPath: path) else {
            setStatus("The actions directory does not exist yet at \(path). Install the runtime first.", tone: .failure)
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func openPaperKnowledgeBaseRootDirectory() {
        openPaperKnowledgeBaseDirectory(
            at: paperKnowledgeBaseExpandedRootPath,
            missingMessage: "The paper knowledge base root does not exist yet at \(paperKnowledgeBaseExpandedRootPath)."
        )
    }

    func openPaperKnowledgeBaseContentPapersDirectory() {
        openPaperKnowledgeBaseDirectory(
            at: paperKnowledgeBaseContentPapersPath,
            missingMessage: "The paper content directory does not exist yet at \(paperKnowledgeBaseContentPapersPath)."
        )
    }

    func openPaperKnowledgeBaseStaticPapersDirectory() {
        openPaperKnowledgeBaseDirectory(
            at: paperKnowledgeBaseStaticPapersPath,
            missingMessage: "The paper PDF directory does not exist yet at \(paperKnowledgeBaseStaticPapersPath)."
        )
    }

    func reloadRuntimeSettings(initialLoad: Bool = false) {
        do {
            runtimeSettings = try RuntimeSettingsDocument.load(from: runtimeSettingsPath)
            if initialLoad, runtimeSettings.loadedProviderSecretFromKeychain {
                do {
                    try runtimeSettings.write(to: runtimeSettingsPath, syncKeychain: false)
                    setSettingsStatus(
                        "Loaded provider secret from Keychain and mirrored it to \(runtimeSettingsPath) for direct Services."
                    )
                    return
                } catch {
                    setSettingsStatus(
                        "Loaded runtime settings, but could not mirror provider secrets for direct Services: \(error.localizedDescription)",
                        tone: .warning
                    )
                    return
                }
            }

            setSettingsStatus(
                initialLoad
                    ? "Loaded runtime settings from \(runtimeSettingsPath)."
                    : "Reloaded runtime settings from \(runtimeSettingsPath)."
            )
        } catch RuntimeSettingsError.missingSettings {
            runtimeSettings = RuntimeSettingsDocument()
            setSettingsStatus("No settings.env was found at \(runtimeSettingsPath). Save from this window to create one.", tone: .warning)
        } catch {
            setSettingsStatus(error.localizedDescription, tone: .failure)
        }
    }

    func saveRuntimeSettings() {
        do {
            try runtimeSettings.write(to: runtimeSettingsPath)
            setSettingsStatus("Saved settings. Provider secrets are protected in Keychain and mirrored to the private runtime file for direct Services.", tone: .success)
        } catch {
            setSettingsStatus(error.localizedDescription, tone: .failure)
        }
    }

    func applyRecommendedNotificationDefaults() {
        runtimeSettings.notifyOnSuccess = true
        runtimeSettings.notifyOnFailure = true
        setSettingsStatus("Notification defaults restored. Direct Services will notify on both success and failure.", tone: .success)
    }

    func importSelectedClipboardItemsAsPaper() {
        guard let proposal = selectedPaperImportProposal else {
            setStatus(paperImportSelectionSummary, tone: .warning)
            return
        }

        do {
            let result = try ClipboardPaperImporter.import(
                proposal: proposal,
                configuration: paperKnowledgeBaseConfiguration
            )
            setStatus(result.summary, tone: .success)
        } catch {
            setStatus(error.localizedDescription, tone: .failure)
        }
    }

    func refreshLaunchAtLoginStatus(initialLoad: Bool = false) {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = (status == .enabled)
        let tone: StatusTone

        switch status {
        case .enabled:
            launchAtLoginStatusMessage = "RightClick AI will start automatically when you log in."
            tone = .success
        case .notRegistered:
            launchAtLoginStatusMessage = "RightClick AI will stay off until you launch it manually."
            tone = .neutral
        case .requiresApproval:
            launchAtLoginStatusMessage = "macOS still requires approval in System Settings > General > Login Items."
            tone = .warning
        case .notFound:
            launchAtLoginStatusMessage = "Launch at login is unavailable from this app bundle."
            tone = .failure
        @unknown default:
            launchAtLoginStatusMessage = "Launch at login status is unavailable right now."
            tone = .warning
        }

        launchAtLoginStatusTone = tone

        if !initialLoad {
            setSettingsStatus(launchAtLoginStatusMessage, tone: tone)
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            refreshLaunchAtLoginStatus(initialLoad: true)
            setSettingsStatus("Could not update launch at login: \(error.localizedDescription)", tone: .failure)
            return
        }

        refreshLaunchAtLoginStatus(initialLoad: true)

        if enabled, !launchAtLoginEnabled {
            setSettingsStatus("RightClick AI asked macOS to launch it at login, but approval is still required.", tone: .warning)
        } else if enabled {
            setSettingsStatus("RightClick AI will now launch automatically when you log in.", tone: .success)
        } else {
            setSettingsStatus("RightClick AI will no longer launch automatically when you log in.", tone: .success)
        }
    }

    private func configureClipboardBindings() {
        clipboardManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        clipboardManager.$items
            .sink { [weak self] _ in
                self?.reconcileClipboardSelection()
            }
            .store(in: &cancellables)
    }

    private func routeClipboardItemToReview(
        itemID: ClipboardItem.ID,
        actionID: String? = nil,
        prepareAfterRouting: Bool = false
    ) {
        guard let item = clipboardManager.item(withID: itemID) else {
            setStatus("The clipboard item no longer exists.", tone: .warning)
            return
        }

        guard let text = item.restorableText, ClipboardTextNormalization.hasMeaningfulContent(text) else {
            setStatus("That clipboard item does not contain usable text yet.", tone: .warning)
            return
        }

        selectedText = text
        launchSource = "Clipboard History"
        userInstruction = ""
        preview = nil

        if let actionID, availableActions.contains(where: { $0.id == actionID }) {
            selectedActionID = actionID
        }

        activeWorkspaceMode = .selection
        setStatus("Loaded \(item.kind.displayName.lowercased()) content from clipboard history.", tone: .success)

        if prepareAfterRouting {
            preparePreview()
        }
    }

    private func setStatus(_ message: String, tone: StatusTone = .neutral) {
        statusMessage = message
        statusTone = tone
    }

    private func setSettingsStatus(_ message: String, tone: StatusTone = .neutral) {
        settingsStatusMessage = message
        settingsStatusTone = tone
    }

    private func openPaperKnowledgeBaseDirectory(at path: String, missingMessage: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            setSettingsStatus(missingMessage, tone: .failure)
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func reconcileClipboardSelection() {
        let visibleItemIDs = Set(filteredClipboardItems.map(\.id))
        var reconciledSelection = selectedClipboardItemIDs.intersection(visibleItemIDs)
        if reconciledSelection.isEmpty, let firstVisibleItem = filteredClipboardItems.first {
            reconciledSelection = [firstVisibleItem.id]
        }

        if reconciledSelection != selectedClipboardItemIDs {
            selectedClipboardItemIDs = reconciledSelection
        }
    }

    private func loadActions() throws -> [ActionDescriptor] {
        let actions = try runtimeBridge.availableActions(configuration: runtimeConfiguration)
        availableActions = actions

        if actions.contains(where: { $0.id == selectedActionID }) {
            return actions
        }

        selectedActionID = actions.first?.id ?? ""
        return actions
    }

    private static func initialRuntimeRootPath() -> String {
        if let savedPath = UserDefaults.standard.string(forKey: runtimeRootDefaultsKey) {
            return savedPath
        }

        let fileManager = FileManager.default
        let preferredPath = (defaultRuntimeRootPath as NSString).expandingTildeInPath
        if fileManager.fileExists(atPath: preferredPath) {
            return defaultRuntimeRootPath
        }

        let legacyPath = (legacyRuntimeRootPath as NSString).expandingTildeInPath
        if fileManager.fileExists(atPath: legacyPath) {
            return legacyRuntimeRootPath
        }

        return defaultRuntimeRootPath
    }

    private static func initialPaperKnowledgeBaseRootPath() -> String {
        let fileManager = FileManager.default
        if let savedPath = UserDefaults.standard.string(forKey: paperKnowledgeBaseRootDefaultsKey),
           fileManager.fileExists(atPath: (savedPath as NSString).expandingTildeInPath) {
            return savedPath
        }

        if let environmentPath = ProcessInfo.processInfo.environment["MY_KNOWLEDGE_BASE_ROOT"],
           fileManager.fileExists(atPath: (environmentPath as NSString).expandingTildeInPath) {
            return environmentPath
        }

        for candidate in [
            defaultPaperKnowledgeBaseRootPath,
            legacyVolumePaperKnowledgeBaseRootPath,
            legacyPaperKnowledgeBaseRootPath,
            "~/local_projects/my-knowledge-base",
        ] {
            if fileManager.fileExists(atPath: (candidate as NSString).expandingTildeInPath) {
                return candidate
            }
        }

        return defaultPaperKnowledgeBaseRootPath
    }

    private static func initialWorkspaceMode() -> WorkspaceMode {
        guard let storedValue = UserDefaults.standard.string(forKey: workspaceModeDefaultsKey) else {
            return .selection
        }

        return WorkspaceMode(rawValue: storedValue) ?? .selection
    }

    private static func initialClipboardHotkeyEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: clipboardHotkeyEnabledDefaultsKey) == nil {
            return true
        }

        return UserDefaults.standard.bool(forKey: clipboardHotkeyEnabledDefaultsKey)
    }
}
