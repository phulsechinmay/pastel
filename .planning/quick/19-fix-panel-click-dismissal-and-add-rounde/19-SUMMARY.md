---
phase: quick-19
plan: 01
subsystem: ui
tags: [nspanel, event-monitors, corner-radius, calayer, appkit]

# Dependency graph
requires:
  - phase: quick-018
    provides: "NSGlassEffectView panel with containerView architecture"
provides:
  - "Panel that handles inside vs outside clicks correctly"
  - "Edge-aware rounded corners at the window level"
affects: [panel, settings]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Global click monitor with panel frame guard"
    - "Delayed deactivation observer for false-positive prevention"
    - "FirstMouseView pattern for borderless NSPanel click acceptance"
    - "CACornerMask edge-aware rounding based on PanelEdge"

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/PanelController.swift
    - Pastel/Views/Panel/SlidingPanel.swift

key-decisions:
  - "Use 150ms delayed deactivation check instead of removing deactivation observer entirely"
  - "FirstMouseView subclass instead of trying to override acceptsFirstMouse on NSPanel (NSView method, not NSWindow)"
  - "CACornerMask for edge-aware rounding instead of full 4-corner radius"

patterns-established:
  - "FirstMouseView: custom NSView subclass for acceptsFirstMouse in borderless panels"
  - "Delayed deactivation observer: asyncAfter + re-check NSApp.isActive before dismissing"

# Metrics
duration: 2min
completed: 2026-02-11
---

# Quick Task 19: Fix Panel Click Dismissal and Add Rounded Corners Summary

**Fixed panel dismissing on internal clicks via frame-guarded global monitor, delayed deactivation observer, and FirstMouseView; added edge-aware 12pt rounded corners**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-12T00:05:15Z
- **Completed:** 2026-02-12T00:07:14Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Panel no longer dismisses when clicking search bar, label chips, card items, or gear button
- Panel still correctly dismisses on outside clicks, Escape key, and hotkey toggle
- Window-level rounded corners on inward-facing edges (12pt radius) for all four panel edge configurations
- FirstMouseView ensures clicks register immediately without requiring separate activation click

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix panel click-through dismissal** - `e791112` (fix)
2. **Task 2: Add window-level rounded corners** - `0d2385f` (feat)

## Files Created/Modified
- `Pastel/Views/Panel/PanelController.swift` - Fixed event monitors: global click monitor with panel frame guard, local click monitor for re-activation, delayed deactivation observer; added edge-aware CACornerMask rounding to containerView; use FirstMouseView
- `Pastel/Views/Panel/SlidingPanel.swift` - Added FirstMouseView subclass with acceptsFirstMouse override

## Decisions Made
- **150ms deactivation delay:** Chosen over removing the deactivation observer entirely -- still need to dismiss when user Cmd+Tabs away, but need to tolerate momentary focus changes during internal clicks
- **FirstMouseView subclass:** `acceptsFirstMouse(for:)` is an NSView method, not NSWindow -- cannot override on NSPanel. Created lightweight NSView subclass used as containerView
- **CACornerMask edge-awareness:** Only round corners facing inward (away from screen edge) using `maskedCorners` property, matching the SwiftUI-level UnevenRoundedRectangle clipping

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] acceptsFirstMouse is NSView method, not NSWindow**
- **Found during:** Task 1 (SlidingPanel override)
- **Issue:** Plan specified overriding `acceptsFirstMouse(for:)` on SlidingPanel (NSPanel subclass), but this method exists on NSView, not NSWindow. Build failed with "method does not override any method from its superclass"
- **Fix:** Created `FirstMouseView` (NSView subclass) with the override, used it as the panel's containerView in PanelController.createPanel()
- **Files modified:** SlidingPanel.swift, PanelController.swift
- **Verification:** Build succeeded
- **Committed in:** e791112 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minor implementation adjustment. Same functional outcome (first mouse clicks accepted) achieved via view subclass instead of window override.

## Issues Encountered
None beyond the deviation noted above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Panel is now fully mouse-interactive: search, label filtering, card clicking, and gear button all work
- Rounded corners provide polished visual presentation on all edge configurations
- Ready for any future panel enhancements

## Self-Check: PASSED

All files exist, all commits verified.

---
*Phase: quick-19*
*Completed: 2026-02-11*
