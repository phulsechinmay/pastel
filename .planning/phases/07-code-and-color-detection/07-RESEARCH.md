# Phase 7: Code and Color Detection - Research

**Researched:** 2026-02-06
**Domain:** Syntax highlighting, code/language detection heuristics, color value parsing, SwiftUI card rendering
**Confidence:** MEDIUM-HIGH

## Summary

Phase 7 adds two new content detection capabilities to the clipboard monitor: recognizing code snippets (with syntax highlighting and language badges) and recognizing color values (with visual swatches). The data model already has `detectedLanguage` and `detectedColorHex` fields (added in Phase 6), and `.code`/`.color` ContentType cases exist but currently route to plain `TextCardView`.

The primary recommendation is to use **HighlightSwift** (by appstefan) instead of the originally planned Highlightr (by raspu). HighlightSwift is actively maintained, uses highlight.js 11.x (vs 9.x in Highlightr), returns native `AttributedString` (no conversion needed), has a `Sendable` `Highlight` class, includes a relevance score for auto-detection quality gating, and supports 60 languages with 31 themes. For code detection, use a two-phase approach: a fast regex/heuristic pre-filter to avoid false positives on prose, followed by highlight.js auto-detection with relevance threshold gating. For color detection, use Swift Regex to match hex (#RGB, #RRGGBB), rgb(), rgba(), hsl(), hsla() patterns, then normalize to 6-digit hex for storage and NSColor conversion.

**Primary recommendation:** Use HighlightSwift (not raspu/Highlightr) for syntax highlighting; implement a multi-signal pre-filter before delegating to highlight.js auto-detection; use Swift Regex for color parsing with normalization to hex.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| [HighlightSwift](https://github.com/appstefan/HighlightSwift) | 1.1.0 | Syntax highlighting + language auto-detection | Sendable, native AttributedString, highlight.js 11.x, 60 languages, 31 dark themes, relevance scoring, macOS 13+ |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Swift Regex (stdlib) | Swift 5.7+ | Color value pattern matching | Hex/RGB/HSL detection regex patterns |
| NSColor (AppKit) | macOS 14 | Color swatch rendering from parsed values | Converting detected hex to displayable color |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| HighlightSwift | raspu/Highlightr | Highlightr uses ancient highlight.js 9.13.4 (security concerns), returns NSAttributedString (needs conversion), not Sendable, maintenance unclear. Roadmap originally said "Highlightr" but HighlightSwift is the better choice in 2026. |
| HighlightSwift | smittytone/HighlighterSwift | More updated than raspu (hljs 11.9.0), but less SwiftUI-native than HighlightSwift. No built-in `AttributedString` return; uses NSAttributedString API. No relevance scoring API. |
| HighlightSwift | JohnSundell/Splash | Swift-only syntax highlighting. No multi-language support. Not suitable for a clipboard manager that must handle all languages. |
| Swift Regex | NSRegularExpression | Swift Regex is type-safe, more readable. NSRegularExpression is legacy but works. Either is fine; prefer Swift Regex for consistency with Swift 6 codebase. |

**Installation (SPM in Xcode):**
Add package dependency: `https://github.com/appstefan/HighlightSwift.git` from version `1.1.0`.
In Xcode: File > Add Package Dependencies > enter URL > set "Up to Next Major Version" from 1.1.0.

Note: Like KeyboardShortcuts and LaunchAtLogin, add via Xcode project (not Package.swift) since the project uses Xcode as primary build system.

## Architecture Patterns

### Recommended File Structure
```
Pastel/
├── Services/
│   ├── CodeDetectionService.swift    # Multi-signal code heuristic + HighlightSwift wrapper
│   └── ColorDetectionService.swift   # Regex-based color parsing + hex normalization
├── Views/Panel/
│   ├── CodeCardView.swift            # Syntax-highlighted preview + language badge
│   └── ColorCardView.swift           # Color swatch + text display
└── (existing files modified)
    ├── Services/ClipboardMonitor.swift  # Wire detection into processPasteboardContent()
    └── Views/Panel/ClipboardCardView.swift  # Route .code/.color to new card views
```

### Pattern 1: Two-Phase Code Detection (Pre-filter + highlight.js)
**What:** First run a fast heuristic check to determine if text is likely code, then use HighlightSwift's auto-detection for language identification and relevance scoring.
**When to use:** Every time text is captured from the clipboard (in `processPasteboardContent()`).
**Why:** highlight.js auto-detection has known false positive issues with short text -- it will try to match prose as YAML, Properties, or other loose-syntax languages. A pre-filter prevents these false positives.

```swift
// Phase 1: Fast heuristic pre-filter (synchronous, ~microseconds)
struct CodeHeuristic {
    /// Returns true if the text has enough code-like signals to warrant language detection.
    /// Designed to reject prose/URLs/paths quickly.
    static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return false }  // Single-line text rarely is code

        var score = 0

        // Signal 1: Contains common code punctuation patterns
        let codePunctuation = CharacterSet(charactersIn: "{}()[];=<>")
        let punctuationDensity = Double(text.unicodeScalars.filter { codePunctuation.contains($0) }.count) / Double(text.count)
        if punctuationDensity > 0.03 { score += 1 }

        // Signal 2: Contains programming keywords
        let keywords = ["func ", "def ", "class ", "import ", "return ", "if ", "for ", "while ",
                        "let ", "var ", "const ", "public ", "private ", "static ", "void ",
                        "#include", "#import", "function ", "async ", "await "]
        if keywords.contains(where: { text.contains($0) }) { score += 2 }

        // Signal 3: Consistent indentation (spaces or tabs at line starts)
        let indentedLines = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }
        if Double(indentedLines.count) / Double(lines.count) > 0.3 { score += 1 }

        // Signal 4: Line-ending semicolons or braces
        let codeLineEndings = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix(";") || trimmed.hasSuffix("{") || trimmed.hasSuffix("}")
        }
        if Double(codeLineEndings.count) / Double(lines.count) > 0.2 { score += 1 }

        // Signal 5: CamelCase or snake_case identifiers
        let camelCase = try? Regex("[a-z][a-zA-Z]+[A-Z][a-zA-Z]+")
        let snakeCase = try? Regex("[a-z]+_[a-z]+")
        if let camelCase, text.contains(camelCase) { score += 1 }
        if let snakeCase, text.contains(snakeCase) { score += 1 }

        return score >= 3
    }
}

// Phase 2: HighlightSwift language detection (async, ~50ms for 500 lines)
let highlight = Highlight()
let result = try await highlight.request(text)
// result.relevance: Int -- higher means more confident
// result.language: String -- detected language identifier
// Threshold: relevance >= 5 to classify as code (avoids low-confidence matches)
```

### Pattern 2: Color Detection with Regex + Normalization
**What:** Match standalone color values using regex patterns for hex, rgb(), rgba(), hsl(), hsla(). Normalize all to 6-digit hex for storage in `detectedColorHex`.
**When to use:** After text capture, before code detection (since color values are simpler to detect and should take priority).

```swift
struct ColorDetectionService {
    /// Attempts to detect a standalone color value in the text.
    /// Returns a 6-digit hex string (no #) if found, nil otherwise.
    /// Only matches if the ENTIRE trimmed text is a color value (not embedded in prose).
    static func detectColor(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip multi-line text (not a standalone color value)
        guard !trimmed.contains("\n") else { return nil }

        // Try hex patterns: #RGB, #RRGGBB, #RRGGBBAA
        if let hex = matchHex(trimmed) { return hex }

        // Try rgb()/rgba()
        if let hex = matchRGB(trimmed) { return hex }

        // Try hsl()/hsla()
        if let hex = matchHSL(trimmed) { return hex }

        return nil
    }

    private static func matchHex(_ text: String) -> String? {
        // Match #RGB, #RRGGBB (ignore #RRGGBBAA for simplicity)
        let hexPattern = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/
        guard let match = text.wholeMatch(of: hexPattern) else { return nil }
        let hex = String(match.1)
        if hex.count == 3 {
            // Expand #RGB to RRGGBB
            return hex.map { "\($0)\($0)" }.joined()
        }
        return hex.uppercased()
    }

    private static func matchRGB(_ text: String) -> String? {
        // Match rgb(R, G, B) or rgba(R, G, B, A)
        let rgbPattern = /^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*[\d.]+\s*)?\)$/
        guard let match = text.wholeMatch(of: rgbPattern) else { return nil }
        guard let r = Int(match.1), let g = Int(match.2), let b = Int(match.3),
              (0...255).contains(r), (0...255).contains(g), (0...255).contains(b) else { return nil }
        return String(format: "%02X%02X%02X", r, g, b)
    }

    private static func matchHSL(_ text: String) -> String? {
        // Match hsl(H, S%, L%) or hsla(H, S%, L%, A)
        let hslPattern = /^hsla?\(\s*(\d{1,3})\s*,\s*(\d{1,3})%\s*,\s*(\d{1,3})%\s*(?:,\s*[\d.]+\s*)?\)$/
        guard let match = text.wholeMatch(of: hslPattern) else { return nil }
        guard let h = Int(match.1), let s = Int(match.2), let l = Int(match.3),
              (0...360).contains(h), (0...100).contains(s), (0...100).contains(l) else { return nil }
        // Convert HSL to RGB, then to hex
        let color = NSColor(hue: CGFloat(h) / 360.0,
                           saturation: CGFloat(s) / 100.0,
                           brightness: CGFloat(l) / 100.0,  // Note: NSColor uses HSB not HSL
                           alpha: 1.0)
        // Proper HSL->RGB conversion needed (NSColor uses HSB)
        // See "Don't Hand-Roll" section
        return hslToHex(h: h, s: s, l: l)
    }
}
```

### Pattern 3: Detection Integration into ClipboardMonitor
**What:** After capturing text/richText content, run color detection first (synchronous, fast), then code detection (async via HighlightSwift). Update the ClipboardItem's type, detectedLanguage, and detectedColorHex fields before saving.
**When to use:** In `processPasteboardContent()` after reading text content but before inserting the item.

```swift
// In ClipboardMonitor.processPasteboardContent(), after text is read:

// 1. Color detection (synchronous, runs first)
if let colorHex = ColorDetectionService.detectColor(primaryContent) {
    item.type = .color
    item.detectedColorHex = colorHex
}
// 2. Code detection (only if not already classified as color or URL)
else if contentType == .text || contentType == .richText {
    if CodeHeuristic.looksLikeCode(primaryContent) {
        // Run HighlightSwift detection asynchronously
        // Option A: Fire-and-forget async update after insert
        // Option B: Detect before insert (adds ~50ms latency per capture)
        // Recommendation: Detect before insert for data consistency
        item.type = .code
        item.detectedLanguage = detectedLanguage
    }
}
```

### Pattern 4: Cached AttributedString for CodeCardView
**What:** Syntax highlighting is expensive (~50ms). Cache the highlighted `AttributedString` in memory so scrolling through cards doesn't re-highlight on every view appearance.
**When to use:** In CodeCardView, compute highlighting once and cache by content hash.

```swift
// Simple actor-based cache
actor HighlightCache {
    static let shared = HighlightCache()
    private var cache: [String: AttributedString] = [:]  // contentHash -> highlighted

    func get(_ hash: String) -> AttributedString? { cache[hash] }
    func set(_ hash: String, value: AttributedString) {
        cache[hash] = value
        // Evict old entries if cache grows too large
        if cache.count > 200 { /* LRU eviction */ }
    }
}
```

### Anti-Patterns to Avoid
- **Running highlight.js on every text capture without pre-filtering:** highlight.js auto-detection is slow (~50ms) and produces false positives on short prose. Always pre-filter with the heuristic.
- **Storing highlighted AttributedString in SwiftData:** AttributedString is not directly persistable in SwiftData. Store only the raw text + detected language; re-highlight on display.
- **Blocking the main thread with highlight.js:** The JavaScriptCore-based highlighting runs synchronously inside HighlightSwift's async wrapper. Ensure it's called with `await` from a background-compatible context.
- **Using NSColor(hue:saturation:brightness:) for HSL conversion:** NSColor uses HSB (Hue-Saturation-Brightness), not HSL (Hue-Saturation-Lightness). These are different color models. Must implement proper HSL-to-RGB conversion.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Syntax highlighting | Custom regex-based highlighter | HighlightSwift (highlight.js) | 185+ language grammars, years of edge-case tuning, theme system, relevance scoring |
| Language detection | Keyword-counting classifier | highlight.js `highlightAuto` via HighlightSwift | highlight.js has relevance-weighted grammar matching across all supported languages |
| HSL to RGB conversion | Naive formula | Proper algorithm with intermediate chroma/hue mapping | HSL-to-RGB involves piecewise functions; off-by-one in hue sector selection causes wrong colors. Use a well-tested implementation. |
| NSAttributedString -> SwiftUI | Manual attribute parsing | HighlightSwift returns native `AttributedString` | HighlightSwift handles the HTML->NSAttributedString->AttributedString pipeline internally |

**Key insight:** Syntax highlighting and language detection are deeply intertwined in highlight.js -- the same pass that detects the language also produces the highlighting. Don't separate detection from highlighting; use the same library for both.

## Common Pitfalls

### Pitfall 1: False Positive Code Detection on Short Text
**What goes wrong:** highlight.js auto-detection classifies short prose as YAML, Properties, or other loose-syntax languages. A user copies "Hello world" and gets a code card.
**Why it happens:** highlight.js tries all grammars and picks the one with highest relevance. Simple key-value-like text scores non-zero in YAML/Properties grammars.
**How to avoid:**
1. Require minimum 2 lines for code detection (single-line text is almost never a meaningful code snippet)
2. Run the heuristic pre-filter before highlight.js
3. Require highlight.js relevance score >= 5 (HighlightSwift marks language name with "?" when relevance <= 5)
4. Never classify concealed items as code (password managers)
**Warning signs:** During testing, copy short phrases and check they remain `.text` type.

### Pitfall 2: Color Detection Too Greedy
**What goes wrong:** Text containing a hex-like string (e.g., "Error code #FF5733 occurred") is classified as a color.
**Why it happens:** Regex matches the hex pattern within larger text.
**How to avoid:** Only match color values when the ENTIRE trimmed text is a color value. Use `wholeMatch` (Swift Regex) or anchor with `^...$`. This means "Copy #FF5733" won't match, but copying just "#FF5733" will.
**Warning signs:** Copy sentences containing color-like substrings and verify they remain `.text`.

### Pitfall 3: HighlightSwift Async on Main Thread
**What goes wrong:** ClipboardMonitor is `@MainActor`. Calling `await highlight.request()` on the main actor blocks the main thread during JavaScriptCore execution.
**Why it happens:** `Highlight` is `Sendable` and its methods are async, but the underlying JavaScriptCore work is CPU-bound.
**How to avoid:**
- Option A: Detect code asynchronously after the item is saved (fire-and-forget update). The card initially shows as `.text`, then updates to `.code` once detection completes.
- Option B: Wrap the detection in `Task.detached` to run off the main actor, then update the item back on main actor.
- Recommendation: Option A is simpler and avoids adding latency to clipboard capture. The item saves immediately, and the code detection task updates `contentType` and `detectedLanguage` shortly after.
**Warning signs:** UI jank when rapidly copying text snippets.

### Pitfall 4: SwiftData Model Updates from Background
**What goes wrong:** If code detection runs in a background Task, updating the ClipboardItem from a non-main-actor context causes SwiftData threading violations.
**Why it happens:** SwiftData ModelContext is not thread-safe. The model must be modified on the same actor that owns the context.
**How to avoid:** Run the detection on a background thread, but dispatch the model update back to `@MainActor`:
```swift
Task.detached {
    let result = try await highlight.request(text)
    await MainActor.run {
        item.type = .code
        item.detectedLanguage = result.language
        try? modelContext.save()
    }
}
```
**Warning signs:** Crashes with "SwiftData: model context accessed from wrong thread."

### Pitfall 5: Detection Order Matters (Color Before Code)
**What goes wrong:** `rgb(255, 87, 51)` could be detected as code (it contains parentheses, commas -- scoring on code heuristics).
**Why it happens:** The code heuristic's punctuation density check counts `()` as code punctuation.
**How to avoid:** Always run color detection FIRST. If text matches a color pattern, skip code detection entirely. Color patterns are more specific (exact format match) while code patterns are heuristic (approximate).
**Warning signs:** Color values showing as code cards instead of color cards.

### Pitfall 6: HSL vs HSB Confusion
**What goes wrong:** Using `NSColor(hue:saturation:brightness:)` to convert HSL values produces wrong colors. A user copies `hsl(0, 100%, 50%)` (pure red) but the swatch shows a different color.
**Why it happens:** NSColor uses HSB (Hue-Saturation-Brightness), where Brightness=1.0 is full color. HSL uses Lightness, where Lightness=0.5 is full color and Lightness=1.0 is white.
**How to avoid:** Implement proper HSL-to-RGB-to-hex conversion. The conversion formula:
```
if S == 0: R = G = B = L
else:
  q = L < 0.5 ? L * (1 + S) : L + S - L * S
  p = 2 * L - q
  R = hueToRGB(p, q, H + 1/3)
  G = hueToRGB(p, q, H)
  B = hueToRGB(p, q, H - 1/3)
```
**Warning signs:** HSL colors don't match expected appearance.

## Code Examples

Verified patterns from official sources and codebase analysis:

### HighlightSwift Basic Usage
```swift
// Source: https://github.com/appstefan/HighlightSwift README
import HighlightSwift

let highlight = Highlight()

// Auto-detect language and highlight
let result: HighlightResult = try await highlight.request(codeString)
// result.attributedText: AttributedString (ready for SwiftUI Text())
// result.language: String (e.g., "swift", "python")
// result.relevance: Int (higher = more confident)
// result.languageName: String (e.g., "Swift" or "Python?" if low relevance)
// result.backgroundColor: Color

// With explicit language
let attributed = try await highlight.attributedText(
    codeString,
    language: "swift",
    colors: .dark(.atomOne)  // Always-dark theme
)
```

### SwiftUI Text with AttributedString
```swift
// Source: Apple docs, SwiftUI Text init(AttributedString)
struct CodePreview: View {
    let attributedCode: AttributedString

    var body: some View {
        Text(attributedCode)
            .font(.system(.caption, design: .monospaced))
            .lineLimit(6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

### Language Badge
```swift
// Language badge similar to GitHub's style
struct LanguageBadge: View {
    let language: String

    var body: some View {
        Text(language)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }
}
```

### Color Swatch in SwiftUI
```swift
// Source: Codebase pattern (URLCardView HStack style)
struct ColorSwatchView: View {
    let hexColor: String  // 6-digit hex, no #

    private var color: Color {
        let scanner = Scanner(string: hexColor)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .frame(width: 32, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}
```

### Hex Color from NSColor (for HSL conversion result)
```swift
extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "000000" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
```

### ClipboardCardView Routing Update
```swift
// Source: Existing codebase pattern in ClipboardCardView.contentPreview
@ViewBuilder
private var contentPreview: some View {
    switch item.type {
    case .text, .richText:
        TextCardView(item: item)
    case .url:
        URLCardView(item: item)
    case .image:
        ImageCardView(item: item)
    case .file:
        FileCardView(item: item)
    case .code:
        CodeCardView(item: item)   // NEW: was TextCardView
    case .color:
        ColorCardView(item: item)  // NEW: was TextCardView
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| raspu/Highlightr (highlight.js 9.x) | HighlightSwift (highlight.js 11.x) | 2024 | Modern API, Sendable, native AttributedString, security patches |
| NSAttributedString for SwiftUI text | AttributedString (Swift 5.5+) | 2021 | Direct SwiftUI Text() support, no NSViewRepresentable needed |
| NSRegularExpression for pattern matching | Swift Regex (Swift 5.7+) | 2022 | Type-safe, readable, compile-time checked patterns |
| Highlightr returns NSAttributedString | HighlightSwift returns AttributedString | 2024 | No manual conversion, direct use in SwiftUI |

**Deprecated/outdated:**
- raspu/Highlightr: Uses highlight.js 9.13.4 (released ~2018). Earlier versions of highlight.js have known security issues. The library itself still builds but is not actively maintained. The roadmap mentioned "Highlightr" generically -- HighlightSwift is the modern successor in this space.

## Open Questions

Things that couldn't be fully resolved:

1. **HighlightSwift Swift 6 strict concurrency**
   - What we know: Package.swift uses Swift tools 5.10 with experimental "StrictConcurrency" enabled. The `Highlight` class is `Sendable`. The package does NOT declare `.swiftLanguageMode(.v6)`.
   - What's unclear: Whether importing it into a Swift 6 project produces concurrency warnings or errors. The project uses `swiftLanguageMode(.v6)` in Package.swift.
   - Recommendation: Add the SPM dependency and verify it builds without errors in the Xcode project. If there are concurrency warnings, use `@preconcurrency import HighlightSwift`. This is a validation step for Plan 07-02, not a blocker.

2. **Optimal relevance threshold for code detection**
   - What we know: HighlightSwift marks language names with "?" when relevance <= 5. highlight.js relevance is based on matched grammar keywords/patterns. Short snippets often have low relevance.
   - What's unclear: What threshold produces the best false-positive vs false-negative tradeoff for clipboard content (which varies from 1-line commands to full functions).
   - Recommendation: Start with relevance >= 5 as the threshold (matching HighlightSwift's own "uncertain" marker). Tune during testing with real-world clipboard data. Consider making this a configurable constant.

3. **Async detection timing**
   - What we know: ClipboardMonitor is @MainActor. HighlightSwift `request()` is async. Clipboard polling is every 0.5s.
   - What's unclear: Whether detection should happen before or after initial save. Before-save is simpler for data consistency but adds latency. After-save requires a follow-up model update.
   - Recommendation: Use the fire-and-forget pattern (save as .text first, then update to .code asynchronously). This keeps clipboard capture fast. The card view can handle the transition gracefully (show as text briefly, then update to code card). The 0.5s polling interval gives ~450ms headroom for detection before the next poll.

4. **HighlightSwift theme choice for always-dark panel**
   - What we know: 31 themes available, each with dark/light variants. The app uses always-dark vibrancy panel.
   - What's unclear: Which dark theme looks best on the dark vibrancy background.
   - Recommendation: Start with `.dark(.atomOne)` (Atom One Dark is a well-known dark code theme). Can be tuned visually during Plan 07-02 implementation. Other good candidates: `.dark(.github)`, `.dark(.tokyoNight)`, `.dark(.horizon)`.

## Sources

### Primary (HIGH confidence)
- [HighlightSwift GitHub](https://github.com/appstefan/HighlightSwift) - README, Package.swift, source files (Highlight.swift, HighlightResult.swift, HighlightLanguage.swift, HighlightTheme.swift)
- [highlight.js Core API docs](https://highlightjs.readthedocs.io/en/latest/api.html) - highlightAuto API, relevance scoring
- [highlight.js auto-detection discussion](https://github.com/highlightjs/highlight.js/issues/1213) - Known false positive issues, relevance score challenges
- Existing codebase files: ContentType.swift, ClipboardItem.swift, ClipboardMonitor.swift, ClipboardCardView.swift, TextCardView.swift, URLCardView.swift

### Secondary (MEDIUM confidence)
- [raspu/Highlightr GitHub](https://github.com/raspu/Highlightr) - API reference, Package.swift (Swift tools 5.3, hljs 9.x)
- [HighlighterSwift comparison](https://smittytone.net/highlighterswift/) - Highlightr vs HighlighterSwift maintenance status
- [CSS color regex patterns](https://gist.github.com/olmokramer/82ccce673f86db7cda5e) - Hex/RGB/HSL regex patterns
- [Highlightr build error #83](https://github.com/raspu/Highlightr/issues/83) - strtoul compatibility issue
- [Swift Regex builder proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0351-regex-builder.md) - Swift Regex API reference

### Tertiary (LOW confidence)
- Web search results for code detection heuristics (no single authoritative source; patterns synthesized from multiple community resources)
- Web search for clipboard manager code detection approaches (limited specific results)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - HighlightSwift source verified, API documented, Sendable confirmed, themes enumerated
- Architecture: MEDIUM-HIGH - Detection patterns follow established highlight.js usage; integration with existing codebase is well-understood from reading source files; async timing pattern needs validation
- Pitfalls: HIGH - highlight.js false positives documented in official issue tracker; HSL/HSB confusion is well-known; SwiftData threading is documented in project memory
- Color detection: HIGH - Regex patterns are straightforward and well-established; only concern is HSL conversion formula correctness

**Research date:** 2026-02-06
**Valid until:** 2026-03-06 (30 days -- stable domain, libraries unlikely to change)
