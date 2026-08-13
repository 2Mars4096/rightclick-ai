import Foundation

struct ActionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

@main
struct ClipboardPaperImportSmoke {
    static func main() throws {
        let fileManager = FileManager.default
        let buildRoot = fileManager.temporaryDirectory
            .appendingPathComponent("right-click-paper-import-\(UUID().uuidString)", isDirectory: true)
        let sourcePDFDirectory = buildRoot.appendingPathComponent("incoming", isDirectory: true)
        let knowledgeBaseRoot = buildRoot.appendingPathComponent("my-knowledge-base", isDirectory: true)
        let sourcePDFURL = sourcePDFDirectory.appendingPathComponent("paper.pdf", isDirectory: false)

        try fileManager.createDirectory(at: sourcePDFDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: knowledgeBaseRoot.appendingPathComponent("content/papers", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: knowledgeBaseRoot.appendingPathComponent("static/papers", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("%PDF-1.4\nmock\n".utf8).write(to: sourcePDFURL)

        defer {
            try? fileManager.removeItem(at: buildRoot)
        }

        let items = makeClipboardItems(sourcePDFURL: sourcePDFURL)
        let configuration = PaperKnowledgeBaseConfiguration(rootPath: knowledgeBaseRoot.path)

        let analysis = ClipboardPaperImportAnalyzer.analyze(items: items, configuration: configuration)
        guard case let .ready(proposal) = analysis else {
            fail("Expected paper import analysis to succeed.")
        }

        guard proposal.citationKey == "acemoglu2012network" else {
            fail("Expected citation key to be parsed from BibTeX.")
        }

        guard proposal.paperTitle == "The Network Origins of Aggregate Fluctuations" else {
            fail("Expected title to be parsed from BibTeX.")
        }

        let result = try ClipboardPaperImporter.import(
            proposal: proposal,
            configuration: configuration,
            now: Date(timeIntervalSince1970: 0)
        )
        guard result.createdPage, result.copiedPDF else {
            fail("Expected the first import to create both the page and canonical PDF.")
        }

        let pageContents = try String(contentsOf: result.pageURL, encoding: .utf8)
        guard pageContents.contains("pageID: \"acemoglu2012network\"") else {
            fail("Expected pageID front matter to match the citation key.")
        }

        guard pageContents.contains("paperPDF filename=\"acemoglu2012network.pdf\"") else {
            fail("Expected the canonical PDF filename to be embedded in the paper page.")
        }

        guard pageContents.contains("link: \"https://doi.org/10.3982/ecta9623\"") else {
            fail("Expected DOI links to be normalized into a Hugo-friendly URL.")
        }

        let secondResult = try ClipboardPaperImporter.import(
            proposal: proposal,
            configuration: configuration,
            now: Date(timeIntervalSince1970: 0)
        )
        guard !secondResult.createdPage, !secondResult.copiedPDF else {
            fail("Expected re-importing the same paper to keep the existing page and canonical PDF.")
        }

        guard let match = PaperKnowledgeBaseResolver.match(
            for: result.pdfURL,
            configuration: configuration
        ) else {
            fail("Expected the canonical PDF to resolve to its paper notes.")
        }

        guard match.citationKey == "acemoglu2012network", match.pageURL == result.pageURL else {
            fail("Expected the resolved note to preserve the citation-key pairing.")
        }

        let request = CodexPaperIngestionRequest(
            proposal: proposal,
            knowledgeBaseRoot: knowledgeBaseRoot,
            keepSourcePDF: false,
            model: "gpt-5.6-terra"
        )
        let arguments = CodexPaperIngestionLauncher.arguments(for: request)
        guard arguments.contains("--approve-for-me"),
              arguments.contains("workspace-write"),
              arguments.contains("--model"),
              arguments.contains("gpt-5.6-terra"),
              request.prompt.contains("Use $ingest-paper-kb"),
              request.prompt.contains(proposal.bibliographyEntry.rawBibTeX) else {
            fail("Expected the Codex handoff to invoke the ingestion skill with reviewed inputs.")
        }

        let defaultModelRequest = CodexPaperIngestionRequest(
            proposal: proposal,
            knowledgeBaseRoot: knowledgeBaseRoot,
            keepSourcePDF: false,
            model: nil
        )
        guard !CodexPaperIngestionLauncher.arguments(for: defaultModelRequest).contains("--model") else {
            fail("Expected Codex Default to inherit the user's configured model.")
        }

        let jsonLines = """
        {"type":"item.completed","item":{"type":"agent_message","text":"Ingested and verified."}}
        {"type":"turn.completed"}
        """
        guard CodexPaperIngestionLauncher.finalAgentMessage(fromJSONLines: jsonLines) == "Ingested and verified." else {
            fail("Expected the final Codex agent message to be extracted from JSONL output.")
        }

        print("Clipboard paper import smoke passed.")
    }

    private static func makeClipboardItems(sourcePDFURL: URL) -> [ClipboardItem] {
        let pdfReference = ClipboardItem(
            kind: .fileURL,
            text: sourcePDFURL.path,
            sourceName: "Finder"
        )
        let bibtex = ClipboardItem(
            kind: .text,
            text: """
            @article{acemoglu2012network,
              title={The Network Origins of Aggregate Fluctuations},
              author={Acemoglu, Daron and Carvalho, Vasco M and Ozdaglar, Asuman and Tahbaz-Salehi, Alireza},
              journal={Econometrica},
              volume={80},
              number={5},
              pages={1977--2016},
              year={2012},
              doi={10.3982/ecta9623}
            }
            """,
            sourceName: "Google Scholar"
        )

        return [pdfReference, bibtex]
    }

    private static func fail(_ message: String) -> Never {
        fputs("\(message)\n", stderr)
        exit(1)
    }
}
