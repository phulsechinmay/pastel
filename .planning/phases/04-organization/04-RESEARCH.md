# Phase 4: Organization - Research

**Researched:** 2026-02-06
**Domain:** SwiftData search/filtering, SwiftUI context menus, label management, deletion
**Confidence:** HIGH

## Summary

Phase 4 adds search, labels, chip-bar filtering, and deletion to the existing clipboard history panel. The core technical challenges are: (1) building dynamic SwiftData predicates that combine text search with optional label relationships, (2) adding a new `Label` model with a one-to-many relationship to the existing `ClipboardItem`, (3) implementing right-click context menus in SwiftUI hosted inside an NSPanel, and (4) handling deletion with image file cleanup.

The existing codebase is well-structured for these additions. `PanelContentView` uses `@Query` which can be replaced with a dynamic query pattern. `ImageStorageService` already has a `deleteImage(imagePath:thumbnailPath:)` method. The `ClipboardItem` model needs one new optional property (`label`) and `PastelApp.init` needs to register the `Label` model in the `ModelContainer`.

**Primary recommendation:** Use SwiftData's lightweight migration (automatic) to add the `Label` model and optional relationship. Use the `@Query` init pattern with `#Predicate` combining `localizedStandardContains` for search and `persistentModelID` comparison for label filtering. Use SwiftUI's `.contextMenu` modifier for right-click menus with submenus.

## Standard Stack

No new libraries required for Phase 4. All functionality is achievable with the existing stack.

### Core (Already in Project)
| Technology | Version | Purpose | Phase 4 Usage |
|------------|---------|---------|---------------|
| SwiftData | macOS 14+ | Persistence | New Label model, predicates for search + filter |
| SwiftUI | macOS 14+ | UI framework | Search field, chip bar, context menus |
| AppKit | macOS 14+ | System integration | NSPanel already exists (no changes needed) |

### No New Dependencies
Phase 4 requires zero additional packages. SwiftData `#Predicate` handles search, SwiftUI `.contextMenu` handles right-click menus, and standard SwiftUI views handle the chip bar and search field.

## Architecture Patterns

### Recommended File Changes

```
Pastel/
  Models/
    ClipboardItem.swift       # ADD: optional label relationship
    Label.swift               # NEW: Label @Model
  Views/
    Panel/
      PanelContentView.swift  # MODIFY: add search, chip bar, dynamic @Query
      SearchFieldView.swift   # NEW: persistent search field
      ChipBarView.swift       # NEW: horizontal label chip bar
      FilteredCardListView.swift # NEW: subview with dynamic @Query init
  Services/
    ImageStorageService.swift # EXISTING: deleteImage already implemented
  PastelApp.swift             # MODIFY: add Label.self to ModelContainer
```

### Pattern 1: Dynamic @Query with Init-Based Predicate

**What:** SwiftData's `@Query` cannot be changed dynamically after view creation. To filter based on search text and label selection, create a child view whose initializer accepts filter parameters and constructs the `@Query` predicate.

**When to use:** Any time the query predicate depends on `@State` values (search text, selected label).

**Implementation approach:**

The parent view (`PanelContentView`) holds `@State` for `searchText` and `selectedLabel`. It passes these to a child view (`FilteredCardListView`) which constructs the `@Query` in its `init`. When the state changes, SwiftUI recreates the child view with the new init parameters, producing a new `@Query`.

```swift
// Parent: PanelContentView
@State private var searchText = ""
@State private var selectedLabel: Label? = nil

// In body:
FilteredCardListView(
    searchText: searchText,
    selectedLabelID: selectedLabel?.persistentModelID
)

// Child: FilteredCardListView
struct FilteredCardListView: View {
    @Query private var items: [ClipboardItem]

    init(searchText: String, selectedLabelID: PersistentIdentifier?) {
        let predicate: Predicate<ClipboardItem>

        if let labelID = selectedLabelID {
            if searchText.isEmpty {
                predicate = #Predicate<ClipboardItem> { item in
                    item.label?.persistentModelID == labelID
                }
            } else {
                let search = searchText
                predicate = #Predicate<ClipboardItem> { item in
                    item.label?.persistentModelID == labelID &&
                    (item.textContent?.localizedStandardContains(search) ?? false ||
                     item.sourceAppName?.localizedStandardContains(search) ?? false)
                }
            }
        } else if !searchText.isEmpty {
            let search = searchText
            predicate = #Predicate<ClipboardItem> { item in
                item.textContent?.localizedStandardContains(search) ?? false ||
                item.sourceAppName?.localizedStandardContains(search) ?? false
            }
        } else {
            predicate = #Predicate<ClipboardItem> { _ in true }
        }

        _items = Query(
            filter: predicate,
            sort: \ClipboardItem.timestamp,
            order: .reverse
        )
    }
}
```

