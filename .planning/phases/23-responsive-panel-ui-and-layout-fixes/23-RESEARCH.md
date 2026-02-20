# Phase 23: Responsive Panel UI and Layout Fixes - Research

**Researched:** 2026-02-20
**Domain:** SwiftUI layout, NSPanel frame sizing, responsive UI
**Confidence:** HIGH

## Summary

This phase addresses hardcoded dimensions and layout fragility in the sliding panel UI. The current implementation has several specific problems rooted in magic numbers scattered across `PanelEdge.swift`, `FilteredCardListView.swift`, and `ClipboardCardView.swift`. The panel width (320pt), height (265pt for horizontal), card dimensions (260x195 in horizontal mode), and card min-heights (80/120/140pt) are all hardcoded constants that don't adapt to content changes like multi-line label chips or different screen sizes.

The core issues are: (1) the panel frame in `PanelEdge.panelSize()` uses fixed dimensions that don't account for chip bar height growth when labels wrap to multiple lines, (2) horizontal-mode cards have a rigid `frame(width: 260, height: 195)` that clips content at the bottom, (3) card footers (title + keycap badge) are not bottom-aligned in horizontal mode where all cards should be uniform height, and (4) the panel bottom edge can clip into the screen edge depending on content height.

The fix strategy is straightforward: centralize layout constants, replace hardcoded card heights with flexible sizing using `maxHeight` constraints, use `Spacer()` to push footers to card bottoms in horizontal mode, and make `PanelEdge.panelSize()` accept dynamic content height inputs for the horizontal panel. No new libraries or frameworks are needed -- this is purely a SwiftUI layout restructuring within existing code.

**Primary recommendation:** Centralize all layout constants into a single `PanelLayout` namespace, replace fixed `.frame()` calls with flexible min/max constraints, and use `Spacer()` for footer alignment in horizontal cards.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 14+ | All panel UI views | Already in use, native framework |
| AppKit (NSPanel) | macOS 14+ | Panel window frame management | Already in use for SlidingPanel |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SwiftUI Layout protocol | macOS 13+ | CenteredFlowLayout for chip bar | Already implemented in ChipBarView.swift |
| ViewThatFits | macOS 13+ | Adaptive layout selection | Could replace manual isHorizontal branching in some places |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual isHorizontal checks | ViewThatFits | ViewThatFits auto-selects first fitting child, but panel orientation is user-chosen (not content-driven), so explicit branching is correct here |
| GeometryReader for dynamic sizing | Flexible frame constraints | GeometryReader causes layout loops when writing back to state; prefer min/max frame constraints |

## Architecture Patterns

### Recommended Layout Constants Structure
```
Pastel/
├── Views/Panel/
│   ├── PanelLayout.swift          # NEW: centralized layout constants
│   ├── PanelContentView.swift     # References PanelLayout constants
│   ├── FilteredCardListView.swift # References PanelLayout for card sizing
│   ├── ClipboardCardView.swift    # Uses flexible frame constraints
│   └── ...
├── Models/
│   └── PanelEdge.swift            # panelSize() uses PanelLayout constants
```

### Pattern 1: Centralized Layout Constants
**What:** A single `PanelLayout` enum/struct holding all panel dimension constants.
**When to use:** Whenever a dimension value is referenced in more than one file, or is related to other dimensions (e.g., panel width = card width + 2 * padding).

```swift
/// Centralized panel layout constants.
/// All dimension values that affect panel sizing live here so changes
/// propagate consistently across PanelEdge, PanelContentView, FilteredCardListView, and card views.
enum PanelLayout {
    // Panel outer dimensions
    static let edgeInset: CGFloat = 10
    static let panelOuterPadding: CGFloat = 10
    static let panelCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 10

    // Vertical panel (left/right edges)
    static let verticalPanelWidth: CGFloat = 320

    // Horizontal panel (top/bottom edges)
    static let horizontalPanelHeight: CGFloat = 265
    static let horizontalCardWidth: CGFloat = 260

    // Card dimensions
    static let cardSpacing: CGFloat = 8
    static let cardHorizontalPadding: CGFloat = 14
    static let cardVerticalPadding: CGFloat = 10
    static let cardMinHeightDefault: CGFloat = 80
    static let cardMinHeightImage: CGFloat = 120
    static let cardMinHeightURL: CGFloat = 140
    static let cardMaxHeight: CGFloat = 195
}
```

