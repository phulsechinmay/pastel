# Architecture Research: v1.1 Integration

**Domain:** macOS clipboard manager -- rich content, enhanced paste, label enrichment
**Researched:** 2026-02-07
**Confidence:** HIGH (based on direct source code analysis of the v1.0 codebase plus established macOS API patterns)

## Confidence Note

All integration points are derived from direct analysis of the existing Pastel source code (every Swift file was read). Technology recommendations for syntax highlighting (NSAttributedString + regex), URL metadata fetching (LPMetadataProvider / raw Open Graph), and color parsing (regex) are based on established macOS API knowledge. WebSearch was unavailable; library version details are MEDIUM confidence and should be verified during implementation.

---

## Existing Architecture Summary

The v1.0 architecture has clean separation of concerns and well-defined boundaries:

```
PastelApp (@main)
    |
    +-- AppState (@Observable, @MainActor)
    |       |-- ClipboardMonitor (Timer polling -> SwiftData insert)
    |       |-- PanelController (NSPanel lifecycle, show/hide)
    |       |-- PasteService (pasteboard write + CGEvent Cmd+V)
    |       |-- RetentionService (scheduled purge)
    |       `-- modelContainer (SwiftData)
    |
    +-- Models
    |       |-- ClipboardItem (@Model: textContent, htmlContent, rtfData, contentType, imagePath, etc.)
    |       |-- ContentType (enum: text, richText, url, image, file)
    |       |-- Label (@Model: name, colorName, sortOrder)
    |       `-- LabelColor (enum: 8 preset colors)
    |
    +-- Views/Panel
    |       |-- PanelController -> SlidingPanel (NSPanel subclass)
    |       |-- PanelContentView (SwiftUI root: header + search + chips + list)
    |       |-- FilteredCardListView (dynamic @Query with init-based predicates)
    |       |-- ClipboardCardView (dispatcher: routes to type-specific subviews)
    |       |-- TextCardView, URLCardView, ImageCardView, FileCardView
    |       `-- ChipBarView (label filtering + inline create)
    |
    +-- Views/Settings
    |       |-- SettingsWindowController (NSWindow hosting SwiftUI)
    |       |-- GeneralSettingsView (launch, hotkey, position, retention, paste behavior)
    |       `-- LabelSettingsView (CRUD for labels)
    |
    +-- Services
    |       |-- ClipboardMonitor (polls NSPasteboard, classifies, deduplicates, persists)
    |       |-- PasteService (writeToPasteboard + simulatePaste via CGEvent)
    |       |-- ImageStorageService (disk save, thumbnail gen, cleanup)
    |       |-- ExpirationService (concealed item auto-expire)
    |       |-- RetentionService (history age-based purge)
    |       `-- AccessibilityService (AXIsProcessTrusted check)
    |
    +-- Extensions
    |       |-- NSPasteboard+Reading (classifyContent, readTextContent, readURLContent, readFileContent)
    |       |-- NSImage+Thumbnail (CGImageSource-based thumbnail generation)
    |       `-- NSWorkspace+AppIcon (app icon lookup by bundle ID)
    |
    `-- External Dependencies
            |-- KeyboardShortcuts (sindresorhus) -- Carbon RegisterEventHotKey wrapper
            `-- LaunchAtLogin-Modern -- SMAppService wrapper
```

### Key Architectural Properties

1. **ClipboardMonitor is the single ingestion point.** All clipboard content flows through `processPasteboardContent()` which calls `pasteboard.classifyContent()` then branches by ContentType.

2. **ContentType enum drives card routing.** `ClipboardCardView.contentPreview` switches on `item.type` to dispatch to TextCardView, URLCardView, ImageCardView, or FileCardView.

3. **SwiftData @Query is init-based.** `FilteredCardListView` reconstructs its `@Query` predicate in `init()` -- the view is recreated (via `.id()` modifier) when search/filter/count changes.

4. **PasteService is item-type-aware.** `writeToPasteboard(item:)` switches on `item.type` to write the correct pasteboard representations.

5. **KeyboardShortcuts library wraps Carbon hotkeys.** The existing `togglePanel` shortcut uses `KeyboardShortcuts.Name` with `.onKeyUp(for:)`. The library has `.one` through `.nine` key constants and supports `Shortcut(.one, modifiers: [.command])`.

6. **Label model is minimal.** `Label` has `name: String`, `colorName: String`, `sortOrder: Int` and a `@Relationship` to `[ClipboardItem]`.

---

## Feature 1: Code Detection + Syntax Highlighting

### Integration Analysis

**What changes:** ClipboardMonitor must detect code in text content. A new card view renders highlighted code. No new ContentType enum case is needed -- code detection is a **sub-classification of `.text`**.

