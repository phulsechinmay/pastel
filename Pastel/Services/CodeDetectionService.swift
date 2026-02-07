import Foundation

/// Detects code snippets in clipboard text using a multi-signal heuristic pre-filter.
///
/// Two-phase detection:
/// 1. `looksLikeCode(_:)` -- fast synchronous heuristic (this plan)
/// 2. `detectLanguage(_:)` -- async HighlightSwift detection (stub; implemented in Plan 07-02)
///
/// The heuristic scores text across 5 signals (punctuation density, keywords, indentation,
/// line endings, identifier patterns). A score >= 3 indicates likely code.
struct CodeDetectionService {

    // MARK: - Synchronous Heuristic Pre-filter

    /// Returns true if the text has enough code-like signals to warrant language detection.
    ///
    /// Designed to reject prose, URLs, and file paths quickly. Requires minimum 2 lines
    /// (single-line text is almost never a meaningful code snippet).
    ///
    /// - Parameter text: The clipboard text to analyze.
    /// - Returns: `true` if the text likely contains code (score >= 3 across 5 signals).
    static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        // Single-line text is almost never meaningful code
        guard lines.count >= 2 else { return false }

        // Filter out empty lines for ratio calculations
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonEmptyLines.isEmpty else { return false }

        var score = 0

        // Signal 1 (+1): Punctuation density > 0.03
        // Count code-specific punctuation characters relative to total length
        let codePunctuation = CharacterSet(charactersIn: "{}()[];=<>")
        let punctuationCount = text.unicodeScalars.filter { codePunctuation.contains($0) }.count
        let punctuationDensity = Double(punctuationCount) / Double(max(text.count, 1))
        if punctuationDensity > 0.03 { score += 1 }

        // Signal 2 (+2): Contains programming keywords
        // Keywords must appear with trailing space or at line start to reduce false positives
        let keywords = [
            "func ", "def ", "class ", "import ", "return ", "if ", "for ", "while ",
            "let ", "var ", "const ", "public ", "private ", "static ", "void ",
            "#include", "#import", "function ", "async ", "await "
        ]
        if keywords.contains(where: { text.contains($0) }) { score += 2 }

        // Signal 3 (+1): >30% of non-empty lines have consistent indentation
        // (start with 2+ spaces or a tab)
        let indentedLines = nonEmptyLines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }
        if Double(indentedLines.count) / Double(nonEmptyLines.count) > 0.3 { score += 1 }

        // Signal 4 (+1): >20% of non-empty lines end with ;, {, or }
        let codeLineEndings = nonEmptyLines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix(";") || trimmed.hasSuffix("{") || trimmed.hasSuffix("}")
        }
        if Double(codeLineEndings.count) / Double(nonEmptyLines.count) > 0.2 { score += 1 }

        // Signal 5 (+1): Contains CamelCase or snake_case identifiers
        let hasCamelCase = text.range(of: "[a-z][a-zA-Z]*[A-Z][a-zA-Z]*", options: .regularExpression) != nil
        let hasSnakeCase = text.range(of: "[a-z]+_[a-z]+", options: .regularExpression) != nil
        if hasCamelCase || hasSnakeCase { score += 1 }

        return score >= 3
    }

    // MARK: - Async Language Detection (Stub)

    /// Detects the programming language of the given text using HighlightSwift.
    ///
    /// **Stub implementation** -- returns nil. Will be implemented in Plan 07-02 when
    /// the HighlightSwift SPM dependency is added.
    ///
    /// - Parameter text: The code text to analyze.
    /// - Returns: A tuple of (language identifier, relevance score), or nil if not detected.
    static func detectLanguage(_ text: String) async -> (language: String, relevance: Int)? {
        // TODO: Plan 07-02 -- add HighlightSwift dependency and implement:
        // let highlight = Highlight()
        // let result = try await highlight.request(text)
        // guard result.relevance >= 5 else { return nil }
        // return (result.language, result.relevance)
        return nil
    }
}
