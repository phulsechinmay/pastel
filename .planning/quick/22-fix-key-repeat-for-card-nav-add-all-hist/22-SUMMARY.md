---
phase: quick-022
plan: 01
subsystem: ui
tags: [nsEvent, keyRepeat, chipBar, dragPaste, swiftUI, appKit]

# Dependency graph
requires:
  - phase: quick-021
    provides: Initial key repeat attempt via SwiftUI .onKeyPress phases
provides:
  - NSEvent-based arrow key monitor for reliable key repeat card navigation
  - "All History" chip in label chip bar with Cmd+arrow cycling support
  - Auto-dismiss panel after drag-to-paste with settings toggle
affects: [panel, settings, chipBar]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - NSEvent.addLocalMonitorForEvents for key handling immune to SwiftUI re-render interruptions
    - UserDefaults nil-check pattern for default-true booleans (object(forKey:) == nil || bool(forKey:))

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/FilteredCardListView.swift
    - Pastel/Views/Panel/ChipBarView.swift
    - Pastel/Views/Panel/PanelContentView.swift
    - Pastel/Views/Panel/PanelController.swift
    - Pastel/Views/Settings/GeneralSettingsView.swift

key-decisions:
  - "NSEvent local monitor instead of SwiftUI .onKeyPress for arrow keys -- AppKit-level event handling is immune to SwiftUI re-render interruptions that break key repeat"
  - "UserDefaults nil-check pattern for dismissAfterDragPaste -- bool(forKey:) returns false for unset keys, but desired default is true"
  - "All History chip as synthetic first item in CenteredFlowLayout rather than injecting into label data model"

patterns-established:
  - "NSEvent local monitor for key repeat: install in onAppear, remove in onDisappear, pass through non-handled keys"

# Metrics
duration: 2min
completed: 2026-02-12
---

# Quick 022: Fix Key Repeat, All History Chip, Drag-to-Paste Dismiss Summary

**NSEvent-based arrow key monitor for reliable key repeat, "All History" label chip with Cmd+arrow cycling, and auto-dismiss panel after drag-to-paste**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-12T23:30:58Z
- **Completed:** 2026-02-12T23:33:23Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Holding arrow keys now continuously scrolls through panel cards via NSEvent local monitor (bypasses SwiftUI re-render interruption)
- "All History" chip with circle-arrow icon appears as first chip in label bar, highlighted when no label is filtered
- Cmd+Left/Right cycling includes "All History" position: All History -> first label -> ... -> last label -> All History
- Panel auto-dismisses after drag-to-paste completes (500ms delay), gated by new Settings toggle (default: on)

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix key repeat card navigation + Add "All History" chip + Cmd+arrow cycling** - `f8b1cf1` (feat)
2. **Task 2: Auto-dismiss panel after drag-to-paste with settings toggle** - `62903e4` (feat)

## Files Created/Modified
- `Pastel/Views/Panel/FilteredCardListView.swift` - Replaced .onKeyPress arrow handlers with NSEvent local monitor for key repeat
- `Pastel/Views/Panel/ChipBarView.swift` - Added "All History" chip as first item with isAllHistoryActive/onSelectAllHistory properties
- `Pastel/Views/Panel/PanelContentView.swift` - Updated ChipBarView call sites and cycleLabelFilter to include All History position
- `Pastel/Views/Panel/PanelController.swift` - Added auto-dismiss after drag-to-paste with UserDefaults setting gate
- `Pastel/Views/Settings/GeneralSettingsView.swift` - Added "Dismiss panel after drag-to-paste" toggle in Paste Behavior section

## Decisions Made
- NSEvent local monitor chosen over SwiftUI .onKeyPress because AppKit-level event handling is immune to re-render interruptions that break key repeat chains
- UserDefaults nil-check pattern (`object(forKey:) == nil || bool(forKey:)`) used for dismissAfterDragPaste since `bool(forKey:)` returns false for unset keys but desired default is true
- "All History" implemented as synthetic UI chip rather than data model injection, keeping label data model clean

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All three usability fixes complete and building
- Key repeat, All History chip, and drag-dismiss ready for manual testing

---
*Phase: quick-022*
*Completed: 2026-02-12*
