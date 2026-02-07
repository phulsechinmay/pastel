# Stack Research: v1.1 Rich Content & Enhanced Paste

**Domain:** Native macOS Clipboard Manager -- Stack Additions
**Project:** Pastel
**Researched:** 2026-02-07
**Confidence:** MEDIUM-HIGH

> **Note on sources:** WebSearch and WebFetch were unavailable during this research session. Recommendations are based on: (1) direct inspection of the Pastel codebase and all source files, (2) direct inspection of the checked-out KeyboardShortcuts v2.4.0 source code in `.build/checkouts/`, (3) the resolved Package.resolved confirming exact dependency versions, and (4) training knowledge of Apple's frameworks and the macOS ecosystem. Apple's first-party frameworks are stable APIs. Third-party library versions should be verified against current GitHub releases before adding to `project.yml`.

> **Scope:** This document covers ONLY the stack additions needed for v1.1. The existing v1.0 stack is validated and unchanged.

---

## Existing Stack (Validated, No Changes)

| Technology | Version | Purpose | Status |
|------------|---------|---------|--------|
| Swift 6.0 | 6.0 | Primary language | Validated |
| SwiftUI + AppKit hybrid | macOS 14+ | UI framework | Validated |
| SwiftData | macOS 14+ | Persistence | Validated |
| KeyboardShortcuts (sindresorhus) | 2.4.0 (from Package.resolved) | Panel toggle hotkey + recorder | Validated |
| LaunchAtLogin-Modern (sindresorhus) | 1.1.0 (from Package.resolved) | Login item | Validated |
| NSPanel + NSHostingView | AppKit | Non-activating sliding panel | Validated |
| CGEvent Cmd+V | CoreGraphics | Paste simulation | Validated |
| NSPasteboard polling (0.5s) | AppKit | Clipboard monitoring | Validated |
| XcodeGen (project.yml) | -- | Project generation | Validated |

---

## New Stack Additions for v1.1

### 1. Syntax Highlighting for Code Snippets

**Recommendation: Highlightr (raspu/Highlightr)**

