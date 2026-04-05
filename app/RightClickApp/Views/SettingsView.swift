import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            Form {
                Section {
                    Text("Configure your provider once, then keep RightClick AI running quietly in the menu bar.")
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Save Settings") {
                            model.saveRuntimeSettings()
                        }

                        Button("Reload From Disk") {
                            model.reloadRuntimeSettings()
                        }

                        Button("Open Actions Folder") {
                            model.openActionsDirectory()
                        }

                        Spacer()
                    }

                    StatusBanner(message: model.settingsStatusMessage, tone: model.settingsStatusTone)
                }

                Section("Provider") {
                    Picker("Active Provider", selection: $model.runtimeSettings.provider) {
                        ForEach(RuntimeProviderOption.all) { provider in
                            Text(provider.title).tag(provider.id)
                        }
                    }

                    Text("New action runs will use \(model.selectedProviderTitle).")
                        .foregroundStyle(.secondary)

                    activeProviderFields
                }

                Section("Runtime Defaults") {
                    TextField("Request Timeout (seconds)", text: $model.runtimeSettings.requestTimeoutSeconds)
                        .textFieldStyle(.roundedBorder)
                    TextField("Calendar Name", text: $model.runtimeSettings.calendarName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Timezone", text: $model.runtimeSettings.timezone)
                        .textFieldStyle(.roundedBorder)
                    TextField("Default Event Duration (minutes)", text: $model.runtimeSettings.defaultEventDurationMinutes)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Notifications") {
                    Toggle("Notify on success", isOn: $model.runtimeSettings.notifyOnSuccess)
                    Toggle("Notify on failure", isOn: $model.runtimeSettings.notifyOnFailure)

                    HStack {
                        Button("Use Recommended Defaults") {
                            model.applyRecommendedNotificationDefaults()
                        }

                        Spacer()
                    }

                    Text(model.notificationDefaultsSummary)
                        .foregroundStyle(.secondary)

                    Text("Direct Services now default to visible feedback on both success and failure so text actions do not feel silent the first time you use them.")
                        .foregroundStyle(.secondary)
                }

                Section("Clipboard") {
                    Toggle(
                        "Enable clipboard history hotkey (\(model.clipboardHotkeyShortcutLabel))",
                        isOn: Binding(
                            get: { model.clipboardHotkeyEnabled },
                            set: { model.setClipboardHotkeyEnabled($0) }
                        )
                    )

                    HStack {
                        Button(model.clipboardManager.isPaused ? "Resume Clipboard Capture" : "Pause Clipboard Capture") {
                            model.toggleClipboardPause()
                        }

                        Button("Clear Last Clipboard Item") {
                            model.clearMostRecentClipboardItem()
                        }
                        .disabled(model.filteredClipboardItems.isEmpty)

                        Button("Open Clipboard History") {
                            (NSApp.delegate as? AppDelegate)?.showClipboardHistory(nil)
                        }

                        Spacer()
                    }

                    Text("Clipboard history stays local to this Mac. Known password-manager sources are excluded by default, temporary clipboard changes must stay stable briefly before capture, oversized images are skipped, and you can pause capture at any time from the menu bar or the hotkey window.")
                        .foregroundStyle(.secondary)
                }

                Section("Launch At Login") {
                    Toggle(
                        "Start RightClick AI automatically when I log in",
                        isOn: Binding(
                            get: { model.launchAtLoginEnabled },
                            set: { model.setLaunchAtLoginEnabled($0) }
                        )
                    )

                    HStack {
                        Button("Refresh Launch Status") {
                            model.refreshLaunchAtLoginStatus()
                        }

                        Spacer()
                    }

                    Text(model.launchAtLoginStatusMessage)
                        .foregroundStyle(.secondary)
                }

                Section("Installed Actions") {
                    ForEach(model.availableActions) { action in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.title)
                                .font(.headline)
                            Text(action.subtitle)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    Text("These actions are available in the RightClick AI window and as direct Services where the host app supports them.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    DisclosureGroup("Advanced") {
                        VStack(alignment: .leading, spacing: 16) {
                            TextField("Runtime Root", text: $model.runtimeRootPath)
                                .textFieldStyle(.roundedBorder)

                            HStack {
                                Button("Use Installed Default") {
                                    model.resetRuntimeRootPath()
                                }

                                Button("Reload Actions") {
                                    model.reloadActions()
                                }

                                Button("Open settings.env") {
                                    model.openRuntimeSettingsFile()
                                }

                                Button("Open Runtime Root") {
                                    model.openRuntimeRootDirectory()
                                }

                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                runtimePathRow(title: "Executable", value: model.runtimeExecutablePath)
                                runtimePathRow(title: "settings.env", value: model.runtimeSettingsPath)
                                runtimePathRow(title: "Actions", value: model.actionBundleLocation)
                                runtimePathRow(title: "Keychain Service", value: model.runtimeKeychainServiceName)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 680, height: 860)
    }

    @ViewBuilder
    private var activeProviderFields: some View {
        switch model.runtimeSettings.provider {
        case "openai_compatible":
            VStack(alignment: .leading, spacing: 10) {
                TextField("API URL", text: $model.runtimeSettings.openAIAPIURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $model.runtimeSettings.openAIAPIKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $model.runtimeSettings.openAIModel)
                    .textFieldStyle(.roundedBorder)
                TextField("Auth Header", text: $model.runtimeSettings.openAIAuthHeader)
                    .textFieldStyle(.roundedBorder)
                TextField("Auth Scheme", text: $model.runtimeSettings.openAIAuthScheme)
                    .textFieldStyle(.roundedBorder)
            }
        case "anthropic":
            VStack(alignment: .leading, spacing: 10) {
                TextField("API URL", text: $model.runtimeSettings.anthropicAPIURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $model.runtimeSettings.anthropicAPIKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $model.runtimeSettings.anthropicModel)
                    .textFieldStyle(.roundedBorder)
                TextField("API Version", text: $model.runtimeSettings.anthropicVersion)
                    .textFieldStyle(.roundedBorder)
            }
        case "gemini":
            VStack(alignment: .leading, spacing: 10) {
                TextField("API URL", text: $model.runtimeSettings.geminiAPIURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $model.runtimeSettings.geminiAPIKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $model.runtimeSettings.geminiModel)
                    .textFieldStyle(.roundedBorder)
            }
        case "custom_command":
            VStack(alignment: .leading, spacing: 10) {
                TextField("Shell Command", text: $model.runtimeSettings.customProviderCommand, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                Text("The custom command receives the rendered prompt on stdin and must print plain text or normalized JSON to stdout.")
                    .foregroundStyle(.secondary)
            }
        default:
            Text("Mock mode is available for development-only testing.")
                .foregroundStyle(.secondary)
        }
    }

    private func runtimePathRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}