**Why not add a `.code` ContentType?** Adding a new enum case would break existing SwiftData `@Query` predicates (the `contentType` field is stored as a raw String). It would also require migrating every existing item. Instead, add a `detectedLanguage: String?` field to ClipboardItem. When non-nil, ClipboardCardView routes to a CodeCardView.

### New Components

| Component | Type | Location |
|-----------|------|----------|
| `CodeDetectionService` | New service | `Pastel/Services/CodeDetectionService.swift` |
| `CodeCardView` | New view | `Pastel/Views/Panel/CodeCardView.swift` |
| `SyntaxHighlighter` | New utility | `Pastel/Utilities/SyntaxHighlighter.swift` |

### Modified Components

| Component | Change |
|-----------|--------|
| `ClipboardItem` | Add `detectedLanguage: String?` property (nil = not code) |
| `ClipboardMonitor.processPasteboardContent()` | After classifying as `.text`/`.richText`, run code detection; set `detectedLanguage` |
| `ClipboardCardView.contentPreview` | When `item.detectedLanguage != nil`, route to `CodeCardView` instead of `TextCardView` |

### Data Flow

```
ClipboardMonitor.processPasteboardContent()
    |
    +-- classifyContent() returns .text
    |
    +-- Read textContent
    |
    +-- CodeDetectionService.detectLanguage(textContent)
    |       |
    |       +-- Check for shebang lines (#!/usr/bin/env python, etc.)
    |       +-- Check for common syntax patterns (braces + semicolons, def/fn/func, import/require, etc.)
    |       +-- Check for high density of special characters (::, =>, ->, etc.)
    |       +-- Return: language name String or nil
    |
    +-- Set item.detectedLanguage = result
    |
    +-- Insert into SwiftData (existing flow, unchanged)
```

```
ClipboardCardView.contentPreview
    |
    +-- if item.detectedLanguage != nil:
    |       CodeCardView(item: item)
    |           |-- SyntaxHighlighter.highlight(text, language: lang) -> NSAttributedString
    |           |-- Render via Text(AttributedString(nsAttrString)) or NSTextView wrapper
    |           |-- Show language badge (e.g., "Swift", "Python") in corner
    |
    +-- else: existing TextCardView/URLCardView/etc. routing
```

### Syntax Highlighting Approach

**Recommended: Regex-based NSAttributedString highlighting (no external dependency).**

The highlighting does not need to be compiler-grade -- it is a preview card in a clipboard manager. A lightweight regex-based highlighter that covers keywords, strings, comments, and numbers for ~10 popular languages is sufficient and keeps the app dependency-free.

**Architecture:**

```swift
// SyntaxHighlighter.swift
struct SyntaxHighlighter {
    struct LanguageRules {
        let keywords: Set<String>
        let singleLineComment: String?     // e.g., "//"
        let multiLineComment: (String, String)?  // e.g., ("/*", "*/")
        let stringDelimiters: [Character]  // e.g., ['"', "'"]
    }

    static let languages: [String: LanguageRules] = [
        "swift": LanguageRules(keywords: ["func", "var", "let", "struct", ...], ...),
        "python": LanguageRules(keywords: ["def", "class", "import", ...], ...),
        "javascript": LanguageRules(keywords: ["function", "const", "let", ...], ...),
        // ~10 languages total
    ]

    static func highlight(_ text: String, language: String) -> NSAttributedString {
        // 1. Start with monospace font, base foreground color
        // 2. Apply keyword coloring (bold + accent color)
        // 3. Apply string literal coloring (green-ish)
        // 4. Apply comment coloring (gray/dim)
        // 5. Apply number literal coloring (orange-ish)
        // Return NSAttributedString
    }
}
```

**Alternative considered: TreeSitter.** Much more accurate but requires bundling grammar files (~2-5 MB per language) and a C library. Overkill for preview cards. Could be added in a future version if users demand it.

**Alternative considered: Highlightr (CocoaPods/SPM library).** Uses highlight.js under the hood via JavaScriptCore. Adds a non-trivial dependency and JS evaluation overhead. Not recommended for a lightweight native app.

### CodeCardView Design

```swift
struct CodeCardView: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Language badge
            HStack {
                Text(item.detectedLanguage?.capitalized ?? "Code")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.12), in: Capsule())
                Spacer()
            }

            // Highlighted code preview (monospace, 3-4 lines)
            Text(highlightedText)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(isHorizontal ? 6 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var highlightedText: AttributedString {
        let nsAttr = SyntaxHighlighter.highlight(
            item.textContent ?? "",
            language: item.detectedLanguage ?? "plain"
        )
        return (try? AttributedString(nsAttr, including: \.uiKit)) ?? AttributedString(item.textContent ?? "")
    }
}
```

