import Foundation
import Security

protocol RuntimeBridge {
    func availableActions(configuration: RuntimeConfiguration) throws -> [ActionDescriptor]
    func preparePreview(for request: RuntimeRequest, configuration: RuntimeConfiguration) throws -> RuntimePreview
    func performAction(for request: RuntimeRequest, configuration: RuntimeConfiguration) throws
}

struct RuntimeConfiguration {
    let runtimeRootPath: String

    var expandedRuntimeRootPath: String {
        (runtimeRootPath as NSString).expandingTildeInPath
    }

    var runtimeExecutablePath: String {
        expandedRuntimeRootPath + "/bin/right-click-action"
    }

    var settingsFilePath: String {
        expandedRuntimeRootPath + "/settings.env"
    }

    var actionsDirectoryPath: String {
        expandedRuntimeRootPath + "/actions"
    }

    var keychainServiceName: String {
        RuntimeKeychainStore.serviceName(for: expandedRuntimeRootPath)
    }
}

struct RuntimeProviderOption: Identifiable, Hashable {
    let id: String
    let title: String

    static let all: [RuntimeProviderOption] = [
        RuntimeProviderOption(id: "openai_compatible", title: "OpenAI-Compatible"),
        RuntimeProviderOption(id: "anthropic", title: "Anthropic"),
        RuntimeProviderOption(id: "gemini", title: "Gemini"),
        RuntimeProviderOption(id: "custom_command", title: "Custom Command"),
        RuntimeProviderOption(id: "mock", title: "Mock")
    ]

    static func title(for identifier: String) -> String {
        all.first(where: { $0.id == identifier })?.title ?? identifier
    }
}

enum RuntimeSettingsError: LocalizedError {
    case missingSettings(String)
    case unreadableSettings(String)

    var errorDescription: String? {
        switch self {
        case let .missingSettings(path):
            return "No settings.env was found at \(path). Save from Settings to create one."
        case let .unreadableSettings(path):
            return "The runtime settings at \(path) could not be read as UTF-8 text."
        }
    }
}

enum RuntimeKeychainError: LocalizedError {
    case unexpectedStatus(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(operation, status):
            return "\(operation) failed with Keychain status \(status)."
        }
    }
}

struct RuntimeKeychainStore {
    let runtimeRootPath: String

    var serviceName: String {
        Self.serviceName(for: runtimeRootPath)
    }

    static func serviceName(for runtimeRootPath: String) -> String {
        "RightClickAI:\((runtimeRootPath as NSString).expandingTildeInPath)"
    }

    func readSecret(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw RuntimeKeychainError.unexpectedStatus("Reading \(account)", status)
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func writeSecret(_ secret: String, account: String) throws {
        let encodedSecret = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: encodedSecret
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw RuntimeKeychainError.unexpectedStatus("Updating \(account)", updateStatus)
        }

        var newItem = query
        newItem[kSecValueData as String] = encodedSecret
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw RuntimeKeychainError.unexpectedStatus("Writing \(account)", addStatus)
        }
    }

    func deleteSecret(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RuntimeKeychainError.unexpectedStatus("Deleting \(account)", status)
        }
    }
}

struct RuntimeSettingsDocument: Equatable {
    private static let openAISecretAccount = "OPENAI_API_KEY"
    private static let anthropicSecretAccount = "ANTHROPIC_API_KEY"
    private static let geminiSecretAccount = "GEMINI_API_KEY"

    var provider = "openai_compatible"
    var calendarName = ""
    var timezone = TimeZone.current.identifier
    var defaultEventDurationMinutes = "60"
    var requestTimeoutSeconds = "120"
    var notifyOnSuccess = true
    var notifyOnFailure = true

    var openAIAPIURL = "https://api.openai.com/v1/chat/completions"
    var openAIAPIKey = ""
    var openAIModel = "gpt-4.1-mini"
    var openAIAuthHeader = "Authorization"
    var openAIAuthScheme = "Bearer"

    var anthropicAPIURL = "https://api.anthropic.com/v1/messages"
    var anthropicAPIKey = ""
    var anthropicModel = "claude-sonnet-4-20250514"
    var anthropicVersion = "2023-06-01"

    var geminiAPIURL = "https://generativelanguage.googleapis.com/v1beta/models"
    var geminiAPIKey = ""
    var geminiModel = "gemini-2.5-flash"

    var customProviderCommand = ""
    var additionalEntries: [String: String] = [:]

