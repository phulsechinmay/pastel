---
phase: quick
plan: 003
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/PanelContentView.swift
  - Pastel/Views/Panel/FilteredCardListView.swift
autonomous: true

must_haves:
  truths:
    - "In top/bottom panel mode, header (Pastel + gear), search field, and label chips all appear in one horizontal row"
    - "Searching by text filters items to only those whose textContent or sourceAppName contain the search string"
    - "Selecting a label chip filters items to only those assigned that specific label"
    - "Combining search text + label chip shows only items matching BOTH criteria"
    - "Vertical (left/right) panel layout is unchanged -- header row on top, search and chips below"
  artifacts:
    - path: "Pastel/Views/Panel/PanelContentView.swift"
      provides: "Inline header layout for horizontal mode"
    - path: "Pastel/Views/Panel/FilteredCardListView.swift"
      provides: "Corrected SwiftData predicates for search and label filtering"
  key_links:
    - from: "PanelContentView.swift"
      to: "FilteredCardListView.swift"
      via: "debouncedSearchText and selectedLabel?.persistentModelID passed to init"
      pattern: "FilteredCardListView\\("
---

<objective>
Fix two bugs in the Pastel clipboard manager panel:

1. **Horizontal layout:** In top/bottom panel mode, merge the header row (Pastel title + settings gear) with the search field and label chips into a single inline row, instead of stacking them vertically.

2. **Search and label filtering:** Fix broken SwiftData predicates in FilteredCardListView. The root cause is that SwiftData's `#Predicate` macro generates incorrect SQL when using optional chaining with `?? false` (e.g., `item.textContent?.localizedStandardContains(search) ?? false`) and optional relationship traversal (e.g., `item.label?.persistentModelID == labelID`). These produce predicates that return wrong result sets.

Purpose: Make the horizontal panel mode space-efficient and restore search/label filtering to correct behavior.
Output: Two modified Swift files with layout and predicate fixes.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Panel/PanelContentView.swift
@Pastel/Views/Panel/FilteredCardListView.swift
@Pastel/Views/Panel/SearchFieldView.swift
@Pastel/Views/Panel/ChipBarView.swift
@Pastel/Models/ClipboardItem.swift
@Pastel/Models/Label.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Inline header layout for horizontal panel mode</name>
  <files>Pastel/Views/Panel/PanelContentView.swift</files>
  <action>
Restructure PanelContentView.body so that in horizontal mode (`isHorizontal == true`), the header (Pastel title + gear button), search field, and label chip bar all appear in a SINGLE horizontal row. In vertical mode, keep the existing stacked layout unchanged.

Specifically for horizontal mode:
- Replace the current structure (VStack with separate header HStack, Divider, then HStack of search+chips) with a single top bar HStack containing: Text("Pastel"), SearchFieldView (constrained to ~200pt width), ChipBarView (takes remaining space), Spacer, gear button.
- Remove the Divider in horizontal mode (the single row replaces the need for visual separation).
- Add vertical padding (~10pt) and horizontal padding (~12pt) to the row.

For vertical mode, keep the EXACT current structure: header HStack -> Divider -> SearchFieldView -> ChipBarView -> FilteredCardListView.

The conditional should branch at the top level of VStack's content. Use `if isHorizontal { ... } else { ... }` to produce the two layouts, with the FilteredCardListView always appearing after the header/search section in both branches.
  </action>
  <verify>Build succeeds: `cd /Users/phulsechinmay/Desktop/Projects/pastel && xcodebuild -scheme Pastel -destination 'platform=macOS' build 2>&1 | tail -5` shows BUILD SUCCEEDED.</verify>
  <done>In horizontal (top/bottom) mode, Pastel title, search field, label chips, and gear icon are all in one row. Vertical mode layout is unchanged.</done>
</task>

<task type="auto">
  <name>Task 2: Fix SwiftData predicates for search and label filtering</name>
  <files>Pastel/Views/Panel/FilteredCardListView.swift</files>
  <action>
Rewrite the predicate construction in FilteredCardListView.init to avoid SwiftData `#Predicate` bugs with optional chaining and `?? false`.

**The problem:** SwiftData's `#Predicate` macro translates `item.textContent?.localizedStandardContains(search) ?? false` and `item.label?.persistentModelID == labelID` into incorrect SQL, causing wrong result sets. Optional chaining combined with nil-coalescing inside `#Predicate` is unreliable.

**The fix:** Use a `FetchDescriptor`-compatible approach. Restructure predicates to avoid optional chaining inside `#Predicate`:

For **search-only** (no label selected, search text non-empty):
```swift
let search = searchText
predicate = #Predicate<ClipboardItem> { item in
    item.textContent != nil &&
    item.textContent!.localizedStandardContains(search)
    ||
    item.sourceAppName != nil &&
    item.sourceAppName!.localizedStandardContains(search)
}
```

For **label-only** (label selected, search text empty):
```swift
predicate = #Predicate<ClipboardItem> { item in
    item.label != nil &&
    item.label!.persistentModelID == labelID
}
```

For **both** (label selected AND search text non-empty):
```swift
let search = searchText
predicate = #Predicate<ClipboardItem> { item in
    item.label != nil &&
    item.label!.persistentModelID == labelID &&
    (item.textContent != nil &&
     item.textContent!.localizedStandardContains(search)
     ||
     item.sourceAppName != nil &&
     item.sourceAppName!.localizedStandardContains(search))
}
```

For **no filter** (no label, empty search):
```swift
predicate = #Predicate<ClipboardItem> { _ in true }
```

Keep the rest of the init unchanged (the Query construction with sort by timestamp descending, the _selectedIndex and onPaste assignments).

**Important:** The `!` force-unwraps are safe here because they are guarded by the `!= nil` check in the same `&&` expression. SwiftData evaluates these conjunctions correctly, unlike the optional chaining `?.` pattern.
  </action>
  <verify>Build succeeds: `cd /Users/phulsechinmay/Desktop/Projects/pastel && xcodebuild -scheme Pastel -destination 'platform=macOS' build 2>&1 | tail -5` shows BUILD SUCCEEDED.</verify>
  <done>Search filtering returns only items matching the search text. Label filtering returns only items with the selected label. Combined filtering returns items matching both. Empty filter returns all items.</done>
</task>

</tasks>

<verification>
1. `xcodebuild -scheme Pastel -destination 'platform=macOS' build` succeeds with no errors.
2. Run the app, switch to top or bottom panel edge in settings. Confirm the header row shows Pastel title, search, chips, and gear all inline.
3. Copy several distinct text items (e.g., "hello", "world", "swift", "code"). Type "hello" in search -- only the "hello" item should appear.
4. Create a label and assign it to one item. Click the label chip -- only items with that label should appear.
5. With a label chip active, type search text -- results should be the intersection of label filter AND search filter.
6. Switch back to left/right panel edge. Confirm vertical layout is unchanged (header on top, search below, chips below that).
</verification>

<success_criteria>
- Horizontal mode shows single-row header with search and chips inline
- Vertical mode layout unchanged
- Search returns correct filtered results (not random/latest-2)
- Label chip returns only items with that label (not random items)
- Combined search + label returns intersection
- Build succeeds with zero errors
</success_criteria>

<output>
After completion, create `.planning/quick/003-fix-horizontal-header-and-search-label-filtering/003-SUMMARY.md`
</output>