---

## Feature 2: URL Metadata Fetching (Open Graph)

### Integration Analysis

**What changes:** When a URL is captured, the app should asynchronously fetch the page's Open Graph metadata (title, description, favicon URL, og:image URL). This metadata is cached on the ClipboardItem for display. The URLCardView gets a major visual upgrade.

**Key constraint:** Network fetching must be non-blocking with graceful fallback. If fetching fails, the card falls back to the current globe-icon + URL layout.

### New Components

| Component | Type | Location |
|-----------|------|----------|
| `URLMetadataService` | New service | `Pastel/Services/URLMetadataService.swift` |
| `URLMetadataCardView` | New view (or enhanced URLCardView) | `Pastel/Views/Panel/URLCardView.swift` (modify existing) |

### Modified Components

| Component | Change |
|-----------|--------|
| `ClipboardItem` | Add `urlTitle: String?`, `urlDescription: String?`, `urlFaviconPath: String?`, `urlImagePath: String?` |
| `ClipboardMonitor.processPasteboardContent()` | After inserting a `.url` item, trigger async metadata fetch |
| `URLCardView` | Enhanced to show title + favicon when metadata is available, fallback to current layout when not |

### Data Flow

```
ClipboardMonitor.processPasteboardContent()
    |
    +-- classifyContent() returns .url
    +-- Insert ClipboardItem (existing flow, immediate)
    +-- modelContext.save() (item appears in UI immediately with URL-only card)
    |
    +-- URLMetadataService.fetchMetadata(for: item) [async, fire-and-forget]
            |
            +-- Use LPMetadataProvider (LinkPresentation framework)
            |       OR manual URLSession + HTML <meta> tag parsing
            |
            +-- On success:
            |       item.urlTitle = metadata.title
            |       item.urlDescription = metadata.description
            |       Download favicon -> save to disk -> item.urlFaviconPath = filename
            |       Download og:image -> save to disk -> item.urlImagePath = filename
            |       modelContext.save()
            |       (UI auto-updates via SwiftData observation)
            |
            +-- On failure:
                    Log warning, leave fields nil
                    (UI shows fallback URL-only card)
```

### LPMetadataProvider vs Manual Fetching

**Recommended: LPMetadataProvider (LinkPresentation framework).**

Apple's LinkPresentation framework provides `LPMetadataProvider` which fetches Open Graph metadata natively. It handles:
- og:title, og:description, og:image
- Favicon extraction
- Twitter card metadata
- Timeout and error handling

**Advantages:**
- Built into macOS (no external dependency)
- Handles HTTP redirects, HTTPS certificates, etc.
- Returns `LPLinkMetadata` with icon and image as `NSItemProvider`

**Disadvantages:**
- The `LPLinkMetadata` object is designed for use with `LPLinkView` -- extracting raw data (title string, favicon image data) requires a bit of work with `NSItemProvider.loadObject()`
- Rate limiting behavior is undocumented
- Cannot customize User-Agent or headers

**Fallback approach:** If LPMetadataProvider proves unreliable, implement manual Open Graph fetching:
```swift
// Manual approach:
// 1. URLSession.shared.data(from: url) with 5-second timeout
// 2. Parse HTML for <meta property="og:title">, <meta property="og:image">, etc.
// 3. Parse <link rel="icon"> for favicon
// 4. Download images separately
```

### URLMetadataService Design

```swift
@MainActor
final class URLMetadataService {
    static let shared = URLMetadataService()

    /// Fetch and cache metadata for a URL clipboard item.
    /// Call after the item is persisted to SwiftData.
    /// Updates the item's urlTitle/urlDescription/urlFaviconPath/urlImagePath fields.
    func fetchMetadata(for item: ClipboardItem, modelContext: ModelContext) {
        guard let urlString = item.textContent,
              let url = URL(string: urlString) else { return }

        Task.detached(priority: .utility) {
            let provider = LPMetadataProvider()
            provider.timeout = 5.0  // Don't hang on slow sites

            do {
                let metadata = try await provider.startFetchingMetadata(for: url)

                let title = metadata.title
                let description = metadata.value(forKey: "summary") as? String  // or parse from metadata

                // Extract favicon image data from NSItemProvider
                var faviconPath: String?
                if let iconProvider = metadata.iconProvider {
                    if let image = try? await iconProvider.loadObject(ofClass: NSImage.self) {
                        // Save to disk via ImageStorageService pattern
                        faviconPath = await self.saveFavicon(image as! NSImage, for: urlString)
                    }
                }

                // Extract og:image
                var ogImagePath: String?
                if let imageProvider = metadata.imageProvider {
                    if let image = try? await imageProvider.loadObject(ofClass: NSImage.self) {
                        ogImagePath = await self.saveOGImage(image as! NSImage, for: urlString)
                    }
                }

                await MainActor.run {
                    item.urlTitle = title
                    item.urlFaviconPath = faviconPath
                    item.urlImagePath = ogImagePath
                    try? modelContext.save()
                }
            } catch {
                // Silently fail -- URL card falls back to plain display
            }
        }
    }
}
```

