# Phase 22: Code/Color Edit Controls and Panel Toolbar Tools - Research

**Researched:** 2026-02-19
**Domain:** SwiftUI/AppKit hybrid UI controls, NSColorPanel, HighlightSwift language enums, panel toolbar
**Confidence:** HIGH

## Summary

Phase 22 adds four distinct UI features to the Pastel clipboard manager: (1) a language override/removal control in the edit modal for code items, (2) a color picker integration in the edit modal for color items, (3) a standalone color picker tool in the panel toolbar, and (4) a panel position switcher in the panel toolbar.

All four features build on well-established patterns already in the codebase. The language override uses HighlightSwift's `HighlightLanguage` enum (~50 languages) and modifies the existing `detectedLanguage` and `contentType` fields on `ClipboardItem`. The color picker features use either SwiftUI's `ColorPicker` (for the edit modal) or `NSColorPanel.shared` (for the standalone toolbar tool). The position switcher reuses the existing `ScreenEdgePicker` or a simplified dropdown bound to `@AppStorage("panelEdge")`.

**Primary recommendation:** Use SwiftUI `ColorPicker` for the edit modal integration (inline, scoped to the item). Use `NSColorPanel.shared` with target/action for the standalone toolbar color tool (allows picking colors independently, copying hex/RGB values to clipboard). Extend `EditItemView` conditionally based on `item.type` to show code or color controls only when relevant.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| HighlightSwift | (existing dep) | `HighlightLanguage` enum for language list | Already used for syntax highlighting and language detection |
| AppKit NSColorPanel | macOS 14+ | Standalone system color picker | macOS standard, singleton, accessible via `NSColorPanel.shared` |
| SwiftUI ColorPicker | macOS 11+ | Inline color picker control | Native SwiftUI control, wraps NSColorWell/NSColorPanel |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SwiftData | macOS 14+ | Persisting language/contentType changes | Already used for all model mutations |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NSColorPanel for toolbar tool | SwiftUI ColorPicker | ColorPicker requires a binding and is designed for editing an existing color -- NSColorPanel is better for a standalone "pick any color" tool |
| HighlightLanguage enum for language list | Hardcoded string array | HighlightLanguage ensures the list stays in sync with what HighlightSwift can actually highlight |

## Architecture Patterns

### Recommended File Structure
```
Pastel/Views/Panel/
  EditItemView.swift          # Extended with code/color sections
  PanelContentView.swift      # Toolbar buttons added next to gear icon
  ColorToolController.swift   # NEW: NSColorPanel target/action bridge
```

### Pattern 1: Conditional Edit Sections by ContentType
**What:** EditItemView shows different controls based on `item.type`. Code items get a language picker and "Remove code detection" button. Color items get a ColorPicker and format copy buttons.
**When to use:** When edit modal needs content-type-specific controls.
**Example:**
```swift
// Inside EditItemView body, after label section:
if item.type == .code {
    CodeEditSection(item: item)
}
if item.type == .color {
    ColorEditSection(item: item)
}
```

### Pattern 2: NSColorPanel Target/Action Bridge for Toolbar Tool
**What:** A controller class that wraps `NSColorPanel.shared`, sets target/action, and converts selected colors to hex/RGB strings for clipboard copy.
**When to use:** For the standalone color picker tool in the panel toolbar.
**Example:**
```swift
// Source: Apple Developer Documentation + NSColorPanel gist
@MainActor
final class ColorToolController {
    static let shared = ColorToolController()

    func showColorPicker() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.isContinuous = true
        panel.level = .floating  // Above the sliding panel
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        let color = sender.color
        // Convert to hex and copy to pasteboard
        let hex = String(format: "#%02X%02X%02X",
            Int(color.redComponent * 255),
            Int(color.greenComponent * 255),
            Int(color.blueComponent * 255))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
    }
}
```

