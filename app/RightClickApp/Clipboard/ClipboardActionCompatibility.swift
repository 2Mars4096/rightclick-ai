import Foundation

struct ClipboardActionCompatibility: Codable, Hashable {
    enum Status: String, Codable, Hashable {
        case compatible
        case deferred
        case incompatible
    }

    let actionID: String
    let actionTitle: String
    let itemID: UUID
    let itemKind: ClipboardItemKind
    let status: Status
    let reason: String?

    var isCompatible: Bool {
        status == .compatible
    }

    var isDeferred: Bool {
        status == .deferred
    }

    static func evaluate(action: ActionDescriptor, item: ClipboardItem) -> ClipboardActionCompatibility {
        if item.kind.isDeferredNonText {
            return ClipboardActionCompatibility(
                actionID: action.id,
                actionTitle: action.title,
                itemID: item.id,
                itemKind: item.kind,
                status: .deferred,
                reason: item.kind.isDeferredVisual
                    ? "Visual clipboard items can already be previewed and restored, but AI actions are still text-only."
                    : "\(item.kind.displayName) clipboard items can already be previewed and restored, but AI actions are still text-only."
            )
        }

        guard let text = item.restorableText, ClipboardTextNormalization.hasMeaningfulContent(text) else {
            return ClipboardActionCompatibility(
                actionID: action.id,
                actionTitle: action.title,
                itemID: item.id,
                itemKind: item.kind,
                status: .incompatible,
                reason: "The clipboard item does not contain usable text."
            )
        }

        return ClipboardActionCompatibility(
            actionID: action.id,
            actionTitle: action.title,
            itemID: item.id,
            itemKind: item.kind,
            status: .compatible,
            reason: text.isEmpty ? "The clipboard item does not contain usable text." : nil
        )
    }

    static func evaluate(actionID: String, actionTitle: String, item: ClipboardItem) -> ClipboardActionCompatibility {
        evaluate(
            action: ActionDescriptor(id: actionID, title: actionTitle, subtitle: ""),
            item: item
        )
    }
}

struct ClipboardSelectionComposition: Hashable {
    let itemCount: Int
    let text: String
}

struct PaperKnowledgeBaseConfiguration: Hashable {
    let rootPath: String

    var normalizedRootPath: String {
        ClipboardTextNormalization.normalizeMetadata(rootPath) ?? ""
    }

    var expandedRootPath: String {
        (normalizedRootPath as NSString).expandingTildeInPath
    }

    var isConfigured: Bool {
        !normalizedRootPath.isEmpty
    }

    var rootURL: URL? {
        guard isConfigured else {
            return nil
        }

        return URL(fileURLWithPath: expandedRootPath, isDirectory: true)
    }

    var contentPapersDirectoryURL: URL? {
        rootURL?.appendingPathComponent("content/papers", isDirectory: true)
    }

    var staticPapersDirectoryURL: URL? {
        rootURL?.appendingPathComponent("static/papers", isDirectory: true)
    }
}

struct ClipboardPaperBibliographyEntry: Hashable {
    let entryType: String
    let citationKey: String
    let rawBibTeX: String
    let title: String?
    let link: String?
}

struct ClipboardPaperImportProposal: Hashable {
    let bibliographyEntry: ClipboardPaperBibliographyEntry
    let sourcePDFURL: URL
    let destinationPDFURL: URL
    let destinationPageURL: URL
    let pageAlreadyExists: Bool
    let destinationPDFAlreadyExists: Bool

    var citationKey: String {
        bibliographyEntry.citationKey
    }

    var paperTitle: String {
        bibliographyEntry.title ?? citationKey
    }

    var summary: String {
        let pageSummary = pageAlreadyExists ? "reuse the existing page" : "create a new paper page"
        let pdfSummary = destinationPDFAlreadyExists ? "keep the existing canonical PDF" : "copy the selected PDF"
        return "Import \(citationKey) into the knowledge base, \(pageSummary), and \(pdfSummary)."
    }
}