### Pattern 2: Flexible Card Height with Footer Pinning
**What:** Use `Spacer()` between content and footer in horizontal mode to push the footer (title + keycap badge) to the bottom of the card, ensuring visual alignment across cards of different content heights.
**When to use:** Horizontal panel mode where all cards have the same fixed height.

```swift
// In ClipboardCardView.body:
VStack(alignment: .leading, spacing: 6) {
    // Header row (source app icon + labels + timestamp)
    headerRow

    // Content preview
    contentPreview

    // In horizontal mode, push footer to bottom
    if isHorizontal {
        Spacer(minLength: 0)
    }

    // Footer row (title + keycap badge)
    if hasFooterContent {
        footerRow
    }
}
```

### Pattern 3: Dynamic Horizontal Panel Height
**What:** Instead of a fixed 265pt height for horizontal panels, calculate height based on toolbar height + chip bar height + card height + padding. The chip bar can wrap to multiple lines when many labels exist.
**When to use:** When the user has many labels and the chip bar wraps, the panel should grow to accommodate.

```swift
// In PanelEdge.panelSize(), accept an optional content height override:
func panelSize(screenFrame: NSRect, contentHeight: CGFloat? = nil) -> NSSize {
    let inset = Self.edgeInset
    if isVertical {
        return NSSize(width: PanelLayout.verticalPanelWidth, height: screenFrame.height - 2 * inset)
    } else {
        let height = contentHeight ?? PanelLayout.horizontalPanelHeight
        // Clamp to reasonable bounds (don't exceed half screen)
        let clampedHeight = min(height, screenFrame.height * 0.5)
        return NSSize(width: screenFrame.width - 2 * inset, height: clampedHeight)
    }
}
```

### Anti-Patterns to Avoid
- **GeometryReader writing back to @State:** GeometryReader that reads size and writes to a @State property causes layout loops. If you need to measure chip bar height, use a preference key (one-way communication) or calculate it from label count, not GeometryReader feedback.
- **Mixing hardcoded values:** Never use a raw number in a `.frame()` call. Always reference `PanelLayout` constants. This is the entire point of this phase.
- **Over-engineering dynamic sizing:** The vertical panel (left/right) is already the right width at 320pt. Don't make it dynamically resize -- it would cause jarring UX. Only the horizontal panel height needs flexibility.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Flow layout for chips | Custom flow layout | Existing `CenteredFlowLayout` | Already implemented and working correctly |
| Measuring wrapped chip bar height | GeometryReader + State feedback | Preference key or calculation from label count | GeometryReader feedback loops |
| Bottom-aligned footers | Custom Layout protocol | `Spacer(minLength: 0)` in VStack | Standard SwiftUI pattern, no complexity |

**Key insight:** This phase is about removing complexity (hardcoded values, implicit assumptions) not adding it. The fixes are simple SwiftUI layout adjustments, not new architecture.

## Common Pitfalls

### Pitfall 1: GeometryReader Layout Feedback Loops
**What goes wrong:** Using GeometryReader to measure a view's size, then writing that size to @State, which triggers a re-layout, which changes the GeometryReader size, causing an infinite loop.
**Why it happens:** GeometryReader is a layout primitive that reports size during layout. Writing to @State during layout triggers a new layout pass.
**How to avoid:** Use `.onGeometryChange()` (macOS 15+) or PreferenceKey to communicate sizes upward without blocking layout. For this phase, prefer calculating heights from known inputs (label count, font metrics) rather than measuring.
**Warning signs:** Views flickering, console warnings about "layout loop detected", CPU spike on panel show.

### Pitfall 2: Card Clipping in Horizontal Mode
**What goes wrong:** Cards in horizontal mode have `frame(width: 260, height: 195)` followed by `.clipped()`. If card content (header + content + footer) exceeds 195pt, the footer gets clipped off the bottom.
**Why it happens:** The fixed height doesn't account for variable content like multi-line labels in the header, or URL cards with banners.
**How to avoid:** Use `.frame(width: 260, maxHeight: 195)` without `.clipped()`, or ensure content stays within bounds by limiting content area height. Keep `.clipped()` only as a safety net.
**Warning signs:** Footer keycap badges or title text cut off at the bottom of cards.

