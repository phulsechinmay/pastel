# Phase 11: Item Titles, Multi-Label Support, and Edit Modal - Research

**Researched:** 2026-02-08
**Domain:** SwiftData relationships, migration, predicates; SwiftUI modal editing
**Confidence:** MEDIUM-HIGH (verified against codebase and official documentation patterns)

## Summary

Phase 11 transforms the data model from single-label assignment (`var label: Label?`) to multi-label support (`var labels: [Label]`), adds user-assigned titles to clipboard items, and introduces an edit modal. The primary technical challenges are: (1) migrating the existing single-optional relationship to a many-to-many array relationship, (2) filtering items by multiple selected labels when SwiftData `#Predicate` has known limitations with to-many relationship queries, and (3) presenting a `.sheet()` modal inside an NSPanel-hosted SwiftUI view.

The migration strategy is the most critical decision. The project has a prior decision [06-01] that optional fields with nil defaults need no VersionedSchema. Adding `title: String?` follows this pattern. However, changing `label: Label?` to `labels: [Label]` is a relationship type change that requires careful handling. The recommended approach is a two-property strategy: add the new `labels` array alongside the existing `label` property, run an in-app migration on launch, then mark the old property for removal in a future release.

For multi-label filtering, SwiftData's `#Predicate` cannot reliably use `.contains()` on to-many relationship arrays (crashes with "to-many key not allowed here"). The recommended approach is to query from the Label side (using the inverse relationship's `items` array) and collect the matching item IDs, then filter by those IDs -- or use a hybrid approach with in-memory post-filtering for the label dimension only.

**Primary recommendation:** Use a two-property migration strategy (keep `label`, add `labels`), migrate data in-app on launch, and use a hybrid filtering approach where search uses `#Predicate` but multi-label filtering uses in-memory post-filter on the Label side.

## Standard Stack

No new libraries are needed. This phase uses existing project dependencies exclusively.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData | macOS 14+ | Persistence, relationships, queries | Already in use; handles many-to-many automatically |
| SwiftUI | macOS 14+ | Edit modal, card layout, chip bar | Already in use; `.sheet()` proven in project |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Foundation | macOS 14+ | `RelativeDateTimeFormatter` / `Date.RelativeFormatStyle` | Custom time abbreviation formatting |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| In-memory label filtering | `#Predicate` with `.contains(where:)` | Crashes at runtime with to-many relationships; not viable |
| VersionedSchema migration | Two-property in-app migration | VersionedSchema adds complexity; two-property approach is simpler for direct distribution |
| Scratch ModelContext for edit modal | Direct `@Bindable` live editing | Decision locked: live editing with no save/cancel; matches existing LabelSettingsView pattern |

**Installation:**
```bash
# No new dependencies needed
```

## Architecture Patterns

### Recommended Project Structure
```
Pastel/
├── Models/
│   ├── ClipboardItem.swift      # Add title, labels; keep label temporarily
│   └── Label.swift               # Update inverse relationship
├── Views/Panel/
│   ├── ClipboardCardView.swift   # Restructured header/footer layout
│   ├── FilteredCardListView.swift # Multi-label filtering logic
│   ├── PanelContentView.swift    # Multi-select label state
│   ├── ChipBarView.swift         # Multi-select binding
│   └── EditItemView.swift        # NEW: Edit modal sheet view
├── Services/
│   └── MigrationService.swift    # NEW: One-time label migration
```

### Pattern 1: Two-Property Migration Strategy
**What:** Add `labels: [Label]` as new property alongside existing `label: Label?`. Run one-time migration on launch to copy `label` values into `labels` array. Keep both properties temporarily.
**When to use:** When changing a relationship type (single-to-array) without VersionedSchema.
**Example:**
```swift
// ClipboardItem.swift - Updated model
@Model
final class ClipboardItem {
    // ... existing properties ...

    /// User-assigned title for easier discovery. Nil = no title.
    var title: String?

    /// Multiple labels for organization (many-to-many).
    /// New in Phase 11. SwiftData auto-initializes to empty array.
    var labels: [Label]

    /// DEPRECATED: Single label (kept for migration).
    /// Will be removed in a future release after all users have migrated.
    var label: Label?

    // ... rest of model ...
}
```

