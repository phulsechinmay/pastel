---
phase: 31-allow-user-to-rearrange-labels
plan: 01
subsystem: ui
tags: [swiftui, list, onMove, drag-reorder, settings]

# Dependency graph
requires:
  - phase: label-model
    provides: Label.sortOrder property
provides:
  - Drag-to-reorder labels in Settings via List onMove
affects: [label-management, settings-ui]

# Tech tracking
tech-stack:
  added: []
  patterns: [List onMove for drag reorder with sortOrder persistence]

key-files:
  created: []
  modified:
    - Pastel/Views/Settings/LabelSettingsView.swift

key-decisions:
  - "List with onMove instead of custom drag gesture -- native macOS drag affordance, minimal code"
  - "sortOrder updated only when changed (if label.sortOrder != index) to minimize writes"

patterns-established:
  - "List onMove + sortOrder index pattern for reorderable SwiftData lists"

requirements-completed: [QUICK-31]

# Metrics
duration: 2min
completed: 2026-02-26
---

# Quick Task 31: Allow User to Rearrange Labels in Settings Summary

**Drag-to-reorder labels in Settings via List onMove with sortOrder persistence to SwiftData**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-26T05:02:45Z
- **Completed:** 2026-02-26T05:04:36Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Replaced ScrollView/LazyVStack with List + ForEach + onMove for native drag reorder
- Added moveLabels method that rebuilds sortOrder indices on each affected Label
- Panel ChipBarView automatically reflects new order via existing @Query(sort: \Label.sortOrder)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add drag-to-reorder in LabelSettingsView** - `ab4cb61` (feat)

## Files Created/Modified
- `Pastel/Views/Settings/LabelSettingsView.swift` - Replaced ScrollView/LazyVStack with List + onMove for drag reorder; added moveLabels method

## Decisions Made
- Used List with onMove instead of custom drag gesture -- provides native macOS drag affordance with minimal code
- sortOrder only updated when value actually changes (if label.sortOrder != index) to minimize unnecessary SwiftData writes
- Removed manual Divider padding since List provides its own row separators

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Label reordering is fully functional
- No blockers or concerns

## Self-Check: PASSED

- FOUND: Pastel/Views/Settings/LabelSettingsView.swift
- FOUND: ab4cb61

---
*Quick Task: 31-allow-user-to-rearrange-labels*
*Completed: 2026-02-26*