enum ClipboardPaperImportAnalysis: Hashable {
    case ready(ClipboardPaperImportProposal)
    case unavailable(String)

    var proposal: ClipboardPaperImportProposal? {
        switch self {
        case let .ready(proposal):
            return proposal
        case .unavailable:
            return nil
        }
    }

    var message: String {
        switch self {
        case let .ready(proposal):
            return proposal.summary
        case let .unavailable(message):
            return message
        }
    }
}

struct ClipboardPaperImportResult: Hashable {
    let citationKey: String
    let pageURL: URL
    let pdfURL: URL
    let createdPage: Bool
    let copiedPDF: Bool

    var summary: String {
        let pageSummary = createdPage ? "created the paper page" : "kept the existing paper page"
        let pdfSummary = copiedPDF ? "copied the PDF" : "kept the existing PDF"
        return "Imported \(citationKey): \(pageSummary) and \(pdfSummary)."
    }
}

struct PaperKnowledgeBaseMatch: Hashable {
    let citationKey: String
    let pageURL: URL
    let pdfURL: URL
}

enum PaperKnowledgeBaseResolver {
    static func match(
        for selectedPDFURL: URL,
        configuration: PaperKnowledgeBaseConfiguration,
        fileManager: FileManager = .default
    ) -> PaperKnowledgeBaseMatch? {
        guard let contentDirectoryURL = configuration.contentPapersDirectoryURL,
              let staticDirectoryURL = configuration.staticPapersDirectoryURL else {
            return nil
        }

        let selectedFilename = selectedPDFURL.lastPathComponent
        let selectedStandardPath = selectedPDFURL.standardizedFileURL.path
        let paperDirectories: [URL]

        do {
            paperDirectories = try fileManager.contentsOfDirectory(
                at: contentDirectoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return nil
        }

        for paperDirectory in paperDirectories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let pageURL = paperDirectory.appendingPathComponent("index.md", isDirectory: false)
            guard let markdown = try? String(contentsOf: pageURL, encoding: .utf8),
                  let embeddedFilename = paperPDFFilename(in: markdown) else {
                continue
            }

            let canonicalPDFURL = staticDirectoryURL.appendingPathComponent(embeddedFilename, isDirectory: false)
            let exactPathMatch = canonicalPDFURL.standardizedFileURL.path == selectedStandardPath
            let filenameMatch = embeddedFilename.caseInsensitiveCompare(selectedFilename) == .orderedSame
            guard exactPathMatch || filenameMatch else {
                continue
            }

            return PaperKnowledgeBaseMatch(
                citationKey: paperDirectory.lastPathComponent,
                pageURL: pageURL,
                pdfURL: fileManager.fileExists(atPath: canonicalPDFURL.path) ? canonicalPDFURL : selectedPDFURL
            )
        }

        return nil
    }

    static func match(
        citationKey: String,
        configuration: PaperKnowledgeBaseConfiguration,
        fileManager: FileManager = .default
    ) -> PaperKnowledgeBaseMatch? {
        guard let contentDirectoryURL = configuration.contentPapersDirectoryURL,
              let staticDirectoryURL = configuration.staticPapersDirectoryURL else {
            return nil
        }

        let pageURL = contentDirectoryURL
            .appendingPathComponent(citationKey, isDirectory: true)
            .appendingPathComponent("index.md", isDirectory: false)
        guard let markdown = try? String(contentsOf: pageURL, encoding: .utf8),
              let embeddedFilename = paperPDFFilename(in: markdown) else {
            return nil
        }

        let pdfURL = staticDirectoryURL.appendingPathComponent(embeddedFilename, isDirectory: false)
        guard fileManager.fileExists(atPath: pdfURL.path) else {
            return nil
        }

        return PaperKnowledgeBaseMatch(citationKey: citationKey, pageURL: pageURL, pdfURL: pdfURL)
    }

