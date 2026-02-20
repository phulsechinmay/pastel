---
phase: 24-fix-panel-window-level-for-screenshot-preview-compatibility
plan: 01
subsystem: ui
tags: [nswindow, nspanel, window-level, screenshot, cgwindowlevel]

requires:
  - phase: 22-code-color-edit-controls-and-panel-toolbar-tools
    provides: ColorToolController with NSColorPanel management
provides:
  - Panel window level at 23 (above Dock, below Screenshot overlay)
  - Color picker window level matching sliding panel
affects: []

tech-stack:
  added: []
  patterns:
    - "CGWindowLevelForKey(.dockWindow) + 3 for panel level derivation"

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/SlidingPanel.swift
    - Pastel/Services/ColorToolController.swift

key-decisions:
  - "Use CGWindowLevelForKey(.dockWindow) + 3 (level 23) instead of .statusBar (25) for panel window level"

patterns-established:
  - "Derive panel level from CGWindowLevelForKey rather than using fixed NSWindow.Level presets"

duration: 6min
completed: 2026-02-20
---

# Phase 24 Plan 01: Fix Panel Window Level for Screenshot Preview Compatibility Summary

**Panel window level lowered from .statusBar (25) to CGWindowLevelForKey(.dockWindow) + 3 (23) so macOS screenshot thumbnails appear above the panel**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-20T21:24:23Z
- **Completed:** 2026-02-20T21:30:19Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Panel window level changed from .statusBar (25) to custom level 23, below screenshot overlay (24)
- Color picker (NSColorPanel) level updated to match the sliding panel
- Human-verified: panel above Dock, screenshot thumbnail above panel and interactive, Liquid Glass normal

## Task Commits

Each task was committed atomically:

1. **Task 1: Change panel and color picker window levels** - `3a59498` (feat)
2. **Task 2: Verify panel level behavior** - human-verify checkpoint (no commit)

## Files Created/Modified
- `Pastel/Views/Panel/SlidingPanel.swift` - Panel level changed from .statusBar to dockWindow + 3
- `Pastel/Services/ColorToolController.swift` - NSColorPanel level changed to match SlidingPanel

## Decisions Made
- Used `CGWindowLevelForKey(.dockWindow) + 3` rather than a hardcoded integer -- derives from the system dock level for robustness

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Panel window level hierarchy is now correct for screenshot preview compatibility
- No blockers or concerns

---
*Phase: 24-fix-panel-window-level-for-screenshot-preview-compatibility*
*Completed: 2026-02-20*
