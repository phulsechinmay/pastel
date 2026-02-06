---
phase: 04-organization
plan: 02
subsystem: ui
tags: [swiftui, swiftdata, label, chip-bar, context-menu, filtering, popover]

# Dependency graph
requires:
  - phase: 04-organization-01
    provides: Label SwiftData model, FilteredCardListView with selectedLabelID predicate, PanelContentView with selectedLabel state
  - phase: 02-sliding-panel
    provides: PanelContentView, ClipboardCardView dispatcher pattern
provides:
  - LabelColor enum with 8 preset colors
  - ChipBarView horizontal scrolling chip bar with label selection and inline creation
  - Context menu on ClipboardCardView with label assignment submenu and delete action
  - Full label filtering chain wired through PanelContentView
affects: [04-03 bulk operations, 04-04 deletion with image cleanup, 05 settings label management]

# Tech tracking
tech-stack:
  added: []
  patterns: [popover for inline creation in menu-bar app, @Query in child views for context menu data]

key-files:
  created:
    - Pastel/Models/LabelColor.swift
    - Pastel/Views/Panel/ChipBarView.swift
  modified:
    - Pastel/Views/Panel/ClipboardCardView.swift
    - Pastel/Views/Panel/PanelContentView.swift
    - Pastel.xcodeproj/project.pbxproj

key-decisions:
  - "Popover for label creation (not sheet) since menu-bar-only app has no main window"
  - "@Query for labels in ClipboardCardView (context menu) and PanelContentView (chip bar) separately"
  - "persistentModelID comparison for both chip selection and context menu checkmark"

patterns-established:
  - "Popover pattern: .popover on button in menu-bar app for inline forms"
  - "@Query in leaf views: child views can independently query models for context menus"

# Metrics
duration: 2min
completed: 2026-02-06
---

# Phase 4 Plan 2: Chip Bar and Label Context Menu Summary

**Horizontal chip bar for label filtering with inline popover creation, and right-click context menu on cards for label assignment and deletion**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-06T19:59:19Z
- **Completed:** 2026-02-06T20:01:54Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- LabelColor enum with 8 preset colors mapped to SwiftUI Color values
- ChipBarView with horizontal scrolling, label chip selection/deselection, and "+" creation chip
- Inline label creation popover with name field, color palette picker, and create/cancel actions
- Context menu on ClipboardCardView with Label submenu (assign with checkmark, remove) and Delete action
- Full filtering chain: chip selection -> selectedLabel -> persistentModelID -> FilteredCardListView predicate

## Task Commits

Each task was committed atomically:

1. **Task 1: LabelColor enum + ChipBarView with inline label creation** - `171d7cf` (feat)
2. **Task 2: Context menu on cards + chip bar wired into PanelContentView** - `22b5b58` (feat)

## Files Created/Modified
- `Pastel/Models/LabelColor.swift` - Enum with 8 color cases (red, orange, yellow, green, blue, purple, pink, gray) and SwiftUI Color mapping
- `Pastel/Views/Panel/ChipBarView.swift` - Horizontal scrolling chip bar with label chips, selection toggle, "+" creation chip, and popover form
- `Pastel/Views/Panel/ClipboardCardView.swift` - Added @Query for labels, @Environment modelContext, and .contextMenu with Label submenu and Delete
- `Pastel/Views/Panel/PanelContentView.swift` - Added @Query for labels, inserted ChipBarView between search field and card list
- `Pastel.xcodeproj/project.pbxproj` - Regenerated via xcodegen to include new source files

## Decisions Made
- Used `.popover` for label creation instead of `.sheet` -- menu-bar-only apps have no main window to anchor sheets, but popovers work correctly attached to the "+" chip button
- Placed `@Query(sort: \Label.sortOrder)` independently in both ClipboardCardView (for context menu label list) and PanelContentView (for chip bar) -- each view needs labels for different purposes, and SwiftData queries are lightweight
- Used `persistentModelID` comparison everywhere (chip selection, context menu checkmark) to avoid fragile object identity comparisons with SwiftData models

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Regenerated Xcode project for new source files**
- **Found during:** Task 2 (build verification)
- **Issue:** xcodebuild could not find `ChipBarView` in scope because the .xcodeproj file did not reference the newly created files
- **Fix:** Ran `xcodegen generate` to regenerate project from project.yml (which auto-discovers all files under Pastel/)
- **Files modified:** Pastel.xcodeproj/project.pbxproj
- **Verification:** Build succeeds after regeneration
- **Committed in:** 22b5b58 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Standard project maintenance. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Label system fully functional: create, assign, filter, remove
- Context menu provides foundation for additional actions (bulk ops in 04-03)
- Delete action is basic (no image cleanup) -- 04-04 will add proper cleanup via ImageStorageService
- Chip bar ready for any future label management enhancements

---
*Phase: 04-organization*
*Completed: 2026-02-06*
