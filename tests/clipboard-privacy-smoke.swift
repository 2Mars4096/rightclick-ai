import Foundation

@main
struct ClipboardPrivacySmoke {
    static func main() {
        let policy = ClipboardPrivacyPolicy.standard

        assertSuppressed(
            policy,
            text: """
            -----BEGIN OPENSSH PRIVATE KEY-----
            b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAA...
            -----END OPENSSH PRIVATE KEY-----
            """,
            label: "private key block"
        )

        assertSuppressed(
            policy,
            text: "Authorization: Bearer sk-abcdefghijklmnopqrstuvwxyzABCDE12345678901234567890",
            label: "bearer token header"
        )

        assertSuppressed(
            policy,
            text: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkRleHRlciIsImlhdCI6MTUxNjIzOTAyMn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
            label: "jwt token"
        )

        assertSuppressed(
            policy,
            text: "api_key = sk-abcdefghijklmnopqrstuvwxyzABCDE12345678901234567890",
            label: "api key assignment"
        )

        assertAllowed(
            policy,
            text: "Dinner with Alex tomorrow at 7pm at IFC Mall",
            label: "normal calendar text"
        )

        assertAllowed(
            policy,
            text: "Could you please send the revised deck by tomorrow morning? Thanks.",
            label: "normal draft text"
        )

        print("Clipboard privacy smoke passed.")
    }

    private static func assertSuppressed(_ policy: ClipboardPrivacyPolicy, text: String, label: String) {
        let decision = policy.decision(
            for: "TextEdit",
            sourceBundleIdentifier: "com.apple.TextEdit",
            clipboardText: text
        )

        guard decision.shouldSuppress else {
            fputs("Expected suppression for \(label).\n", stderr)
            exit(1)
        }
    }

    private static func assertAllowed(_ policy: ClipboardPrivacyPolicy, text: String, label: String) {
        let decision = policy.decision(
            for: "TextEdit",
            sourceBundleIdentifier: "com.apple.TextEdit",
            clipboardText: text
        )

        guard !decision.shouldSuppress else {
            fputs("Expected capture to be allowed for \(label), but got: \(decision.reason ?? "unknown reason").\n", stderr)
            exit(1)
        }
    }
}
