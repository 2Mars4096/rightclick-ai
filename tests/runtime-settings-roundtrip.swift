import Foundation

struct ActionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String

    var displayOrder: Int {
        0
    }
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

@main
struct RuntimeSettingsRoundtrip {
    static func main() throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("right-click-runtime-settings-\(UUID().uuidString)", isDirectory: true)
        let settingsURL = temporaryDirectory.appendingPathComponent("settings.env")

        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        var document = RuntimeSettingsDocument()
        document.provider = "custom_command"
        document.calendarName = "Personal"
        document.timezone = "Asia/Hong_Kong"
        document.defaultEventDurationMinutes = "90"
        document.requestTimeoutSeconds = "120"
        document.notifyOnSuccess = false
        document.openAIAPIKey = "sk-test'quoted"
        document.customProviderCommand = "cat | sed 's/foo/bar/'"
        document.additionalEntries = [
            "EXTRA_FLAG": "enabled",
            "EXTRA_NOTE": "keep me"
        ]

        try document.write(to: settingsURL.path)
        let reloaded = try RuntimeSettingsDocument.load(from: settingsURL.path)
        guard reloaded == document else {
            fputs("Runtime settings roundtrip mismatch.\n", stderr)
            Foundation.exit(1)
        }
        let rendered = try String(contentsOf: settingsURL, encoding: .utf8)
        guard rendered.contains("PROVIDER='custom_command'") else {
            fputs("Missing provider line in rendered settings.\n", stderr)
            Foundation.exit(1)
        }
        guard rendered.contains("OPENAI_API_KEY='sk-test'") else {
            fputs("API key should be mirrored into settings.env for direct Services.\n", stderr)
            Foundation.exit(1)
        }
        let permissions = try fileManager.attributesOfItem(atPath: settingsURL.path)[.posixPermissions] as? NSNumber
        guard permissions?.intValue == 0o600 else {
            fputs("settings.env should be saved with 0600 permissions.\n", stderr)
            Foundation.exit(1)
        }
        guard rendered.contains("EXTRA_FLAG='enabled'") else {
            fputs("Additional entries were not preserved.\n", stderr)
            Foundation.exit(1)
        }

        print("Runtime settings roundtrip OK")
    }
}