**Confidence:** HIGH -- This is the documented pattern from Hacking with Swift and Apple's own SwiftData tutorials for dynamic filtering.

### Pattern 2: Debounced Search with `.task(id:)`

**What:** Use SwiftUI's `.task(id:)` modifier to debounce search input. When the search text changes, the previous task is automatically cancelled and a new one starts with a sleep delay.

**When to use:** For the search field to avoid rebuilding the query on every keystroke.

```swift
@State private var searchText = ""
@State private var debouncedSearchText = ""

TextField("Search...", text: $searchText)
    .task(id: searchText) {
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        debouncedSearchText = searchText
    }

// Pass debouncedSearchText to FilteredCardListView
```

**Confidence:** HIGH -- `.task(id:)` auto-cancels previous tasks, making it a clean native debounce mechanism. No Combine or third-party libraries needed.

### Pattern 3: SwiftUI `.contextMenu` with Submenu

**What:** SwiftUI's `.contextMenu` modifier works on macOS for right-click menus. Submenus can be created using `Menu` inside the context menu closure.

**When to use:** For the right-click context menu on clipboard cards (label assignment + delete).

```swift
.contextMenu {
    Menu("Label") {
        ForEach(labels) { label in
            Button {
                assignLabel(label, to: item)
            } label: {
                HStack {
                    Circle()
                        .fill(colorForLabel(label))
                        .frame(width: 8, height: 8)
                    Text(label.name)
                    if item.label?.persistentModelID == label.persistentModelID {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        if item.label != nil {
            Divider()
            Button("Remove Label") {
                item.label = nil
            }
        }
    }
    Divider()
    Button("Delete", role: .destructive) {
        deleteItem(item)
    }
}
```

**Confidence:** HIGH -- `.contextMenu` is a standard SwiftUI modifier that works correctly on macOS including inside NSPanel-hosted SwiftUI views. Submenus via `Menu` are supported on macOS 14+.

### Pattern 4: Label Chip Bar

**What:** A horizontal `ScrollView` with toggle-style buttons representing each label. Tapping selects/deselects a label for filtering.

**When to use:** Below the search field, above the card list. Only visible when labels exist.

```swift
struct ChipBarView: View {
    let labels: [Label]
    @Binding var selectedLabel: Label?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(labels) { label in
                    ChipButton(
                        label: label,
                        isSelected: selectedLabel?.persistentModelID == label.persistentModelID,
                        action: {
                            if selectedLabel?.persistentModelID == label.persistentModelID {
                                selectedLabel = nil
                            } else {
                                selectedLabel = label
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
        }
    }
}
```

**Confidence:** HIGH -- Standard SwiftUI pattern for horizontal chip/tag bars.

### Anti-Patterns to Avoid

- **Do NOT use `@Query` directly with changing filter state.** `@Query` predicates are static once the view is created. You must use the init-based pattern with a child view to achieve dynamic filtering.
- **Do NOT compare Label objects directly in predicates.** Compare `persistentModelID` instead. Direct entity comparison causes compiler type-check timeouts.
- **Do NOT use `.cascade` delete rule on Label -> ClipboardItem.** Deleting a label should NOT delete all its items. Use `.nullify` (the default) so items simply lose their label reference.
- **Do NOT use `lowercased()` or `uppercased()` in `#Predicate`.** These are not supported and will crash at runtime. Use `localizedStandardContains()` instead.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Case-insensitive search | Custom lowercase comparison | `localizedStandardContains()` in `#Predicate` | Handles Unicode, diacritics, locale-aware matching natively |
| Debounce mechanism | Custom timer/Combine publisher | `.task(id:)` with `Task.sleep` | Auto-cancellation built in, zero dependencies |
| Right-click context menu | NSMenu bridging code | SwiftUI `.contextMenu` modifier | Works natively in NSPanel-hosted SwiftUI, includes submenu support |
| Schema migration | VersionedSchema for adding Label | SwiftData lightweight migration (automatic) | Adding a new model and optional relationship to existing model is automatic |
| Batch delete all items | Manual fetch-then-delete loop | `modelContext.delete(model: ClipboardItem.self)` | SwiftData's built-in batch delete, handles all items in one call |

**Key insight:** SwiftData and SwiftUI have matured enough that every feature in Phase 4 can be built with zero custom infrastructure. The main complexity is understanding the predicate API limitations (optional handling, entity comparison).

## Common Pitfalls

### Pitfall 1: SwiftData Predicate with Optional String Properties

