---
phase: 29-robust-item-deletion-with-undo-scroll-preservation-and-panel-refresh
plan: 02
subsystem: ui
tags: [swiftui, nsevent, animation, scroll-preservation, undo, soft-delete]

# Dependency graph
requires:
  - phase: 29-01
    provides: DeletionManager service with soft-delete buffer, undo, sound, deferred cleanup
provides:
  - Soft-delete exclusion in FilteredCardListView via DeletionManager.softDeletedIDs
  - Slide-left + fade removal animation on card deletion
  - Cmd+Z undo handler in NSEvent keyboard monitor
  - Selection advancement after deletion
  - Scroll position preservation across panel dismiss/reopen
  - deletionCount fully removed from codebase
affects: [panel-refresh, deletion-ux]

# Tech tracking
tech-stack:
  added: []
  patterns: [onChange-based data refresh without view recreation for scroll preservation, asymmetric transition for slide-left removal]

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/FilteredCardListView.swift
    - Pastel/Views/Panel/PanelContentView.swift
    - Pastel/Views/Panel/PanelController.swift
    - Pastel/Views/Panel/ClipboardCardView.swift

key-decisions:
  - "showCount replaces deletionCount -- single parameter for panel reopen refresh, not deletion trigger"
  - "showCount excluded from .id() so scroll position survives dismiss/reopen -- data refresh via onChange handler"
  - "softDeletedIDs observed via onChange (not .id()) to avoid view recreation on delete"

patterns-established:
  - "onChange-based refresh for mutable counters: pass as parameter + onChange handler, never include in .id()"
  - "Asymmetric transition pattern: .opacity for insertion, .move(edge:).combined(with: .opacity) for removal"

requirements-completed: [DEL-07, DEL-08, DEL-09, DEL-10, DEL-11, DEL-12]

# Metrics
duration: 3min
completed: 2026-02-22
---

# Phase 29 Plan 02: Panel View Integration Summary

**Soft-delete exclusion with slide-left animations, Cmd+Z undo, scroll preservation across dismiss/reopen, and deletionCount removal**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-22T02:50:37Z
- **Completed:** 2026-02-22T02:53:55Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Integrated DeletionManager into FilteredCardListView: soft-deleted items excluded from display, slide-left + fade animation on removal
- Added Cmd+Z undo handler to NSEvent keyboard monitor that restores soft-deleted item with fade-in
- Scroll position preserved across panel dismiss/reopen by excluding showCount from .id() and using onChange handler
- Fully removed deletionCount from PanelActions, PanelContentView, ClipboardCardView, and FilteredCardListView

## Task Commits

Each task was committed atomically:

1. **Task 1: Add soft-delete exclusion, slide-left transitions, Cmd+Z undo, and selection advancement** - `178c8b8` (feat)
2. **Task 2: Clean up PanelContentView and PanelController -- remove deletionCount, add scroll position memory** - `641e5b1` (feat)

## Files Created/Modified
- `Pastel/Views/Panel/FilteredCardListView.swift` - Added @Environment(AppState.self), softDeletedIDs exclusion in computeFilteredItems, .transition(.asymmetric) on cards, Cmd+Z handler, showCount parameter replacing deletionCount, onChange handlers for soft-delete and panel reopen
- `Pastel/Views/Panel/PanelContentView.swift` - Pass showCount instead of deletionCount, exclude showCount from .id() for scroll preservation
- `Pastel/Views/Panel/PanelController.swift` - Removed deletionCount from PanelActions, updated showCount comment
- `Pastel/Views/Panel/ClipboardCardView.swift` - Removed panelActions.deletionCount += 1 from deleteItem()

## Decisions Made
- Replaced deletionCount with showCount as the single panel-reopen refresh parameter; deletion refresh now driven by DeletionManager.softDeletedIDs observation
- Excluded showCount from PanelContentView .id() so view is NOT recreated on panel reopen, preserving scroll position; data refresh happens via onChange(of: showCount) handler instead
- Added PanelContentView parameter change (showCount pass-through) in Task 1 as Rule 3 auto-fix to maintain build success

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated PanelContentView parameter in Task 1 instead of Task 2**
- **Found during:** Task 1 (FilteredCardListView changes)
- **Issue:** After removing deletionCount parameter from FilteredCardListView and adding showCount, PanelContentView still passed `deletionCount: panelActions.deletionCount` which would not compile
- **Fix:** Changed PanelContentView to pass `showCount: panelActions.showCount` in Task 1 to maintain build success
- **Files modified:** Pastel/Views/Panel/PanelContentView.swift
- **Verification:** Build succeeded
- **Committed in:** 178c8b8 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Moved one line change from Task 2 to Task 1 for compilation. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 29 is complete: DeletionManager service (Plan 01) + panel view integration (Plan 02)
- Single-item deletion has full UX: soft-delete, slide-left animation, trash sound, Cmd+Z undo, scroll preservation
- Bulk deletion (2+ items) retains confirmation dialog and bypasses undo (unchanged behavior)

## Self-Check: PASSED

---
*Phase: 29-robust-item-deletion-with-undo-scroll-preservation-and-panel-refresh*
*Completed: 2026-02-22*