### Pattern 3: Language Override with Picker
**What:** A SwiftUI `Picker` or `Menu` listing available languages from HighlightLanguage, plus a "None (plain text)" option. Changing the selection updates `item.detectedLanguage` and optionally `item.contentType`.
**When to use:** In the edit modal for code items.
**Example:**
```swift
// HighlightLanguage is not CaseIterable, so define the list manually
// or use a static array. The alias property gives highlight.js identifiers.
let supportedLanguages: [(display: String, id: String)] = [
    ("Swift", "swift"),
    ("Python", "python"),
    ("JavaScript", "javascript"),
    // ... etc
]

Picker("Language", selection: languageBinding) {
    Text("Auto-detected").tag(String?.none)
    Divider()
    ForEach(supportedLanguages, id: \.id) { lang in
        Text(lang.display).tag(Optional(lang.id))
    }
}
```

### Pattern 4: Panel Position Dropdown in Toolbar
**What:** A `Menu` or `Picker` bound to `@AppStorage("panelEdge")` that shows top/right/bottom/left options. On change, calls `appState.panelController.handleEdgeChange()` -- exactly the pattern already used in GeneralSettingsView and OnboardingView.
**When to use:** Panel toolbar, next to the gear icon.
**Example:**
```swift
Menu {
    ForEach(PanelEdge.allCases, id: \.self) { edge in
        Button {
            panelEdgeRaw = edge.rawValue
        } label: {
            HStack {
                Text(edge.displayName)
                if panelEdgeRaw == edge.rawValue {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
} label: {
    Image(systemName: "rectangle.leadinghalf.inset.filled.arrow.leading")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
}
```

### Anti-Patterns to Avoid
- **Reopening NSColorPanel multiple times:** `NSColorPanel.shared` is a singleton. Always use the shared instance; never try to create new instances.
- **Setting NSColorPanel target without clearing it:** If the edit modal also uses ColorPicker (which internally uses NSColorPanel), be careful about target/action conflicts. The toolbar tool should only set target/action when explicitly invoked.
- **Modifying contentType without clearing detectedLanguage:** When removing code detection, both `contentType` must revert to `.text`/`.richText` AND `detectedLanguage` must be set to `nil`. Otherwise the card will show a language badge with no highlighting.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Color picker UI | Custom color wheel view | `NSColorPanel.shared` / SwiftUI `ColorPicker` | macOS provides a full-featured system color picker with eyedropper, palettes, sliders |
| Language list | Hardcoded language names | `HighlightLanguage` enum cases | Stays in sync with what HighlightSwift actually supports |
| Color format conversion | Manual RGB/HSL string parsing | `NSColor` component accessors | NSColor handles color space conversion correctly |
| Panel edge persistence | Custom UserDefaults logic | `@AppStorage("panelEdge")` | Already used throughout the codebase |

**Key insight:** All four features use existing macOS platform capabilities and existing Pastel patterns. No new libraries or novel approaches are needed.

## Common Pitfalls

### Pitfall 1: NSColorPanel Conflicts with SwiftUI ColorPicker
**What goes wrong:** SwiftUI's `ColorPicker` also uses `NSColorPanel.shared` under the hood. If the toolbar color tool sets a target/action on the shared panel, and then the user opens the edit modal with a ColorPicker, the target/action can interfere.
**Why it happens:** There's only one `NSColorPanel.shared` instance per app.
**How to avoid:** Clear the toolbar tool's target/action when the NSColorPanel closes (observe `NSWindow.willCloseNotification` on the panel). Alternatively, only use SwiftUI `ColorPicker` in the edit modal (it manages its own target/action lifecycle).
**Warning signs:** Color changes in the edit modal's ColorPicker trigger the toolbar tool's copy-to-clipboard action.

### Pitfall 2: Removing Code Detection Without Reverting ContentType
**What goes wrong:** User removes code detection, but `contentType` stays as `.code`. The card still renders as `CodeCardView` but without highlighting or language badge.
**Why it happens:** Only `detectedLanguage` was set to nil but `contentType` wasn't reverted.
**How to avoid:** When removing code detection, set `item.contentType = "text"` (or `"richText"` if `item.rtfData != nil`) AND set `item.detectedLanguage = nil`. When changing language, only update `detectedLanguage`.
**Warning signs:** Cards show as code cards but with no language badge and plain text rendering.