| Attribute | Value |
|-----------|-------|
| Library | [Highlightr](https://github.com/raspu/Highlightr) |
| SPM | `from: "2.2.0"` (VERIFY on GitHub -- training data version) |
| Platform | macOS, iOS |
| License | MIT |
| Approach | Wraps highlight.js -- 190+ languages, 90+ themes, auto-detection |
| Confidence | MEDIUM |

**Why Highlightr over Splash:**

A clipboard manager captures code from ANY language -- Swift, Python, JavaScript, Go, Rust, Ruby, SQL, YAML, Dockerfile, shell scripts, and dozens more. The syntax highlighter must handle all of them.

| Criterion | Highlightr (Recommended) | Splash (JohnSundell) |
|-----------|-------------------------|---------------------|
| Language coverage | 190+ languages with individual grammars | Swift-focused tokenizer, heuristic for C-family |
| Auto language detection | Yes -- `highlightAuto()` uses highlight.js detection | No -- single tokenizer assumes Swift-like syntax |
| Ruby, Python, SQL, YAML, Shell | Correct highlighting with proper grammars | Approximate at best, broken at worst |
| Bundle size | ~2MB (highlight.js + themes) | ~50KB |
| Performance | JS evaluation via JavaScriptCore (one-time init) | Pure Swift |
| Output | `NSAttributedString` | `AttributedString` via custom OutputFormat |

**The bundle size tradeoff is worth it.** Pastel is a desktop app, not a mobile app. 2MB is negligible. The alternative -- showing broken syntax highlighting for Python or SQL -- is worse than showing slightly slower-loading correct highlighting.

**Why NOT Splash:** Splash's tokenizer is fundamentally designed for Swift. Its "works for C-family" claim means it recognizes braces, semicolons, and common keywords. For Python (indentation-significant, no braces, `def`/`class` keywords), Ruby (`do`/`end` blocks, `@` instance variables), SQL (`SELECT`/`FROM`/`WHERE`), YAML (colon-delimited key-value), and shell scripts (`$` variables, pipes, `if`/`fi`), Splash will produce incorrect or absent highlighting. A clipboard manager that only highlights Swift well is a poor user experience.

**Integration pattern:**
```swift
import Highlightr

// Singleton -- Highlightr loads highlight.js once (~100ms cold start)
let highlightr: Highlightr = {
    let h = Highlightr()!
    h.setTheme(to: "atom-one-dark")  // Matches Pastel's always-dark UI
    return h
}()

// Auto-detect language and highlight
func highlightCode(_ code: String) -> NSAttributedString? {
    // highlightAuto returns (result: NSAttributedString?, language: String?)
    return highlightr.highlight(code)
}
```

**SwiftUI rendering for code cards:**
- For 4-8 line preview cards: convert `NSAttributedString` to `AttributedString`, use `Text(attributedString)`.
- For scrollable full-code views (if ever needed): bridge `NSTextView` via `NSViewRepresentable`.

**Cold start mitigation:** Initialize `Highlightr()` once at app launch in `AppState`, not per-card render. The highlight.js runtime loads in ~100ms on first call, then subsequent highlights are fast (<5ms for typical clipboard-sized code).

#### Code Detection Heuristic (No Library Needed)

Detection happens at capture time in `ClipboardMonitor.processPasteboardContent()`. Use a scoring heuristic:

```swift
func isLikelyCode(_ text: String) -> Bool {
    let lines = text.components(separatedBy: .newlines)
    guard lines.count >= 2 else { return false }

    var score = 0

    // Structural indicators
    if text.contains("{") && text.contains("}") { score += 2 }
    if text.contains(";") { score += 1 }

    // Indentation (2+ spaces or tabs)
    let indentedLines = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }
    if indentedLines.count > lines.count / 3 { score += 2 }

    // Language keywords
    let keywords = ["func ", "def ", "class ", "import ", "const ", "let ", "var ",
                     "return ", "if ", "else ", "for ", "while ", "fn ", "pub ",
                     "function ", "async ", "await ", "struct ", "enum ", "interface "]
    for keyword in keywords where text.contains(keyword) { score += 1; break }

    // Comment patterns
    if text.contains("//") || text.contains("/*") || text.contains("# ") { score += 1 }

    return score >= 3
}
```

**False positive avoidance:** Score threshold of 3 means casual text with a semicolon or brace won't trigger. False negatives (missing some code) are acceptable -- the item shows as plain text, which is still usable.

**Confidence:** MEDIUM for Highlightr (verify maintenance status, SPM version, Swift 6 compatibility on GitHub). HIGH for code detection heuristic (standard pattern, no dependencies).

---

### 2. URL Metadata Fetching (Open Graph)

**Recommendation: Apple's LinkPresentation framework (LPMetadataProvider)**

| Attribute | Value |
|-----------|-------|
| Framework | LinkPresentation (Apple first-party) |
| Import | `import LinkPresentation` |
| Availability | macOS 10.15+ (well within our 14.0 target) |
| Dependency | None -- ships with macOS |
| Confidence | HIGH |

**Why LPMetadataProvider:**

1. **Apple's official API for exactly this use case.** It extracts Open Graph metadata, page titles, favicons, and preview images from URLs.
2. **Zero dependencies.** Ships with macOS. No SPM package needed.
3. **Handles edge cases internally.** HTML encoding, relative URLs, favicon discovery from `<link>` tags, OG tag parsing, and image downloading are all handled by Apple's implementation.
4. **Async/await support.** `try await provider.startFetchingMetadata(for: url)` integrates cleanly with Swift concurrency.

**Why NOT URLSession + regex HTML parsing:**

Building a custom HTML metadata extractor requires:
- Fetching HTML with URLSession (straightforward)
- Parsing `<meta property="og:title">`, `<meta property="og:image">`, `<title>` tags (regex is fragile for HTML)
- Handling relative URLs for favicons and images
- Handling charset encoding variations
- Handling redirects, non-HTML responses, malformed HTML

This is reimplementing what `LPMetadataProvider` already does. The "control" benefit is marginal -- a clipboard manager does not need fine-grained control over metadata extraction. It needs "title + favicon + image if available, nil if not."

**Known LPMetadataProvider behaviors to handle:**
- It can be slow (2-5s) on some URLs. Solution: use a timeout and fire-and-forget. Card shows URL text immediately, updates when metadata arrives.
- It is not cancellable once started. Solution: ignore results for items that have been deleted by the time the fetch completes.
- It caches internally. For a clipboard manager this is actually beneficial -- re-copying the same URL won't trigger another network request.

**Integration pattern:**
```swift
import LinkPresentation

@MainActor
final class URLMetadataService {
    func fetchMetadata(for url: URL) async -> (title: String?, faviconData: Data?, ogImageURL: URL?) {
        let provider = LPMetadataProvider()
        provider.timeout = 5.0  // Don't hang on slow sites

        do {
            let metadata = try await provider.startFetchingMetadata(for: url)

            let title = metadata.title

            // Extract favicon data from NSItemProvider
            var faviconData: Data? = nil
            if let iconProvider = metadata.iconProvider {
                faviconData = try? await iconProvider.loadDataRepresentation(for: .png)
            }

            // Get OG image URL (download separately if needed)
            var ogImageURL: URL? = nil
            if let imageProvider = metadata.imageProvider {
                // imageProvider provides the actual image data
                // Store URL from metadata.url or download the image
            }

            return (title, faviconData, ogImageURL)
        } catch {
            return (nil, nil, nil)  // Graceful fallback to plain URL card
        }
    }
}
```

**Favicon fallback:** If LPMetadataProvider fails or returns no icon, use the Google favicon service as a reliable backup:
```
https://www.google.com/s2/favicons?domain=example.com&sz=32
```

**Data storage on ClipboardItem:**
```swift
var urlTitle: String?            // Cached page title
var urlFaviconPath: String?      // Disk path to cached favicon PNG
var urlPreviewImagePath: String? // Disk path to cached OG image
var urlMetadataFetched: Bool     // Whether fetch was attempted (default: false)
```

Store favicon/images on disk (reuse `ImageStorageService` directory) rather than inline in SwiftData. This keeps the database lean, especially with many URL items.

**Fetch strategy:**
1. When a URL item is created in `ClipboardMonitor`, fire-and-forget an async metadata fetch.
2. On completion, update the `ClipboardItem` fields and save.
3. Card view observes the model and updates automatically via SwiftData/SwiftUI binding.
4. On failure, set `urlMetadataFetched = true` to prevent re-fetching. Card falls back to globe + URL text.

**Confidence:** HIGH. LPMetadataProvider is a stable Apple framework, available since macOS 10.15, designed for exactly this use case.

---

### 3. Color Value Detection and Swatches

**Recommendation: No Library -- Pure Swift Regex + SwiftUI Color Rendering**

| Attribute | Value |
|-----------|-------|
| Dependency | None |
| Approach | Regex detection at capture time, SwiftUI `Color` for swatch |
| Confidence | HIGH |

Color detection is a well-defined string parsing problem. The formats are finite and standardized. No library needed.

**Detection patterns:**
```swift
/// Detect if text is primarily a color value (the whole string is a color)
func detectColorValue(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    // Hex: #RGB, #RRGGBB, #RRGGBBAA
    if let match = trimmed.wholeMatch(of: /^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/) {
        return normalizeToHex6(String(match.1))
    }

    // rgb(R, G, B) / rgba(R, G, B, A)
    if let match = trimmed.wholeMatch(of: /^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*[\d.]+\s*)?\)$/) {
        let r = Int(match.1)!, g = Int(match.2)!, b = Int(match.3)!
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    // hsl(H, S%, L%) / hsla(H, S%, L%, A)
    if let match = trimmed.wholeMatch(of: /^hsla?\(\s*(\d{1,3})\s*,\s*(\d{1,3})%\s*,\s*(\d{1,3})%\s*(?:,\s*[\d.]+\s*)?\)$/) {
        return hslToHex(h: Int(match.1)!, s: Int(match.2)!, l: Int(match.3)!)
    }

    return nil
}
```

**Why `wholeMatch` (entire string must be a color):** If text contains a color embedded in a larger context (e.g., `background-color: #FF5733;`), it should remain classified as `.text` (or `.code`), not `.color`. Only standalone color values get the `.color` content type. Embedded colors can optionally show a small swatch overlay but the card type does not change.

**Swatch rendering (SwiftUI):**
```swift
func colorFromHex(_ hex: String) -> Color {
    let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    var hexValue: UInt64 = 0
    Scanner(string: clean).scanHexInt64(&hexValue)
    let r = Double((hexValue >> 16) & 0xFF) / 255.0
    let g = Double((hexValue >> 8) & 0xFF) / 255.0
    let b = Double(hexValue & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
}

// ColorCardView: large swatch + text overlay
VStack(spacing: 8) {
    RoundedRectangle(cornerRadius: 8)
        .fill(colorFromHex(item.detectedColorHex ?? "#000000"))
        .frame(height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
    Text(item.textContent ?? "")
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(.secondary)
}
```

**Confidence:** HIGH. Pure Swift, no dependencies, well-understood problem space.

---

### 4. Cmd+1-9 Global Hotkeys for Direct Paste

**Recommendation: Use existing KeyboardShortcuts library (already installed, v2.4.0)**

| Attribute | Value |
|-----------|-------|
| Library | KeyboardShortcuts (sindresorhus) -- already in project |
| Version | 2.4.0 (confirmed in Package.resolved) |
| New dependency | None |
| Confidence | HIGH (verified against checked-out source code) |

**Why reuse KeyboardShortcuts (not raw Carbon):**

I inspected the checked-out KeyboardShortcuts v2.4.0 source code directly and confirmed:

1. **Key constants exist.** `Key.swift` defines `.one` through `.nine` (mapping to `kVK_ANSI_1` through `kVK_ANSI_9`).

2. **Shortcut construction works.** `Shortcut(.one, modifiers: [.command])` creates a Cmd+1 shortcut.

3. **Programmatic registration is supported.** `KeyboardShortcuts.Name("pasteSlot1", default: .init(.one, modifiers: [.command]))` registers a named shortcut with a default binding.

4. **Handler registration uses the same pattern as the existing panel toggle.** `KeyboardShortcuts.onKeyUp(for: .pasteSlot1) { ... }` -- identical to `AppState.swift` line 65.

5. **Enable/disable is supported.** `KeyboardShortcuts.enable(.pasteSlot1)` and `KeyboardShortcuts.disable(.pasteSlot1)` (confirmed in KeyboardShortcuts.swift lines 233-268) allow runtime toggling for a Settings UI.

6. **Carbon under the hood.** `CarbonKeyboardShortcuts.swift` calls `RegisterEventHotKey` -- the exact same API a raw Carbon implementation would use. There is zero performance or capability difference.

**Why NOT raw Carbon for this:**

Writing raw Carbon `RegisterEventHotKey` code directly (as suggested by some approaches) means:
- Duplicating the event handler setup that KeyboardShortcuts already manages
- Managing `EventHotKeyRef` lifecycle manually
- Handling `Unmanaged` pointer dance for the callback's `userData`
- Potentially conflicting with KeyboardShortcuts' existing Carbon event handler
- More error-prone code for the same result

KeyboardShortcuts is already installed, already manages the Carbon event handler, and provides a clean Swift API. Using it for Cmd+1-9 is strictly simpler.

**Integration pattern:**
```swift
// Define shortcut names (in AppState.swift extension)
extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.command, .shift]))
    static let pasteSlot1 = Self("pasteSlot1", default: .init(.one, modifiers: [.command]))
    static let pasteSlot2 = Self("pasteSlot2", default: .init(.two, modifiers: [.command]))
    static let pasteSlot3 = Self("pasteSlot3", default: .init(.three, modifiers: [.command]))
    static let pasteSlot4 = Self("pasteSlot4", default: .init(.four, modifiers: [.command]))
    static let pasteSlot5 = Self("pasteSlot5", default: .init(.five, modifiers: [.command]))
    static let pasteSlot6 = Self("pasteSlot6", default: .init(.six, modifiers: [.command]))
    static let pasteSlot7 = Self("pasteSlot7", default: .init(.seven, modifiers: [.command]))
    static let pasteSlot8 = Self("pasteSlot8", default: .init(.eight, modifiers: [.command]))
    static let pasteSlot9 = Self("pasteSlot9", default: .init(.nine, modifiers: [.command]))
}

// In AppState.setupPanel(), register all 9:
let slotNames: [KeyboardShortcuts.Name] = [
    .pasteSlot1, .pasteSlot2, .pasteSlot3, .pasteSlot4, .pasteSlot5,
    .pasteSlot6, .pasteSlot7, .pasteSlot8, .pasteSlot9
]
for (index, name) in slotNames.enumerated() {
    KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
        MainActor.assumeIsolated {
            self?.pasteNthItem(index: index)
        }
    }
}
```

**Critical: Cmd+1-9 conflict mitigation**

Cmd+1 through Cmd+9 are used by Safari (tabs), Chrome (tabs), Terminal (tabs), Finder (sidebar), and many other apps. Carbon `RegisterEventHotKey` intercepts globally -- other apps will NOT receive these shortcuts.

**Recommended approach:**
- **Default to DISABLED.** Unlike the panel toggle (which has no common conflict), Cmd+1-9 will break basic functionality in browsers and terminals. Opt-in is the right default.
- Add a "Quick Paste Shortcuts" toggle in Settings (General tab). When enabled, registers all 9 hotkeys. When disabled, calls `KeyboardShortcuts.disable(...)` for all 9.
- Show a warning: "Enabling quick paste shortcuts will override Cmd+1 through Cmd+9 in all apps."
- Consider offering alternative modifiers: Ctrl+1-9 or Cmd+Shift+1-9 have fewer conflicts.

**Settings UI:**
A single Toggle + informational text. Do NOT show 9 individual recorder rows -- these are fixed bindings, not user-configurable.

```swift
Toggle("Enable Quick Paste (Cmd+1-9)", isOn: $quickPasteEnabled)
    .onChange(of: quickPasteEnabled) { _, enabled in
        if enabled {
            KeyboardShortcuts.enable(slotNames)
        } else {
            KeyboardShortcuts.disable(slotNames)
        }
    }

Text("When enabled, pressing Cmd+1 pastes the most recent item, Cmd+2 the second most recent, and so on. This overrides Cmd+1-9 in other apps.")
    .font(.caption)
    .foregroundStyle(.secondary)
```

**Confidence:** HIGH. Verified directly against the checked-out KeyboardShortcuts v2.4.0 source code. Key constants, Shortcut construction, and enable/disable APIs all confirmed.

---

### 5. Label Emoji Support

**Recommendation: No Library -- SwiftUI TextField + System Emoji Picker**

| Attribute | Value |
|-----------|-------|
| Dependency | None |
| API | `NSApp.orderFrontCharacterPalette(_:)` + SwiftUI TextField |
| Availability | macOS 10.0+ |
| Confidence | HIGH |

**Model change:**
```swift
@Model
final class Label {
    var name: String
    var colorName: String
    var sortOrder: Int
    var emoji: String?  // NEW: single emoji character, nil = use color dot

    @Relationship(deleteRule: .nullify, inverse: \ClipboardItem.label)
    var items: [ClipboardItem]
    // ...
}
```

SwiftData handles lightweight migration automatically for new optional properties (they get nil default).

**Emoji input approach (in LabelSettingsView):**

A compact TextField where the user can:
1. Type or paste an emoji directly.
2. Press Ctrl+Cmd+Space (or Globe key on newer keyboards) to open the system emoji picker, which inserts into the focused TextField.

```swift
HStack(spacing: 8) {
    // Emoji field (or button to clear)
    if let emoji = label.emoji, !emoji.isEmpty {
        Button {
            label.emoji = nil  // Clear emoji, revert to color dot
            try? modelContext.save()
        } label: {
            Text(emoji)
                .font(.system(size: 18))
        }
        .buttonStyle(.plain)
        .help("Click to remove emoji")
    } else {
        TextField("", text: Binding(
            get: { label.emoji ?? "" },
            set: { newValue in
                if let first = newValue.first {
                    label.emoji = String(first)
                } else {
                    label.emoji = nil
                }
                try? modelContext.save()
            }
        ))
        .frame(width: 32)
        .help("Type an emoji or press Globe key")
    }
}
```

**Why NOT a custom emoji grid picker:**
- Adds UI complexity for a feature that users rarely change.
- The system emoji picker (Ctrl+Cmd+Space) is the standard macOS way to input emoji.
- A text field is simpler, familiar, and supports all emoji without a curated subset.

**Display in chips and cards:**
```swift
// In ChipBarView and ClipboardCardView label indicator:
if let emoji = label.emoji, !emoji.isEmpty {
    Text(emoji).font(.system(size: 12))
} else {
    Circle()
        .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
        .frame(width: 8, height: 8)
}
```

**Expanded color palette (bonus):**

Add 4 new cases to `LabelColor`. All use SwiftUI named colors available on macOS 14+:

```swift
enum LabelColor: String, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink, gray
    // New in v1.1
    case teal, indigo, brown, mint

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        case .teal: .teal
        case .indigo: .indigo
        case .brown: .brown
        case .mint: .mint
        }
    }
}
```

No migration concern -- `LabelColor` is a Swift enum used at the view layer. The database stores raw color name strings. Existing labels with old color names remain valid.

**Confidence:** HIGH. Pure SwiftUI + SwiftData, no dependencies, standard patterns.

---

## Summary: New Dependencies

### Required New SPM Dependency

| Library | Package URL | Version | Purpose | Confidence |
|---------|-------------|---------|---------|------------|
| Highlightr | `https://github.com/raspu/Highlightr` | `from: "2.2.0"` (VERIFY) | Syntax highlighting for code cards -- 190+ languages with auto-detection | MEDIUM |

### Everything Else: Zero New Dependencies

| Capability | Technology | Why No Library Needed |
|------------|-----------|----------------------|
| URL metadata | LinkPresentation (Apple framework) | Ships with macOS 10.15+; just `import LinkPresentation` |
| Color detection | Swift Regex | ~40 lines of regex patterns for hex/rgb/hsl |
| Color swatch rendering | SwiftUI `Color(red:green:blue:)` | Native SwiftUI |
| Cmd+1-9 hotkeys | KeyboardShortcuts (already installed) | v2.4.0 already in project; supports `.one`-`.nine` key constants |
| Emoji input | SwiftUI TextField + system picker | `NSApp.orderFrontCharacterPalette(_:)` built into macOS |
| Expanded label colors | SwiftUI named colors | `.teal`, `.indigo`, `.brown`, `.mint` on macOS 14+ |

**Total new third-party dependencies: 1 (Highlightr)**

---

## What NOT to Add

| Technology | Why Avoid | Use Instead |
|------------|-----------|-------------|
| Splash (JohnSundell) | Swift-focused tokenizer. Poor coverage for Python, Ruby, SQL, YAML, Shell -- common in clipboard content. | Highlightr (190+ language grammars) |
| SwiftSoup / Kanna (HTML parsers) | Over-engineering for URL metadata when LPMetadataProvider exists. | `import LinkPresentation` |
| TreeSitter (swift-tree-sitter) | Requires per-language grammar binaries, complex build integration. Designed for editors, not preview cards. | Highlightr |
| WKWebView for code rendering | Loads entire web engine per card. Performance disaster in scrolling list. | Highlightr -> NSAttributedString -> SwiftUI Text |
| Raw Carbon RegisterEventHotKey | Duplicates what KeyboardShortcuts already manages. More error-prone, potentially conflicts with existing Carbon handler. | KeyboardShortcuts (already installed) |
| Custom emoji picker libraries | macOS has a built-in one. Adding a library is unnecessary weight. | TextField + system picker |
| NSColorPanel for color swatches | Full color picker UI. We only display swatches, not pick colors. | SwiftUI `Color(red:green:blue:)` |
| OpenGraph.swift (third-party) | ~20 lines of work that LPMetadataProvider already handles. | LinkPresentation |

---

## SwiftData Model Changes

### ContentType enum additions

```swift
enum ContentType: String, Codable, CaseIterable, Sendable {
    case text
    case richText
    case url
    case image
    case file
    case code      // NEW: detected code snippet
    case color     // NEW: detected color value (standalone hex/rgb/hsl)
}
```

### ClipboardItem new fields

```swift
// Code snippet metadata
var detectedLanguage: String?       // Language from Highlightr auto-detect, e.g. "swift", "python"

// Color detection
var detectedColorHex: String?       // Normalized "#RRGGBB" value

// URL metadata (cached from LPMetadataProvider)
var urlTitle: String?               // Page title from OG or <title>
var urlFaviconPath: String?         // Disk path to cached favicon image
var urlPreviewImagePath: String?    // Disk path to cached OG image
var urlMetadataFetched: Bool        // Whether fetch was attempted (default: false)
```

### Label new field

```swift
var emoji: String?                  // Single emoji character; nil = use color dot
```

**Migration:** All new fields are optional or have default values (`urlMetadataFetched` defaults to `false`). SwiftData automatic lightweight migration handles this with no manual migration code.

---

## project.yml Changes

```yaml
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: "2.4.0"
  LaunchAtLogin:
    url: https://github.com/sindresorhus/LaunchAtLogin-Modern
    from: "1.1.0"
  Highlightr:                                    # NEW for v1.1
    url: https://github.com/raspu/Highlightr
    from: "2.2.0"                                # VERIFY on GitHub before adding

targets:
  Pastel:
    dependencies:
      - package: KeyboardShortcuts
      - package: LaunchAtLogin
      - package: Highlightr                      # NEW
```

---

## Integration Points with Existing Code

| Existing File | Change Needed | Reason |
|---------------|---------------|--------|
| `Models/ContentType.swift` | Add `.code` and `.color` cases | New content types |
| `Models/ClipboardItem.swift` | Add 6 new optional properties | Code language, color hex, URL metadata |
| `Models/Label.swift` | Add `emoji: String?` | Emoji label support |
| `Models/LabelColor.swift` | Add `.teal`, `.indigo`, `.brown`, `.mint` cases | Expanded palette |
| `Services/ClipboardMonitor.swift` | Call code/color detection after text classification; trigger async URL metadata fetch for URL items | Enrichment at capture time |
| `App/AppState.swift` | Register Cmd+1-9 handlers via KeyboardShortcuts; add `pasteNthItem(index:)`; initialize Highlightr singleton | Quick paste + highlighting |
| `Views/Panel/ClipboardCardView.swift` | Add `.code` and `.color` cases to `contentPreview` switch | Route to new card subviews |
| `Views/Panel/URLCardView.swift` | Enhance to show `urlTitle`, favicon, OG image when available | Rich URL cards |
| `Views/Panel/ChipBarView.swift` | Show emoji instead of color dot when `label.emoji != nil` | Emoji labels |
| `Views/Settings/LabelSettingsView.swift` | Add emoji input field to label row | Emoji label management |
| `Views/Settings/GeneralSettingsView.swift` | Add "Quick Paste Shortcuts" toggle section | Cmd+1-9 enable/disable |

### New Files to Create

| File | Purpose | Dependencies |
|------|---------|--------------|
| `Services/CodeDetectionService.swift` | Heuristic code detection scoring | None (pure Swift) |
| `Services/ColorDetectionService.swift` | Regex color detection + hex normalization | Foundation |
| `Services/URLMetadataService.swift` | Async LPMetadataProvider fetch + disk caching | LinkPresentation, ImageStorageService |
| `Views/Panel/CodeCardView.swift` | Syntax-highlighted code preview card | Highlightr |
| `Views/Panel/ColorCardView.swift` | Color swatch + hex/rgb text display | SwiftUI |

---

## Confidence Assessment

| Area | Confidence | Reason |
|------|------------|--------|
| Cmd+1-9 via KeyboardShortcuts | HIGH | Verified against checked-out source code; Key.one-.nine confirmed, enable/disable API confirmed |
| URL metadata via LPMetadataProvider | HIGH | Apple first-party framework, stable since macOS 10.15 |
| Color detection via regex | HIGH | Pure Swift, well-defined format space |
| Emoji for labels | HIGH | SwiftData optional property + SwiftUI TextField |
| Expanded label colors | HIGH | SwiftUI named colors on macOS 14+ |
| Highlightr for syntax highlighting | MEDIUM | Well-known library, but current version/maintenance unverified (WebSearch unavailable) |
| SwiftData lightweight migration | HIGH | All new fields optional/defaulted; standard SwiftData behavior |

---

## Verification Checklist (Before Implementation)

- [ ] Highlightr: verify latest tag on GitHub, confirm Swift 6 / macOS 14 compatibility, confirm SPM target exists
- [ ] Highlightr: test `highlightAuto()` with Python, JavaScript, SQL, YAML, Shell samples
- [ ] LPMetadataProvider: test with 10 diverse URLs (news sites, GitHub, Twitter, etc.) to confirm latency and reliability
- [ ] KeyboardShortcuts: test Cmd+1 registration to confirm it works alongside existing Cmd+Shift+V toggle
- [ ] SwiftData migration: test adding new optional fields to existing database with existing clipboard items

---

## Sources

- **KeyboardShortcuts source code** -- directly inspected at `/Users/phulsechinmay/Desktop/Projects/pastel/.build/checkouts/KeyboardShortcuts/` (v2.4.0, confirmed in Package.resolved)
- **Pastel codebase** -- all 40+ source files inspected for integration points
- **Package.resolved** -- confirmed KeyboardShortcuts 2.4.0, LaunchAtLogin-Modern 1.1.0
- **Apple Developer Documentation** (training knowledge) -- LPMetadataProvider, LinkPresentation framework
- **Highlightr** (training knowledge) -- github.com/raspu/Highlightr; version needs verification

---
*Stack research for: Pastel v1.1 -- Rich Content & Enhanced Paste*
*Researched: 2026-02-07*