    private static func paperPDFFilename(in markdown: String) -> String? {
        let pattern = #"paperPDF\s+filename\s*=\s*\"([^\"]+)\""#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: markdown,
                range: NSRange(markdown.startIndex..., in: markdown)
              ),
              let filenameRange = Range(match.range(at: 1), in: markdown) else {
            return nil
        }

        return String(markdown[filenameRange])
    }
}

struct CodexPaperIngestionRequest: Hashable {
    let proposal: ClipboardPaperImportProposal
    let knowledgeBaseRoot: URL
    let keepSourcePDF: Bool

    var prompt: String {
        let sourceInstruction = keepSourcePDF
            ? "Copy the PDF so the original remains at its current path."
            : "Move the PDF into the canonical paper library after the destination copy is verified."

        return """
        Use $ingest-paper-kb to ingest exactly one academic paper into the configured knowledge base.

        Knowledge-base root:
        \(knowledgeBaseRoot.path)

        Source PDF:
        \(proposal.sourcePDFURL.path)

        User-supplied Google Scholar BibTeX entry:
        \(proposal.bibliographyEntry.rawBibTeX)

        \(sourceInstruction)

        Follow the skill completely: verify the PDF against the BibTeX entry, preflight before mutation, skim the paper, write evidence-based notes, apply safely, and verify the resulting PDF and Markdown page. Do not replace the supplied BibTeX entry by searching. If metadata mismatches, a collision is ambiguous, or the paper cannot be read reliably, make no unsafe changes and explain the blocker in the final response. Do not ask an interactive question because this run is launched non-interactively.
        """
    }
}

enum CodexPaperIngestionError: LocalizedError {
    case codexNotFound
    case launchFailed(String)
    case failed(exitCode: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "Codex CLI was not found. Install it or make `codex` available in PATH."
        case let .launchFailed(message):
            return "Could not start Codex: \(message)"
        case let .failed(exitCode, output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "Codex paper ingestion failed with exit code \(exitCode)."
                : "Codex paper ingestion failed: \(detail)"
        }
    }
}

enum CodexPaperIngestionLauncher {
    static func executableURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [String] = []
        if let configured = environment["CODEX_EXECUTABLE"], !configured.isEmpty {
            candidates.append(configured)
        }

        candidates.append(contentsOf: ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"])
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }

        for candidate in candidates {
            let expanded = (candidate as NSString).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded, isDirectory: false)
            }
        }

        return nil
    }

    static func arguments(for request: CodexPaperIngestionRequest) -> [String] {
        [
            "exec",
            "--json",
            "--sandbox", "workspace-write",
            "--approve-for-me",
            "--cd", request.knowledgeBaseRoot.path,
            "--add-dir", request.proposal.sourcePDFURL.deletingLastPathComponent().path,
            request.prompt,
        ]
    }

    static func run(_ request: CodexPaperIngestionRequest) async throws -> String {
        guard let executableURL = executableURL() else {
            throw CodexPaperIngestionError.codexNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let outputPipe = Pipe()
                process.executableURL = executableURL
                process.arguments = arguments(for: request)
                process.currentDirectoryURL = request.knowledgeBaseRoot
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CodexPaperIngestionError.launchFailed(error.localizedDescription))
                    return
                }

                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(
                        throwing: CodexPaperIngestionError.failed(
                            exitCode: process.terminationStatus,
                            output: finalAgentMessage(fromJSONLines: output) ?? output
                        )
                    )
                }
            }
        }
    }

    static func finalAgentMessage(fromJSONLines output: String) -> String? {
        var finalMessage: String?
        for line in output.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let item = object["item"] as? [String: Any],
                  item["type"] as? String == "agent_message",
                  let text = item["text"] as? String else {
                continue
            }

            finalMessage = text
        }

        return finalMessage
    }
}

enum ClipboardPaperImportError: LocalizedError {
    case invalidKnowledgeBaseRoot(String)
    case missingSourcePDF(String)
    case destinationPDFConflict(String)
    case pagePathConflict(String)
    case unsupportedCitationKey(String)