    static func load(from path: String) throws -> RuntimeSettingsDocument {
        guard FileManager.default.fileExists(atPath: path) else {
            throw RuntimeSettingsError.missingSettings(path)
        }

        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw RuntimeSettingsError.unreadableSettings(path)
        }

        var document = RuntimeSettingsDocument()
        contents.enumerateLines { line, _ in
            guard let entry = parseAssignment(from: line) else {
                return
            }
            document.apply(value: entry.value, for: entry.key)
        }
        try document.loadSecrets(using: keychainStore(for: path))
        return document
    }

    func write(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try persistSecrets(using: Self.keychainStore(for: path))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try render().write(to: url, atomically: true, encoding: .utf8)
    }

    private mutating func apply(value: String, for key: String) {
        switch key {
        case "PROVIDER":
            provider = value
        case "CALENDAR_NAME":
            calendarName = value
        case "TIMEZONE":
            timezone = value
        case "DEFAULT_EVENT_DURATION_MINUTES":
            defaultEventDurationMinutes = value
        case "REQUEST_TIMEOUT_SECONDS":
            requestTimeoutSeconds = value
        case "NOTIFY_ON_SUCCESS":
            notifyOnSuccess = Self.parseBool(value)
        case "NOTIFY_ON_FAILURE":
            notifyOnFailure = Self.parseBool(value)
        case "OPENAI_API_URL":
            openAIAPIURL = value
        case "OPENAI_API_KEY":
            openAIAPIKey = value
        case "OPENAI_MODEL":
            openAIModel = value
        case "OPENAI_AUTH_HEADER":
            openAIAuthHeader = value
        case "OPENAI_AUTH_SCHEME":
            openAIAuthScheme = value
        case "ANTHROPIC_API_URL":
            anthropicAPIURL = value
        case "ANTHROPIC_API_KEY":
            anthropicAPIKey = value
        case "ANTHROPIC_MODEL":
            anthropicModel = value
        case "ANTHROPIC_VERSION":
            anthropicVersion = value
        case "GEMINI_API_URL":
            geminiAPIURL = value
        case "GEMINI_API_KEY":
            geminiAPIKey = value
        case "GEMINI_MODEL":
            geminiModel = value
        case "CUSTOM_PROVIDER_COMMAND":
            customProviderCommand = value
        default:
            additionalEntries[key] = value
        }
    }

    private func render() -> String {
        var lines: [String] = [
            "# Right Click AI settings",
            "# This file is sourced by the shared runtime.",
            "# Values stay shell-safe so the native app and CLI use the same config contract.",
            "",
            "PROVIDER=\(Self.quote(provider))",
            "CALENDAR_NAME=\(Self.quote(calendarName))",
            "TIMEZONE=\(Self.quote(timezone))",
            "DEFAULT_EVENT_DURATION_MINUTES=\(Self.quote(defaultEventDurationMinutes))",
            "REQUEST_TIMEOUT_SECONDS=\(Self.quote(requestTimeoutSeconds))",
            "NOTIFY_ON_SUCCESS=\(Self.quote(Self.boolString(notifyOnSuccess)))",
            "NOTIFY_ON_FAILURE=\(Self.quote(Self.boolString(notifyOnFailure)))",
            "",
            "# OpenAI-compatible providers",
            "# API keys are loaded from Keychain when the native app saves settings.",
            "OPENAI_API_URL=\(Self.quote(openAIAPIURL))",
            "OPENAI_API_KEY=\(Self.quote(""))",
            "OPENAI_MODEL=\(Self.quote(openAIModel))",
            "OPENAI_AUTH_HEADER=\(Self.quote(openAIAuthHeader))",
            "OPENAI_AUTH_SCHEME=\(Self.quote(openAIAuthScheme))",
            "",
            "# Anthropic",
            "ANTHROPIC_API_URL=\(Self.quote(anthropicAPIURL))",
            "ANTHROPIC_API_KEY=\(Self.quote(""))",
            "ANTHROPIC_MODEL=\(Self.quote(anthropicModel))",
            "ANTHROPIC_VERSION=\(Self.quote(anthropicVersion))",
            "",
            "# Gemini",
            "GEMINI_API_URL=\(Self.quote(geminiAPIURL))",
            "GEMINI_API_KEY=\(Self.quote(""))",
            "GEMINI_MODEL=\(Self.quote(geminiModel))",
            "",
            "# Custom provider",
            "# The command receives the rendered prompt on stdin and must print model output",
            "# or normalized JSON to stdout.",
            "CUSTOM_PROVIDER_COMMAND=\(Self.quote(customProviderCommand))"
        ]

        if !additionalEntries.isEmpty {
            lines.append("")
            lines.append("# Additional settings preserved by the native app")
            for key in additionalEntries.keys.sorted() {
                lines.append("\(key)=\(Self.quote(additionalEntries[key] ?? ""))")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private mutating func loadSecrets(using keychainStore: RuntimeKeychainStore) throws {
        openAIAPIKey = try keychainStore.readSecret(account: Self.openAISecretAccount) ?? openAIAPIKey
        anthropicAPIKey = try keychainStore.readSecret(account: Self.anthropicSecretAccount) ?? anthropicAPIKey
        geminiAPIKey = try keychainStore.readSecret(account: Self.geminiSecretAccount) ?? geminiAPIKey
    }

    private func persistSecrets(using keychainStore: RuntimeKeychainStore) throws {
        try syncSecret(openAIAPIKey, account: Self.openAISecretAccount, using: keychainStore)
        try syncSecret(anthropicAPIKey, account: Self.anthropicSecretAccount, using: keychainStore)
        try syncSecret(geminiAPIKey, account: Self.geminiSecretAccount, using: keychainStore)
    }

    private func syncSecret(_ value: String, account: String, using keychainStore: RuntimeKeychainStore) throws {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty {
            try keychainStore.deleteSecret(account: account)
        } else {
            try keychainStore.writeSecret(trimmedValue, account: account)
        }
    }

    private static func keychainStore(for settingsPath: String) -> RuntimeKeychainStore {
        RuntimeKeychainStore(
            runtimeRootPath: URL(fileURLWithPath: settingsPath).deletingLastPathComponent().path
        )
    }

    private static func parseAssignment(from line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equalsIndex = trimmed.firstIndex(of: "=") else {
            return nil
        }

        var key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        if key.hasPrefix("export ") {
            key = String(key.dropFirst("export ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            return nil
        }

        let rawValue = String(trimmed[trimmed.index(after: equalsIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key, parseShellValue(rawValue))
    }

    private static func parseShellValue(_ rawValue: String) -> String {
        guard !rawValue.isEmpty else {
            return ""
        }

        if rawValue.hasPrefix("'"), rawValue.hasSuffix("'"), rawValue.count >= 2 {
            let inner = String(rawValue.dropFirst().dropLast())
            return inner.replacingOccurrences(of: "'\\''", with: "'")
        }

        if rawValue.hasPrefix("\""), rawValue.hasSuffix("\""), rawValue.count >= 2 {
            let inner = String(rawValue.dropFirst().dropLast())
            return inner
                .replacingOccurrences(of: "\\\\", with: "\\")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\$", with: "$")
                .replacingOccurrences(of: "\\`", with: "`")
        }

        return rawValue
    }

    private static func parseBool(_ rawValue: String) -> Bool {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }

    private static func boolString(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum RuntimeBridgeError: LocalizedError {
    case missingRuntime(String)
    case invalidActionList
    case commandFailed(String)
    case emptyPreview(String)
    case invalidPreview(String)

    var errorDescription: String? {
        switch self {
        case let .missingRuntime(path):
            return "The runtime executable was not found at \(path). Install Right Click first or update the runtime path in Settings."
        case .invalidActionList:
            return "The runtime returned an unreadable action list."
        case let .commandFailed(message):
            return message
        case let .emptyPreview(actionTitle):
            return "\(actionTitle) returned an empty preview."
        case let .invalidPreview(actionTitle):
            return "\(actionTitle) returned preview data that the app could not interpret."
        }
    }
}

private struct CalendarPreviewEnvelope: Decodable {
    let reason: String
    let events: [CalendarPreviewEvent]
}

private struct CalendarPreviewEvent: Decodable {
    let title: String
    let start: String
    let end: String
    let allDay: Bool
    let location: String
    let notes: String
    let calendar: String
}

struct InstalledRuntimeBridge: RuntimeBridge {
    func availableActions(configuration: RuntimeConfiguration) throws -> [ActionDescriptor] {
        let output = try runCommand(
            executablePath: configuration.runtimeExecutablePath,
            arguments: ["--list-actions"],
            input: nil
        )
        let actions = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> ActionDescriptor? in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2 else {
                    return nil
                }
                return ActionDescriptor(
                    id: parts[0],
                    title: parts[1],
                    subtitle: subtitle(for: parts[0], title: parts[1])
                )
            }

        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }

        guard !actions.isEmpty else {
            throw RuntimeBridgeError.invalidActionList
        }

        return actions
    }

    func preparePreview(for request: RuntimeRequest, configuration: RuntimeConfiguration) throws -> RuntimePreview {
        var arguments = [request.actionID, "--dry-run"]
        if let instruction = request.userInstruction, !instruction.isEmpty {
            arguments.append(contentsOf: ["--instruction", instruction])
        }

        let output = try runCommand(
            executablePath: configuration.runtimeExecutablePath,
            arguments: arguments,
            input: request.selectedText
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !output.isEmpty else {
            throw RuntimeBridgeError.emptyPreview(request.actionTitle)
        }

        return RuntimePreview(
            title: "\(request.actionTitle) Preview",
            summary: previewSummary(for: request.actionID),
            proposedOutput: output,
            content: try previewContent(for: request, output: output)
        )
    }

    func performAction(for request: RuntimeRequest, configuration: RuntimeConfiguration) throws {
        var arguments = [request.actionID]
        if let instruction = request.userInstruction, !instruction.isEmpty {
            arguments.append(contentsOf: ["--instruction", instruction])
        }

        _ = try runCommand(
            executablePath: configuration.runtimeExecutablePath,
            arguments: arguments,
            input: request.selectedText
        )
    }

    private func subtitle(for actionID: String, title: String) -> String {
        switch actionID {
        case "draft-response":
            return "Draft a usable reply from the selected text through the shared runtime."
        case "polish-draft":
            return "Polish selected text while keeping the original intent before copying it back."
        case "explain":
            return "Explain the selected text in plain language through the shared runtime."
        case "summarize":
            return "Condense selected text through the shared runtime."
        case "rewrite-friendly":
            return "Rewrite selected text in a warmer tone before copying it back."
        case "extract-action-items":
            return "Turn selected text into a short checklist through the shared runtime."
        case "add-to-calendar":
            return "Preview extracted events before the calendar side effect runs."
        default:
            return "Loaded from the configured runtime: \(title)."
        }
    }

    private func previewSummary(for actionID: String) -> String {
        switch actionID {
        case "draft-response":
            return "Review the drafted reply before copying it to the clipboard."
        case "polish-draft":
            return "Review the polished rewrite before copying it to the clipboard."
        case "explain":
            return "Review the explanation before copying it to the clipboard."
        case "summarize":
            return "Loaded from the shared runtime with a non-destructive dry run."
        case "rewrite-friendly":
            return "Review the rewritten text before copying it back into the clipboard."
        case "extract-action-items":
            return "Review the extracted action list before copying it to the clipboard."
        case "add-to-calendar":
            return "Review the extracted event payload before applying the calendar side effect."
        default:
            return "Loaded from the shared runtime with a non-destructive dry run."
        }
    }

    private func previewContent(for request: RuntimeRequest, output: String) throws -> RuntimePreviewContent {
        switch request.actionID {
        case "rewrite-friendly", "polish-draft":
            return .rewriteDiff(original: request.selectedText, rewritten: output)
        case "add-to-calendar":
            return try buildCalendarPreview(from: output)
        default:
            return .text(output)
        }
    }

    private func buildCalendarPreview(from output: String) throws -> RuntimePreviewContent {
        guard let data = output.data(using: .utf8) else {
            throw RuntimeBridgeError.invalidPreview("Right Click Calendar")
        }

        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(CalendarPreviewEnvelope.self, from: data) else {
            throw RuntimeBridgeError.invalidPreview("Right Click Calendar")
        }

        let events = envelope.events.enumerated().map { index, event in
            RuntimeEventDraft(
                id: "\(index)-\(event.title)-\(event.start)",
                title: event.title,
                start: event.start,
                end: event.end,
                allDay: event.allDay,
                location: event.location,
                notes: event.notes,
                calendar: event.calendar
            )
        }

        return .eventDrafts(reason: envelope.reason, events: events)
    }

    private func runCommand(executablePath: String, arguments: [String], input: String?) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw RuntimeBridgeError.missingRuntime(executablePath)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        process.environment = environment

        if let input {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            try process.run()
            if let data = input.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            stdinPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = [stderr, stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "The runtime exited with status \(process.terminationStatus)."
            throw RuntimeBridgeError.commandFailed(message)
        }

        return stdout
    }
}