```swift
// MigrationService.swift - One-time migration
@MainActor
final class MigrationService {
    static func migrateLabelsIfNeeded(modelContext: ModelContext) {
        let key = "hasCompletedLabelMigration"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let descriptor = FetchDescriptor<ClipboardItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }

        for item in items {
            if let singleLabel = item.label {
                if !item.labels.contains(where: {
                    $0.persistentModelID == singleLabel.persistentModelID
                }) {
                    item.labels.append(singleLabel)
                }
                item.label = nil
            }
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}
```

### Pattern 2: Hybrid Label Filtering (Predicate + In-Memory)
**What:** Use `#Predicate` for text search and basic filtering, then post-filter for multi-label matching since `#Predicate` cannot handle `.contains()` on to-many relationships.
**When to use:** When SwiftData predicates don't support the needed relationship queries.
**Example:**
```swift
// Approach A: Query from Label side, collect item IDs
// In FilteredCardListView init, when labels are selected:
// 1. Fetch selected labels
// 2. Collect their .items arrays
// 3. Compute union (OR logic)
// 4. Filter @Query results to intersection with text search

// Approach B: Simpler hybrid - fetch all, filter in-memory for labels
// For a clipboard manager with hundreds to low-thousands of items,
// in-memory filtering is acceptable performance.

init(
    searchText: String,
    selectedLabelIDs: Set<PersistentIdentifier>,  // Changed from single optional
    selectedIndex: Binding<Int?>,
    // ... other params
) {
    // Text search predicate (works reliably)
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
    // Label filtering applied in-memory in the body via .filter()
}

// In body, filter items by labels:
private var filteredItems: [ClipboardItem] {
    guard !selectedLabelIDs.isEmpty else { return items }
    return items.filter { item in
        // OR logic: item has ANY of the selected labels
        item.labels.contains { label in
            selectedLabelIDs.contains(label.persistentModelID)
        }
    }
}
```

### Pattern 3: Edit Modal with @Bindable
**What:** Present a `.sheet()` modal with `@Bindable` for live editing of SwiftData model properties.
**When to use:** For editing item title and label assignments.
**Example:**
```swift
// EditItemView.swift
struct EditItemView: View {
    @Bindable var item: ClipboardItem
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Item")
                .font(.headline)

            // Title field
            TextField("Title (optional)", text: titleBinding)
                .textFieldStyle(.roundedBorder)

            // Label multi-select
            Text("Labels")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Wrapping flow of label toggle chips
            CenteredFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(allLabels) { label in
                    labelToggleChip(for: label)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
            }
        }
        .padding()
        .frame(width: 280)
    }

    // Binding that converts nil to empty string for TextField
    private var titleBinding: Binding<String> {
        Binding(
            get: { item.title ?? "" },
            set: { item.title = $0.isEmpty ? nil : $0 }
        )
    }

    private func labelToggleChip(for label: Label) -> some View {
        let isAssigned = item.labels.contains { $0.persistentModelID == label.persistentModelID }
        // Toggle chip on tap: add/remove from item.labels
    }
}
```

### Pattern 4: Multi-Select Chip Bar
**What:** Change chip bar from single-select (`selectedLabel: Label?`) to multi-select (`selectedLabels: Set<PersistentIdentifier>`).
**When to use:** For OR-logic label filtering.
**Example:**
```swift
// ChipBarView.swift - Updated binding
struct ChipBarView: View {
    let labels: [Label]
    @Binding var selectedLabelIDs: Set<PersistentIdentifier>

    // Tap toggles membership in the set
    private func labelChip(for label: Label) -> some View {
        let isActive = selectedLabelIDs.contains(label.persistentModelID)
        // ... chip UI ...
        .onTapGesture {
            if isActive {
                selectedLabelIDs.remove(label.persistentModelID)
            } else {
                selectedLabelIDs.insert(label.persistentModelID)
            }
        }
    }
}
```