    var errorDescription: String? {
        switch self {
        case let .invalidKnowledgeBaseRoot(path):
            return "The configured paper knowledge base root is invalid: \(path)."
        case let .missingSourcePDF(path):
            return "The selected PDF could not be found at \(path)."
        case let .destinationPDFConflict(path):
            return "A different PDF already exists at \(path). Rename or move it first."
        case let .pagePathConflict(path):
            return "A non-file item already exists at \(path)."
        case let .unsupportedCitationKey(citationKey):
            return "The BibTeX citation key \(citationKey) cannot be used as a paper folder name."
        }
    }
}

enum ClipboardSelectionComposer {
    static func compose(items: [ClipboardItem]) -> ClipboardSelectionComposition? {
        let usableItems = items.enumerated().compactMap { offset, item -> String? in
            guard let text = item.restorableText, ClipboardTextNormalization.hasMeaningfulContent(text) else {
                return nil
            }

            let normalizedText = ClipboardTextNormalization.normalizeText(text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedText.isEmpty else {
                return nil
            }

            let descriptor = item.reviewDescriptor(position: offset + 1)
            return "[\(descriptor)]\n\(normalizedText)"
        }

        guard usableItems.count == items.count, !usableItems.isEmpty else {
            return nil
        }

        return ClipboardSelectionComposition(
            itemCount: usableItems.count,
            text: usableItems.joined(separator: "\n\n")
        )
    }
}

enum ClipboardPaperImportAnalyzer {
    static func analyze(
        pdfURL: URL,
        bibTeX: String,
        configuration: PaperKnowledgeBaseConfiguration,
        fileManager: FileManager = .default
    ) -> ClipboardPaperImportAnalysis {
        let pdfItem = ClipboardItem(kind: .fileURL, text: pdfURL.path, sourceName: "Finder")
        let bibliographyItem = ClipboardItem(kind: .text, text: bibTeX, sourceName: "Google Scholar")
        return analyze(items: [pdfItem, bibliographyItem], configuration: configuration, fileManager: fileManager)
    }

    static func analyze(
        items: [ClipboardItem],
        configuration: PaperKnowledgeBaseConfiguration,
        fileManager: FileManager = .default
    ) -> ClipboardPaperImportAnalysis {
        guard configuration.isConfigured else {
            return .unavailable("Set the Paper Knowledge Base root in Settings before importing papers.")
        }

        guard let rootURL = configuration.rootURL,
              let contentPapersDirectoryURL = configuration.contentPapersDirectoryURL,
              let staticPapersDirectoryURL = configuration.staticPapersDirectoryURL else {
            return .unavailable("The configured paper knowledge base root is incomplete.")
        }

        guard fileManager.fileExists(atPath: rootURL.path) else {
            return .unavailable("The configured paper knowledge base root does not exist at \(rootURL.path).")
        }

        let bibliographyEntries = deduplicatedBibliographyEntries(from: items)
        guard let bibliographyEntry = bibliographyEntries.first else {
            return .unavailable("Select a clipboard item that contains the paper's BibTeX entry.")
        }

        guard bibliographyEntries.count == 1 else {
            return .unavailable("Select only one BibTeX entry when importing a paper.")
        }

        guard isSupportedCitationKey(bibliographyEntry.citationKey) else {
            return .unavailable("The BibTeX citation key \(bibliographyEntry.citationKey) cannot be used as a paper folder name.")
        }

        let candidatePDFURLs = deduplicatedPDFURLs(from: items)
        guard let sourcePDFURL = candidatePDFURLs.first else {
            return .unavailable("Select one clipboard item that references the paper PDF.")
        }

        guard candidatePDFURLs.count == 1 else {
            return .unavailable("Select only one PDF file reference when importing a paper.")
        }

        guard fileManager.fileExists(atPath: sourcePDFURL.path) else {
            return .unavailable("The selected PDF could not be found at \(sourcePDFURL.path).")
        }

        let destinationPageURL = contentPapersDirectoryURL
            .appendingPathComponent(bibliographyEntry.citationKey, isDirectory: true)
            .appendingPathComponent("index.md", isDirectory: false)
        let destinationPDFURL = staticPapersDirectoryURL
            .appendingPathComponent("\(bibliographyEntry.citationKey).pdf", isDirectory: false)

        return .ready(
            ClipboardPaperImportProposal(
                bibliographyEntry: bibliographyEntry,
                sourcePDFURL: sourcePDFURL,
                destinationPDFURL: destinationPDFURL,
                destinationPageURL: destinationPageURL,
                pageAlreadyExists: fileManager.fileExists(atPath: destinationPageURL.path),
                destinationPDFAlreadyExists: fileManager.fileExists(atPath: destinationPDFURL.path)
            )
        )
    }