### Enhanced URLCardView Design

```swift
struct URLCardView: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // If we have metadata, show rich preview
            if let title = item.urlTitle {
                HStack(spacing: 8) {
                    // Favicon
                    if let faviconPath = item.urlFaviconPath {
                        AsyncThumbnailView(filename: faviconPath)
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.blue)
                    }

                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }

                // URL below title (dimmer)
                Text(item.textContent ?? "")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

            } else {
                // Fallback: existing globe + URL layout
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.blue)
                    Text(item.textContent ?? "")
                        .font(.callout)
                        .lineLimit(2)
                        .foregroundStyle(Color.blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

### Disk Storage for Favicon / OG Images

Reuse the existing `ImageStorageService` pattern:
- Favicons: `~/Library/Application Support/Pastel/images/{hash}_favicon.png` (16x16 or 32x32)
- OG images: `~/Library/Application Support/Pastel/images/{hash}_ogimage.png` (thumbnail-sized, max 200px)
- Use URL hash as filename prefix (not UUID) to enable dedup across multiple copies of same URL

These images should be cleaned up by the existing `RetentionService` / item deletion flow. The `clearAllHistory()` method in AppState already iterates items and calls `ImageStorageService.shared.deleteImage()` -- extend it to also clean up `urlFaviconPath` and `urlImagePath`.

---

## Feature 3: Color Detection + Swatches

### Integration Analysis

**What changes:** When text is captured, check if it's a color value (hex, rgb, hsl). If so, set a flag and show a color swatch alongside the text in the card.

**Approach: Sub-classification of `.text`, not a new ContentType.** Like code detection, this adds an optional field to ClipboardItem rather than a new enum case.

### New Components

| Component | Type | Location |
|-----------|------|----------|
| `ColorDetectionService` | New service | `Pastel/Services/ColorDetectionService.swift` |
| `ColorSwatchView` | New view | `Pastel/Views/Panel/ColorSwatchView.swift` |

### Modified Components

| Component | Change |
|-----------|--------|
| `ClipboardItem` | Add `detectedColorHex: String?` (normalized 6-digit hex, nil = not a color) |
| `ClipboardMonitor.processPasteboardContent()` | After classifying as `.text`, run color detection |
| `ClipboardCardView.contentPreview` | When `item.detectedColorHex != nil`, show color swatch alongside text |

### Color Detection Patterns

```swift
struct ColorDetectionService {
    /// Detect if text represents a color value. Returns normalized 6-digit hex (no #) or nil.
    static func detectColor(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only detect single-value strings, not paragraphs containing a color
        guard trimmed.count < 50 else { return nil }

        // 1. Hex: #RGB, #RRGGBB, #RRGGBBAA (strip alpha)
        if let hex = parseHex(trimmed) { return hex }

        // 2. rgb(R, G, B) / rgba(R, G, B, A)
        if let hex = parseRGB(trimmed) { return hex }

        // 3. hsl(H, S%, L%) / hsla(H, S%, L%, A)
        if let hex = parseHSL(trimmed) { return hex }

        return nil
    }

    private static func parseHex(_ text: String) -> String? {
        // Match: #FFF, #FFFFFF, #FFFFFFAA, FFF, FFFFFF (with or without #)
        let pattern = /^#?([0-9A-Fa-f]{3,8})$/
        guard let match = text.firstMatch(of: pattern) else { return nil }
        let hex = String(match.1)
        switch hex.count {
        case 3:
            // Expand #RGB -> RRGGBB
            return hex.map { "\($0)\($0)" }.joined()
        case 6:
            return hex
        case 8:
            return String(hex.prefix(6)) // Strip alpha
        default:
            return nil
        }
    }

    // ... parseRGB, parseHSL with regex patterns
}
```

### Data Flow

```
ClipboardMonitor.processPasteboardContent()
    |
    +-- classifyContent() returns .text
    +-- Read textContent
    +-- CodeDetectionService.detectLanguage(textContent) [check first]
    |
    +-- If no code detected:
    |       ColorDetectionService.detectColor(textContent)
    |       item.detectedColorHex = result (or nil)
    |
    +-- Insert into SwiftData
```

### Card Rendering

```
ClipboardCardView.contentPreview
    |
    +-- if item.detectedLanguage != nil:
    |       CodeCardView(item: item)
    |
    +-- else if item.detectedColorHex != nil:
    |       ColorCardView: TextCardView content + color swatch
    |       (HStack: color circle/rectangle + text)
    |
    +-- else: existing routing
