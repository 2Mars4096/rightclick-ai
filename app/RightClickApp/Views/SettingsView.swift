import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            Form {
                Section {
                    Text("Set up your provider once, then let RightClick AI stay in the background as a Mac utility.")
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Save Settings") {
                            model.saveRuntimeSettings()
                        }

                        Button("Reload From Disk") {
                            model.reloadRuntimeSettings()
                        }

                        Spacer()
                    }

                    StatusBanner(message: model.settingsStatusMessage, tone: model.settingsStatusTone)
                }

                Section("General") {
                    Toggle(
                        "Start RightClick AI automatically after login",
                        isOn: Binding(
                            get: { model.launchAtLoginEnabled },
                            set: { model.setLaunchAtLoginEnabled($0) }
                        )
                    )

                    Text("This is the normal macOS startup behavior for menu bar apps. The app launches after you sign in, not before the login screen.")
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Refresh Startup Status") {
                            model.refreshLaunchAtLoginStatus()
                        }

                        Spacer()
                    }

                    StatusBanner(message: model.launchAtLoginStatusMessage, tone: model.launchAtLoginStatusTone)

                    Divider()

                    Toggle(
                        "Enable clipboard history hotkey (\(model.clipboardHotkeyShortcutLabel))",
                        isOn: Binding(
                            get: { model.clipboardHotkeyEnabled },
                            set: { model.setClipboardHotkeyEnabled($0) }
                        )
                    )

                    HStack {
                        Button("Open Clipboard History") {
                            (NSApp.delegate as? AppDelegate)?.showClipboardHistory(nil)
                        }

                        Button(model.clipboardManager.isPaused ? "Resume Clipboard Capture" : "Pause Clipboard Capture") {
                            model.toggleClipboardPause()
                        }

                        Spacer()
                    }

                    Text("Clipboard history stays local to this Mac. Known password-manager sources are excluded by default, likely secrets are skipped, temporary clipboard changes must stay stable briefly before capture, and you can pause capture any time.")
                        .foregroundStyle(.secondary)

                    DisclosureGroup("Notifications") {
                        VStack(alignment: .leading, spacing: 12) {
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
                        }
                        .padding(.top, 8)
                    }
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

                Section {
                    DisclosureGroup("Action Defaults") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Calendar Name", text: $model.runtimeSettings.calendarName)
                                .textFieldStyle(.roundedBorder)
                            TextField("Timezone", text: $model.runtimeSettings.timezone)
                                .textFieldStyle(.roundedBorder)
                            TextField("Default Event Duration (minutes)", text: $model.runtimeSettings.defaultEventDurationMinutes)
                                .textFieldStyle(.roundedBorder)
                            TextField("Request Timeout (seconds)", text: $model.runtimeSettings.requestTimeoutSeconds)
                                .textFieldStyle(.roundedBorder)

                            Text("These defaults affect slower providers, relative dates, and calendar extraction when the selected text is incomplete.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }

                Section {
                    DisclosureGroup("Installed Actions") {
                        VStack(alignment: .leading, spacing: 14) {
                            if !model.coreActions.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(ActionTier.core.sectionTitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(model.coreActions.map(\.title).joined(separator: "  ·  "))
                                }
                            }

                            if !model.utilityActions.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(ActionTier.utility.sectionTitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(model.utilityActions.map(\.title).joined(separator: "  ·  "))
                                }
                            }

                            HStack {
                                Button("Open Actions Folder") {
                                    model.openActionsDirectory()
                                }

                                Spacer()
                            }

                            Text("These actions appear in the RightClick AI window and, where supported, as direct Services from the text selection menu.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
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
        .frame(width: 680, height: 820)
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

                DisclosureGroup("Advanced Provider Fields") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Auth Header", text: $model.runtimeSettings.openAIAuthHeader)
                            .textFieldStyle(.roundedBorder)
                        TextField("Auth Scheme", text: $model.runtimeSettings.openAIAuthScheme)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 8)
                }
            }
        case "anthropic":
            VStack(alignment: .leading, spacing: 10) {
                TextField("API URL", text: $model.runtimeSettings.anthropicAPIURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $model.runtimeSettings.anthropicAPIKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $model.runtimeSettings.anthropicModel)
                    .textFieldStyle(.roundedBorder)

                DisclosureGroup("Advanced Provider Fields") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("API Version", text: $model.runtimeSettings.anthropicVersion)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 8)
                }
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