    private static func deduplicatedBibliographyEntries(from items: [ClipboardItem]) -> [ClipboardPaperBibliographyEntry] {
        var seenCitationKeys = Set<String>()
        return items.compactMap(\.paperBibliographyEntry).filter { entry in
            seenCitationKeys.insert(entry.citationKey).inserted
        }
    }

    private static func deduplicatedPDFURLs(from items: [ClipboardItem]) -> [URL] {
        var seenPaths = Set<String>()
        return items
            .flatMap(\.paperPDFCandidateURLs)
            .compactMap { candidateURL in
                let standardizedURL = candidateURL.standardizedFileURL
                let standardizedPath = standardizedURL.path
                guard seenPaths.insert(standardizedPath).inserted else {
                    return nil
                }

                return standardizedURL
            }
    }

    private static func isSupportedCitationKey(_ citationKey: String) -> Bool {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        guard !citationKey.isEmpty else {
            return false
        }

        return citationKey.rangeOfCharacter(from: invalidCharacters) == nil
    }
}

enum ClipboardPaperImporter {
    static func `import`(
        proposal: ClipboardPaperImportProposal,
        configuration: PaperKnowledgeBaseConfiguration,
        fileManager: FileManager = .default,
        now: Date = .now
    ) throws -> ClipboardPaperImportResult {
        guard configuration.isConfigured,
              let rootURL = configuration.rootURL else {
            throw ClipboardPaperImportError.invalidKnowledgeBaseRoot(configuration.rootPath)
        }

        guard fileManager.fileExists(atPath: rootURL.path) else {
            throw ClipboardPaperImportError.invalidKnowledgeBaseRoot(configuration.expandedRootPath)
        }

        guard fileManager.fileExists(atPath: proposal.sourcePDFURL.path) else {
            throw ClipboardPaperImportError.missingSourcePDF(proposal.sourcePDFURL.path)
        }

        guard proposal.destinationPageURL.lastPathComponent == "index.md" else {
            throw ClipboardPaperImportError.pagePathConflict(proposal.destinationPageURL.path)
        }

        guard proposal.destinationPageURL.path.contains("/content/papers/"),
              proposal.destinationPDFURL.path.contains("/static/papers/") else {
            throw ClipboardPaperImportError.invalidKnowledgeBaseRoot(configuration.expandedRootPath)
        }

        try fileManager.createDirectory(
            at: proposal.destinationPageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: proposal.destinationPDFURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let copiedPDF = try copyPDFIfNeeded(
            from: proposal.sourcePDFURL,
            to: proposal.destinationPDFURL,
            fileManager: fileManager
        )
        let createdPage = try createPaperPageIfNeeded(
            proposal: proposal,
            fileManager: fileManager,
            now: now
        )

        return ClipboardPaperImportResult(
            citationKey: proposal.citationKey,
            pageURL: proposal.destinationPageURL,
            pdfURL: proposal.destinationPDFURL,
            createdPage: createdPage,
            copiedPDF: copiedPDF
        )
    }

    private static func copyPDFIfNeeded(from sourceURL: URL, to destinationURL: URL, fileManager: FileManager) throws -> Bool {
        if fileManager.fileExists(atPath: destinationURL.path) {
            if sourceURL.standardizedFileURL.path == destinationURL.standardizedFileURL.path {
                return false
            }

            if try filesMatch(lhs: sourceURL, rhs: destinationURL) {
                return false
            }

            throw ClipboardPaperImportError.destinationPDFConflict(destinationURL.path)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return true
    }

    private static func createPaperPageIfNeeded(
        proposal: ClipboardPaperImportProposal,
        fileManager: FileManager,
        now: Date
    ) throws -> Bool {
        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(atPath: proposal.destinationPageURL.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                throw ClipboardPaperImportError.pagePathConflict(proposal.destinationPageURL.path)
            }

            return false
        }

        let markdown = renderPaperPage(for: proposal, now: now)
        try markdown.write(to: proposal.destinationPageURL, atomically: true, encoding: .utf8)
        return true
    }

    private static func renderPaperPage(for proposal: ClipboardPaperImportProposal, now: Date) -> String {
        let timestamp = paperPageTimestampString(from: now)
        let title = yamlEscaped(proposal.paperTitle)
        let link = yamlEscaped(proposal.bibliographyEntry.link ?? "")
        let bibTeXBlock = indentedBibTeXBlock(from: proposal.bibliographyEntry.rawBibTeX)
        let pdfFilename = yamlEscaped(proposal.destinationPDFURL.lastPathComponent)

        return [
            "---",
            "title: \"\(title)\"",
            "subtitle: \"\"",
            "date: \(timestamp)",
            "draft: false",
            "abstract: \"\"",
            "link: \"\(link)\"",
            "pageID: \"\(proposal.citationKey)\"",
            "bibtex: >",
            bibTeXBlock,
            "tags: []",
            "---",
            "",
            "{{< paperPDF filename=\"\(pdfFilename)\" height=\"800px\" >}}",
            "",
            "## Takeaways",
            "",
            "## Q&A",
            ""
        ].joined(separator: "\n")
    }

    private static func indentedBibTeXBlock(from rawBibTeX: String) -> String {
        let lines = ClipboardTextNormalization.normalizeText(rawBibTeX)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)

        return lines.map { "    \($0)" }.joined(separator: "\n")
    }

