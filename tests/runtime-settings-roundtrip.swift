import Foundation

struct ActionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

struct RuntimeRequest {
    let selectedText: String
    let actionID: String
    let actionTitle: String
}

struct RuntimePreview: Equatable {
    let title: String
    let summary: String
    let proposedOutput: String
}

@main
struct RuntimeSettingsRoundtrip {
    static func main() throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("right-click-runtime-settings-\(UUID().uuidString)", isDirectory: true)
        let settingsURL = temporaryDirectory.appendingPathComponent("settings.env")
        let keychainStore = RuntimeKeychainStore(runtimeRootPath: temporaryDirectory.path)

        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? keychainStore.deleteSecret(account: "OPENAI_API_KEY")
            try? keychainStore.deleteSecret(account: "ANTHROPIC_API_KEY")
            try? keychainStore.deleteSecret(account: "GEMINI_API_KEY")
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
        guard rendered.contains("OPENAI_API_KEY=''") else {
            fputs("API key should not be written to settings.env.\n", stderr)
            Foundation.exit(1)
        }
        guard rendered.contains("EXTRA_FLAG='enabled'") else {
            fputs("Additional entries were not preserved.\n", stderr)
            Foundation.exit(1)
        }

        print("Runtime settings roundtrip OK")
    }
}
