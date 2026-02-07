@preconcurrency import HighlightSwift
import Foundation

/// Detects code snippets in clipboard text using a multi-signal heuristic pre-filter,
/// then performs async language detection and syntax highlighting via HighlightSwift.
///
/// Two-phase detection:
/// 1. `looksLikeCode(_:)` -- fast synchronous heuristic
/// 2. `detectLanguage(_:)` -- async HighlightSwift detection with relevance >= 5 threshold
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

    // MARK: - Async Language Detection

    /// Detects the programming language of the given text using HighlightSwift,
    /// supplemented by keyword-based hints to correct common highlight.js misdetections.
    ///
    /// highlight.js auto-detection can misidentify languages (e.g., Swift as SCSS).
    /// Keyword hints check for strong language-specific signals and override when
    /// the auto-detected language seems wrong.
    ///
    /// - Parameter text: The code text to analyze.
    /// - Returns: A tuple of (language identifier, relevance score), or nil if not detected.
    static func detectLanguage(_ text: String) async -> (language: String, relevance: Int)? {
        // Check keyword hints first for strong language signals
        let hintedLanguage = languageHint(for: text)

        do {
            let highlight = Highlight()
            let result = try await highlight.request(text)

            // If we have a keyword hint and highlight.js returned something different,
            // prefer the keyword hint (highlight.js often misdetects Swift as SCSS, etc.)
            if let hint = hintedLanguage, result.language != hint {
                return (hint, max(result.relevance, 5))
            }

            // Accept highlight.js result if relevance is reasonable
            guard result.relevance >= 3 else { return nil }
            return (result.language, result.relevance)
        } catch {
            // If highlight.js failed but we have a keyword hint, use it
            if let hint = hintedLanguage {
                return (hint, 5)
            }
            return nil
        }
    }

    // MARK: - Keyword-based Language Hints

    /// Checks for strong language-specific keyword patterns that indicate a particular language.
    /// Returns nil if no strong signal is found.
    private static func languageHint(for text: String) -> String? {
        // Swift: func/let/var/guard/struct/enum/protocol with Swift-style syntax
        let swiftKeywords = ["func ", "guard ", "struct ", "enum ", "protocol ", "@Observable", "@MainActor", "@State ", "@Binding ", "-> "]
        let swiftCount = swiftKeywords.filter { text.contains($0) }.count
        if swiftCount >= 2 { return "swift" }

        // Python: def/elif/except/self./print(
        let pythonKeywords = ["def ", "elif ", "except ", "self.", "print(", "import ", "__init__", "lambda "]
        let pythonCount = pythonKeywords.filter { text.contains($0) }.count
        if pythonCount >= 2 { return "python" }

        // JavaScript/TypeScript: const/=>/===/.then(/async function
        let jsKeywords = ["=> ", "=== ", "!== ", ".then(", "async function", "console.log", "require(", "export "]
        let jsCount = jsKeywords.filter { text.contains($0) }.count
        if jsCount >= 2 { return "javascript" }

        // Rust: fn /let mut/impl /pub fn/->
        let rustKeywords = ["fn ", "let mut ", "impl ", "pub fn ", "&self", "::new(", "unwrap()"]
        let rustCount = rustKeywords.filter { text.contains($0) }.count
        if rustCount >= 2 { return "rust" }

        // Go: func (/ := /package /fmt./go func
        let goKeywords = [":= ", "package ", "fmt.", "go func", "func (", "interface{"]
        let goCount = goKeywords.filter { text.contains($0) }.count
        if goCount >= 2 { return "go" }

        return nil
    }
}

// MARK: - Highlight Cache

/// Actor-based cache for syntax-highlighted `AttributedString` values, keyed by content hash.
///
/// Prevents re-highlighting when scrolling through code cards. Limited to 200 entries
/// with simple oldest-first eviction.
actor HighlightCache {
    static let shared = HighlightCache()

    private var cache: [String: AttributedString] = [:]
    private var insertionOrder: [String] = []
    private let maxEntries = 200

    /// Retrieve a cached highlighted AttributedString by content hash.
    func get(_ hash: String) -> AttributedString? {
        cache[hash]
    }

    /// Store a highlighted AttributedString keyed by content hash.
    func set(_ hash: String, value: AttributedString) {
        if cache[hash] == nil {
            insertionOrder.append(hash)
        }
        cache[hash] = value

        // Evict oldest entries when cache exceeds limit
        while cache.count > maxEntries, let oldest = insertionOrder.first {
            insertionOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}