### Pitfall 3: Panel Not Accounting for Safe Areas
**What goes wrong:** Panel bottom edge clips into the screen edge or dock area.
**Why it happens:** `PanelEdge.onScreenFrame()` uses `screenFrame.origin.y + inset` for the bottom edge, but the `screenFrame` passed from PanelController already subtracts the menu bar. The dock area is handled by `screen.visibleFrame` but PanelController intentionally uses `screen.frame` (minus menu bar) to cover the dock. The 10pt `edgeInset` may be insufficient.
**How to avoid:** Verify the inset is sufficient on all screen configurations. The current approach of covering the dock is intentional (panel floats above dock at `.statusBar` level). Ensure the panel content has enough internal padding so content doesn't touch the panel edges.
**Warning signs:** Content appearing to clip into screen edges, especially on smaller displays or with dock visible.

### Pitfall 4: NSPanel Frame vs SwiftUI Content Size Mismatch
**What goes wrong:** The NSPanel frame is set by `PanelEdge.onScreenFrame()` at the AppKit level, but the SwiftUI content inside may want a different size. If the panel is too small for the content, scrolling works for vertical mode but horizontal mode clips.
**Why it happens:** AppKit and SwiftUI have separate layout systems. The NSHostingView with `sizingOptions = []` means SwiftUI takes whatever size AppKit gives it.
**How to avoid:** Ensure the constants in `PanelLayout` are used consistently by both `PanelEdge` (AppKit frame) and SwiftUI views. The panel frame must always be large enough for the non-scrollable header/toolbar/chip-bar content.
**Warning signs:** Chip bar getting clipped at the bottom, search field not fully visible.

### Pitfall 5: Breaking the Git Checkpoint Requirement
**What goes wrong:** Making many changes without a revert point, then discovering the layout is worse than before.
**Why it happens:** Layout changes are visually subtle and hard to verify without running the app.
**How to avoid:** Create a git tag/branch before starting changes. The user specifically requested remembering a git checkpoint for reverting.
**Warning signs:** Forgetting to create the checkpoint before modifying files.

## Code Examples

### Current Hardcoded Values That Need Centralizing

```swift
// PanelEdge.swift line 24 -- panel width for vertical edges
return NSSize(width: 320, height: screenFrame.height - 2 * inset)

// PanelEdge.swift line 26 -- panel height for horizontal edges
return NSSize(width: screenFrame.width - 2 * inset, height: 265)

// PanelEdge.swift line 15 -- edge inset
private static let edgeInset: CGFloat = 10

// FilteredCardListView.swift line 146 -- horizontal card size
.frame(width: 260, height: 195)

// PanelContentView.swift line 14 -- outer padding
static let panelOuterPadding: CGFloat = 10

// ClipboardCardView.swift line 113 -- card frame
.frame(maxWidth: .infinity, minHeight: cardMinHeight, maxHeight: 195, alignment: .topLeading)

// ClipboardCardView.swift lines 352-359 -- card min heights
private var cardMinHeight: CGFloat {
    if item.type == .image { return 120 }
    else if item.type == .url && item.urlPreviewImagePath != nil { return 140 }
    else { return 80 }
}

// PanelController.swift line 391 -- corner radius
containerView.layer?.cornerRadius = 12

// PanelController.swift line 441 -- glass corner radius
glassView.cornerRadius = 12
```

### Footer Alignment Fix for Horizontal Mode

