import Foundation

struct ActionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

@main
struct ClipboardSelectionCompositionSmoke {
    static func main() {
        testMixedPaperSelectionComposition()
        testIncompatibleSelectionFailsComposition()
        print("Clipboard selection composition smoke passed.")
    }

    private static func testMixedPaperSelectionComposition() {
        let pdfReference = ClipboardItem(
            kind: .fileURL,
            text: "/Volumes/data/Dropbox/Projects/my-knowledge-base/static/papers/example-paper.pdf",
            sourceName: "Finder"
        )
        let bibtex = ClipboardItem(
            kind: .text,
            text: """
            @article{smith2026example,
              title={An Example Paper},
              author={Smith, Jane},
              year={2026}
            }
            """,
            sourceName: "Google Scholar"
        )

        guard let composition = ClipboardSelectionComposer.compose(items: [pdfReference, bibtex]) else {
            fail("Expected file reference and BibTeX text to compose into one review input.")
        }

        guard composition.itemCount == 2 else {
            fail("Expected composition to report two selected items.")
        }

        guard composition.text.contains("Clipboard Item 1 | File URL | Finder") else {
            fail("Expected the file reference section header to be present.")
        }

        guard composition.text.contains("Clipboard Item 2 | Text | Google Scholar") else {
            fail("Expected the BibTeX section header to be present.")
        }

        guard composition.text.contains("/Volumes/data/Dropbox/Projects/my-knowledge-base/static/papers/example-paper.pdf") else {
            fail("Expected the file reference path to be preserved in the combined review input.")
        }

        guard composition.text.contains("@article{smith2026example") else {
            fail("Expected BibTeX content to be preserved in the combined review input.")
        }
    }

    private static func testIncompatibleSelectionFailsComposition() {
        let screenshot = ClipboardItem(kind: .screenshot, text: nil)
        let note = ClipboardItem(kind: .text, text: "A plain text note")

        guard ClipboardSelectionComposer.compose(items: [screenshot, note]) == nil else {
            fail("Expected a visual-only clipboard item to prevent combined text review composition.")
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("\(message)\n", stderr)
        exit(1)
    }
}
