---
phase: 11-item-titles-multi-label-edit-modal
plan: 02
subsystem: ui
tags: [swiftui, card-layout, context-menu, label-chips, relative-time, sheet-modal]

# Dependency graph
requires:
  - phase: 11-item-titles-multi-label-edit-modal
    provides: ClipboardItem.title, ClipboardItem.labels, EditItemView modal
  - phase: 04-labels-filtering
    provides: Label model, LabelColor enum, cardLabelChipBackground helper
provides:
  - "Restructured card header with optional title display and abbreviated relative time"
  - "Card footer with up to 3 label chips and +N overflow badge"
  - "Multi-label toggle context menu with checkmarks and Remove All Labels"
  - "Edit sheet trigger from context menu opening EditItemView"
  - "labelChipSmall compact footer chip helper"
  - "relativeTimeString abbreviated time formatter (secs/mins/hours/days)"
affects: [11-03 filtering and drag-drop updates]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Abbreviated relative time via custom formatter (no auto-update, acceptable for brief panel)", "Footer label chip overflow with +N badge pattern"]

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/ClipboardCardView.swift

key-decisions:
  - "[11-02]: Custom relativeTimeString over built-in Date.RelativeFormatStyle -- gives exact 'mins/secs' wording control; panel is open briefly so static string is acceptable"
  - "[11-02]: Footer shows max 3 label chips with +N overflow badge to prevent layout breakage on narrow panels"
  - "[11-02]: Label submenu uses toggle pattern (add/remove) with checkmark indicators instead of single-assignment"

patterns-established:
  - "labelChipSmall: compact footer chip (size 8 emoji, size 9 text, 5px horizontal padding) for space-constrained contexts"
  - "Context menu multi-select label pattern: contains check by persistentModelID, toggle add/remove, checkmark indicator"

# Metrics
duration: 3min
completed: 2026-02-08
---

# Phase 11 Plan 02: Card Layout Restructure Summary

**Restructured ClipboardCardView with title in header, multi-label chips in footer with +N overflow, abbreviated relative time, and context menu edit/label-toggle actions**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-09T03:59:50Z
- **Completed:** 2026-02-09T04:11:52Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Moved title display to card header (bold caption2, shown when set)
- Replaced built-in relative time format with custom abbreviated format (secs/mins/hours/days)
- Restructured footer to show metadata text, up to 3 label chips with +N overflow badge, and keycap badge
- Updated context menu with "Edit..." action triggering EditItemView sheet and multi-label toggle submenu with checkmarks

## Task Commits

Each task was committed atomically:

1. **Task 1: Restructure card header with title and abbreviated time** - `9594afa` (feat)
2. **Task 2: Restructure footer, multi-label context menu, and edit sheet** - `cc60c97` (feat)

**Plan metadata:** TBD (docs: complete plan)

## Files Created/Modified
- `Pastel/Views/Panel/ClipboardCardView.swift` - Restructured header (title + abbreviated time), footer (label chips + overflow), context menu (edit + label toggle), added labelChipSmall and relativeTimeString helpers

## Decisions Made
- Custom `relativeTimeString` formatter chosen over `Date.RelativeFormatStyle` for exact "mins/secs/hours/days" abbreviation control; the panel is open briefly so static strings are acceptable
- Footer enforces max 3 visible label chips with "+N" overflow badge to prevent layout issues on narrow panels
- Context menu label submenu uses toggle pattern with `persistentModelID` comparison and checkmark indicators

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Card layout fully restructured for multi-label display
- EditItemView accessible from context menu via sheet presentation
- Ready for Plan 11-03: multi-label filtering, chip bar multi-select, drag-drop label append, search including title

---
*Phase: 11-item-titles-multi-label-edit-modal*
*Completed: 2026-02-08*