**What goes wrong:** `textContent` and `sourceAppName` are optional on `ClipboardItem`. Calling `.localizedStandardContains()` on an optional without unwrapping causes the predicate to return `Bool?` instead of `Bool`, which fails compilation.

**Why it happens:** `#Predicate` closures must return `Bool`, but optional chaining produces `Bool?`.

**How to avoid:** Use nil-coalescing:
```swift
item.textContent?.localizedStandardContains(search) ?? false
```
Or use `if let` / `flatMap` patterns:
```swift
if let text = item.textContent {
    return text.localizedStandardContains(search)
} else {
    return false
}
```

**Confidence:** HIGH -- Well-documented issue with verified solutions.

### Pitfall 2: Filtering by Optional Relationship in Predicate

**What goes wrong:** Comparing a `Label` object directly in a `#Predicate` causes "compiler unable to type-check" errors. Checking `$0.label != nil` on an optional to-one relationship can also be problematic.

**Why it happens:** `#Predicate` macro cannot handle entity references directly. It needs scalar or ID comparisons.

**How to avoid:** Always compare `persistentModelID`:
```swift
// Extract the ID OUTSIDE the predicate closure
let labelID = selectedLabel.persistentModelID

let predicate = #Predicate<ClipboardItem> { item in
    item.label?.persistentModelID == labelID
}
```

**Warning signs:** Compiler timeout errors, or runtime crashes when using entity comparison.

**Confidence:** HIGH -- Documented across Apple Developer Forums and multiple Swift blogs.

### Pitfall 3: ModelContainer Must Register All Models

**What goes wrong:** Adding a `Label` model with a relationship to `ClipboardItem` but not including `Label.self` in the `ModelContainer` initialization causes a crash or the relationship to silently fail.

**Why it happens:** SwiftData needs to know about all models at container creation time to set up the SQLite schema.

**How to avoid:** Update the `ModelContainer` initialization:
```swift
// Before (Phase 3):
container = try ModelContainer(for: ClipboardItem.self)

// After (Phase 4):
container = try ModelContainer(for: ClipboardItem.self, Label.self)
```

Note: SwiftData may automatically discover `Label` through the relationship on `ClipboardItem`, but explicitly listing both models is safer and clearer.

**Confidence:** HIGH -- Standard SwiftData requirement.

### Pitfall 4: Image Cleanup on Deletion

**What goes wrong:** Deleting a `ClipboardItem` from SwiftData does not automatically delete its image and thumbnail files from disk. Orphaned files accumulate over time.

**Why it happens:** SwiftData manages database records, not external files. File cleanup must be manual.

**How to avoid:** Before calling `modelContext.delete(item)`, call `ImageStorageService.shared.deleteImage(imagePath: item.imagePath, thumbnailPath: item.thumbnailPath)`. The existing `ImageStorageService.deleteImage` method already handles this on a background queue.

For "Clear All History", after `modelContext.delete(model: ClipboardItem.self)`, also delete the entire images directory contents (or iterate items first to collect file paths).

**Confidence:** HIGH -- The `deleteImage` method already exists in the codebase.

### Pitfall 5: Clear All Must Also Handle Labels and Pending Expirations

**What goes wrong:** Clearing all history deletes ClipboardItem records but leaves orphaned Label objects and pending expiration timers in ExpirationService.

**Why it happens:** `delete(model: ClipboardItem.self)` only affects ClipboardItem, not related services.

**How to avoid:** On clear all: (1) delete all image files, (2) delete all ClipboardItem records, (3) optionally keep Labels (they are reusable), (4) cancel all pending expirations in ExpirationService, (5) reset `itemCount` in ClipboardMonitor.

**Confidence:** HIGH -- Based on codebase analysis of ExpirationService and ClipboardMonitor.

### Pitfall 6: @Query Init Invalidation

**What goes wrong:** When `searchText` or `selectedLabel` changes by a single character, the entire `FilteredCardListView` is recreated with a new `@Query`. This is by design but can cause visual flicker if not handled.

**Why it happens:** SwiftUI recreates the child view when init parameters change, which triggers a new SwiftData fetch.

**How to avoid:** (1) Debounce search text (200ms) so the query only rebuilds after the user pauses. (2) Use `animation` on the parent to smooth transitions. (3) SwiftData queries are fast for typical clipboard history sizes (< 10K items), so this is unlikely to be a real performance issue.

**Confidence:** MEDIUM -- The pattern is standard, but the flicker concern is speculative and may not manifest in practice.

## Code Examples

### Label Model Definition

