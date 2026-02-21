# Phase 26: Panel Performance Optimization - Research

**Researched:** 2026-02-21
**Domain:** SwiftUI/SwiftData rendering pipeline performance, NSPanel lifecycle
**Confidence:** HIGH

## Summary

The panel suffers from three distinct performance problems, each with identifiable root causes in the current architecture. After thorough analysis of the codebase, the bottlenecks are:

1. **First-open lag**: The `.id()` modifier on `FilteredCardListView` includes `appState.itemCount`, which changes on every clipboard capture. This forces a **full view destruction and recreation** every time the panel opens if any items were captured since last open. The entire `@Query` re-executes, all LazyVStack children are discarded, and the SwiftUI view hierarchy is rebuilt from scratch. Additionally, `AppIconColorService.dominantColor()` runs synchronously with CIFilter on the main thread for each card's `.task` modifier on first appearance.

2. **Scroll jank**: When scrolling to unseen cards, multiple expensive operations fire simultaneously per card: (a) `AppIconColorService.dominantColor()` runs CIFilter GPU work synchronously on the main thread, (b) `NSWorkspace.shared.appIcon(forBundleIdentifier:)` is called per card without caching, (c) code cards trigger async HighlightSwift highlighting, (d) image/URL cards trigger disk I/O via `NSImage(contentsOf:)`, and (e) the `filteredItems` computed property re-evaluates on every body call, iterating all items for sync + label filtering.

3. **Label filter switch latency**: Changing `selectedLabelIDs` changes the `.id()` string on `FilteredCardListView`, triggering full view recreation. The `@Query` re-fetches all items from SwiftData, then `filteredItems` re-filters them in-memory. Since the query fetches ALL items (no fetchLimit), this is O(n) on the entire clipboard history.

**Primary recommendation:** Eliminate the `.id()` nuclear recreation pattern; use `@Query` with in-memory filtering reactively. Cache expensive per-card computations (app icons, dominant colors). Add pagination via `fetchLimit` to bound query cost. Pre-warm caches when the panel is hidden.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 14+ | View layer | Already in use, LazyVStack/LazyHStack provide view recycling |
| SwiftData | macOS 14+ | Persistence + query | Already in use, supports fetchLimit/fetchOffset |
| HighlightSwift | Current | Code syntax highlighting | Already in use, async with caching |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| os.signpost | macOS 14+ | Performance measurement | Instrument specific bottlenecks during development |
| OSLog | macOS 14+ | Structured logging | Already in use, add performance-specific subsystem |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftData @Query | Manual FetchDescriptor | More control over fetch timing but loses automatic observation |
| In-memory label filtering | Custom SQLite query | Would eliminate O(n) filtering but adds complexity and breaks SwiftData abstraction |
| NSImage(contentsOf:) for thumbnails | CGImageSource thumbnail API | Faster for large images but thumbnails are already 200px, marginal gain |

## Architecture Patterns

### Pattern 1: Eliminate .id() Nuclear Recreation
**What:** Remove `appState.itemCount` from the `.id()` modifier so that new clipboard items don't force full view destruction/recreation. Instead, rely on `@Query`'s built-in observation to reactively update the item list.
**When to use:** The `.id()` was a workaround for `@Query` inside `NSHostingView/NSPanel` not reliably auto-observing new insertions. The fix should test whether removing `itemCount` from `.id()` works with the current SwiftData version, and if not, find a lighter-weight refresh mechanism (e.g., toggling a dummy query parameter).
**Why it matters:** `.id()` change = entire FilteredCardListView is destroyed and recreated. All child views (cards) are torn down and rebuilt. All `.task` modifiers re-fire. All scroll position is lost.

```swift
// CURRENT (causes full recreation on every new clipboard item):
FilteredCardListView(...)
    .id("\(appState.itemCount)\(debouncedSearchText)\(selectedLabelIDs...)")

// PROPOSED (only recreate on actual filter changes):
FilteredCardListView(...)
    .id("\(debouncedSearchText)\(selectedLabelIDs...)")
// If @Query auto-observation works in NSPanel, itemCount is unnecessary.
// If it doesn't, use a lighter mechanism like:
//   .onChange(of: appState.itemCount) { /* trigger minimal refresh */ }
```

