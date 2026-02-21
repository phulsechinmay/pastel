---
phase: 29-fix-settings-disappearing-on-panel-dismi
plan: 01
subsystem: ui
tags: [NSPanel, LSUIElement, SwiftUI, SwiftData, panel-dismiss, settings-window]

# Dependency graph
requires:
  - phase: 26-panel-performance-optimization
    provides: "@State memoization pattern for FilteredCardListView"
provides:
  - "Settings-aware panel dismissal (LSUIElement window preservation)"
  - "Reliable filtered item refresh on SwiftData deletion"
affects: [panel, settings, FilteredCardListView]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "NSApp.windows visibility check before previousApp.activate() for LSUIElement apps"
    - "items.map(\\.id) for onChange identity tracking instead of array equality"

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/PanelController.swift
    - Pastel/Views/Panel/FilteredCardListView.swift

key-decisions:
  - "Check all visible Pastel windows (not just Settings) before re-activating previous app -- handles Edit modal, Color Picker, etc."
  - "Use items.map(\\.id) instead of items for onChange trigger -- SwiftData array equality unreliable for deletion detection"

patterns-established:
  - "LSUIElement dismiss guard: always check NSApp.windows for visible siblings before activating external app"

requirements-completed: [FIX-SETTINGS-DISMISS, FIX-PANEL-REFRESH-ON-DELETE]

# Metrics
duration: 1min 31s
completed: 2026-02-21
---

# Quick Task 29: Fix Settings Disappearing on Panel Dismiss Summary

**Settings-aware panel dismissal preserving all visible Pastel windows, plus identity-based onChange for reliable deletion refresh**

## Performance

- **Duration:** 1 min 31s
- **Started:** 2026-02-21T21:33:48Z
- **Completed:** 2026-02-21T21:35:19Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Settings window (and any other Pastel window) no longer disappears when the panel is dismissed
- Panel card list immediately refreshes when an item is deleted via right-click context menu
- Existing behavior preserved: previous app is re-activated when no other Pastel windows are open

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix Settings window disappearing on panel dismiss** - `cd36a3b` (fix)
2. **Task 2: Fix panel not refreshing after item deletion** - `28d42e9` (fix)

## Files Created/Modified
- `Pastel/Views/Panel/PanelController.swift` - Added visible-window check before previousApp.activate() in hide() completion handler
- `Pastel/Views/Panel/FilteredCardListView.swift` - Changed onChange trigger from items array to items.map(\.id) for identity-based change detection

## Decisions Made
- Used `NSApp.windows.contains { $0.isVisible && $0 != panel }` as a generic check rather than specifically checking SettingsWindowController -- this handles Settings, Edit modal, Color Picker, and any future windows
- Used `items.map(\.id)` for onChange trigger rather than adding a separate `onChange(of: items.count)` -- mapping to IDs catches both additions and removals in a single handler, and is more robust than count alone (which would miss replace-in-place scenarios)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Both bugs are fixed and verified via successful build
- Manual testing recommended: open Settings from panel, dismiss panel, verify Settings stays visible
- Manual testing recommended: right-click delete an item, verify it disappears from the panel list

## Self-Check: PASSED

- [x] PanelController.swift exists
- [x] FilteredCardListView.swift exists
- [x] 29-SUMMARY.md exists
- [x] Commit cd36a3b exists (Task 1)
- [x] Commit 28d42e9 exists (Task 2)

---
*Quick Task: 29-fix-settings-disappearing-on-panel-dismi*
*Completed: 2026-02-21*
