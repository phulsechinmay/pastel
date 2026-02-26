---
phase: 31-allow-user-to-rearrange-labels
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Settings/LabelSettingsView.swift
autonomous: true
requirements: [QUICK-31]

must_haves:
  truths:
    - "User can drag labels up/down in Settings to reorder them"
    - "Reordered labels persist their new sortOrder to SwiftData"
    - "Panel chip bar reflects the new label order immediately"
  artifacts:
    - path: "Pastel/Views/Settings/LabelSettingsView.swift"
      provides: "Drag-to-reorder label rows with sortOrder persistence"
      contains: "onMove"
  key_links:
    - from: "Pastel/Views/Settings/LabelSettingsView.swift"
      to: "Label.sortOrder"
      via: "onMove handler updates sortOrder for each label"
      pattern: "sortOrder"
    - from: "Pastel/Views/Panel/ChipBarView.swift"
      to: "Label.sortOrder"
      via: "@Query(sort: \\Label.sortOrder) in PanelContentView"
      pattern: "sort.*sortOrder"
---

<objective>
Add drag-to-reorder functionality for labels in the Settings Labels tab. When the user drags a label row to a new position, update the `sortOrder` property on each affected Label model. The panel's ChipBarView already displays labels sorted by `sortOrder` via `@Query(sort: \Label.sortOrder)`, so reordering in Settings automatically updates the panel chip order.

Purpose: Let users control the display order of their labels across the entire app.
Output: Updated LabelSettingsView.swift with drag reorder support.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Models/Label.swift
@Pastel/Views/Settings/LabelSettingsView.swift
@Pastel/Views/Panel/ChipBarView.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add drag-to-reorder in LabelSettingsView</name>
  <files>Pastel/Views/Settings/LabelSettingsView.swift</files>
  <action>
Replace the ScrollView > LazyVStack > ForEach label list with a List-based approach that supports native `onMove`. This is the simplest and most reliable way to get drag reorder on macOS.

Specific changes to LabelSettingsView:

1. Replace the `ScrollView { LazyVStack { ForEach ... } }` block (lines 46-55) with a `List` that uses `ForEach(labels)` and `.onMove(perform: moveLabels)`.

2. Style the List to blend with the current Settings appearance:
   - Apply `.listStyle(.plain)` to remove default List chrome.
   - Each row should keep its current LabelRow appearance (color/emoji button, name, delete button).
   - Add a drag handle using `Image(systemName: "line.3.horizontal")` styled `.foregroundStyle(.tertiary)` at the leading edge of each row, or rely on the default List onMove drag affordance.

3. Add a `moveLabels(from:to:)` method to LabelSettingsView:
   ```swift
   private func moveLabels(from source: IndexSet, to destination: Int) {
       // Build a mutable array from the @Query results
       var reordered = Array(labels)
       reordered.move(fromOffsets: source, toOffset: destination)
       // Update sortOrder on each label to match new array index
       for (index, label) in reordered.enumerated() {
           if label.sortOrder != index {
               label.sortOrder = index
           }
       }
       saveWithLogging(modelContext, operation: "reorder labels")
   }
   ```

4. Keep the existing LabelRow struct unchanged -- it already works as a row view.

5. Keep the empty state (`if labels.isEmpty`) as-is -- only modify the non-empty branch.

6. The Divider between rows: List provides its own separators, so remove the manual `Divider().padding(.leading, 38)` that was inside ForEach.

Important: Do NOT touch ChipBarView or PanelContentView. They already use `@Query(sort: \Label.sortOrder)` so the reorder propagates automatically when sortOrder values change in SwiftData.
  </action>
  <verify>
Build the project with `xcodebuild -scheme "Pastel Sparkle" -configuration Debug build 2>&1 | tail -20` -- should compile with 0 errors.
  </verify>
  <done>
Labels in Settings can be dragged to reorder. The sortOrder property updates on each affected Label. Panel chip bar reflects the new order on next open (or immediately if already visible). Build succeeds.
  </done>
</task>

</tasks>

<verification>
1. Build succeeds: `xcodebuild -scheme "Pastel Sparkle" -configuration Debug build` completes with 0 errors
2. LabelSettingsView uses List with onMove for drag reorder
3. moveLabels method updates Label.sortOrder and saves via saveWithLogging
4. No changes to Label model (sortOrder already exists)
5. No changes to ChipBarView or PanelContentView (they already sort by sortOrder)
</verification>

<success_criteria>
- LabelSettingsView has drag-to-reorder via List onMove
- Reordering updates sortOrder on each affected Label
- Project builds successfully
- Panel ChipBarView automatically reflects new order (no code change needed)
</success_criteria>

<output>
After completion, create `.planning/quick/31-allow-user-to-rearrange-labels-in-settin/31-SUMMARY.md`
</output>
