---
phase: quick-30
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/PanelContentView.swift
autonomous: true
requirements: [QUICK-30]

must_haves:
  truths:
    - "Panel opens to All History (no label filter selected) every time"
    - "Panel scroll position is at the top on every open"
    - "Search text is cleared on every panel open"
  artifacts:
    - path: "Pastel/Views/Panel/PanelContentView.swift"
      provides: "Reset logic in onChange(of: showCount)"
      contains: "selectedLabelIDs.removeAll"
  key_links:
    - from: "PanelContentView.onChange(of: showCount)"
      to: "FilteredCardListView .id()"
      via: "selectedLabelIDs change triggers view recreation which resets scroll"
      pattern: "selectedLabelIDs\\.removeAll"
---

<objective>
Reset the side panel to "All History" filter and scroll to top every time it opens.

Purpose: Currently the panel preserves its label filter and scroll position between opens. Users expect a fresh view each time they invoke the panel — showing the most recent items at the top with no label filter active.

Output: Modified PanelContentView.swift with reset logic in the showCount observer.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Panel/PanelContentView.swift
@Pastel/Views/Panel/FilteredCardListView.swift
@Pastel/Views/Panel/PanelController.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Reset label filter, search text, and scroll position on panel open</name>
  <files>Pastel/Views/Panel/PanelContentView.swift</files>
  <action>
In `PanelContentView.swift`, modify the `.onChange(of: panelActions.showCount)` handler (currently around line 143) to also reset the panel state:

```swift
.onChange(of: panelActions.showCount) { _, _ in
    // Reset to "All History" — clear label filter
    selectedLabelIDs.removeAll()
    // Clear search text so panel opens fresh
    searchText = ""
    debouncedSearchText = ""
    // Focus card list, not search
    isSearchFocused = false
    panelFocus = .cardList
}
```

This works because:
1. Clearing `selectedLabelIDs` changes the `.id()` string on `FilteredCardListView` (line ~119), which triggers SwiftUI to recreate the view — this inherently resets scroll position to the top.
2. Clearing `searchText` and `debouncedSearchText` ensures no stale search filter persists. Both must be cleared: `searchText` is the live text field binding, `debouncedSearchText` is used in the @Query predicate. Clearing `debouncedSearchText` directly avoids waiting for the 200ms debounce task.
3. The `selectedIndex` reset in FilteredCardListView's `.onAppear` (line ~229) handles clearing the card selection when the view is recreated.

Do NOT change FilteredCardListView.swift — its existing `.onChange(of: showCount)` handler still serves as a fallback for data refresh when the `.id()` does not change (e.g., if the panel was already showing All History with no search text, the `.id()` string is the same, so the view is NOT recreated and showCount's onChange refreshes filteredItems instead).
  </action>
  <verify>
Build the project with `xcodebuild -scheme "Pastel Sparkle" -configuration Debug build 2>&1 | tail -5` and confirm BUILD SUCCEEDED. Verify the onChange handler contains all four resets: selectedLabelIDs.removeAll(), searchText = "", debouncedSearchText = "", and focus reset.
  </verify>
  <done>
Panel resets to "All History" filter (no label selected), clears search text, and scrolls to top on every open. The existing behavior of FilteredCardListView's showCount observer provides data refresh when .id() doesn't change.
  </done>
</task>

</tasks>

<verification>
1. Build succeeds without errors or warnings in the modified file
2. The onChange(of: panelActions.showCount) handler clears selectedLabelIDs, searchText, and debouncedSearchText
3. No other onChange handlers or .id() logic was inadvertently modified
</verification>

<success_criteria>
- PanelContentView resets selectedLabelIDs, searchText, and debouncedSearchText on every showCount change
- Build compiles successfully
- FilteredCardListView is untouched (existing showCount fallback preserved)
</success_criteria>

<output>
After completion, create `.planning/quick/30-reset-sidepanel-to-all-history-and-scrol/30-SUMMARY.md`
</output>
