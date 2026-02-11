@preconcurrency import HighlightSwift
import SwiftUI

/// Card content for `.code` clipboard items with syntax-highlighted text
/// and a language badge.
///
/// Highlights code asynchronously using HighlightSwift and caches the result
/// in `HighlightCache` so re-scrolling does not re-highlight. Falls back to
/// plain monospaced text while the async highlighting loads.
///
/// Line limits adapt to panel orientation: 6 lines for vertical (left/right),
/// 10 lines for horizontal (top/bottom).
struct CodeCardView: View {

    let item: ClipboardItem
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

    @State private var highlightedText: AttributedString?

    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    private var lineLimit: Int {
        isHorizontal ? 10 : 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Code preview: highlighted or plain fallback
            codePreview

            // Language badge (shown when detected)
            if let language = item.detectedLanguage, !language.isEmpty {
                LanguageBadge(language: language)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: item.contentHash) {
            await loadHighlighting()
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private var codePreview: some View {
        if let highlighted = highlightedText {
            Text(highlighted)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Plain text fallback while highlighting loads
            Text(item.textContent ?? "")
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(lineLimit)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Highlighting

    /// Load syntax highlighting from cache or compute it.
    private func loadHighlighting() async {
        let hash = item.contentHash
        let code = item.textContent ?? ""
        guard !code.isEmpty else { return }

        // Check cache first
        if let cached = await HighlightCache.shared.get(hash) {
            highlightedText = cached
            return
        }

        // Highlight with HighlightSwift
        do {
            let highlight = Highlight()
            let result: AttributedString
            if let language = item.detectedLanguage, !language.isEmpty {
                // Use known language for precise highlighting
                result = try await highlight.attributedText(
                    code,
                    language: language,
                    colors: .dark(.atomOne)
                )
            } else {
                // Auto-detect language
                let highlightResult = try await highlight.request(code, mode: .automatic, colors: .dark(.atomOne))
                result = highlightResult.attributedText
            }

            // Cache and display
            await HighlightCache.shared.set(hash, value: result)
            highlightedText = result
        } catch {
            // On error, keep showing plain text fallback (highlightedText stays nil)
        }
    }
}

// MARK: - Language Badge

/// A small capsule badge showing the detected programming language icon and display name.
///
/// Uses Devicon SVG icons from the asset catalog when available (`LanguageIcons/lang-*`),
/// falling back to a generic code symbol for languages without a dedicated icon.
private struct LanguageBadge: View {
    let language: String

    var body: some View {
        HStack(spacing: 4) {
            if let iconName = iconAssetName {
                Image(iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text(displayName)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.15), in: Capsule())
        .foregroundStyle(.secondary)
    }

    /// Human-readable display name for highlight.js language identifiers.
    private var displayName: String {
        switch language.lowercased() {
        case "csharp", "cs": return "C#"
        case "cpp", "c++": return "C++"
        case "objectivec", "objc": return "Objective-C"
        case "javascript", "js": return "JavaScript"
        case "typescript", "ts": return "TypeScript"
        case "fsharp", "fs": return "F#"
        case "golang": return "Go"
        case "dockerfile": return "Docker"
        case "powershell", "ps1": return "PowerShell"
        case "yml": return "YAML"
        case "graphql", "gql": return "GraphQL"
        case "plaintext": return "Text"
        default: return language.capitalized
        }
    }

    /// Asset catalog name for the language icon, or nil if no icon is available.
    ///
    /// Maps highlight.js language identifiers to `LanguageIcons/lang-*` asset names.
    /// Languages without a dedicated Devicon icon (e.g., SQL, YAML, JSON) return nil
    /// and the badge falls back to a generic SF Symbol.
    private var iconAssetName: String? {
        let key = language.lowercased()
        switch key {
        case "swift": return "LanguageIcons/lang-swift"
        case "python": return "LanguageIcons/lang-python"
        case "javascript", "js": return "LanguageIcons/lang-javascript"
        case "typescript", "ts": return "LanguageIcons/lang-typescript"
        case "rust": return "LanguageIcons/lang-rust"
        case "go", "golang": return "LanguageIcons/lang-go"
        case "ruby": return "LanguageIcons/lang-ruby"
        case "java": return "LanguageIcons/lang-java"
        case "kotlin": return "LanguageIcons/lang-kotlin"
        case "csharp", "cs": return "LanguageIcons/lang-csharp"
        case "cpp", "c++": return "LanguageIcons/lang-cpp"
        case "c": return "LanguageIcons/lang-c"
        case "objectivec", "objc": return "LanguageIcons/lang-c" // closest match
        case "php": return "LanguageIcons/lang-php"
        case "r": return "LanguageIcons/lang-r"
        case "lua": return "LanguageIcons/lang-lua"
        case "perl": return "LanguageIcons/lang-perl"
        case "scala": return "LanguageIcons/lang-scala"
        case "elixir": return "LanguageIcons/lang-elixir"
        case "haskell": return "LanguageIcons/lang-haskell"
        case "dart": return "LanguageIcons/lang-dart"
        case "html": return "LanguageIcons/lang-html"
        case "css", "scss", "sass", "less": return "LanguageIcons/lang-css"
        case "bash", "shell", "sh", "zsh": return "LanguageIcons/lang-bash"
        case "dockerfile": return "LanguageIcons/lang-docker"
        case "graphql", "gql": return "LanguageIcons/lang-graphql"
        default: return nil
        }
    }
}