```

The ColorSwatchView is simple:

```swift
struct ColorSwatchView: View {
    let hexColor: String  // 6-digit hex, no #

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(hex: hexColor))
            .frame(width: 32, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            )
    }
}

// Color extension for hex parsing
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
```

---

## Feature 4: Cmd+1-9 Direct Paste Hotkeys

### Integration Analysis

**What changes:** The user presses Cmd+1 through Cmd+9 (globally, without opening the panel) to paste the Nth most recent clipboard item. This is the most architecturally significant v1.1 feature because it requires:

1. Nine new global hotkey registrations
2. A way to fetch the Nth most recent item without the panel being involved
3. PasteService invocation from a non-panel code path
4. Self-paste loop prevention without panel hide (panel is already hidden)

### Design Decision: KeyboardShortcuts Library vs Direct Carbon

**Recommended: Use the existing KeyboardShortcuts library.**

The KeyboardShortcuts library already wraps Carbon `RegisterEventHotKey`. It has `Key.one` through `Key.nine` constants and supports `Shortcut(.one, modifiers: [.command])`. Using it avoids raw Carbon code and stays consistent with the existing `togglePanel` hotkey.

**Important caveat: Cmd+1-9 are not user-configurable.** These are hardcoded shortcuts (unlike the panel toggle which has a Recorder). We define them as `KeyboardShortcuts.Name` with a default `Shortcut` and no recorder UI.

However, there is a conflict risk: **Cmd+1-9 are commonly used by browsers** (switch to tab N) and other apps. These hotkeys should be configurable (enable/disable) in Settings, and potentially use a different modifier like Ctrl+1-9 or Cmd+Shift+1-9. The default should be Cmd+Shift+1-9 to avoid conflicts.

### Modified Components

| Component | Change |
|-----------|--------|
| `AppState` | Add `registerQuickPasteHotkeys()`, `quickPaste(index:)` methods |
| `PasteService` | Add `pasteWithoutPanel(item:, clipboardMonitor:)` method (no panel hide step) |
| `GeneralSettingsView` | Add toggle for "Enable Cmd+Shift+1-9 quick paste" |

### New Components

None -- this integrates into existing AppState and PasteService.

### KeyboardShortcuts Name Definitions

```swift
extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.command, .shift]))

    // Quick paste: Cmd+Shift+1 through Cmd+Shift+9
    static let quickPaste1 = Self("quickPaste1", default: .init(.one, modifiers: [.command, .shift]))
    static let quickPaste2 = Self("quickPaste2", default: .init(.two, modifiers: [.command, .shift]))
    static let quickPaste3 = Self("quickPaste3", default: .init(.three, modifiers: [.command, .shift]))
    static let quickPaste4 = Self("quickPaste4", default: .init(.four, modifiers: [.command, .shift]))
    static let quickPaste5 = Self("quickPaste5", default: .init(.five, modifiers: [.command, .shift]))
    static let quickPaste6 = Self("quickPaste6", default: .init(.six, modifiers: [.command, .shift]))
    static let quickPaste7 = Self("quickPaste7", default: .init(.seven, modifiers: [.command, .shift]))
    static let quickPaste8 = Self("quickPaste8", default: .init(.eight, modifiers: [.command, .shift]))
    static let quickPaste9 = Self("quickPaste9", default: .init(.nine, modifiers: [.command, .shift]))
}
```

### Data Flow

```
User presses Cmd+Shift+3 (globally, any app focused)
    |
    +-- KeyboardShortcuts fires onKeyUp for .quickPaste3
    |
    +-- AppState.quickPaste(index: 3)
            |
            +-- Fetch 3rd most recent ClipboardItem from SwiftData:
            |       FetchDescriptor<ClipboardItem>(
            |           sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            |       )
            |       fetchLimit = 3
            |       Take last item from result
            |
            +-- Guard: item exists, Accessibility granted, !IsSecureEventInputEnabled()
            |
            +-- PasteService.pasteWithoutPanel(item:, clipboardMonitor:)
                    |
                    +-- writeToPasteboard(item: item)  // existing method
                    +-- clipboardMonitor.skipNextChange = true  // self-paste prevention
                    +-- NOTE: No panel hide (panel is not shown)
                    +-- After 50ms delay: simulatePaste()  // existing CGEvent method
