# Phase 12: History Browser and Bulk Actions - Research

**Researched:** 2026-02-08
**Domain:** SwiftUI grid layout, multi-selection, bulk clipboard operations, NSWindow resizing
**Confidence:** HIGH

## Summary

This phase adds a "History" tab to the existing Settings window that displays clipboard items in a responsive grid layout with multi-select and bulk operations (copy, paste, delete). The implementation is entirely within the existing SwiftUI + AppKit architecture -- no new libraries or external dependencies are needed.

The core technical challenges are: (1) building a responsive grid using `LazyVGrid` with `GridItem(.adaptive)` that reflows as the settings window resizes, (2) implementing Cmd-click and Shift-click multi-selection on a grid (SwiftUI's built-in List selection does not apply to grids, so custom selection state management is required), (3) concatenating selected items' text content for bulk copy/paste, and (4) making the settings window resizable by adding `.resizable` to its NSWindow `styleMask`.

**Primary recommendation:** Reuse existing `ClipboardCardView`, `SearchFieldView`, `ChipBarView`, and the `FilteredCardListView` query pattern (init-based `@Query` with `.id()` recreation), but build a new `HistoryGridView` that arranges cards in a `LazyVGrid(.adaptive)` instead of `LazyVStack`. Implement multi-selection as a `Set<PersistentIdentifier>` managed by the History tab view, with Cmd-click toggle and Shift-click range selection. For bulk operations, concatenate `textContent` with `\n` separators and use `NSPasteboard.general` directly (no PasteService needed for settings window context).

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI `LazyVGrid` | macOS 14+ | Responsive card grid | Built-in, lazy rendering, supports `.adaptive` GridItem for automatic reflow |
| SwiftUI `GridItem(.adaptive)` | macOS 14+ | Dynamic column count | Automatically computes column count from available width and minimum item size |
| SwiftData `@Query` | macOS 14+ | Data fetching | Already used throughout app; same init-based predicate pattern as FilteredCardListView |
| `NSPasteboard.general` | macOS 14+ | Clipboard write for bulk copy | Direct pasteboard access for concatenated text; already used in PasteService |
| `.confirmationDialog` | macOS 14+ | Delete confirmation | SwiftUI built-in; auto-includes cancel button; supports `.destructive` role buttons |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `NSWindow.styleMask` `.resizable` | macOS 14+ | Make settings window resizable | Add to SettingsWindowController's NSWindow creation |
| `PasteService` | existing | Paste-back for bulk paste | Only needed for "Paste" action (simulates Cmd+V); Copy action uses NSPasteboard directly |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `LazyVGrid(.adaptive)` | Fixed-column `LazyVGrid` | Adaptive auto-reflows on resize; fixed columns require manual GeometryReader calculation |
| Custom `Set<PersistentIdentifier>` selection | SwiftUI `List` with selection binding | List has built-in multi-select on macOS but forces list layout, not grid |
| `.confirmationDialog` | `.alert` | Both work on macOS; `.alert` already used in GeneralSettingsView for "Clear All History"; either is fine but `.alert` is more consistent with existing codebase |

## Architecture Patterns

### Recommended Project Structure
```
Pastel/Views/Settings/
  SettingsView.swift            # Add .history case to SettingsTab enum
  SettingsWindowController.swift # Add .resizable to styleMask, increase frame size
  HistoryBrowserView.swift      # NEW: History tab root (search + chips + grid + toolbar)
  HistoryGridView.swift         # NEW: LazyVGrid with @Query, multi-select, card rendering
```

### Pattern 1: Adaptive Grid with LazyVGrid
**What:** Use `GridItem(.adaptive(minimum: 280))` to create a responsive grid that automatically reflows columns based on available width.
**When to use:** The History tab grid layout.
**Example:**
```swift
// Source: Apple LazyVGrid docs + Hacking with Swift verified
private let columns = [
    GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 12)
]

ScrollView {
    LazyVGrid(columns: columns, spacing: 12) {
        ForEach(filteredItems) { item in
            ClipboardCardView(item: item, isSelected: selectedIDs.contains(item.persistentModelID))
                .onTapGesture { handleTap(item: item) }
        }
    }
    .padding(12)
}
```

### Pattern 2: Init-Based @Query with .id() Recreation (existing pattern)
**What:** Construct `@Query` predicate in `init`, use `.id()` modifier with all filter inputs to force view recreation when filters change.
**When to use:** The `HistoryGridView` must follow the same pattern as `FilteredCardListView`.
**Example:**
```swift
// Source: Existing FilteredCardListView.swift pattern
struct HistoryGridView: View {
    @Query private var items: [ClipboardItem]
    private let selectedLabelIDs: Set<PersistentIdentifier>

    init(searchText: String, selectedLabelIDs: Set<PersistentIdentifier>, ...) {
        self.selectedLabelIDs = selectedLabelIDs
        let predicate: Predicate<ClipboardItem>
        if !searchText.isEmpty {
            let search = searchText
            predicate = #Predicate<ClipboardItem> { item in
                item.textContent?.localizedStandardContains(search) == true ||
                item.sourceAppName?.localizedStandardContains(search) == true ||
                item.title?.localizedStandardContains(search) == true
            }
        } else {
            predicate = #Predicate<ClipboardItem> { _ in true }
        }
        _items = Query(filter: predicate, sort: \ClipboardItem.timestamp, order: .reverse)
    }

    // In-memory label filtering (same as FilteredCardListView)
    private var filteredItems: [ClipboardItem] {
        guard !selectedLabelIDs.isEmpty else { return items }
        return items.filter { item in
            item.labels.contains { label in
                selectedLabelIDs.contains(label.persistentModelID)
            }
        }
    }
}
```

### Pattern 3: Custom Multi-Selection with Cmd-Click and Shift-Click
**What:** Manage a `Set<PersistentIdentifier>` for selected items. Cmd-click toggles individual items. Shift-click selects a range from the last-clicked item.
**When to use:** Grid multi-selection (SwiftUI List selection does not work with grids).
**Example:**
```swift
@State private var selectedIDs: Set<PersistentIdentifier> = []
@State private var lastClickedIndex: Int? = nil

private func handleTap(item: ClipboardItem, index: Int, modifiers: EventModifiers) {
    let id = item.persistentModelID
    if modifiers.contains(.command) {
        // Cmd-click: toggle individual selection
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        lastClickedIndex = index
    } else if modifiers.contains(.shift), let anchor = lastClickedIndex {
        // Shift-click: range selection
        let range = min(anchor, index)...max(anchor, index)
        for i in range {
            selectedIDs.insert(filteredItems[i].persistentModelID)
        }
    } else {
        // Plain click: single selection
        selectedIDs = [id]
        lastClickedIndex = index
    }
}
```

### Pattern 4: Bulk Copy with Newline Concatenation
**What:** Concatenate `textContent` of selected items with `\n` separator and write to `NSPasteboard.general`.
**When to use:** "Copy" and "Copy + Paste" bulk actions.
**Example:**
```swift
private func bulkCopy() {
    let selectedItems = filteredItems.filter { selectedIDs.contains($0.persistentModelID) }
    // Maintain chronological order (items are already sorted by timestamp desc)
    let concatenated = selectedItems
        .compactMap { $0.textContent }
        .joined(separator: "\n")

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(concatenated, forType: .string)
}
```

### Pattern 5: Settings Window Resize Support
**What:** Add `.resizable` to the NSWindow styleMask and adjust frame constraints.
**When to use:** SettingsWindowController modification.
**Example:**
```swift
// In SettingsWindowController.showSettings()
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 700, height: 550),
    styleMask: [.titled, .closable, .resizable],  // ADD .resizable
    backing: .buffered,
    defer: true
)
// Also update SettingsView frame constraints:
.frame(minWidth: 500, minHeight: 480)  // Remove maxWidth constraint for resizability
```

### Anti-Patterns to Avoid
- **Using SwiftUI List for the grid:** List forces a single-column list layout. Use LazyVGrid for multi-column responsive grid.
- **Modifying @Query predicate after init:** @Query predicate is immutable after init. Must use `.id()` pattern to force view recreation.
- **Using #Predicate .contains() on to-many relationships:** SwiftData crashes. Continue using in-memory post-filtering (established in Phase 11).
- **Calling PasteService.paste from settings window:** PasteService hides the panel and targets the "previous app." The History browser is in the settings window, not the panel. For paste-back from settings, write to pasteboard and simulate Cmd+V directly, or simply copy-only (let user Cmd+V manually). The settings window is a regular activating window, so the paste flow differs from the panel flow.
- **Removing maxWidth from the entire SettingsView:** Other tabs (General, Labels) look best at fixed width. Use conditional frame constraints -- fixed width for General/Labels, flexible for History tab.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Responsive grid column calculation | Manual GeometryReader + column math | `GridItem(.adaptive(minimum: 280))` | SwiftUI handles column count automatically based on available width |
| Confirmation dialog with cancel | Custom alert view | `.confirmationDialog()` or `.alert()` | Built-in cancel handling, destructive button styling, automatic dismiss |
| Debounced search | Custom Timer debounce | `.task(id: searchText)` with `Task.sleep` | Already proven pattern in PanelContentView (200ms debounce) |
| In-memory label filtering | Custom fetch descriptor | Existing `filteredItems` computed property pattern | Already battle-tested in FilteredCardListView; SwiftData #Predicate cannot handle to-many .contains() |

**Key insight:** Almost every component needed already exists in the codebase. The History browser is essentially a re-composition of existing views (ClipboardCardView, SearchFieldView, ChipBarView) in a grid layout with added multi-select. The only truly new code is: (1) the grid layout container, (2) multi-selection state management, and (3) bulk action toolbar.

## Common Pitfalls

### Pitfall 1: Settings Window Not Resizable
**What goes wrong:** The current SettingsWindowController creates an NSWindow without `.resizable` in styleMask, and SettingsView has `maxWidth: 500` which prevents expansion.
**Why it happens:** Original settings design was fixed-size for simple content.
**How to avoid:** Add `.resizable` to styleMask. Make SettingsView frame flexible for History tab. Use conditional sizing: General/Labels can stay at fixed width, History tab expands to fill.
**Warning signs:** Grid shows only one column despite window being wide.

### Pitfall 2: @Query Not Updating When Filters Change
**What goes wrong:** Grid shows stale results when search text or label filter changes.
**Why it happens:** SwiftData `@Query` predicate is set once in `init` and never updates dynamically.
**How to avoid:** Use the established `.id()` pattern with ALL filter inputs concatenated into the id string. This forces SwiftUI to destroy and recreate the view with a fresh `@Query`.
**Warning signs:** Typing in search field has no effect on displayed items.

### Pitfall 3: Shift-Click Range Selection Breaks with Filtered Items
**What goes wrong:** Shift-click selects wrong items because index mapping changes after label filtering.
**Why it happens:** Selection indices are based on `filteredItems` array but if the filter changes between clicks, the anchor index points to a different item.
**How to avoid:** Store the anchor as a `PersistentIdentifier` (stable across filter changes) rather than an integer index. When computing range for shift-click, find both the anchor item and clicked item in the current `filteredItems` array and select the range between them.
**Warning signs:** Shift-click selects unexpected items or crashes with out-of-bounds.

### Pitfall 4: Paste-Back from Settings Window vs Panel
**What goes wrong:** Using PasteService.paste() from the History browser hides the panel (not the settings window) and targets the wrong "previous app."
**Why it happens:** PasteService is wired to hide the panel and paste to the app that was active before the panel opened. The settings window is a different context.
**How to avoid:** For the settings History browser, "Paste" should: (1) write to pasteboard, (2) minimize/hide the settings window, (3) simulate Cmd+V after a delay. Or simply make "Paste" equivalent to "Copy" and let the user paste manually. Recommendation: implement "Copy" (write to pasteboard only) and "Paste" (write to pasteboard + simulate Cmd+V after hiding settings window).
**Warning signs:** Paste action from History tab pastes into wrong window or hides panel instead of settings.

### Pitfall 5: Non-Text Items in Bulk Copy
**What goes wrong:** Images, files, and color items have no `textContent` or their textContent is a file path, which is not meaningful to concatenate.
**Why it happens:** Not all clipboard items are text-based.
**How to avoid:** For bulk copy, only concatenate items that have meaningful textContent (text, richText, url, code, color types). Skip image and file items, or include their file paths. Show a warning or just silently skip. For images, bulk copy does not make sense -- consider disabling bulk copy when selection includes image-only items.
**Warning signs:** Pasted text includes UUID filenames or empty lines.

### Pitfall 6: Large Selection Set Performance
**What goes wrong:** Selecting hundreds of items causes UI lag when computing `selectedIDs.contains()` in every card.
**Why it happens:** LazyVGrid still evaluates visibility for all items; `Set.contains` is O(1) but re-rendering many selected cards can be slow.
**How to avoid:** LazyVGrid naturally handles this by only rendering visible items. The `Set<PersistentIdentifier>` lookup is O(1). Should be fine for typical history sizes.
**Warning signs:** Scrolling becomes choppy with many selected items.

### Pitfall 7: Settings Window Size Changes Break Other Tabs
**What goes wrong:** Making the window resizable causes General and Labels tabs to stretch awkwardly.
**Why it happens:** These tabs were designed for fixed ~500pt width.
**How to avoid:** Use per-tab frame constraints. General and Labels views keep their fixed-width layout (centered in available space), while History view expands to fill. The SettingsView can apply different frame modifiers based on the selected tab.
**Warning signs:** General settings form stretches to full window width with huge gaps.

## Code Examples

### Verified: LazyVGrid with Adaptive Columns
```swift
// Source: Apple docs + Hacking with Swift (verified)
let columns = [
    GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 12)
]

ScrollView {
    LazyVGrid(columns: columns, spacing: 12) {
        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
            ClipboardCardView(
                item: item,
                isSelected: selectedIDs.contains(item.persistentModelID)
            )
            .onTapGesture {
                handleTap(item: item, index: index)
            }
        }
    }
    .padding(12)
}
```

### Verified: Confirmation Dialog for Bulk Delete
```swift
// Source: useyourloaf.com confirmed pattern, matches existing .alert usage in GeneralSettingsView
@State private var showDeleteConfirmation = false

// Trigger
Button("Delete", role: .destructive) {
    showDeleteConfirmation = true
}
.disabled(selectedIDs.isEmpty)

// Dialog
.alert("Delete \(selectedIDs.count) Items", isPresented: $showDeleteConfirmation) {
    Button("Delete", role: .destructive) {
        performBulkDelete()
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This will permanently delete \(selectedIDs.count) clipboard items. This action cannot be undone.")
}
```

### Verified: Detecting Modifier Keys on Tap
```swift
// Source: Codebase pattern (NSEvent.addLocalMonitorForEvents used in PanelContentView for shift detection)
// For detecting Cmd and Shift on click in the grid:
// Option A: Use onTapGesture + NSEvent.modifierFlags
.onTapGesture {
    let modifiers = NSEvent.modifierFlags
    if modifiers.contains(.command) {
        toggleSelection(item)
    } else if modifiers.contains(.shift) {
        extendSelection(to: item, index: index)
    } else {
        selectSingle(item, index: index)
    }
}
```

### Verified: Writing Concatenated Text to Pasteboard
```swift
// Source: Existing PasteService.writeToPasteboard pattern
func bulkCopySelectedItems() {
    let selected = filteredItems.filter { selectedIDs.contains($0.persistentModelID) }
    let textParts = selected.compactMap { item -> String? in
        switch item.type {
        case .text, .richText, .url, .code, .color:
            return item.textContent
        case .image, .file:
            return nil  // Skip non-text items
        }
    }
    guard !textParts.isEmpty else { return }

    let concatenated = textParts.joined(separator: "\n")
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(concatenated, forType: .string)
}
```

### Verified: Making Settings Window Resizable
```swift
// Source: Existing SettingsWindowController.swift pattern + NSWindow API
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 700, height: 550),
    styleMask: [.titled, .closable, .resizable],  // Add .resizable
    backing: .buffered,
    defer: true
)
window.minSize = NSSize(width: 500, height: 480)  // Prevent shrinking below usable size
```

### Verified: Bulk Delete with Image Cleanup
```swift
// Source: Existing AppState.clearAllHistory pattern + ClipboardCardView.deleteItem
func performBulkDelete() {
    let itemsToDelete = filteredItems.filter { selectedIDs.contains($0.persistentModelID) }
    for item in itemsToDelete {
        // Clean up disk images
        ImageStorageService.shared.deleteImage(
            imagePath: item.imagePath,
            thumbnailPath: item.thumbnailPath
        )
        ImageStorageService.shared.deleteImage(
            imagePath: item.urlFaviconPath,
            thumbnailPath: item.urlPreviewImagePath
        )
        item.labels.removeAll()  // Clear many-to-many before delete
        modelContext.delete(item)
    }
    try? modelContext.save()
    selectedIDs.removeAll()
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Fixed column grids | `GridItem(.adaptive)` auto-reflow | SwiftUI 2.0 (2020) | No manual column calculation needed |
| ActionSheet (iOS) / custom alert | `.confirmationDialog` | SwiftUI 3.0 (2021) / macOS 12 | Cross-platform confirmation with destructive role support |
| NSTableView multi-select | SwiftUI `List` selection + custom grid selection | SwiftUI 2.0+ | SwiftUI List has built-in multi-select on macOS; grids require custom implementation |

**Deprecated/outdated:**
- `ActionSheet` is deprecated in favor of `.confirmationDialog`, but for macOS this project uses `.alert` already and that remains valid.

## Open Questions

1. **Paste-back behavior from settings window**
   - What we know: PasteService is coupled to the panel (hides panel, targets previous app). Settings window is a regular NSWindow.
   - What's unclear: Should "Paste" from History tab hide the settings window and simulate Cmd+V? Or should it just copy to clipboard?
   - Recommendation: Implement both. "Copy" writes to pasteboard only. "Paste" writes to pasteboard, hides settings window, and simulates Cmd+V after a delay (same as panel paste flow but targeting settings window close instead of panel hide). Since the settings window is a standard activating window, the previously active app should regain focus after close/minimize.

2. **Card size in grid vs panel**
   - What we know: Cards in the panel have no explicit width (fill available width). In a grid, each card needs bounded dimensions.
   - What's unclear: Exact minimum/maximum card width for visual balance.
   - Recommendation: Use `GridItem(.adaptive(minimum: 280, maximum: 400))` as a starting point. Cards already have `maxHeight: 195` from ClipboardCardView. This gives 1 column at 500pt width, 2 at ~600pt, 3 at ~900pt.

3. **Select All keyboard shortcut**
   - What we know: Cmd+A is standard for select all on macOS.
   - What's unclear: Whether this is required for Phase 12 MVP.
   - Recommendation: Implement Cmd+A (select all) and Escape (deselect all) as keyboard shortcuts in the History tab. Low effort, high UX value.

4. **Toolbar placement for bulk actions**
   - What we know: Need Copy, Paste, Delete buttons when items are selected.
   - What's unclear: Where to place them -- floating toolbar, bottom bar, or inline with search?
   - Recommendation: Bottom action bar that appears when `selectedIDs.count > 0`. Shows "N items selected" + Copy + Paste + Delete buttons. This follows standard macOS selection toolbar patterns.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `FilteredCardListView.swift` -- init-based @Query pattern, in-memory label filtering
- Existing codebase: `PanelContentView.swift` -- search + chip bar + .id() recreation pattern
- Existing codebase: `ClipboardCardView.swift` -- card rendering, context menu, delete with image cleanup
- Existing codebase: `SettingsWindowController.swift` -- NSWindow creation pattern
- Existing codebase: `PasteService.swift` -- pasteboard write and Cmd+V simulation
- [Hacking with Swift - LazyVGrid](https://www.hackingwithswift.com/quick-start/swiftui/how-to-position-views-in-a-grid-using-lazyvgrid-and-lazyhgrid) -- GridItem adaptive API
- [Use Your Loaf - Confirmation Dialogs](https://useyourloaf.com/blog/swiftui-confirmation-dialogs/) -- .confirmationDialog API

### Secondary (MEDIUM confidence)
- [Apple LazyVGrid docs](https://developer.apple.com/documentation/swiftui/lazyvgrid) -- official API reference (JS-gated, verified via secondary sources)

### Tertiary (LOW confidence)
- None -- all findings verified against codebase or official sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components are built-in SwiftUI/AppKit, already used in codebase
- Architecture: HIGH - Patterns directly mirror existing FilteredCardListView and PanelContentView
- Pitfalls: HIGH - Derived from known SwiftData quirks documented in project memory + codebase analysis
- Multi-selection: MEDIUM - Cmd/Shift click detection via NSEvent.modifierFlags is standard but not yet used in this exact grid context in the codebase
- Paste-back from settings: MEDIUM - Different context from panel; needs careful handling

**Research date:** 2026-02-08
**Valid until:** 2026-03-10 (stable -- SwiftUI grid APIs have not changed since macOS 14)