### Anti-Patterns to Avoid
- **Using `#Predicate` with `.contains()` on to-many relationships:** Compiles but crashes at runtime with "to-many key not allowed here". Use in-memory filtering instead.
- **Using VersionedSchema for simple additions:** Adding `title: String?` (optional with nil default) does NOT require VersionedSchema per project decision [06-01]. SwiftData handles it via lightweight migration.
- **Removing `label` property immediately:** Would break the migration path. Keep it temporarily and remove in a future version.
- **Using `.id()` with Set<PersistentIdentifier> directly:** Sets don't have stable hash values across runs. Convert to a sorted string representation for the `.id()` modifier.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Many-to-many join table | Manual join model | SwiftData `[Label]` / `[ClipboardItem]` arrays | SwiftData manages the SQLite join table automatically |
| Relative time formatting | Manual string computation | `Date.RelativeFormatStyle` with `unitsStyle: .narrow` or custom `RelativeDateTimeFormatter` | Handles localization, edge cases, automatic updating |
| Flow layout for label chips | Custom HStack wrapping | Existing `CenteredFlowLayout` (already in ChipBarView.swift) | Already implemented and tested in the project |
| Modal presentation | Custom NSWindow/NSPanel | SwiftUI `.sheet()` modifier | Already proven in ChipBarView (label creation) and LabelSettingsView (color palette) |

**Key insight:** The project already has all the UI infrastructure needed (flow layout, sheet modals, chip styling). The new work is primarily data model changes and wiring, not UI invention.

## Common Pitfalls

### Pitfall 1: #Predicate Crashes with To-Many Relationship Filtering
**What goes wrong:** Using `item.labels.contains { $0.persistentModelID == labelID }` inside a `#Predicate` compiles successfully but crashes at runtime with CoreData error "to-many key not allowed here".
**Why it happens:** SwiftData's `#Predicate` macro generates SQL that CoreData's SQLite backend cannot execute for collection predicates on to-many relationships.
**How to avoid:** Use in-memory post-filtering for label-based queries. Keep `#Predicate` for text search only. This is documented in the project's CONTEXT.md constraints.
**Warning signs:** App crashes when selecting a label filter; error log mentions "to-many key not allowed here".

### Pitfall 2: .id() Modifier Must Include All Filter Inputs
**What goes wrong:** Changing label selection doesn't update the filtered list because `@Query` predicate is frozen at init time.
**Why it happens:** Per project MEMORY.md: "@Query predicate is set once in init and NEVER updates. Must use `.id()` that includes ALL filter inputs."
**How to avoid:** The `.id()` on FilteredCardListView must include: debounced search text, the sorted set of selected label IDs (as a string), and the item count. Example: `.id("\(debouncedSearchText)\(selectedLabelIDsString)\(appState.itemCount)")`.
**Warning signs:** Filtering appears to work once but doesn't respond to subsequent changes.

### Pitfall 3: SwiftData Optional Predicate Patterns
**What goes wrong:** Using force-unwrap (`!`) or nil-coalescing (`?? ""`) with CONTAINS in `#Predicate` generates unsupported SQL.
**Why it happens:** Per project MEMORY.md: "Force-unwrap is unsupported. Nil-coalescing with CONTAINS generates unsupported TERNARY SQL."
**How to avoid:** Use the `?.method() == true` pattern for optional string methods in predicates.
**Example:** `item.title?.localizedStandardContains(search) == true` (correct), NOT `(item.title ?? "").localizedStandardContains(search)` (crashes).

### Pitfall 4: Migration Order and Timing
**What goes wrong:** Migration runs before SwiftData has finished schema setup, causing crashes or data loss.
**Why it happens:** SwiftData needs to complete its lightweight migration (adding the new `labels` array property) before custom migration code can access it.
**How to avoid:** Run `MigrationService.migrateLabelsIfNeeded()` after `ModelContainer` creation and after `AppState.setup()`. Use a UserDefaults flag to ensure it runs only once.
**Warning signs:** Crash on first launch after update; `labels` property not found errors.

### Pitfall 5: Sheet Modal in NSPanel Context
**What goes wrong:** `.sheet()` presented from inside an NSPanel-hosted SwiftUI view may not appear or may appear behind the panel.
**Why it happens:** NSPanel with `.nonactivatingPanel` style has special window level behavior that can interfere with sheet presentation.
**How to avoid:** The project already uses `.sheet()` successfully in ChipBarView (inside the same NSPanel context) for label creation, so this pattern is proven to work. Follow the same approach. If issues arise, ensure the sheet is attached to a view within the NSHostingView hierarchy, not at the panel level.
**Warning signs:** Sheet appears but is not interactive; sheet appears behind the panel.

