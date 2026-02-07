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

/// A small capsule badge showing the detected programming language name.
private struct LanguageBadge: View {
    let language: String

    var body: some View {
        Text(language.capitalized)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }
}