```swift
// ClipboardCardView.swift -- add isHorizontal check and Spacer
@AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

private var isHorizontal: Bool {
    let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
    return !edge.isVertical
}

var body: some View {
    VStack(alignment: .leading, spacing: 6) {
        // Header row
        HStack(spacing: 4) { /* ... existing header ... */ }

        // Content preview
        contentPreview

        // Push footer to bottom in horizontal mode (uniform card height)
        if isHorizontal {
            Spacer(minLength: 0)
        }

        // Footer row
        if hasFooterContent {
            HStack(spacing: 4) { /* ... existing footer ... */ }
        }
    }
    .padding(.horizontal, PanelLayout.cardHorizontalPadding)
    .padding(.vertical, PanelLayout.cardVerticalPadding)
    .frame(maxWidth: .infinity, minHeight: cardMinHeight, maxHeight: PanelLayout.cardMaxHeight, alignment: .topLeading)
}
```

### Making PanelEdge Use Centralized Constants

```swift
// PanelEdge.swift -- reference PanelLayout instead of magic numbers
func panelSize(screenFrame: NSRect) -> NSSize {
    let inset = PanelLayout.edgeInset
    if isVertical {
        return NSSize(
            width: PanelLayout.verticalPanelWidth,
            height: screenFrame.height - 2 * inset
        )
    } else {
        return NSSize(
            width: screenFrame.width - 2 * inset,
            height: PanelLayout.horizontalPanelHeight
        )
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| GeometryReader for responsive layout | `ViewThatFits` + flexible frames | macOS 13 / WWDC 2022 | Simpler adaptive layouts without feedback loops |
| Manual size calculation | `.containerRelativeFrame()` | macOS 14 / WWDC 2023 | Size relative to container without GeometryReader |
| `.onAppear` + GeometryReader for size | `.onGeometryChange()` | macOS 15 / WWDC 2024 | Safe size observation without layout loops |

**Note:** The project targets macOS 14+, so `ViewThatFits` and `.containerRelativeFrame()` are available. `.onGeometryChange()` requires macOS 15 so use with `if #available` guard or avoid in favor of preference keys.

## Open Questions

1. **Should the horizontal panel height be truly dynamic (grow with chip bar)?**
   - What we know: The chip bar uses `CenteredFlowLayout` and wraps to multiple lines. The current fixed 265pt height may clip when many labels exist.
   - What's unclear: Whether dynamically growing the panel height would look good or cause jarring resizing during label filter changes. Would require communicating chip bar height from SwiftUI back to PanelController (AppKit).
   - Recommendation: Start with a conservative approach -- increase the fixed horizontal height slightly (e.g., 280pt) and limit chip bar to 2 visible lines with horizontal scrolling or truncation. True dynamic height can be a follow-up if needed.

2. **Should card max height differ between vertical and horizontal modes?**
   - What we know: Horizontal cards are fixed at 260x195. Vertical cards grow naturally with content (minHeight 80, maxHeight 195).
   - What's unclear: Whether 195 is the right max for both modes. Horizontal mode cards might benefit from a taller max since the panel is shorter.
   - Recommendation: Keep the same maxHeight for both modes initially. The 195pt max is reasonable -- it prevents any single card from dominating the view.

3. **How to handle the chip bar overflow in horizontal mode?**
   - What we know: In horizontal mode, the toolbar is a single HStack: logo + search + chips + buttons. When many labels exist, chips can overflow.
   - What's unclear: Whether to scroll horizontally, truncate, or wrap to a second line.
   - Recommendation: In horizontal mode, limit the chip bar to a horizontal scroll (no wrapping) since vertical space is precious. In vertical mode, keep the current wrapping behavior.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: Direct reading of all panel-related Swift files (PanelEdge.swift, PanelController.swift, PanelContentView.swift, FilteredCardListView.swift, ClipboardCardView.swift, ChipBarView.swift, SlidingPanel.swift, all card subviews)
- Apple SwiftUI docs via Context7 (`/websites/developer_apple_swiftui`) - ViewThatFits, Layout protocol, GeometryReader

### Secondary (MEDIUM confidence)
- SwiftUI layout best practices (ViewThatFits vs GeometryReader tradeoffs) - verified against Apple documentation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - no new dependencies, pure SwiftUI/AppKit layout work in existing codebase
- Architecture: HIGH - all files read and analyzed, hardcoded values fully catalogued
- Pitfalls: HIGH - pitfalls identified from direct code analysis (not theoretical)

**Research date:** 2026-02-20
**Valid until:** 2026-04-20 (stable -- SwiftUI layout fundamentals don't change fast)