```swift
// Source: SwiftData @Model pattern + CONTEXT.md decisions
import SwiftData

@Model
final class Label {
    var name: String
    var colorName: String
    var sortOrder: Int

    // Inverse relationship: one label -> many items
    // Delete rule: .nullify (default) -- deleting label sets item.label = nil
    @Relationship(deleteRule: .nullify, inverse: \ClipboardItem.label)
    var items: [ClipboardItem]

    init(name: String, colorName: String, sortOrder: Int) {
        self.name = name
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.items = []
    }
}
```

### ClipboardItem Relationship Addition

```swift
// Add to existing ClipboardItem model:
var label: Label?
```

This is an optional to-one relationship. SwiftData automatically handles lightweight migration for this addition (optional properties default to nil for existing records).

### Color Preset Mapping

```swift
// Source: CONTEXT.md decision -- 6-8 preset colors
import SwiftUI

enum LabelColor: String, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink, gray

    var color: Color {
        switch self {
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .blue:   return .blue
        case .purple: return .purple
        case .pink:   return .pink
        case .gray:   return .gray
        }
    }
}
```

### Delete Individual Item

```swift
func deleteItem(_ item: ClipboardItem, modelContext: ModelContext) {
    // 1. Clean up image files from disk
    ImageStorageService.shared.deleteImage(
        imagePath: item.imagePath,
        thumbnailPath: item.thumbnailPath
    )

    // 2. Cancel any pending expiration
    if let monitor = clipboardMonitor {
        monitor.expirationService.cancelExpiration(for: item.persistentModelID)
    }

    // 3. Delete from SwiftData
    modelContext.delete(item)
    do {
        try modelContext.save()
    } catch {
        modelContext.rollback()
    }
}
```

### Clear All History

```swift
func clearAllHistory(modelContext: ModelContext) {
    // 1. Fetch all items to get image paths before deletion
    let descriptor = FetchDescriptor<ClipboardItem>()
    if let allItems = try? modelContext.fetch(descriptor) {
        for item in allItems {
            ImageStorageService.shared.deleteImage(
                imagePath: item.imagePath,
                thumbnailPath: item.thumbnailPath
            )
        }
    }

    // 2. Batch delete all items
    do {
        try modelContext.delete(model: ClipboardItem.self)
        try modelContext.save()
    } catch {
        modelContext.rollback()
    }
}
```

### Search + Label Combined Predicate

```swift
// Full predicate construction with all 4 cases:
// (no search + no label), (search + no label), (no search + label), (search + label)
static func buildPredicate(
    searchText: String,
    labelID: PersistentIdentifier?
) -> Predicate<ClipboardItem> {
    let hasSearch = !searchText.isEmpty
    let search = searchText

    if let labelID, hasSearch {
        return #Predicate<ClipboardItem> { item in
            item.label?.persistentModelID == labelID &&
            (item.textContent?.localizedStandardContains(search) ?? false ||
             item.sourceAppName?.localizedStandardContains(search) ?? false)
        }
    } else if let labelID {
        return #Predicate<ClipboardItem> { item in
            item.label?.persistentModelID == labelID
        }
    } else if hasSearch {
        return #Predicate<ClipboardItem> { item in
            item.textContent?.localizedStandardContains(search) ?? false ||
            item.sourceAppName?.localizedStandardContains(search) ?? false
        }
    } else {
        return #Predicate<ClipboardItem> { _ in true }
    }
}
```

### Label Management (Quick Create via Chip Bar '+')

```swift
func createLabel(name: String, colorName: String, modelContext: ModelContext) {
    let sortOrder: Int
    let descriptor = FetchDescriptor<Label>(
        sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
    )
    if let maxLabel = try? modelContext.fetch(descriptor).first {
        sortOrder = maxLabel.sortOrder + 1
    } else {
        sortOrder = 0
    }

    let label = Label(name: name, colorName: colorName, sortOrder: sortOrder)
    modelContext.insert(label)
    do {
        try modelContext.save()
    } catch {
        modelContext.rollback()
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSPredicate string-based queries | `#Predicate` macro type-safe predicates | macOS 14 / WWDC 2023 | Compile-time safety, no string typos |
| ObservableObject + @Published for search | `@Observable` + `@State` | macOS 14 / WWDC 2023 | Less boilerplate, automatic view updates |
| Core Data migration mappings | SwiftData automatic lightweight migration | macOS 14 / WWDC 2023 | Adding models/optional properties is zero-config |
| NSMenu + NSViewRepresentable for right-click | SwiftUI `.contextMenu` with `Menu` submenus | macOS 12+ (matured 14+) | Declarative, no AppKit bridging needed |
| Combine `debounce` publisher | `.task(id:)` with `Task.sleep` | Swift 5.5+ structured concurrency | No Combine import, auto-cancellation |