### Pitfall 6: Label Chip Layout in Narrow Panels
**What goes wrong:** Multiple label chips overflow the footer row and break card layout, especially on narrow vertical panels.
**Why it happens:** Card width varies by panel edge position. Footer space is shared with metadata text and keycap badges.
**How to avoid:** Enforce the "first 3 chips + '+N' badge" overflow rule strictly. Use `.lineLimit(1)` and fixed max-width for chip text. Test with 5+ labels assigned and narrow panel widths.
**Warning signs:** Card height increases unexpectedly; chips overlap or get clipped.

### Pitfall 7: Drag-Drop Label Append vs Replace
**What goes wrong:** Dragging a label onto a card replaces all existing labels instead of appending.
**Why it happens:** Current code does `item.label = label` (single assignment). Must change to `item.labels.append(label)` with duplicate check.
**How to avoid:** Before appending, check if the label is already in the array: `guard !item.labels.contains(where: { $0.persistentModelID == label.persistentModelID }) else { return true }`.

## Code Examples

### Updated ClipboardItem Model
```swift
// Source: Codebase analysis + SwiftData many-to-many docs
@Model
final class ClipboardItem {
    // ... existing properties unchanged ...

    /// User-assigned title for easier discovery via search.
    /// Nil means no title was set. Displayed in card header when present.
    var title: String?

    /// Multiple labels for organization/filtering (many-to-many).
    @Relationship(deleteRule: .nullify, inverse: \Label.items)
    var labels: [Label]

    /// DEPRECATED: Single label (kept for data migration).
    /// Remove in v1.3+ after all users have migrated.
    var label: Label?

    // ... init updated to include title: String? = nil, labels default to [] ...
}
```

### Updated Label Model
```swift
// Source: Codebase analysis + SwiftData inverse relationship docs
@Model
final class Label {
    var name: String
    var colorName: String
    var sortOrder: Int
    var emoji: String?

    /// Inverse relationship: many labels <-> many clipboard items.
    /// Delete rule: .nullify -- deleting a label removes it from item.labels arrays.
    var items: [ClipboardItem]

    // init unchanged -- items defaults to []
}
```

### Card Header Layout (Title + Timestamp)
```swift
// Source: CONTEXT.md decision - Header layout: [App Icon] [Title] [Spacer] [Timestamp]
HStack {
    sourceAppIcon

    // Title (when set)
    if let title = item.title, !title.isEmpty {
        Text(title)
            .font(.caption2.bold())
            .lineLimit(1)
            .foregroundStyle(isColorCard ? colorCardTextColor : .primary)
    }

    Spacer()

    // Abbreviated relative time
    Text(relativeTimeString(for: item.timestamp))
        .font(.caption2)
        .foregroundStyle(isColorCard ? colorCardTextColor.opacity(0.7) : .secondary)
}
```

### Card Footer Layout (Metadata + Labels + Badge)
```swift
// Source: CONTEXT.md decision - Labels move to footer, max 3 chips + "+N"
HStack(spacing: 4) {
    if let metadata = footerMetadataText {
        Text(metadata)
            .font(.caption2)
            .foregroundStyle(.secondary.opacity(0.7))
            .lineLimit(1)
    }

    // Label chips (max 3 visible)
    let visibleLabels = Array(item.labels.prefix(3))
    ForEach(visibleLabels) { label in
        labelChipSmall(for: label)
    }
    if item.labels.count > 3 {
        Text("+\(item.labels.count - 3)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.1), in: Capsule())
    }

    Spacer()

    if let badgePosition {
        KeycapBadge(number: badgePosition, isShiftHeld: isShiftHeld)
    }
}
```

### Custom Relative Time String
```swift
// Source: CONTEXT.md decision - Use "mins/sec/secs" abbreviated format
// Option 1: Use built-in Date.RelativeFormatStyle with narrow unitsStyle
// This produces "2 min. ago" style (locale-dependent)
private func relativeTimeText(for date: Date) -> Text {
    Text(date, format: .relative(presentation: .named, unitsStyle: .narrow))
}

// Option 2: Custom formatter for exact "2 mins ago" / "30 secs ago" output
private func relativeTimeString(for date: Date) -> String {
    let interval = Date.now.timeIntervalSince(date)
    switch interval {
    case ..<60:
        let secs = Int(interval)
        return secs == 1 ? "1 sec ago" : "\(secs) secs ago"
    case ..<3600:
        let mins = Int(interval / 60)
        return mins == 1 ? "1 min ago" : "\(mins) mins ago"
    case ..<86400:
        let hours = Int(interval / 3600)
        return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
    default:
        let days = Int(interval / 86400)
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }
}
```