```

### PasteService Changes

```swift
/// Paste without involving the panel -- for Cmd+1-9 quick paste hotkeys.
func pasteWithoutPanel(
    item: ClipboardItem,
    clipboardMonitor: ClipboardMonitor
) {
    let behaviorRaw = UserDefaults.standard.string(forKey: "pasteBehavior") ?? PasteBehavior.paste.rawValue
    let behavior = PasteBehavior(rawValue: behaviorRaw) ?? .paste

    if behavior == .copy {
        writeToPasteboard(item: item)
        clipboardMonitor.skipNextChange = true
        return
    }

    guard AccessibilityService.isGranted else { return }
    if IsSecureEventInputEnabled() {
        writeToPasteboard(item: item)
        clipboardMonitor.skipNextChange = true
        return
    }

    writeToPasteboard(item: item)
    clipboardMonitor.skipNextChange = true

    // No panel to hide -- go straight to paste
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        Self.simulatePaste()
    }
}
```

### Settings Toggle

```swift
// In GeneralSettingsView, add:
@AppStorage("quickPasteEnabled") private var quickPasteEnabled: Bool = true

Toggle("Quick Paste (Cmd+Shift+1-9)", isOn: $quickPasteEnabled)
    .toggleStyle(.switch)

// In AppState, check this before registering:
if UserDefaults.standard.bool(forKey: "quickPasteEnabled") {
    registerQuickPasteHotkeys()
}
```

### Bonus: Number Badge on Cards

When the panel is open, show position numbers (1-9) on the first 9 cards. This helps users learn which Cmd+Shift+N maps to which item.

```swift
// In ClipboardCardView or FilteredCardListView:
// Pass index to card, show badge overlay when index < 9
ZStack(alignment: .topTrailing) {
    cardContent
    if index < 9 {
        Text("\(index + 1)")
            .font(.caption2.weight(.bold))
            .padding(4)
            .background(Color.accentColor, in: Circle())
            .foregroundStyle(.white)
    }
}
```

---

## Feature 5: Label Emoji + Color Palette Enhancement

### Integration Analysis

**What changes:** Labels gain an optional emoji field. When set, the emoji replaces the color dot in chip bar and context menu. The color palette expands from 8 to 12 colors.

This is the simplest v1.1 feature -- pure data model + UI changes with no service-layer impact.

### Modified Components

| Component | Change |
|-----------|--------|
| `Label` | Add `emoji: String?` property |
| `LabelColor` | Add 4 new cases: `teal`, `indigo`, `brown`, `mint` |
| `ChipBarView` | Show emoji instead of color dot when `label.emoji != nil` |
| `ClipboardCardView` | Update label display in context menu |
| `LabelSettingsView` | Add emoji picker (text field or grid) to label edit row |
| `LabelRow` | Show emoji preview, add emoji field |

### SwiftData Migration

Adding `emoji: String?` with a default of `nil` is a lightweight schema migration. SwiftData handles optional property additions automatically -- existing labels get `nil` for the new field without requiring a manual migration step.

Adding new `LabelColor` enum cases is also safe because the `colorName` field is stored as a raw String. Existing labels with old color names continue to work.

### Label Model Change

```swift
@Model
final class Label {
    var name: String
    var colorName: String
    var sortOrder: Int
    var emoji: String?  // NEW: optional emoji, replaces color dot when set

    @Relationship(deleteRule: .nullify, inverse: \ClipboardItem.label)
    var items: [ClipboardItem]

    init(name: String, colorName: String, sortOrder: Int, emoji: String? = nil) {
        self.name = name
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.emoji = emoji
        self.items = []
    }
}
```

### LabelColor Expansion

```swift
enum LabelColor: String, CaseIterable {
    case red, orange, yellow, green, teal, blue, indigo, purple, pink, brown, mint, gray

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .mint: .mint
        case .gray: .gray
        }
    }
}
```

### ChipBarView: Emoji-or-Dot Logic

```swift
// In labelChip(for:):
HStack(spacing: 4) {
    if let emoji = label.emoji, !emoji.isEmpty {
        Text(emoji)
            .font(.caption)
    } else {
        Circle()
            .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
            .frame(width: 8, height: 8)
    }
    Text(label.name)
        .font(.caption)
        .lineLimit(1)
}
```

### Emoji Picker in Settings

Use a simple TextField for emoji input (most users will paste or use the macOS emoji picker via Ctrl+Cmd+Space). Alternatively, present a curated grid of common organizational emojis.

```swift
// In LabelRow:
HStack(spacing: 12) {
    // Emoji or color dot
    if let emoji = label.emoji, !emoji.isEmpty {
        Text(emoji).font(.title3)
            .frame(width: 24)
    } else {
        // Existing color dot menu
        colorDotMenu
    }

    // ... name field ...

    // Emoji field
    TextField("", text: Binding(
        get: { label.emoji ?? "" },
        set: { label.emoji = $0.isEmpty ? nil : String($0.prefix(1)) }
    ))
    .textFieldStyle(.plain)
    .frame(width: 30)
    .help("Optional emoji (replaces color dot)")

    // ... delete button ...
}
```

---

## Cross-Cutting Concerns

### SwiftData Schema Evolution

v1.1 adds these fields to `ClipboardItem`:
- `detectedLanguage: String?`
- `detectedColorHex: String?`
- `urlTitle: String?`
- `urlDescription: String?`
- `urlFaviconPath: String?`
- `urlImagePath: String?`

And to `Label`:
- `emoji: String?`

All are optional with nil defaults. SwiftData handles this as a lightweight migration automatically. No manual `VersionedSchema` or `MigrationPlan` should be needed. However, **test the migration** with a v1.0 database before shipping.

### Image Cleanup Extension

The existing `deleteItem()` in ClipboardCardView and `clearAllHistory()` in AppState need to be extended to also clean up `urlFaviconPath` and `urlImagePath` files:

```swift
// In the delete flow, add:
ImageStorageService.shared.deleteImage(imagePath: item.urlFaviconPath, thumbnailPath: nil)
ImageStorageService.shared.deleteImage(imagePath: item.urlImagePath, thumbnailPath: nil)
```

### Detection Priority Order

When a new text item is captured, detections should run in this order:

1. **Color detection first** (cheapest: single regex on short strings; if text is > 50 chars, skip)
2. **Code detection second** (heuristic scan, moderate cost)
3. These are mutually exclusive in practice (a hex color like `#FF5733` could theoretically match both, but the 50-char limit on color detection prevents false positives on code)