### Pitfall 3: NSColorPanel Window Level vs Panel Level
**What goes wrong:** NSColorPanel appears behind the sliding panel.
**Why it happens:** The sliding panel uses `.statusBar` level (NSWindow.Level = 25). NSColorPanel defaults to a lower level.
**How to avoid:** Set `NSColorPanel.shared.level = .floating` or `.statusBar` before showing it. Or better: the user should be able to use the color picker after the panel dismisses. Consider dismissing the panel or keeping the color panel at `.floating` level.
**Warning signs:** User clicks the color picker button but can't see the color picker window.

### Pitfall 4: Color Space Issues When Converting NSColor to Hex
**What goes wrong:** `NSColor.redComponent` crashes if the color is not in RGB color space (e.g., grayscale, CMYK patterns).
**Why it happens:** NSColorPanel can return colors in various color spaces.
**How to avoid:** Always convert to sRGB first: `color.usingColorSpace(.sRGB)` before accessing RGB components. Guard against nil return from color space conversion.
**Warning signs:** Crash on `NSColor.redComponent` with "not valid for this color" exception.

### Pitfall 5: HighlightSwift Language Identifiers vs Display Names
**What goes wrong:** Storing "JavaScript" instead of "javascript" as `detectedLanguage`, causing highlighting to fail.
**Why it happens:** The `HighlightLanguage` rawValue is camelCase (e.g., "javaScript") but highlight.js expects lowercase aliases (e.g., "javascript"). The existing `CodeDetectionService` stores lowercase aliases.
**How to avoid:** Store the highlight.js alias (lowercase) in `detectedLanguage`, not the enum rawValue or display name. Use `HighlightLanguage.alias` or match the identifiers used in `CodeDetectionService.languageHint()`.
**Warning signs:** Language badge shows correctly but syntax highlighting doesn't apply or detects wrong language.

### Pitfall 6: Panel Toolbar Layout in Horizontal Mode
**What goes wrong:** Adding two new buttons to the panel header causes layout overflow in horizontal mode, where the header is a compact single-row HStack.
**Why it happens:** Horizontal mode packs logo + search + chips + gear all in one HStack.
**How to avoid:** In horizontal mode, group the new toolbar buttons next to the gear icon in a compact `HStack(spacing: 4)`. Use small icon-only buttons (14pt SF Symbols) matching the existing gear button style.
**Warning signs:** Toolbar overflows, chips or search field gets squeezed.

## Code Examples

Verified patterns from official sources and codebase analysis:

### NSColor to Hex String (Safe)
```swift
// Source: AppKit documentation pattern
func hexFromNSColor(_ color: NSColor) -> String? {
    guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
    return String(format: "#%02X%02X%02X",
        Int(rgb.redComponent * 255),
        Int(rgb.greenComponent * 255),
        Int(rgb.blueComponent * 255))
}
```

### NSColor to RGB String
```swift
func rgbFromNSColor(_ color: NSColor) -> String? {
    guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
    return String(format: "rgb(%d, %d, %d)",
        Int(rgb.redComponent * 255),
        Int(rgb.greenComponent * 255),
        Int(rgb.blueComponent * 255))
}
```

### Removing Code Detection from an Item
```swift
func removeCodeDetection(from item: ClipboardItem) {
    item.detectedLanguage = nil
    // Revert to original text type
    if item.rtfData != nil {
        item.contentType = ContentType.richText.rawValue
    } else {
        item.contentType = ContentType.text.rawValue
    }
    // Save context
}
```

### Changing Language Override
```swift
func setLanguageOverride(_ language: String?, on item: ClipboardItem) {
    item.detectedLanguage = language
    if language != nil {
        // Ensure it's marked as code
        item.contentType = ContentType.code.rawValue
    }
    // Invalidate highlight cache for this item's contentHash
    // (cache keyed by contentHash, so re-highlight will happen automatically
    // since loadHighlighting checks detectedLanguage)
}
```

### Existing ScreenEdgePicker Reuse Pattern
```swift
// Source: GeneralSettingsView.swift line 28, 194-196
@AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

.onChange(of: panelEdgeRaw) {
    appState.panelController.handleEdgeChange()
}
```