Note: Option 2 gives exact control over abbreviation ("mins", "secs") but loses SwiftUI Text's auto-updating behavior (the built-in `.relative()` format updates automatically as time passes). For a clipboard manager where items are recent and the panel is open briefly, a static string computed on card appearance is acceptable. Alternatively, use a Timer to periodically refresh.

### Search Predicate Including Title
```swift
// Source: CONTEXT.md decision - Include title in search predicate
// Uses ?.method() == true pattern per project MEMORY.md
if !searchText.isEmpty {
    let search = searchText
    predicate = #Predicate<ClipboardItem> { item in
        item.textContent?.localizedStandardContains(search) == true ||
        item.sourceAppName?.localizedStandardContains(search) == true ||
        item.title?.localizedStandardContains(search) == true
    }
}
```

### Context Menu with Edit and Multi-Label
```swift
// Source: CONTEXT.md decisions - Edit via context menu, label append/remove
.contextMenu {
    Button("Copy") { panelActions.copyOnlyItem?(item) }
    Button("Paste") { panelActions.pasteItem?(item) }
    Button("Copy + Paste") { panelActions.pasteItem?(item) }

    Divider()

    Button("Edit...") {
        showingEditSheet = true
    }

    Divider()

    // Label assignment submenu (now appends)
    Menu("Label") {
        ForEach(labels) { label in
            let isAssigned = item.labels.contains {
                $0.persistentModelID == label.persistentModelID
            }
            Button {
                if isAssigned {
                    item.labels.removeAll {
                        $0.persistentModelID == label.persistentModelID
                    }
                } else {
                    item.labels.append(label)
                }
                try? modelContext.save()
            } label: {
                HStack {
                    Image(nsImage: menuIcon(for: label))
                    Text(label.name)
                    if isAssigned {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }

        if !item.labels.isEmpty {
            Divider()
            Button("Remove All Labels") {
                item.labels.removeAll()
                try? modelContext.save()
            }
        }
    }

    Divider()

    Button("Delete", role: .destructive) { deleteItem() }
}
.sheet(isPresented: $showingEditSheet) {
    EditItemView(item: item)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single `var label: Label?` | Many-to-many `var labels: [Label]` | Phase 11 | Items can belong to multiple categories |
| Label chip in header row | Label chips in footer row | Phase 11 | Header freed for title display |
| Single-select chip bar | Multi-select chip bar with OR logic | Phase 11 | More flexible filtering |
| No user-assigned titles | Optional `title: String?` | Phase 11 | Better search/discovery |
| No edit modal | Right-click "Edit" with `.sheet()` | Phase 11 | Direct item editing |

**Deprecated/outdated:**
- `item.label` (single label): Kept temporarily for migration, will be removed in v1.3+
- Single-select `selectedLabel: Label?`: Replaced by `selectedLabelIDs: Set<PersistentIdentifier>`

## Open Questions

1. **Relative time auto-updating behavior**
   - What we know: The current `Text(date, format: .relative(presentation: .named))` auto-updates as time passes. A custom string formatter does not auto-update.
   - What's unclear: Whether the user strongly prefers the exact "mins/secs" wording (requiring custom formatter + Timer) vs. the built-in `.narrow` style which produces "2 min. ago" with periods.
   - Recommendation: Use the custom formatter approach (`relativeTimeString()`) since the panel is opened briefly and items are recent. The user explicitly requested "mins/sec/secs" abbreviation which the built-in formatter does not produce exactly. Compute the string in `.task` or on appear.

2. **When to remove deprecated `label` property**
   - What we know: Must keep it during the transition for migration. Only direct distribution users.
   - What's unclear: How long to keep both properties before removing `label`.
   - Recommendation: Add a `// TODO: Remove in v1.3` comment. Remove in the next milestone. Since this is direct distribution (no App Store review cycles), migration window can be short.