    private static func yamlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func filesMatch(lhs: URL, rhs: URL) throws -> Bool {
        let lhsData = try Data(contentsOf: lhs)
        let rhsData = try Data(contentsOf: rhs)
        return lhsData == rhsData
    }

    private static func paperPageTimestampString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

extension ClipboardItem {
    fileprivate func reviewDescriptor(position: Int) -> String {
        var parts = ["Clipboard Item \(position)", kind.displayName]
        if let sourceName {
            parts.append(sourceName)
        }

        return parts.joined(separator: " | ")
    }

    var restorableText: String? {
        guard kind.isTextual else {
            return nil
        }

        return plainTextFallback
    }

    var restorableURLs: [URL] {
        guard let text = restorableText else {
            return []
        }

        let candidates = ClipboardTextNormalization.normalizeText(text)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        switch kind {
        case .url:
            return candidates.compactMap { URL(string: $0) }
        case .fileURL:
            return candidates.map { URL(fileURLWithPath: $0) }
        case .text, .richText, .html, .color, .image, .screenshot, .unknown:
            return []
        }
    }

    var canOpen: Bool {
        switch kind {
        case .url, .fileURL:
            return !restorableURLs.isEmpty
        case .text, .richText, .html, .color, .image, .screenshot, .unknown:
            return false
        }
    }

    var paperBibliographyEntry: ClipboardPaperBibliographyEntry? {
        guard let text = restorableText else {
            return nil
        }

        return ClipboardPaperBibliographyParser.parseFirstEntry(from: text)
    }

