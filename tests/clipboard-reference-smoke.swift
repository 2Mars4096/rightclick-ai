import Foundation

struct ActionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

@main
struct ClipboardReferenceSmoke {
    static func main() {
        let urlItem = ClipboardItem(
            kind: .url,
            text: """
            https://example.com/docs
            https://openai.com/
            """
        )

        guard urlItem.restorableURLs.count == 2 else {
            fputs("Expected two URL references.\n", stderr)
            exit(1)
        }

        guard urlItem.canOpen, urlItem.canRestore else {
            fputs("Expected URL item to be openable and restorable.\n", stderr)
            exit(1)
        }

        let fileItem = ClipboardItem(
            kind: .fileURL,
            text: """
            /tmp/report.pdf
            /Users/test/Documents/notes.txt
            """
        )

        guard fileItem.restorableURLs.count == 2 else {
            fputs("Expected two file references.\n", stderr)
            exit(1)
        }

        guard fileItem.restorableURLs.allSatisfy(\.isFileURL) else {
            fputs("Expected file references to decode as file URLs.\n", stderr)
            exit(1)
        }

        guard fileItem.canOpen, fileItem.canRestore else {
            fputs("Expected file item to be openable and restorable.\n", stderr)
            exit(1)
        }

        let textItem = ClipboardItem(kind: .text, text: "Hello world")
        guard !textItem.canOpen else {
            fputs("Expected plain text not to be openable.\n", stderr)
            exit(1)
        }

        print("Clipboard reference smoke passed.")
    }
}
