import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    private let settingsLabelWidth: CGFloat = 190

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                settingsHeaderCard
                generalCard
                providerCard
                actionDefaultsCard
                installedActionsCard
                storageCard
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: 720, height: 820)
    }

    private var settingsHeaderCard: some View {
        SettingsCard(
            title: "RightClick AI Settings",
            subtitle: "Set up your provider once, then let RightClick AI stay in the background as a Mac utility."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                settingsActionRow {
                    Button("Save Settings") {
                        model.saveRuntimeSettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reload From Disk") {
                        model.reloadRuntimeSettings()
                    }
                    .buttonStyle(.bordered)
                }

                StatusBanner(message: model.settingsStatusMessage, tone: model.settingsStatusTone)
            }
        }
    }

    private var generalCard: some View {
        SettingsCard(
            title: "General",
            subtitle: "Startup, clipboard, and notification behavior."
        ) {
            SettingsStack {
                settingsRow(
                    "Launch At Login",
                    detail: "Start RightClick AI automatically after you sign in to macOS."
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(
                            "Start RightClick AI automatically after login",
                            isOn: Binding(
                                get: { model.launchAtLoginEnabled },
                                set: { model.setLaunchAtLoginEnabled($0) }
                            )
                        )

                        settingsActionRow {
                            Button("Refresh Startup Status") {
                                model.refreshLaunchAtLoginStatus()
                            }
                            .buttonStyle(.bordered)
                        }

                        StatusBanner(message: model.launchAtLoginStatusMessage, tone: model.launchAtLoginStatusTone)
                    }
                }

                Divider()

                settingsRow(
                    "Clipboard History",
                    detail: "Keep a local history of copied items and open it with \(model.clipboardHotkeyShortcutLabel)."
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(
                            "Enable clipboard history hotkey",
                            isOn: Binding(
                                get: { model.clipboardHotkeyEnabled },
                                set: { model.setClipboardHotkeyEnabled($0) }
                            )
                        )

                        settingsActionRow {
                            Button("Open Clipboard History") {
                                (NSApp.delegate as? AppDelegate)?.showClipboardHistory(nil)
                            }
                            .buttonStyle(.bordered)

                            Button(model.clipboardManager.isPaused ? "Resume Clipboard Capture" : "Pause Clipboard Capture") {
                                model.toggleClipboardPause()
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Clipboard history stays local to this Mac. Known password-manager sources are excluded by default, likely secrets are skipped, and short-lived clipboard changes must stay stable briefly before capture.")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                settingsRow(
                    "Notifications",
                    detail: "Use lightweight confirmations when actions finish."
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Notify on success", isOn: $model.runtimeSettings.notifyOnSuccess)
                        Toggle("Notify on failure", isOn: $model.runtimeSettings.notifyOnFailure)

                        settingsActionRow {
                            Button("Use Recommended Defaults") {
                                model.applyRecommendedNotificationDefaults()
                            }
                            .buttonStyle(.bordered)
                        }

                        Text(model.notificationDefaultsSummary)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var providerCard: some View {
        SettingsCard(
            title: "Provider",
            subtitle: "New actions will use \(model.selectedProviderTitle)."
        ) {
            SettingsStack {
                settingsRow("Active Provider", detail: "Choose the default model backend for new runs.") {
                    Picker("", selection: $model.runtimeSettings.provider) {
                        ForEach(RuntimeProviderOption.all) { provider in
                            Text(provider.title).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                activeProviderFields
            }
        }
    }

    private var actionDefaultsCard: some View {
        SettingsCard(
            title: "Action Defaults",
            subtitle: "These defaults affect slower providers, relative dates, and calendar extraction when the selected text is incomplete."
        ) {
            SettingsStack {
                settingsRow("Calendar Name", detail: "Optional target calendar for event creation.") {
                    TextField("Optional target calendar", text: $model.runtimeSettings.calendarName)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("Timezone", detail: "Used for relative dates like “tomorrow at 2pm.”") {
                    Picker("", selection: $model.runtimeSettings.timezone) {
                        ForEach(timeZoneOptions) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320, alignment: .leading)
                }

                Divider()

                settingsRow("Default Event Duration", detail: "Used when the source text does not include an end time.") {
                    TextField("60", text: $model.runtimeSettings.defaultEventDurationMinutes)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)
                }

                Divider()

                settingsRow("Request Timeout", detail: "Allow slower providers more time before the request fails.") {
                    TextField("120", text: $model.runtimeSettings.requestTimeoutSeconds)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)
                }
            }
        }
    }

    private var installedActionsCard: some View {
        SettingsCard(
            title: "Installed Actions",
            subtitle: "These actions appear in the RightClick AI window and, where supported, as direct Services from the text selection menu."
        ) {
            SettingsStack {
                if !model.coreActions.isEmpty {
                    settingsRow(ActionTier.core.sectionTitle, detail: "Primary everyday actions.") {
                        tokenRow(for: model.coreActions)
                    }
                }

                if !model.utilityActions.isEmpty {
                    Divider()

                    settingsRow(ActionTier.utility.sectionTitle, detail: "Secondary utilities and extractors.") {
                        tokenRow(for: model.utilityActions)
                    }
                }

                Divider()

                settingsRow("Manage", detail: "Open the installed action bundles in Finder.") {
                    settingsActionRow {
                        Button("Open Actions Folder") {
                            model.openActionsDirectory()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var storageCard: some View {
        SettingsCard(
            title: "Storage",
            subtitle: "RightClick AI keeps its runtime files in Application Support, not inside the app bundle. That keeps settings, actions, and clipboard history persistent across app updates."
        ) {
            SettingsStack {
                settingsRow("Runtime Storage", detail: "Persistent app state belongs in Application Support, not inside the app bundle.") {
                    runtimePathValue(model.runtimeConfiguration.expandedRuntimeRootPath)
                }

                Divider()

                settingsRow("settings.env", detail: "Provider defaults and non-secret runtime settings.") {
                    runtimePathValue(model.runtimeSettingsPath)
                }

                Divider()

                settingsRow("Actions", detail: "Installed action bundles that drive Services and review-mode actions.") {
                    runtimePathValue(model.actionBundleLocation)
                }

                Divider()

                settingsRow("Quick Access", detail: "Open the installed runtime folders in Finder.") {
                    VStack(alignment: .leading, spacing: 12) {
                        settingsActionRow {
                            Button("Open Runtime Folder") {
                                model.openRuntimeRootDirectory()
                            }
                            .buttonStyle(.bordered)

                            Button("Open settings.env") {
                                model.openRuntimeSettingsFile()
                            }
                            .buttonStyle(.bordered)

                            Button("Open Actions Folder") {
                                model.openActionsDirectory()
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Cache would be the wrong place for this data because macOS may purge it.")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                settingsRow("Developer Override", detail: "Only change this when developing against a different checked-out runtime.") {
                    DisclosureGroup("Show Developer Override") {
                        VStack(alignment: .leading, spacing: 14) {
                            settingsInlineField("Runtime Root Override") {
                            TextField("Override runtime root", text: $model.runtimeRootPath)
                                .textFieldStyle(.roundedBorder)
                            }

                            settingsActionRow {
                                Button("Use Installed Default") {
                                    model.resetRuntimeRootPath()
                                }
                                .buttonStyle(.bordered)

                                Button("Reload Actions") {
                                    model.reloadActions()
                                }
                                .buttonStyle(.bordered)
                            }

                            settingsInlineField("Executable") {
                                runtimePathValue(model.runtimeExecutablePath)
                            }

                            settingsInlineField("Keychain Service") {
                                runtimePathValue(model.runtimeKeychainServiceName)
                            }

                            Text("Normal installs should leave this on the Application Support location above.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var activeProviderFields: some View {
        switch model.runtimeSettings.provider {
        case "openai_compatible":
            Group {
                Divider()

                settingsRow("API URL", detail: "The OpenAI-compatible chat completion endpoint.") {
                    TextField("https://api.openai.com/v1/chat/completions", text: $model.runtimeSettings.openAIAPIURL)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("API Key", detail: "Stored in Keychain when you save settings.") {
                    SecureField("Required", text: $model.runtimeSettings.openAIAPIKey)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("Model", detail: "Examples: gpt-4.1-mini, kimi-k2.5, local models.") {
                    TextField("gpt-4.1-mini", text: $model.runtimeSettings.openAIModel)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("Advanced", detail: "Only change these if your provider expects non-default headers.") {
                    DisclosureGroup("Show Advanced Provider Fields") {
                        VStack(alignment: .leading, spacing: 14) {
                            settingsInlineField("Auth Header") {
                            TextField("Authorization", text: $model.runtimeSettings.openAIAuthHeader)
                                .textFieldStyle(.roundedBorder)
                            }

                            settingsInlineField("Auth Scheme") {
                                TextField("Bearer", text: $model.runtimeSettings.openAIAuthScheme)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
        case "anthropic":
            Group {
                Divider()

                settingsRow("API URL", detail: "Anthropic Messages API endpoint.") {
                    TextField("https://api.anthropic.com/v1/messages", text: $model.runtimeSettings.anthropicAPIURL)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("API Key", detail: "Stored in Keychain when you save settings.") {
                    SecureField("Required", text: $model.runtimeSettings.anthropicAPIKey)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("Model", detail: "Example: claude-sonnet-4-20250514.") {
                    TextField("claude-sonnet-4-20250514", text: $model.runtimeSettings.anthropicModel)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("Advanced", detail: "Only change this if your endpoint requires a different version header.") {
                    DisclosureGroup("Show Advanced Provider Fields") {
                        VStack(alignment: .leading, spacing: 14) {
                            settingsInlineField("API Version") {
                            TextField("2023-06-01", text: $model.runtimeSettings.anthropicVersion)
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
        case "gemini":
            Group {
                Divider()

                settingsRow("API URL", detail: "Gemini model endpoint base URL.") {
                    TextField("https://generativelanguage.googleapis.com/v1beta/models", text: $model.runtimeSettings.geminiAPIURL)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("API Key", detail: "Stored in Keychain when you save settings.") {
                    SecureField("Required", text: $model.runtimeSettings.geminiAPIKey)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                settingsRow("Model", detail: "Example: gemini-2.5-flash.") {
                    TextField("gemini-2.5-flash", text: $model.runtimeSettings.geminiModel)
                        .textFieldStyle(.roundedBorder)
                }
            }
        case "custom_command":
            Group {
                Divider()

                settingsRow("Shell Command", detail: "The command receives the rendered prompt on stdin and must print plain text or normalized JSON to stdout.") {
                    TextField("Path to your command", text: $model.runtimeSettings.customProviderCommand, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
            }
        default:
            Group {
                Divider()

                settingsRow("Mock Provider", detail: "Available for development-only testing.") {
                    Text("No extra configuration is required.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var timeZoneOptions: [TimeZoneOption] {
        var identifiers: [String] = [
            model.runtimeSettings.timezone,
            TimeZone.current.identifier,
            "UTC"
        ]
        identifiers.append(contentsOf: TimeZone.knownTimeZoneIdentifiers.sorted())

        var seen = Set<String>()
        return identifiers.compactMap { identifier in
            guard !identifier.isEmpty else {
                return nil
            }
            guard seen.insert(identifier).inserted else {
                return nil
            }

            return TimeZoneOption(
                id: identifier,
                label: timeZoneLabel(for: identifier)
            )
        }
    }

    private func timeZoneLabel(for identifier: String) -> String {
        guard let timeZone = TimeZone(identifier: identifier) else {
            return identifier
        }

        let seconds = timeZone.secondsFromGMT(for: Date())
        let hours = seconds / 3600
        let minutes = abs(seconds % 3600) / 60
        return "\(identifier) (UTC\(hours >= 0 ? "+" : "")\(hours):\(String(format: "%02d", minutes)))"
    }

    private func settingsRow<Content: View>(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: settingsLabelWidth, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsInlineField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tokenRow(for actions: [ActionDescriptor]) -> some View {
        SettingsFlowLayout(spacing: 8) {
            ForEach(actions) { action in
                SettingsToken(title: action.title)
            }
        }
    }

    @ViewBuilder
    private func settingsActionRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            content()
            Spacer(minLength: 0)
        }
    }

    private func runtimePathValue(_ value: String) -> some View {
        Text(value)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TimeZoneOption: Identifiable, Hashable {
    let id: String
    let label: String
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SettingsStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
    }
}

private struct SettingsFlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsToken: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(Capsule())
    }
}