    var paperPDFCandidateURLs: [URL] {
        var candidates = [URL]()

        if kind == .fileURL || kind == .url {
            candidates.append(contentsOf: restorableURLs)
        }

        if let text = restorableText {
            let lines = ClipboardTextNormalization.normalizeText(text)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            candidates.append(contentsOf: lines.compactMap { line -> URL? in
                if let url = URL(string: line), url.isFileURL {
                    return url
                }

                if line.hasPrefix("/") {
                    return URL(fileURLWithPath: line)
                }

                return nil
            })
        }

        var seenPaths = Set<String>()
        return candidates.compactMap { candidateURL in
            let standardizedURL = candidateURL.standardizedFileURL
            guard standardizedURL.isFileURL,
                  standardizedURL.pathExtension.lowercased() == "pdf" else {
                return nil
            }

            guard seenPaths.insert(standardizedURL.path).inserted else {
                return nil
            }

            return standardizedURL
        }
    }
}

enum ClipboardPaperBibliographyParser {
    static func parseFirstEntry(from text: String) -> ClipboardPaperBibliographyEntry? {
        let normalizedText = ClipboardTextNormalization.normalizeText(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atSignIndex = normalizedText.firstIndex(of: "@") else {
            return nil
        }

        let entryText = String(normalizedText[atSignIndex...])
        let characters = Array(entryText)
        guard characters.count >= 4 else {
            return nil
        }

        var index = 1
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }

        let entryTypeStart = index
        while index < characters.count, characters[index].isLetter || characters[index].isNumber || characters[index] == "_" {
            index += 1
        }

        guard entryTypeStart < index else {
            return nil
        }

        let entryType = String(characters[entryTypeStart..<index])
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }

        guard index < characters.count else {
            return nil
        }

        let openingDelimiter = characters[index]
        let closingDelimiter: Character
        switch openingDelimiter {
        case "{":
            closingDelimiter = "}"
        case "(":
            closingDelimiter = ")"
        default:
            return nil
        }

        let bodyStartIndex = index + 1
        guard let closingBodyIndex = matchingDelimiterIndex(
            in: characters,
            openingIndex: index,
            openingDelimiter: openingDelimiter,
            closingDelimiter: closingDelimiter
        ) else {
            return nil
        }

        guard bodyStartIndex < closingBodyIndex else {
            return nil
        }

        let entryBody = String(characters[bodyStartIndex..<closingBodyIndex])
        guard let keyDelimiterIndex = topLevelCommaIndex(in: Array(entryBody)) else {
            return nil
        }

