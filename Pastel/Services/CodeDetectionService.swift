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
        let sample = TextWorkBudget.codeSample(text)
        let lines = sample.components(separatedBy: .newlines)
        // Single-line text is almost never meaningful code
        guard lines.count >= 2 else { return false }

        // Filter out empty lines for ratio calculations
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonEmptyLines.isEmpty else { return false }

        var score = 0

        // Signal 1 (+1): Punctuation density > 0.03
        // Count code-specific punctuation characters relative to total length
        let codePunctuation = CharacterSet(charactersIn: "{}()[];=<>")
        let punctuationCount = sample.unicodeScalars.filter { codePunctuation.contains($0) }.count
        let punctuationDensity = Double(punctuationCount) / Double(max(sample.count, 1))
        if punctuationDensity > 0.03 { score += 1 }

        // Signal 2 (+2): Contains programming keywords
        // Keywords must appear with trailing space or at line start to reduce false positives
        let keywords = [
            "func ", "def ", "class ", "import ", "return ", "if ", "for ", "while ",
            "let ", "var ", "const ", "public ", "private ", "static ", "void ",
            "#include", "#import", "function ", "async ", "await "
        ]
        if keywords.contains(where: { sample.contains($0) }) { score += 2 }

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
        let hasCamelCase = sample.range(of: "[a-z][a-zA-Z]*[A-Z][a-zA-Z]*", options: .regularExpression) != nil
        let hasSnakeCase = sample.range(of: "[a-z]+_[a-z]+", options: .regularExpression) != nil
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
        let sample = TextWorkBudget.codeSample(text)
        // Check keyword hints first for strong language signals
        let hintedLanguage = languageHint(for: sample)

        do {
            let highlight = Highlight()
            let result = try await highlight.request(sample)

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
/// Prevents re-highlighting when scrolling through code cards. Entries have both
/// a count and an estimated byte budget, and card input itself is size-capped.
actor HighlightCache {
    static let shared = HighlightCache()

    private var cache: [String: AttributedString] = [:]
    private var costs: [String: Int] = [:]
    private var insertionOrder: [String] = []
    private var totalCost = 0
    private let maxEntries = 100
    private let maxEstimatedBytes = 16 * 1024 * 1024

    /// Retrieve a cached highlighted AttributedString by content hash.
    func get(_ hash: String) -> AttributedString? {
        cache[hash]
    }

    /// Remove every entry for a content hash (e.g., when the user changes language).
    ///
    /// Keys are `"<contentHash>_<d|l>"` because a clip highlighted for dark and the
    /// same clip highlighted for light are two different results. Callers only know
    /// the content hash, so eviction has to clear both appearance variants or a stale
    /// render survives the edit that was supposed to invalidate it.
    func evict(_ hash: String) {
        let prefix = "\(hash)_"
        let doomed = cache.keys.filter { $0 == hash || $0.hasPrefix(prefix) }
        for key in doomed {
            cache.removeValue(forKey: key)
            totalCost -= costs.removeValue(forKey: key) ?? 0
        }
        insertionOrder.removeAll { doomed.contains($0) }
    }

    /// Store a highlighted AttributedString keyed by content hash.
    func set(_ hash: String, value: AttributedString) {
        // Attributed runs cost more than UTF-8 text. The multiplier is conservative
        // bookkeeping, not an exact allocator measurement.
        let estimatedCost = String(value.characters).utf8.count * 8
        if let oldCost = costs[hash] {
            totalCost -= oldCost
        }
        if cache[hash] == nil {
            insertionOrder.append(hash)
        }
        cache[hash] = value
        costs[hash] = estimatedCost
        totalCost += estimatedCost

        while (cache.count > maxEntries || totalCost > maxEstimatedBytes),
              let oldest = insertionOrder.first {
            insertionOrder.removeFirst()
            cache.removeValue(forKey: oldest)
            totalCost -= costs.removeValue(forKey: oldest) ?? 0
        }
    }
}