### Pattern 2: Cache Expensive Per-Card Computations
**What:** Cache `NSWorkspace.shared.appIcon(forBundleIdentifier:)` results and ensure `AppIconColorService.dominantColor()` doesn't re-run CIFilter for already-cached bundle IDs. Currently, the color service caches results, but `NSWorkspace.shared.appIcon()` is called fresh on every card appearance.
**When to use:** Every card view creation.

```swift
// App icon cache (new service or extend AppIconColorService)
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        let icon = NSWorkspace.shared.appIcon(forBundleIdentifier: bundleID)
        if let icon { cache[bundleID] = icon }
        return icon
    }
}
```

### Pattern 3: Paginated Query with fetchLimit
**What:** Use `fetchLimit` on the `@Query` to fetch only the first N items (e.g., 50-100), with a "load more" trigger when scrolling near the end. This bounds the cost of both the query and the in-memory filtering.
**When to use:** When the clipboard history is large (hundreds or thousands of items).
**Caveat:** Label filtering is done in-memory post-query. With fetchLimit, a label filter might show fewer results than expected because the limit applies before filtering. Solutions: (a) fetch more items than displayed (e.g., fetchLimit = 200, show 50), or (b) when a label filter is active, accept showing only matching items from the fetched batch and load more on scroll.

```swift
// In FilteredCardListView init:
_items = Query(
    filter: predicate,
    sort: \ClipboardItem.timestamp,
    order: .reverse
)
// Note: @Query doesn't support fetchLimit directly in the property wrapper.
// May need to use FetchDescriptor with modelContext.fetch() instead,
// or slice filteredItems with a @State page size.
```

### Pattern 4: Pre-warm Caches While Panel is Hidden
**What:** When new clipboard items are captured while the panel is hidden, pre-compute expensive data: app icon + dominant color for the source app. This moves work off the panel-open critical path.
**When to use:** In `ClipboardMonitor.onItemCountChanged` callback.

```swift
// In AppState or ClipboardMonitor, after capturing a new item:
func preWarmCaches(for item: ClipboardItem) {
    if let bundleID = item.sourceAppBundleID {
        _ = AppIconCache.shared.icon(forBundleID: bundleID)
        _ = AppIconColorService.shared.dominantColor(forBundleID: bundleID)
    }
}
```

### Pattern 5: Memoize filteredItems
**What:** The `filteredItems` computed property iterates ALL queried items on every body evaluation, applying sync filtering + label filtering. This should be cached and only recomputed when `items` or `selectedLabelIDs` change.
**When to use:** Always -- this is a hot path that runs on every scroll event that causes any state change.

```swift
// Instead of computed property, use @State with onChange:
@State private var filteredItems: [ClipboardItem] = []

.onChange(of: items) { _, newItems in
    filteredItems = computeFilteredItems(from: newItems)
}
.onChange(of: selectedLabelIDs) { _, _ in
    filteredItems = computeFilteredItems(from: items)
}
```

### Anti-Patterns to Avoid
- **Using `.id()` with rapidly-changing values:** `.id()` is a nuclear option that destroys and recreates the entire view subtree. Never include values that change frequently (like item count) in `.id()`.
- **Synchronous CIFilter on main thread:** `AppIconColorService.dominantColor()` runs `CIFilter(name: "CIAreaAverage")` and `CIContext.render()` synchronously. While individual calls are fast (~1-2ms), many cards appearing simultaneously compound into visible lag.
- **Unbounded @Query without fetchLimit:** Fetching ALL items and filtering in-memory means performance degrades linearly with history size.
- **Creating objects in view body:** The `relativeTimeString(for:)` method in ClipboardCardView and `filteredItems` computed property run on every body evaluation.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Image caching | Custom LRU cache for thumbnails | NSCache with async loading | NSCache handles memory pressure automatically |
| View recycling | Manual view pool | LazyVStack/LazyHStack (already used) | SwiftUI handles view lifecycle correctly |
| Scroll position preservation | Manual offset tracking | ScrollViewReader + .scrollPosition (macOS 14+) | Built-in API handles edge cases |
| Performance measurement | print() timestamps | os.signpost + Instruments | Structured, zero-cost in production, visual timeline |

**Key insight:** The performance problems are primarily architectural (`.id()` recreation, unbounded queries, uncached computations) rather than algorithmic. The fixes are straightforward refactors, not new systems.