### Performance Considerations

- **Code detection:** Runs synchronously in ClipboardMonitor during `processPasteboardContent()`. Must be fast. The heuristic check (shebang, keyword density, brace patterns) on typical clipboard text (<10KB) completes in microseconds.
- **Syntax highlighting:** Runs in the view layer (CodeCardView). Cache the highlighted `NSAttributedString` to avoid re-highlighting on every SwiftUI redraw. Use a simple dictionary cache keyed on `(contentHash, language)`.
- **URL metadata fetching:** Runs asynchronously after item insertion. The 5-second timeout prevents hangs. Downloads (favicon, og:image) use the existing `ImageStorageService` background queue pattern.
- **Color detection:** Trivial regex, runs in microseconds.
- **Quick paste hotkeys:** The SwiftData fetch for the Nth item is fast (indexed by timestamp, fetchLimit = N). No performance concern.

---

## Suggested Build Order

Based on dependency analysis and risk assessment:

### Phase A: Data Model + Detection Infrastructure

**Build first because everything depends on it.**

1. Add new fields to `ClipboardItem` and `Label` (schema changes)
2. Verify SwiftData lightweight migration works with v1.0 data
3. Implement `CodeDetectionService` (pure function, easily testable)
4. Implement `ColorDetectionService` (pure function, easily testable)
5. Wire detections into `ClipboardMonitor.processPasteboardContent()`
6. Expand `LabelColor` enum with 4 new colors

**Rationale:** Schema changes must come first. Detection services are pure functions with no UI dependency -- they can be built and tested in isolation.

### Phase B: Card View Enhancements

**Build second because it depends on Phase A detections.**

1. Build `CodeCardView` with `SyntaxHighlighter`
2. Modify `ClipboardCardView.contentPreview` routing for code and color
3. Build `ColorSwatchView` and integrate into text card display
4. Add `Color(hex:)` extension

**Rationale:** Views depend on the detection data from Phase A. Card views can be developed independently of each other.

### Phase C: URL Metadata + Enhanced URL Cards

**Build third because it's the highest-risk feature (network I/O, async, disk storage).**

1. Build `URLMetadataService` using `LPMetadataProvider`
2. Wire into `ClipboardMonitor` (fire-and-forget after URL item insertion)
3. Enhance `URLCardView` to show title + favicon when available
4. Extend image cleanup to handle favicon/ogimage paths
5. Test graceful fallback when fetch fails or times out

**Rationale:** This is the only feature with external dependencies (network) and the most likely to need debugging. Build it after the simpler features are proven.

### Phase D: Cmd+Shift+1-9 Quick Paste Hotkeys

**Build fourth because it's architecturally independent but needs careful testing.**

1. Define 9 `KeyboardShortcuts.Name` entries with defaults
2. Add `quickPaste(index:)` to AppState
3. Add `pasteWithoutPanel(item:, clipboardMonitor:)` to PasteService
4. Wire up `onKeyUp` handlers in `AppState.setupPanel()`
5. Add settings toggle
6. Add position badges (1-9) on panel cards

**Rationale:** This feature is functionally independent of the card enhancements but requires Accessibility permission and CGEvent testing. Building it after the UI features lets the team focus on one category at a time.