### SwiftUI ColorPicker for Edit Modal
```swift
// Source: Apple Developer Documentation (SwiftUI ColorPicker)
@State private var editColor: Color

ColorPicker("Color", selection: $editColor, supportsOpacity: false)
    .onChange(of: editColor) { _, newColor in
        // Convert Color to hex and update item.detectedColorHex
        if let nsColor = NSColor(newColor).usingColorSpace(.sRGB) {
            item.detectedColorHex = String(format: "%02X%02X%02X",
                Int(nsColor.redComponent * 255),
                Int(nsColor.greenComponent * 255),
                Int(nsColor.blueComponent * 255))
        }
    }
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSColorWell + manual panel management | SwiftUI `ColorPicker` (wraps NSColorWell) | macOS 11 / SwiftUI 2 | Inline color picking with one control |
| Manual language string lists | `HighlightLanguage` enum in HighlightSwift | HighlightSwift 1.x | Type-safe language identifiers |

**Deprecated/outdated:**
- `NSColorPanel.sharedColorPanel()` class method: renamed to `NSColorPanel.shared` property in modern Swift

## Open Questions

1. **Copy format for toolbar color tool**
   - What we know: The user wants to copy hex/RGB/etc. from the system color picker
   - What's unclear: Should there be a format selector (hex vs RGB vs HSL), or default to hex with a format toggle? Should it auto-copy on every color change (continuous) or require a "Copy" button click?
   - Recommendation: Default to copying hex format on each color change (continuous mode). Add a small popover or segmented control for format selection (Hex/RGB/HSL).

2. **Should language override persist through re-copy?**
   - What we know: If the same text is copied again, deduplication may update the timestamp on the existing item
   - What's unclear: Should a manual language override survive a dedup merge?
   - Recommendation: Yes, preserve the override since the user explicitly set it. Dedup already preserves existing item fields.

3. **Toolbar button icons**
   - What we know: Need icons for color picker and position switcher, matching the existing gear icon style (14pt, secondary color)
   - What's unclear: Exact SF Symbol names
   - Recommendation: Use `"eyedropper"` (macOS 14+) for color picker, `"rectangle.leadinghalf.inset.filled.arrow.leading"` or `"sidebar.squares.leading"` for position switcher. Verify SF Symbol availability on macOS 14+.

4. **Highlight cache invalidation on language change**
   - What we know: `HighlightCache` is keyed by `item.contentHash`, and `CodeCardView.loadHighlighting()` uses `item.detectedLanguage` to pick the highlight language
   - What's unclear: If a user changes the language, the cached highlighting (keyed by contentHash) will be stale since it was highlighted with the old language
   - Recommendation: When language is changed, evict the cache entry for that contentHash. Or append the language to the cache key: `"\(contentHash)_\(detectedLanguage ?? "auto")"`.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation - [ColorPicker](https://developer.apple.com/documentation/swiftui/colorpicker) - SwiftUI color picker API
- Apple Developer Documentation - [NSColorPanel](https://developer.apple.com/documentation/appkit/nscolorpanel) - System color panel singleton
- HighlightSwift source code - `HighlightLanguage.swift` enum with ~50 languages and `alias` property
- Codebase analysis - `EditItemView.swift`, `CodeDetectionService.swift`, `ColorDetectionService.swift`, `PanelContentView.swift`, `PanelController.swift`, `ClipboardItem.swift`, `PanelEdge.swift`, `ScreenEdgePicker.swift`, `GeneralSettingsView.swift`

### Secondary (MEDIUM confidence)
- [NSColorPanel usage gist](https://gist.github.com/13db3064ef9ad623ff5a) - Target/action pattern for NSColorPanel in Swift
- [Choosing Colors with Color Wells and Color Panels](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DrawColor/Tasks/ChoosingColors.html) - Apple archive docs on color panel patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components are existing Apple frameworks already used in the project
- Architecture: HIGH - Extends existing patterns (EditItemView, PanelContentView toolbar, AppStorage panelEdge)
- Pitfalls: HIGH - Identified from direct codebase analysis (NSColorPanel singleton, color space conversion, cache invalidation, layout constraints)

**Research date:** 2026-02-19
**Valid until:** 2026-03-19 (stable APIs, no fast-moving dependencies)
