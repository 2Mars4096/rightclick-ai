import AppKit
import Combine
import Foundation
import ServiceManagement

struct ActionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

struct RuntimeRequest {
    let selectedText: String
    let actionID: String
    let actionTitle: String
    let userInstruction: String?
}

struct RuntimeEventDraft: Identifiable, Equatable {
    let id: String
    let title: String
    let start: String
    let end: String
    let allDay: Bool
    let location: String
    let notes: String
    let calendar: String
}

enum RuntimePreviewContent: Equatable {
    case text(String)
    case rewriteDiff(original: String, rewritten: String)
    case eventDrafts(reason: String, events: [RuntimeEventDraft])
}

struct RuntimePreview: Equatable {
    let title: String
    let summary: String
    let proposedOutput: String
    let content: RuntimePreviewContent
}

@MainActor
final class AppModel: ObservableObject {
    private static let runtimeRootDefaultsKey = "rightClick.runtimeRootPath"
    static let defaultRuntimeRootPath = "~/Library/Application Support/RightClickAI"
    private static let legacyRuntimeRootPath = "~/Library/Application Support/RightClickCalendar"

    static let shared = AppModel(runtimeBridge: InstalledRuntimeBridge())

    @Published var selectedText = ""
    @Published var selectedActionID = ""
    @Published var userInstruction = ""
    @Published var availableActions: [ActionDescriptor]
    @Published var preview: RuntimePreview?
    @Published var statusMessage = "Use the RightClick AI service on selected text to start a run."
    @Published var launchSource = "Manual launch"
    @Published var runtimeSettings = RuntimeSettingsDocument()
    @Published var settingsStatusMessage = "Load or create a runtime settings file from the native Settings window."
    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginStatusMessage = "RightClick AI will not start automatically when you log in."
    @Published var runtimeRootPath: String {
        didSet {
            UserDefaults.standard.set(runtimeRootPath, forKey: Self.runtimeRootDefaultsKey)
        }
    }

    private let runtimeBridge: any RuntimeBridge