### Phase E: Label Emoji + Color Enhancement

**Build last because it's the simplest and lowest risk.**

1. Add `emoji: String?` to Label model
2. Update `ChipBarView` and context menu to show emoji-or-dot
3. Add emoji field to `LabelSettingsView` / `LabelRow`
4. Test with existing labels (migration)

**Rationale:** Pure UI polish with no service-layer complexity. Can be built quickly after the heavier features.

---

## Architecture Diagram: v1.1 Additions

```
                        EXISTING (v1.0)                    NEW (v1.1)
                        ================                   ==========

PastelApp
    |
    +-- AppState
    |       |-- ClipboardMonitor -----> [CodeDetectionService]    (NEW)
    |       |                    -----> [ColorDetectionService]   (NEW)
    |       |                    -----> [URLMetadataService]      (NEW, async post-insert)
    |       |
    |       |-- PanelController (unchanged)
    |       |-- PasteService ---------> pasteWithoutPanel()       (NEW method)
    |       |-- RetentionService (unchanged)
    |       +-- quickPaste(index:) -+                             (NEW method)
    |                               |
    |       [KeyboardShortcuts.Name] --> quickPaste1..9            (NEW names)
    |
    +-- Models
    |       |-- ClipboardItem -------> +detectedLanguage          (NEW field)
    |       |                  -------> +detectedColorHex         (NEW field)
    |       |                  -------> +urlTitle, +urlFaviconPath, +urlImagePath (NEW fields)
    |       |
    |       |-- ContentType (UNCHANGED -- no new cases)
    |       |
    |       |-- Label ---------------> +emoji                     (NEW field)
    |       `-- LabelColor ----------> +teal, +indigo, +brown, +mint (NEW cases)
    |
    +-- Views/Panel
    |       |-- ClipboardCardView ---> routing: code? color? (MODIFIED)
    |       |-- [CodeCardView] ------> SyntaxHighlighter          (NEW)
    |       |-- [ColorSwatchView]                                  (NEW)
    |       |-- URLCardView ---------> title + favicon fallback   (MODIFIED)
    |       |-- ChipBarView ---------> emoji-or-dot logic         (MODIFIED)
    |       `-- FilteredCardListView -> position badges 1-9       (MODIFIED)
    |
    +-- Views/Settings
    |       |-- GeneralSettingsView -> quick paste toggle          (MODIFIED)
    |       `-- LabelSettingsView ---> emoji field                 (MODIFIED)
    |
    +-- Services
    |       |-- [CodeDetectionService]                             (NEW)
    |       |-- [ColorDetectionService]                            (NEW)
    |       |-- [URLMetadataService]                               (NEW)
    |       `-- ImageStorageService -> favicon/ogimage cleanup     (MODIFIED)
    |
    `-- Utilities
            `-- [SyntaxHighlighter]                                (NEW)
            `-- [Color+Hex]                                        (NEW extension)
```

**Legend:** `[brackets]` = new component, `->` = integration point, `+field` = new property

---

## Risk Assessment

| Feature | Risk | Reason | Mitigation |
|---------|------|--------|------------|
| Code detection | LOW | Pure heuristic, no external deps | False positives are cosmetic (show code view for non-code) |
| Syntax highlighting | LOW | Regex-based, no external deps | Graceful fallback to plain monospace text |
| URL metadata | MEDIUM | Network I/O, LPMetadataProvider quirks | 5s timeout, nil-field fallback to plain URL card |
| Color detection | LOW | Simple regex on short strings | 50-char limit prevents false positives |
| Cmd+Shift+1-9 hotkeys | MEDIUM | Conflict with system/app shortcuts | Use Cmd+Shift (not plain Cmd), add settings toggle |
| Label emoji | LOW | Simple optional String field | Nil default, backward compatible |
| SwiftData migration | LOW | All new fields are optional | Test with v1.0 database before shipping |

---

## Sources

- **Direct source code analysis:** All 40+ Swift files in Pastel project read and analyzed
- **KeyboardShortcuts library source:** Confirmed `.one` through `.nine` key constants, `Shortcut` constructor, `onKeyUp(for:)` API
- **CarbonKeyboardShortcuts source:** Confirmed `RegisterEventHotKey` wrapping pattern used by the library
- **Apple LPMetadataProvider:** Known from training data (iOS 13+ / macOS 10.15+, LinkPresentation framework) -- MEDIUM confidence on exact async API surface, verify during implementation
- **NSAttributedString + regex highlighting:** Established macOS pattern -- HIGH confidence
- **SwiftData lightweight migration:** Known behavior for optional field additions -- HIGH confidence, test to verify

---
*Architecture research for: Pastel v1.1 (rich content, enhanced paste, label enrichment)*
*Researched: 2026-02-07*
