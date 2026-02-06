---
phase: 03-paste-back-and-hotkeys
plan: 02
subsystem: ui
tags: [keyboard-navigation, selection, double-click, accessibility-onboarding, swiftui]

# Dependency graph
requires:
  - phase: 03-paste-back-and-hotkeys
    plan: 01
    provides: PasteService, AccessibilityService, PanelActions observable bridge, AppState.paste(item:) entry point
  - phase: 02-sliding-panel
    provides: PanelContentView, ClipboardCardView, PanelController
provides:
  - Keyboard navigation (arrow keys + Enter) in PanelContentView
  - Selection highlight (accent background + border) on ClipboardCardView
  - Double-click to paste any card
  - Single-click to select card
  - ScrollViewReader auto-scrolling to selected card
  - AccessibilityPromptView onboarding for first launch
  - AppState.checkAccessibilityOnLaunch() integration
affects: [04-search-and-management, 05-polish-and-preferences]

# Tech tracking
tech-stack:
  added: []
  patterns: [ScrollViewReader for keyboard-driven scroll, .onKeyPress for SwiftUI keyboard handling, Timer.publish polling for permission state]

key-files:
  created:
    - Pastel/Views/Onboarding/AccessibilityPromptView.swift
  modified:
    - Pastel/Views/Panel/PanelContentView.swift
    - Pastel/Views/Panel/ClipboardCardView.swift
    - Pastel/App/AppState.swift
    - Pastel/PastelApp.swift

key-decisions:
  - "Double-tap gesture (count: 2) placed BEFORE single-tap (count: 1) on same view for correct SwiftUI gesture priority"
  - "AccessibilityPromptView uses Timer.publish polling (1s) to auto-dismiss when permission granted"
  - "Onboarding shown via standalone NSWindow (menu-bar-only app has no main window for sheets)"
  - "Selection highlight uses accentColor + strokeBorder to be visually distinct from hover state"

patterns-established:
  - "Keyboard navigation: @State selectedIndex + .onKeyPress + ScrollViewReader for auto-scroll"
  - "Onboarding window: NSWindow with NSHostingView for standalone SwiftUI views in menu-bar apps"
  - "Permission polling: Timer.publish + onReceive to detect async permission grants"

# Metrics
duration: 2min
completed: 2026-02-06
---

# Phase 3 Plan 02: Keyboard Navigation, Selection, and Accessibility Onboarding Summary

**Arrow key navigation with Enter/double-click paste, accent-color selection highlighting, and Accessibility permission onboarding window with auto-dismiss polling**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-06T17:48:19Z
- **Completed:** 2026-02-06T17:50:48Z
- **Tasks:** 2
- **Files modified:** 5 (1 created, 4 modified)

## Accomplishments
- PanelContentView now tracks selectedIndex via @State, with arrow key navigation via .onKeyPress
- ScrollViewReader auto-scrolls to keep selected card visible
- Double-click (count: 2) and Enter trigger paste through PanelActions -> PasteService chain
- Single-click (count: 1) selects a card; selection resets to nil on panel appear
- ClipboardCardView shows accent-color background (0.3 opacity) + border (0.5 opacity, 1.5pt) when selected, distinct from hover
- AccessibilityPromptView explains permission purpose, offers Grant/Settings/Skip buttons
- Onboarding polls AXIsProcessTrusted every 1s and auto-dismisses when granted
- AppState.checkAccessibilityOnLaunch() shows prompt as standalone NSWindow on first launch

## Task Commits

Each task was committed atomically:

1. **Task 1: Keyboard navigation, selection highlight, and double-click paste** - `5300556` (feat)
2. **Task 2: Accessibility permission onboarding view** - `9064ef6` (feat)

## Files Created/Modified
- `Pastel/Views/Panel/PanelContentView.swift` - Added selectedIndex state, onKeyPress handlers, ScrollViewReader, double-click/single-click gestures, pasteItem helper, onAppear reset
- `Pastel/Views/Panel/ClipboardCardView.swift` - Added isSelected property with accent-color background/border, init with defaults for backward compatibility
- `Pastel/Views/Onboarding/AccessibilityPromptView.swift` - New onboarding view with grant/settings/skip buttons and permission polling
- `Pastel/App/AppState.swift` - Added checkAccessibilityOnLaunch() with NSWindow presentation
- `Pastel/PastelApp.swift` - Calls checkAccessibilityOnLaunch in init

## Decisions Made
- Double-tap gesture declared before single-tap on same view element for correct SwiftUI gesture resolution (higher-count gestures must be declared first)
- AccessibilityPromptView uses Timer.publish polling at 1s interval to detect when user grants permission in System Settings (no callback API exists)
- Onboarding displayed via standalone NSWindow with NSHostingView -- menu-bar-only apps have no main window for presenting sheets
- Selection uses accentColor at two opacities (0.3 background, 0.5 border) to distinguish from hover state (white at 0.12)

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered
None. Both tasks built cleanly on first attempt.

## User Setup Required
None. Accessibility permission will be prompted on first launch if not already granted.

## Phase 3 Completion

This plan completes Phase 3. All 5 Phase 3 requirements are now satisfied:

| Requirement | Description | Status |
|-------------|-------------|--------|
| PAST-01 | Double-click card to paste into active app | Done (Plan 02, Task 1) |
| PAST-02 | Accessibility permission onboarding prompt | Done (Plan 02, Task 2) |
| PAST-03 | Non-activating panel (doesn't steal focus) | Done (Plan 01 via SlidingPanel.nonactivatingPanel from Phase 2) |
| PNUI-04 | Global hotkey toggles panel | Done (Phase 2 via KeyboardShortcuts Cmd+Shift+V) |
| PNUI-09 | Arrow key navigation + Enter to paste | Done (Plan 02, Task 1) |

## Next Phase Readiness
- All paste-back and keyboard interaction infrastructure is complete
- Phase 4 (Organization) can add search field, labels, and filtering to PanelContentView
- The .focusable() modifier on PanelContentView may need adjustment when search field is added in Phase 4

---
*Phase: 03-paste-back-and-hotkeys*
*Completed: 2026-02-06*