## Common Pitfalls

### Pitfall 1: @Query Not Updating in NSPanel
**What goes wrong:** `@Query` inside `NSHostingView` hosted in an `NSPanel` may not reliably observe new SwiftData insertions from the `ClipboardMonitor`.
**Why it happens:** The `NSPanel` is created once and reused. SwiftData observation may depend on the `NSHostingView` being part of a properly configured window hierarchy. The original `.id(appState.itemCount)` was added specifically to work around this.
**How to avoid:** Test thoroughly after removing `itemCount` from `.id()`. If `@Query` doesn't auto-update, use a lighter mechanism: a `refreshTrigger` UUID that changes on panel show, or `modelContext.fetch()` explicitly in `.task` on panel appearance.
**Warning signs:** New clipboard items not appearing in the panel until a filter change or panel toggle.

### Pitfall 2: filteredItems Recomputation Breaking Indices
**What goes wrong:** Moving `filteredItems` from a computed property to `@State` can cause index mismatches if the state update is async and the UI reads stale indices.
**Why it happens:** The `ForEach(Array(filteredItems.enumerated()))` pattern uses index-based `.id(index)`, which can cause view identity issues if the array changes while views are still visible.
**How to avoid:** Use `\.element.id` (the ClipboardItem's persistent ID) as the ForEach id instead of enumeration index. Map selected index to item ID for selection tracking.
**Warning signs:** Wrong card selected after filter change, cards jumping positions.

### Pitfall 3: fetchLimit Interacting Poorly with Label Filtering
**What goes wrong:** If `fetchLimit = 50` and only 3 of those 50 items match the selected label, the user sees only 3 items even though hundreds more exist in the database that match.
**Why it happens:** Label filtering happens in-memory AFTER the fetch, because `#Predicate` can't query to-many relationships.
**How to avoid:** When a label filter is active, either remove the fetchLimit or increase it significantly. Or implement "load more" that fetches the next batch when the visible filtered list is short.
**Warning signs:** Label-filtered views showing far fewer items than expected.

### Pitfall 4: Pre-warming Breaking Self-Paste Loop Protection
**What goes wrong:** If pre-warming triggers any clipboard operations or app activation, it could interfere with the clipboard monitoring pause mechanism.
**Why it happens:** `NSWorkspace.shared.appIcon()` and `NSWorkspace.shared.icon(forFile:)` should be safe (read-only), but if any code path accidentally touches `NSPasteboard`, it could trigger monitoring.
**How to avoid:** Pre-warming should ONLY read bundle info and compute colors. Never touch the pasteboard or activate other apps.
**Warning signs:** Duplicate clipboard entries, paste loop detection firing.

### Pitfall 5: .equatable() Breaking @Observable Updates
**What goes wrong:** Using `.equatable()` on views that depend on `@Observable` or `@Environment` values can prevent necessary re-renders because `Equatable` conformance might not account for environment changes.
**Why it happens:** SwiftUI's `Equatable` view optimization skips body evaluation when `==` returns true, but `@Observable` and `@Environment` changes bypass the value comparison.
**How to avoid:** Don't use `.equatable()` on views that read from `@Observable` or `@Environment`. Instead, optimize by extracting subviews so their inputs (plain values) naturally prevent re-evaluation.
**Warning signs:** Views not updating when environment values change.

## Code Examples

### Example 1: Signpost-Based Performance Measurement
```swift
import os

extension Logger {
    static let panelPerformance = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "PanelPerformance"
    )
}

let signposter = OSSignposter(logger: .panelPerformance)

// In PanelController.show():
func show() {
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("PanelShow", id: signpostID)
    // ... existing show logic ...
    signposter.endInterval("PanelShow", state)
}

// In FilteredCardListView, measure query + filter time:
.task {
    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("FilteredItemsCompute", id: signpostID)
    // ... compute filtered items ...
    signposter.endInterval("FilteredItemsCompute", state)
}
```

### Example 2: AppIcon Cache
```swift
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let icon = NSWorkspace.shared.appIcon(forBundleIdentifier: bundleID) else {
            return nil
        }
        cache[bundleID] = icon
        return icon
    }
}
```

### Example 3: Pagination with Load-More Trigger
```swift
// In FilteredCardListView:
@State private var displayLimit: Int = 50
private let pageSize: Int = 50

// Show only displayLimit items
private var visibleItems: [ClipboardItem] {
    Array(filteredItems.prefix(displayLimit))
}

// In the LazyVStack:
LazyVStack(spacing: PanelLayout.cardSpacing) {
    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
        cardView(for: item, at: index)
            .onAppear {
                // Load more when approaching the end
                if index >= displayLimit - 5 {
                    displayLimit += pageSize
                }
            }
    }
}
```

### Example 4: Eliminating .id() with Reactive Refresh
```swift
// In PanelContentView, replace .id() with targeted refresh:
FilteredCardListView(
    searchText: debouncedSearchText,
    selectedLabelIDs: selectedLabelIDs,
    allLabels: labels,
    ...
)
// Only recreate on filter changes, NOT on item count:
.id("\(debouncedSearchText)\(selectedLabelIDsString)")
// Refresh items on panel show without recreation:
.onChange(of: panelActions.showCount) { _, _ in
    // FilteredCardListView handles this internally
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| @Query with .id(itemCount) to force refresh | @Query auto-observation (if working in NSPanel) | Test in this phase | Eliminates O(n) full recreation on every panel open |
| Unbounded fetch (all items) | fetchLimit + pagination | Standard practice | Bounds query cost for large histories |
| Per-card NSWorkspace.appIcon() | Cached icon lookup | Standard practice | Eliminates redundant I/O per card |
| Computed filteredItems on every body | Memoized filteredItems with onChange | SwiftUI best practice | Eliminates O(n) filtering on every body call |

## Open Questions

1. **Does @Query auto-observe in NSPanel without .id(itemCount)?**
   - What we know: `.id(appState.itemCount)` was added as a workaround because @Query inside NSHostingView/NSPanel did not reliably observe new insertions.
   - What's unclear: Whether this was a SwiftData bug fixed in newer macOS versions, or an inherent limitation of the NSPanel hosting approach.
   - Recommendation: Test by removing `itemCount` from `.id()` and verifying new items appear. If they don't, use a UUID-based refresh trigger on panel show instead (lighter than full `.id()` recreation).

2. **How many items trigger noticeable lag?**
   - What we know: The user reports lag, but we don't have specific numbers. The architecture suggests problems start around 200+ items (O(n) filtering + unbounded query).
   - What's unclear: The exact threshold and which of the three bottleneck types is most impactful.
   - Recommendation: Add signpost instrumentation first, measure, then prioritize fixes by impact.

3. **Can @Query support fetchLimit via property wrapper?**
   - What we know: `FetchDescriptor` supports `fetchLimit` and `fetchOffset`. The `@Query` property wrapper accepts `FetchDescriptor` in some init overloads.
   - What's unclear: Whether `@Query(FetchDescriptor(...))` with `fetchLimit` works correctly with the observation system, or whether it requires manual `modelContext.fetch()` calls.
   - Recommendation: Test both approaches. If `@Query` with `fetchLimit` works, it's cleaner. Otherwise, switch to explicit `modelContext.fetch()` in `.task`.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `PanelContentView.swift`, `FilteredCardListView.swift`, `ClipboardCardView.swift`, `CodeCardView.swift`, `URLCardView.swift`, `ImageCardView.swift`, `AsyncThumbnailView.swift`, `AppIconColorService.swift`, `ImageStorageService.swift`, `CodeDetectionService.swift`
- `/avdlee/swiftui-agent-skill` (Context7) - SwiftUI performance patterns, lazy loading, view identity, equatable views, hot path optimization
- `/websites/developer_apple_swiftdata` (Context7) - FetchDescriptor fetchLimit, fetchOffset, pagination

### Secondary (MEDIUM confidence)
- SwiftUI `.id()` behavior: documented in Apple SwiftUI documentation and verified through Context7 agent skill reference

### Tertiary (LOW confidence)
- @Query auto-observation behavior in NSPanel: based on codebase comments (the workaround exists, suggesting the problem was real). Needs validation with current SwiftData version.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - no new dependencies, all existing frameworks
- Architecture: HIGH - bottlenecks are clearly identifiable from codebase analysis
- Pitfalls: HIGH - derived directly from existing code patterns and known SwiftUI/SwiftData behaviors

**Research date:** 2026-02-21
**Valid until:** 2026-03-21 (stable frameworks, patterns unlikely to change)
