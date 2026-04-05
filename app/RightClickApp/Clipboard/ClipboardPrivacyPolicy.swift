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
    var suppressLikelySecretsInClipboardText: Bool
    var sensitiveKeywords: Set<String>
    var sensitiveSourceIdentifiers: Set<String>

    init(
        suppressSensitiveSources: Bool = true,
        suppressLikelySecretsInClipboardText: Bool = true,
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
            "com.apple.securityagent",
            "com.agilebits.onepassword7",
            "com.1password.1password",
            "com.bitwarden.desktop",
            "org.keepassxc.keepassxc",
            "com.lastpass.LastPass",
            "com.dashlane.dashlanephonefinal",
            "com.keepersecurity.passwordmanager",
            "com.robinhood.mymacotp"
        ]
    ) {
        self.suppressSensitiveSources = suppressSensitiveSources
        self.suppressLikelySecretsInClipboardText = suppressLikelySecretsInClipboardText
        self.sensitiveKeywords = sensitiveKeywords
        self.sensitiveSourceIdentifiers = sensitiveSourceIdentifiers
    }

    static let standard = ClipboardPrivacyPolicy()

    func decision(
        for sourceName: String?,
        sourceBundleIdentifier: String?,
        sourceWindowTitle: String? = nil,
        isSensitiveSource: Bool = false,
        clipboardText: String? = nil
    ) -> Decision {
        if suppressSensitiveSources {
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
        }

        if suppressLikelySecretsInClipboardText,
           let contentDecision = sensitiveContentDecision(for: clipboardText) {
            return contentDecision
        }

        return Decision(shouldSuppress: false, reason: nil)
    }

    func allowsCapture(
        sourceName: String?,
        sourceBundleIdentifier: String?,
        sourceWindowTitle: String? = nil,
        isSensitiveSource: Bool = false,
        clipboardText: String? = nil
    ) -> Bool {
        decision(
            for: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceWindowTitle: sourceWindowTitle,
            isSensitiveSource: isSensitiveSource,
            clipboardText: clipboardText
        ).allowsCapture
    }

    private func sensitiveContentDecision(for clipboardText: String?) -> Decision? {
        guard let clipboardText else {
            return nil
        }

        let trimmedText = ClipboardTextNormalization.normalizeText(clipboardText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        if trimmedText.localizedCaseInsensitiveContains("-----BEGIN"),
           trimmedText.localizedCaseInsensitiveContains("PRIVATE KEY-----") {
            return Decision(
                shouldSuppress: true,
                reason: "The clipboard text looks like a private key block."
            )
        }

        let fullTextPatterns: [(pattern: String, reason: String)] = [
            (#"(?im)authorization\s*:\s*bearer\s+[A-Za-z0-9._~+\/=-]{16,}"#, "The clipboard text looks like a bearer token header."),
            (#"(?im)\b(api[_ -]?key|access[_ -]?token|refresh[_ -]?token|auth[_ -]?token|client[_ -]?secret|secret)\s*[:=]\s*['"]?[A-Za-z0-9._~+\/=-]{12,}"#, "The clipboard text looks like a secret assignment.")
        ]

        if let reason = firstRegexReason(in: trimmedText, patterns: fullTextPatterns) {
            return Decision(shouldSuppress: true, reason: reason)
        }

        for token in secretCandidateTokens(in: trimmedText) {
            if looksLikeJWT(token) {
                return Decision(
                    shouldSuppress: true,
                    reason: "The clipboard text looks like a JWT or session token."
                )
            }

            if looksLikeProviderSecret(token) {
                return Decision(
                    shouldSuppress: true,
                    reason: "The clipboard text looks like an API key or secret token."
                )
            }
        }

        return nil
    }

    private func firstRegexReason(in text: String, patterns: [(pattern: String, reason: String)]) -> String? {
        for entry in patterns {
            guard let regex = try? NSRegularExpression(pattern: entry.pattern, options: []) else {
                continue
            }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                return entry.reason
            }
        }

        return nil
    }

    private func secretCandidateTokens(in text: String) -> [String] {
        let tokenPattern = #"[A-Za-z0-9._~+\/=-]{16,}"#
        guard let regex = try? NSRegularExpression(pattern: tokenPattern, options: []) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }

            return String(text[range])
        }
    }

    private func looksLikeJWT(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            return false
        }

        return parts.allSatisfy { part in
            part.count >= 12 && part.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-" || character == "_"
            }
        }
    }

    private func looksLikeProviderSecret(_ token: String) -> Bool {
        let patterns = [
            #"^sk-[A-Za-z0-9]{20,}$"#,
            #"^rk-[A-Za-z0-9]{20,}$"#,
            #"^gh[pousr]_[A-Za-z0-9]{20,}$"#,
            #"^github_pat_[A-Za-z0-9_]{20,}$"#,
            #"^xox[baprs]-[A-Za-z0-9-]{20,}$"#,
            #"^AKIA[0-9A-Z]{16}$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }

            let range = NSRange(token.startIndex..<token.endIndex, in: token)
            if regex.firstMatch(in: token, options: [], range: range) != nil {
                return true
            }
        }

        return false
    }
}
