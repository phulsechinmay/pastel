---
phase: 29-fix-settings-disappearing-on-panel-dismi
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/PanelController.swift
  - Pastel/Views/Panel/FilteredCardListView.swift
autonomous: true
requirements: [FIX-SETTINGS-DISMISS, FIX-PANEL-REFRESH-ON-DELETE]
must_haves:
  truths:
    - "Settings window remains visible and interactive after panel is dismissed"
    - "Panel list updates immediately when an item is deleted via right-click context menu"
  artifacts:
    - path: "Pastel/Views/Panel/PanelController.swift"
      provides: "Settings-aware panel dismissal logic"
    - path: "Pastel/Views/Panel/FilteredCardListView.swift"
      provides: "Reactive filtered items on deletion"
  key_links:
    - from: "PanelController.hide()"
      to: "SettingsWindowController.shared.window"
      via: "Check if settings is visible before re-activating previous app"
---

<objective>
Fix two bugs: (1) Settings window disappearing when panel is dismissed, and (2) panel not refreshing its card list when an item is deleted.

Purpose: These are UX regressions that break core workflows -- settings management and item deletion.
Output: Patched PanelController.swift and FilteredCardListView.swift.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Panel/PanelController.swift
@Pastel/Views/Settings/SettingsWindowController.swift
@Pastel/Views/Panel/FilteredCardListView.swift
@Pastel/Views/Panel/PanelContentView.swift
@Pastel/Views/Panel/ClipboardCardView.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix Settings window disappearing on panel dismiss</name>
  <files>Pastel/Views/Panel/PanelController.swift</files>
  <action>
  The root cause: when `PanelController.hide()` completes its animation, it calls `self?.previousApp?.activate()` (line 238). This re-activates the app that was frontmost before the panel opened. Since Pastel is an LSUIElement app (no Dock icon), activating another app causes macOS to hide all Pastel windows -- including the Settings window.

  Additionally, the `deactivationObserver` (lines 332-344) fires when app resigns active, which can auto-dismiss the panel even when the user is interacting with Settings.

  Fix in `PanelController.hide()` completion handler:
  1. Before calling `previousApp?.activate()`, check if `SettingsWindowController.shared` has a visible window (check its `window?.isVisible` property).
  2. If Settings IS visible: do NOT activate `previousApp`. Instead, keep Pastel active so Settings remains visible. The user will naturally switch away when they close Settings.
  3. If Settings is NOT visible: activate `previousApp` as before (existing behavior preserved).

  The check should be: check if ANY Pastel window (besides the panel itself) is still visible. This handles Settings, Edit modal, Color Picker, etc. Use `NSApp.windows.contains { $0.isVisible && $0 != panel }` as the condition.

  Code change in hide() completion handler (around line 234-240):
  ```swift
  } completionHandler: { [weak self] in
      panel.orderOut(nil)
      self?.removeEventMonitors()
      // Only return focus to the previous app if no other Pastel windows are visible
      // (e.g., Settings, Edit modal). As an LSUIElement app, activating another app
      // hides ALL Pastel windows -- which would close Settings unexpectedly.
      let hasOtherVisibleWindows = NSApp.windows.contains { window in
          window.isVisible && window != panel
      }
      if !hasOtherVisibleWindows {
          self?.previousApp?.activate()
      }
      self?.previousApp = nil
  }
  ```

  This preserves the existing behavior when no other windows are open, and prevents Settings from disappearing when it is.
  </action>
  <verify>
  Build the project with `xcodebuild`. Open Settings from panel gear button, then dismiss the panel (click outside or press Escape). Settings window must remain visible and interactive.
  </verify>
  <done>Settings window stays visible and interactive after panel dismissal. When no other Pastel windows are open, previous app is re-activated as before.</done>
</task>

<task type="auto">
  <name>Task 2: Fix panel not refreshing after item deletion</name>
  <files>Pastel/Views/Panel/FilteredCardListView.swift</files>
  <action>
  The root cause: `FilteredCardListView` uses `@State private var filteredItems` as a memoization cache (Phase 26-02 optimization). The `onChange(of: items)` handler (line 221) should recompute filteredItems when `@Query` results change. However, SwiftData's `@Query` array comparison may not detect a deletion as a change to the array value if the remaining items are the same objects. The `onChange(of:)` modifier uses `Equatable` conformance, and if SwiftData returns a new array that compares equal in some edge case, the onChange won't fire.

  The fix: Instead of relying solely on `onChange(of: items)`, also observe the items count and trigger recomputation. BUT per the user's explicit instruction, do NOT make the panel refresh dependent on total item count (i.e., do not use `appState.itemCount` or similar).

  The most robust fix is to change the `onChange(of: items)` to use `items.count` as an additional trigger, since array count changing is a definitive signal that items were added or removed. Add a second `onChange(of: items.count)` handler that also recomputes:

  ```swift
  .onChange(of: items.count) { _, _ in
      filteredItems = computeFilteredItems(from: items)
  }
  ```

  This is the @Query items.count (local to this view), NOT the global appState.itemCount. The @Query array's count changes when an item is deleted from SwiftData. This ensures deletion always triggers a refresh.

  Also, in the existing `.onChange(of: items)` handler, ensure it fires by comparing identities not just equality. Actually, the simplest and most reliable approach: replace the `onChange(of: items)` with `onChange(of: items.map(\.id))` which tracks the actual set of item IDs. When an item is deleted, its ID disappears from the mapped array, guaranteeing the onChange fires:

  Replace line 221-223:
  ```swift
  .onChange(of: items.map(\.id)) { _, _ in
      filteredItems = computeFilteredItems(from: items)
  }
  ```

  This maps each item to its stable identifier, so any addition or removal of items produces a different array value, guaranteeing the onChange handler fires.
  </action>
  <verify>
  Build the project with `xcodebuild`. Open the panel, right-click an item, choose Delete. The card must disappear immediately from the panel list without needing to close and reopen the panel.
  </verify>
  <done>Deleting an item from the panel via right-click context menu immediately removes the card from the visible list. No panel close/reopen required.</done>
</task>

</tasks>

<verification>
1. Open panel -> open Settings via gear icon -> dismiss panel (Escape or click outside) -> Settings window remains visible
2. Open panel -> right-click any card -> Delete -> card disappears immediately from the list
3. Open panel -> paste an item (double-click) -> panel dismisses and previous app regains focus (existing behavior preserved when no Settings open)
</verification>

<success_criteria>
- Settings window survives panel dismissal
- Panel card list updates immediately on item deletion
- No regression in panel dismiss-and-refocus behavior when no other Pastel windows are open
</success_criteria>

<output>
After completion, create `.planning/quick/29-fix-settings-disappearing-on-panel-dismi/29-01-SUMMARY.md`
</output>