3. **SwiftData many-to-many with @Relationship on both sides**
   - What we know: SwiftData many-to-many requires `@Relationship(inverse:)` on one side. Currently, Label has `@Relationship(deleteRule: .nullify, inverse: \ClipboardItem.label) var items: [ClipboardItem]`.
   - What's unclear: Whether having BOTH `label` and `labels` properties on ClipboardItem with different inverse declarations causes conflicts.
   - Recommendation: Move the `@Relationship(inverse:)` to ClipboardItem's `labels` property and make Label's `items` a plain `var items: [ClipboardItem]` (SwiftData will infer the inverse). Remove the old `@Relationship` from Label's `items` that points to `\ClipboardItem.label`. The old `label: Label?` should NOT have an explicit `@Relationship` -- just keep it as a plain optional property for migration.

4. **In-memory filtering performance at scale**
   - What we know: Clipboard managers typically have hundreds to low thousands of items. In-memory filtering of this scale is negligible.
   - What's unclear: No hard performance data for SwiftData lazy-loading behavior when accessing `.labels` relationship on many items.
   - Recommendation: Proceed with in-memory filtering. If performance becomes an issue, add `.relationshipKeyPathsForPrefetching` to the FetchDescriptor. Monitor for lazy-loading N+1 query patterns.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `ClipboardItem.swift`, `Label.swift`, `ClipboardCardView.swift`, `FilteredCardListView.swift`, `PanelContentView.swift`, `ChipBarView.swift`, `LabelSettingsView.swift`, `PastelApp.swift`
- Project MEMORY.md: SwiftData predicate pitfalls (verified against codebase)
- Project CONTEXT.md: All locked decisions

### Secondary (MEDIUM confidence)
- [Hacking with Swift - Many-to-Many Relationships](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-create-many-to-many-relationships) - SwiftData handles join table automatically; `@Relationship(inverse:)` required on one side
- [Hacking with Swift - Lightweight vs Complex Migrations](https://www.hackingwithswift.com/quick-start/swiftdata/lightweight-vs-complex-migrations) - Adding properties with defaults is lightweight; deleting properties is lightweight
- [Hacking with Swift - Editing SwiftData Objects](https://www.hackingwithswift.com/books/ios-swiftui/editing-swiftdata-model-objects) - `@Bindable` for live editing pattern
- [Swift Forums - Predicate to filter against array](https://forums.swift.org/t/predicate-to-filter-against-array-of-items/70986) - Use extracted UUIDs/IDs instead of model objects in predicates
- [Swift Forums - Complex Predicates in SwiftData](https://forums.swift.org/t/complex-predicates-in-swiftdata/73565) - Confirmed to-many `.contains()` crashes at runtime; acknowledged as SwiftData bug
- [SimplyKyra - SwiftData Filtering by Entity](https://www.simplykyra.com/blog/swiftdata-problems-with-filtering-by-entity-in-the-predicate/) - Use `persistentModelID` for relationship comparisons
- [Fat Bob Man - Dynamic Predicates](https://fatbobman.com/en/posts/how-to-dynamically-construct-complex-predicates-for-swiftdata/) - Predicate combination techniques

### Tertiary (LOW confidence)
- [Apple Docs - Date.RelativeFormatStyle](https://developer.apple.com/documentation/foundation/date/relativeformatstyle) - `.narrow` unitsStyle exists but exact output for "mins"/"secs" unverified on macOS
- Custom relative time formatter: Based on common Swift patterns; the exact wording decision ("mins" vs "min") is a UX choice, not a technical constraint

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - No new dependencies; all existing project infrastructure
- Architecture (migration): MEDIUM - Two-property migration pattern is well-understood but the dual-inverse-relationship concern (open question 3) needs validation during implementation
- Architecture (filtering): MEDIUM - In-memory filtering is a proven workaround; `#Predicate` limitation is well-documented
- Architecture (edit modal): HIGH - `.sheet()` already used successfully in same NSPanel context
- Pitfalls: HIGH - All pitfalls verified against project MEMORY.md and codebase

**Research date:** 2026-02-08
**Valid until:** 2026-03-08 (stable domain; SwiftData API unlikely to change mid-cycle)
