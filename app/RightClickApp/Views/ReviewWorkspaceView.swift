import AppKit
import SwiftUI

struct ReviewWorkspaceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            selectedTextPanel
            actionPanel
            reviewPanel
            statusPanel
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 520)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("RightClick AI")
                    .font(.title2.weight(.semibold))
                Text("Native selected-text host backed by the shared action runtime.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Settings") {
                (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
            }
        }
    }

    private var selectedTextPanel: some View {
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
                    Button("Use Clipboard") {
                        model.importClipboardText()
                    }

                    Text("Fallback path for apps where the Services menu is unavailable or unreliable.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionPanel: some View {
        GroupBox("Action Picker") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Action", selection: $model.selectedActionID) {
                    ForEach(model.availableActions) { action in
                        Text(action.title).tag(action.id)
                    }
                }

                Text(model.selectedAction?.subtitle ?? "Choose an action to prepare a placeholder review.")
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

                    Button("Reload Actions") {
                        model.reloadActions()
                    }

                    Button(model.applyButtonTitle) {
                        model.applyPreview()
                    }
                    .disabled(!model.canApplyPreview)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var reviewPanel: some View {
        GroupBox("Review Surface") {
            VStack(alignment: .leading, spacing: 10) {
                if let preview = model.preview {
                    Text(preview.title)
                        .font(.headline)

                    Text(preview.summary)
                        .foregroundStyle(.secondary)

                    Divider()

                    previewContent(preview)
                } else {
                    Text("Prepare a review to load a real runtime-backed preview.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var statusPanel: some View {
        GroupBox("Session State") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Source: \(model.launchSource)")
                Text("Runtime: \(model.runtimeExecutablePath)")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text(model.statusMessage)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
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
            .frame(minHeight: 140)
        case let .rewriteDiff(original, rewritten):
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Original") {
                    ScrollView {
                        Text(original)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 100)
                }

                GroupBox("Rewritten") {
                    ScrollView {
                        Text(rewritten)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 100)
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
                    .frame(minHeight: 140)
                }

                DisclosureGroup("Raw Runtime Output") {
                    Text(preview.proposedOutput)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
            }
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
}
