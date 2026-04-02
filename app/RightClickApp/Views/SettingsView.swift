import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            Form {
                Section("Runtime Root") {
                    TextField("Runtime Root", text: $model.runtimeRootPath)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Save Settings") {
                            model.saveRuntimeSettings()
                        }

                        Button("Reload From Disk") {
                            model.reloadRuntimeSettings()
                        }

                        Button("Reload Actions") {
                            model.reloadActions()
                        }

                        Button("Use Installed Default") {
                            model.resetRuntimeRootPath()
                        }

                        Button("Open settings.env") {
                            model.openRuntimeSettingsFile()
                        }

                        Button("Open Runtime Root") {
                            model.openRuntimeRootDirectory()
                        }

                        Button("Open Actions Folder") {
                            model.openActionsDirectory()
                        }
                    }
                }

                Section("Provider Center") {
                    Picker("Active Provider", selection: $model.runtimeSettings.provider) {
                        ForEach(RuntimeProviderOption.all) { provider in
                            Text(provider.title).tag(provider.id)
                        }
                    }

                    Text("New action runs will use \(RuntimeProviderOption.title(for: model.runtimeSettings.provider)).")
                        .foregroundStyle(.secondary)

                    TextField("Request Timeout (seconds)", text: $model.runtimeSettings.requestTimeoutSeconds)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Runtime Defaults") {
                    TextField("Calendar Name", text: $model.runtimeSettings.calendarName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Timezone", text: $model.runtimeSettings.timezone)
                        .textFieldStyle(.roundedBorder)
                    TextField("Default Event Duration (minutes)", text: $model.runtimeSettings.defaultEventDurationMinutes)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Notify on success", isOn: $model.runtimeSettings.notifyOnSuccess)
                    Toggle("Notify on failure", isOn: $model.runtimeSettings.notifyOnFailure)
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

                Section("OpenAI-Compatible") {
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

                Section("Anthropic") {
                    TextField("API URL", text: $model.runtimeSettings.anthropicAPIURL)
                        .textFieldStyle(.roundedBorder)
                    SecureField("API Key", text: $model.runtimeSettings.anthropicAPIKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $model.runtimeSettings.anthropicModel)
                        .textFieldStyle(.roundedBorder)
                    TextField("API Version", text: $model.runtimeSettings.anthropicVersion)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Gemini") {
                    TextField("API URL", text: $model.runtimeSettings.geminiAPIURL)
                        .textFieldStyle(.roundedBorder)
                    SecureField("API Key", text: $model.runtimeSettings.geminiAPIKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $model.runtimeSettings.geminiModel)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Custom Provider") {
                    TextField("Shell Command", text: $model.runtimeSettings.customProviderCommand, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)

                    Text("The custom command receives the rendered prompt on stdin and must print plain text or normalized JSON to stdout.")
                        .foregroundStyle(.secondary)
                }

                Section("Resolved Paths") {
                    runtimePathRow(title: "Executable", value: model.runtimeExecutablePath)
                    runtimePathRow(title: "settings.env", value: model.runtimeSettingsPath)
                    runtimePathRow(title: "Actions", value: model.actionBundleLocation)
                    runtimePathRow(title: "Keychain Service", value: model.runtimeKeychainServiceName)
                }

                Section("Status") {
                    Text(model.settingsStatusMessage)
                        .foregroundStyle(.secondary)
                    Text(model.statusMessage)
                        .foregroundStyle(.secondary)
                }

                Section("Notes") {
                    Text("Provider API keys are stored in the macOS Keychain when you save from this window. `settings.env` keeps the non-secret runtime configuration only.")
                        .foregroundStyle(.secondary)
                    Text("After setup, the app can stay in the background. Use the RightClick AI menu bar item or the selected-text service when you need it.")
                        .foregroundStyle(.secondary)
                    Text("Built-in and custom actions stay file-based. Open the actions folder here, then use Codex, Cursor, or direct edits to change prompts and handlers.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .frame(width: 640, height: 860)
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