## Open Questions

1. **Label management UI placement**
   - CONTEXT.md says: "separate management view in Settings" but Phase 5 adds full Settings
   - Recommendation: Build a standalone `LabelManagementView` that can be shown as a sheet/popover now, and embedded into Settings later in Phase 5. This avoids building the full Settings infrastructure prematurely.
   - Confidence: MEDIUM -- This is a planning/scope question, not a technical one.

2. **`#Predicate { _ in true }` performance**
   - When no filters are active, we use a predicate that always returns true. This should produce an unfiltered query equivalent to no predicate at all, but it adds a trivial function call per row.
   - Recommendation: Acceptable for clipboard history sizes. SwiftData translates this to SQL; the optimizer likely eliminates the tautology.
   - Confidence: MEDIUM -- Not explicitly verified, but SwiftData predicates compile to SQL WHERE clauses.

3. **Cascade delete bug with explicit save**
   - Some developers report that `modelContext.save()` after batch delete can interfere with cascade delete rules in SwiftData.
   - Impact on Phase 4: MINIMAL -- We use `.nullify` (not `.cascade`) for Label->ClipboardItem, and we manually clean up images before deleting items. The cascade bug does not affect our delete pattern.
   - Confidence: HIGH that this does not affect us.

## Sources

### Primary (HIGH confidence)
- [Hacking with Swift - Filter SwiftData with predicates](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-filter-swiftdata-results-with-predicates) -- `#Predicate` string methods, `localizedStandardContains`
- [Hacking with Swift - One-to-many relationships](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-create-one-to-many-relationships) -- Relationship patterns, delete rules
- [Hacking with Swift - Lightweight vs complex migrations](https://www.hackingwithswift.com/quick-start/swiftdata/lightweight-vs-complex-migrations) -- Adding models is automatic lightweight migration
- [Hacking with Swift - Dynamic query filtering](https://www.hackingwithswift.com/books/ios-swiftui/dynamically-filtering-our-swiftdata-query) -- `@Query` init pattern with `_items = Query(...)`
- [Fat Bob Man - Optional values in SwiftData predicates](https://fatbobman.com/en/posts/how-to-handle-optional-values-in-swiftdata-predicates/) -- Nil-coalescing, if-let, flatMap patterns
- [Fat Bob Man - SwiftData relationships](https://fatbobman.com/en/posts/relationships-in-swiftdata-changes-and-considerations/) -- Inverse inference, performance considerations
- [Use Your Loaf - SwiftData predicates for parent relationships](https://useyourloaf.com/blog/swiftdata-predicates-for-parent-relationships/) -- `persistentModelID` comparison pattern
- [SimplyKyra - Filtering by entity in predicate](https://www.simplykyra.com/blog/swiftdata-problems-with-filtering-by-entity-in-the-predicate/) -- Entity comparison workaround
- [Hacking with Swift - Delete all instances](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-delete-all-instances-of-a-particular-model) -- `modelContext.delete(model:)` batch delete

### Secondary (MEDIUM confidence)
- [Daniel Saidi - Debounced search context](https://danielsaidi.com/blog/2025/01/08/creating-a-debounced-search-context-for-performant-swiftui-searches) -- Debounce patterns comparison
- [Hacking with Swift - SwiftUI context menus](https://www.hackingwithswift.com/quick-start/swiftui/how-to-show-a-context-menu) -- `.contextMenu` modifier on macOS
- Existing codebase analysis: `ClipboardItem.swift`, `ImageStorageService.swift`, `ExpirationService.swift`, `PanelContentView.swift` -- Current architecture patterns

### Tertiary (LOW confidence)
- WebSearch results on SwiftData cascade delete bugs -- Known issue but does not affect our `.nullify` pattern

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- No new libraries, all SwiftData/SwiftUI built-in
- Architecture (dynamic query pattern): HIGH -- Well-documented init-based @Query pattern
- Architecture (predicate construction): HIGH -- Multiple authoritative sources agree on optional handling
- Label relationship model: HIGH -- Standard SwiftData one-to-many with optional
- Schema migration: HIGH -- Adding new model + optional property is automatic lightweight migration
- Context menu: HIGH -- Standard SwiftUI `.contextMenu` modifier
- Deletion patterns: HIGH -- Existing `deleteImage` method + standard `modelContext.delete`
- Debounce: HIGH -- `.task(id:)` is a standard SwiftUI pattern

**Research date:** 2026-02-06
**Valid until:** 90 days (SwiftData APIs are stable post-macOS 14, no breaking changes expected)