        let entryBodyCharacters = Array(entryBody)
        let citationKey = String(entryBodyCharacters[..<keyDelimiterIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !citationKey.isEmpty else {
            return nil
        }

        let fieldText = String(entryBodyCharacters[entryBodyCharacters.index(after: keyDelimiterIndex)...])
        let fields = parseFields(from: fieldText)
        let title = normalizedFieldValue(fields["title"])
        let doi = normalizedFieldValue(fields["doi"])
        let url = normalizedFieldValue(fields["url"])
        let link = linkValue(doi: doi, url: url)
        let rawBibTeX = String(characters[...closingBodyIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ClipboardPaperBibliographyEntry(
            entryType: entryType,
            citationKey: citationKey,
            rawBibTeX: rawBibTeX,
            title: title,
            link: link
        )
    }

    private static func parseFields(from fieldText: String) -> [String: String] {
        let characters = Array(fieldText)
        var fields = [String: String]()
        var index = 0

        while index < characters.count {
            skipSeparators(in: characters, index: &index)
            guard index < characters.count else {
                break
            }

            let fieldNameStart = index
            while index < characters.count,
                  characters[index].isLetter || characters[index].isNumber || characters[index] == "_" || characters[index] == "-" {
                index += 1
            }

            guard fieldNameStart < index else {
                break
            }

            let fieldName = String(characters[fieldNameStart..<index]).lowercased()
            skipWhitespace(in: characters, index: &index)
            guard index < characters.count, characters[index] == "=" else {
                break
            }

            index += 1
            skipWhitespace(in: characters, index: &index)
            let fieldValue = parseValue(in: characters, index: &index)
            fields[fieldName] = fieldValue
            skipSeparators(in: characters, index: &index)
        }

        return fields
    }

    private static func parseValue(in characters: [Character], index: inout Int) -> String {
        guard index < characters.count else {
            return ""
        }

        let openingCharacter = characters[index]
        if openingCharacter == "{" || openingCharacter == "(" {
            let closingCharacter: Character = openingCharacter == "{" ? "}" : ")"
            let openingIndex = index
            guard let closingIndex = matchingDelimiterIndex(
                in: characters,
                openingIndex: openingIndex,
                openingDelimiter: openingCharacter,
                closingDelimiter: closingCharacter
            ) else {
                index = characters.count
                return String(characters[openingIndex...])
            }

            index = closingIndex + 1
            return String(characters[openingIndex...closingIndex])
        }

        if openingCharacter == "\"" {
            let openingIndex = index
            index += 1
            var isEscaped = false
            while index < characters.count {
                let currentCharacter = characters[index]
                if currentCharacter == "\"" && !isEscaped {
                    let closingIndex = index
                    index += 1
                    return String(characters[openingIndex...closingIndex])
                }

                isEscaped = currentCharacter == "\\" && !isEscaped
                if currentCharacter != "\\" {
                    isEscaped = false
                }
                index += 1
            }

            return String(characters[openingIndex...])
        }

        let valueStart = index
        while index < characters.count, characters[index] != ",", characters[index] != "\n", characters[index] != "\r" {
            index += 1
        }

        return String(characters[valueStart..<index])
    }

    private static func normalizedFieldValue(_ rawValue: String?) -> String? {
        guard var value = ClipboardTextNormalization.normalizeMetadata(rawValue) else {
            return nil
        }

        while true {
            if value.first == "{",
               value.last == "}",
               isFullyWrapped(value, openingDelimiter: "{", closingDelimiter: "}") {
                value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if value.first == "\"", value.last == "\"" {
                value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            break
        }

        value = value
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
        value = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        return value.isEmpty ? nil : value
    }

    private static func linkValue(doi: String?, url: String?) -> String? {
        if let doi, !doi.isEmpty {
            if doi.lowercased().hasPrefix("http://") || doi.lowercased().hasPrefix("https://") {
                return doi
            }

            return "https://doi.org/\(doi)"
        }

        guard let url, !url.isEmpty else {
            return nil
        }

        return url
    }

    private static func matchingDelimiterIndex(
        in characters: [Character],
        openingIndex: Int,
        openingDelimiter: Character,
        closingDelimiter: Character
    ) -> Int? {
        var depth = 0
        var index = openingIndex

        while index < characters.count {
            let currentCharacter = characters[index]
            if currentCharacter == openingDelimiter {
                depth += 1
            } else if currentCharacter == closingDelimiter {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }

            index += 1
        }

        return nil
    }

    private static func topLevelCommaIndex(in characters: [Character]) -> Int? {
        var depth = 0
        var isInsideQuotes = false
        var index = 0

        while index < characters.count {
            let currentCharacter = characters[index]

            if currentCharacter == "\"" {
                isInsideQuotes.toggle()
            } else if !isInsideQuotes {
                if currentCharacter == "{" || currentCharacter == "(" {
                    depth += 1
                } else if currentCharacter == "}" || currentCharacter == ")" {
                    depth = max(0, depth - 1)
                } else if currentCharacter == "," && depth == 0 {
                    return index
                }
            }

            index += 1
        }

        return nil
    }

    private static func skipWhitespace(in characters: [Character], index: inout Int) {
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
    }

    private static func skipSeparators(in characters: [Character], index: inout Int) {
        while index < characters.count,
              characters[index].isWhitespace || characters[index] == "," {
            index += 1
        }
    }

    private static func isFullyWrapped(
        _ value: String,
        openingDelimiter: Character,
        closingDelimiter: Character
    ) -> Bool {
        let characters = Array(value)
        guard characters.first == openingDelimiter, characters.last == closingDelimiter else {
            return false
        }

        return matchingDelimiterIndex(
            in: characters,
            openingIndex: 0,
            openingDelimiter: openingDelimiter,
            closingDelimiter: closingDelimiter
        ) == characters.count - 1
    }
}