    init(runtimeBridge: any RuntimeBridge) {
        self.runtimeBridge = runtimeBridge
        runtimeRootPath = Self.initialRuntimeRootPath()
        availableActions = []
        reloadActions(initialLoad: true)
        reloadRuntimeSettings(initialLoad: true)
        refreshLaunchAtLoginStatus(initialLoad: true)
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
        preview != nil
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

    func acceptSelectedText(_ text: String, source: String) {
        selectedText = text
        userInstruction = ""
        launchSource = source
        preview = nil
        do {
            let actions = try loadActions()
            if actions.isEmpty {
                statusMessage = "Captured \(text.count) characters from \(source), but no installed actions were found."
            } else {
                statusMessage = "Captured \(text.count) characters from \(source). Ready to run \(actions.count) action(s)."
            }
        } catch {
            availableActions = []
            selectedActionID = ""
            statusMessage = error.localizedDescription
        }
    }

    func importClipboardText() {
        let clipboardText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !clipboardText.isEmpty else {
            statusMessage = "The clipboard does not contain plain text yet."
            return
        }

        acceptSelectedText(clipboardText, source: "Clipboard Fallback")
    }

    private var normalizedUserInstruction: String? {
        let trimmed = userInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func preparePreview() {
        let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            statusMessage = "No selected text has been captured yet."
            preview = nil
            return
        }

        guard let selectedAction else {
            statusMessage = "Choose an action before preparing review."
            preview = nil
            return
        }

        do {
            preview = try runtimeBridge.preparePreview(
                for: RuntimeRequest(
                    selectedText: trimmedText,
                    actionID: selectedAction.id,
                    actionTitle: selectedAction.title,
                    userInstruction: normalizedUserInstruction
                ),
                configuration: runtimeConfiguration
            )
            statusMessage = "Prepared a runtime-backed review for \(selectedAction.title)."
        } catch {
            preview = nil
            statusMessage = error.localizedDescription
        }
    }

    func applyPreview() {
        guard let selectedAction else {
            statusMessage = "Choose an action before applying."
            return
        }

        let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            statusMessage = "No selected text has been captured yet."
            return
        }

        guard let preview else {
            statusMessage = "Prepare a review before applying."
            return
        }

        if selectedAction.id == "add-to-calendar" {
            do {
                try runtimeBridge.performAction(
                    for: RuntimeRequest(
                        selectedText: trimmedText,
                        actionID: selectedAction.id,
                        actionTitle: selectedAction.title,
                        userInstruction: normalizedUserInstruction
                    ),
                    configuration: runtimeConfiguration
                )
                statusMessage = "Applied \(selectedAction.title) through the shared runtime."
            } catch {
                statusMessage = error.localizedDescription
            }
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(preview.proposedOutput, forType: .string)
        statusMessage = "Copied \(selectedAction.title) output to the clipboard."
    }

    func reloadActions(initialLoad: Bool = false) {
        do {
            let actions = try loadActions()
            if actions.isEmpty {
                statusMessage = "No installed actions were found at \(actionBundleLocation)."
            } else if initialLoad {
                statusMessage = "Loaded \(actions.count) action(s) from \(runtimeExecutablePath)."
            } else {
                statusMessage = "Reloaded \(actions.count) action(s) from \(runtimeExecutablePath)."
            }
        } catch {
            availableActions = []
            selectedActionID = ""
            preview = nil
            statusMessage = error.localizedDescription
        }
    }

    func resetRuntimeRootPath() {
        runtimeRootPath = Self.defaultRuntimeRootPath
        reloadActions()
        reloadRuntimeSettings()
    }

    func openRuntimeSettingsFile() {
        let url = URL(fileURLWithPath: runtimeSettingsPath)
        guard FileManager.default.fileExists(atPath: runtimeSettingsPath) else {
            statusMessage = "No runtime settings file exists at \(runtimeSettingsPath). Install the runtime first."
            return
        }

        NSWorkspace.shared.open(url)
    }

    func openRuntimeRootDirectory() {
        let path = (runtimeRootPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            statusMessage = "The runtime root does not exist yet at \(path). Install the runtime first."
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func openActionsDirectory() {
        let path = actionBundleLocation
        guard FileManager.default.fileExists(atPath: path) else {
            statusMessage = "The actions directory does not exist yet at \(path). Install the runtime first."
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func reloadRuntimeSettings(initialLoad: Bool = false) {
        do {
            runtimeSettings = try RuntimeSettingsDocument.load(from: runtimeSettingsPath)
            settingsStatusMessage = initialLoad
                ? "Loaded runtime settings from \(runtimeSettingsPath)."
                : "Reloaded runtime settings from \(runtimeSettingsPath)."
        } catch RuntimeSettingsError.missingSettings {
            runtimeSettings = RuntimeSettingsDocument()
            settingsStatusMessage = "No settings.env was found at \(runtimeSettingsPath). Save from this window to create one."
        } catch {
            settingsStatusMessage = error.localizedDescription
        }
    }

    func saveRuntimeSettings() {
        do {
            try runtimeSettings.write(to: runtimeSettingsPath)
            settingsStatusMessage = "Saved runtime settings to \(runtimeSettingsPath) and synced provider secrets to Keychain."
        } catch {
            settingsStatusMessage = error.localizedDescription
        }
    }

    func refreshLaunchAtLoginStatus(initialLoad: Bool = false) {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = (status == .enabled)

        switch status {
        case .enabled:
            launchAtLoginStatusMessage = "RightClick AI will start automatically when you log in."
        case .notRegistered:
            launchAtLoginStatusMessage = "RightClick AI will stay off until you launch it manually."
        case .requiresApproval:
            launchAtLoginStatusMessage = "macOS still requires approval in System Settings > General > Login Items."
        case .notFound:
            launchAtLoginStatusMessage = "Launch at login is unavailable from this app bundle."
        @unknown default:
            launchAtLoginStatusMessage = "Launch at login status is unavailable right now."
        }

        if !initialLoad {
            settingsStatusMessage = launchAtLoginStatusMessage
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
            settingsStatusMessage = "Could not update launch at login: \(error.localizedDescription)"
            return
        }

        refreshLaunchAtLoginStatus(initialLoad: true)

        if enabled, !launchAtLoginEnabled {
            settingsStatusMessage = "RightClick AI asked macOS to launch it at login, but approval is still required."
        } else if enabled {
            settingsStatusMessage = "RightClick AI will now launch automatically when you log in."
        } else {
            settingsStatusMessage = "RightClick AI will no longer launch automatically when you log in."
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
}
