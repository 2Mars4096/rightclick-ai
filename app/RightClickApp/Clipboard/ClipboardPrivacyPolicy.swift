import Foundation

struct ClipboardPrivacyPolicy: Codable, Hashable {
    struct Decision: Codable, Hashable {
        let shouldSuppress: Bool
        let reason: String?

        var allowsCapture: Bool {
            !shouldSuppress
        }
    }

    var suppressSensitiveSources: Bool
    var sensitiveKeywords: Set<String>
    var sensitiveSourceIdentifiers: Set<String>

    init(
        suppressSensitiveSources: Bool = true,
        sensitiveKeywords: Set<String> = [
            "password",
            "passcode",
            "secret",
            "credential",
            "keychain",
            "1password",
            "bitwarden",
            "lastpass",
            "keeper",
            "dashlane",
            "authenticator",
            "otp",
            "verification code"
        ],
        sensitiveSourceIdentifiers: Set<String> = [
            "com.apple.keychainaccess",
            "com.apple.passwordassistant",
            "com.apple.securityagent"
        ]
    ) {
        self.suppressSensitiveSources = suppressSensitiveSources
        self.sensitiveKeywords = sensitiveKeywords
        self.sensitiveSourceIdentifiers = sensitiveSourceIdentifiers
    }

    static let standard = ClipboardPrivacyPolicy()

    func decision(
        for sourceName: String?,
        sourceBundleIdentifier: String?,
        sourceWindowTitle: String? = nil,
        isSensitiveSource: Bool = false
    ) -> Decision {
        guard suppressSensitiveSources else {
            return Decision(shouldSuppress: false, reason: nil)
        }

        if isSensitiveSource {
            return Decision(
                shouldSuppress: true,
                reason: "The clipboard source was marked sensitive."
            )
        }

        let normalizedHaystack = ClipboardTextNormalization.searchIndex(
            from: [sourceName, sourceBundleIdentifier, sourceWindowTitle]
        )
        let compactHaystack = normalizedHaystack.replacingOccurrences(of: " ", with: "")

        if sensitiveSourceIdentifiers.contains(where: { compactHaystack.contains(ClipboardTextNormalization.foldForSearch($0).replacingOccurrences(of: " ", with: "")) }) {
            return Decision(
                shouldSuppress: true,
                reason: "The clipboard source matches a protected identifier."
            )
        }

        if let keyword = sensitiveKeywords.first(where: { normalizedHaystack.contains(ClipboardTextNormalization.foldForSearch($0)) }) {
            return Decision(
                shouldSuppress: true,
                reason: "The clipboard source matches the sensitive keyword \"\(keyword)\"."
            )
        }

        return Decision(shouldSuppress: false, reason: nil)
    }

    func allowsCapture(
        sourceName: String?,
        sourceBundleIdentifier: String?,
        sourceWindowTitle: String? = nil,
        isSensitiveSource: Bool = false
    ) -> Bool {
        decision(
            for: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceWindowTitle: sourceWindowTitle,
            isSensitiveSource: isSensitiveSource
        ).allowsCapture
    }
}
