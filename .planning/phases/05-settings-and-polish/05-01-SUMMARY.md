---
phase: 05-settings-and-polish
plan: 01
subsystem: ui, infra
tags: [settings, NSWindow, LaunchAtLogin, KeyboardShortcuts, SwiftUI, UserDefaults, retention]

# Dependency graph
requires:
  - phase: 02-sliding-panel
    provides: PanelController with show/hide animation
  - phase: 03-paste-back-and-hotkeys
    provides: KeyboardShortcuts.Name.togglePanel, AppState setup
provides:
  - PanelEdge enum with 4-edge frame calculations
  - SettingsWindowController singleton for settings window lifecycle
  - SettingsView with custom tab bar (General + Labels placeholder)
  - GeneralSettingsView with 4 settings controls
  - ScreenEdgePicker visual edge selector
  - RetentionService with hourly auto-purge
  - Settings access from panel header gear icon and menu bar popover
affects: [05-02 Labels tab and horizontal panel layout]

# Tech tracking
tech-stack:
  added: [LaunchAtLogin (already in project.yml, now used)]
  patterns: [SettingsWindowController singleton, @AppStorage for user preferences, visual picker component]

key-files:
  created:
    - Pastel/Models/PanelEdge.swift
    - Pastel/Views/Settings/SettingsWindowController.swift
    - Pastel/Views/Settings/SettingsView.swift
    - Pastel/Views/Settings/GeneralSettingsView.swift
    - Pastel/Views/Settings/ScreenEdgePicker.swift
    - Pastel/Services/RetentionService.swift
  modified:
    - Pastel/Views/Panel/PanelController.swift
    - Pastel/App/AppState.swift
    - Pastel/PastelApp.swift
    - Pastel/Views/Panel/PanelContentView.swift
    - Pastel/Views/MenuBar/StatusPopoverView.swift

key-decisions:
  - "SettingsWindowController accepts both ModelContainer and AppState for full environment wiring"
  - "RetentionService uses stop() method instead of deinit for Swift 6 strict concurrency compatibility"
  - "PanelController recreates panel on vertical<->horizontal orientation change"
  - "@AppStorage panelEdge defaults to 'right', historyRetention defaults to 90 days"

patterns-established:
  - "Settings singleton: SettingsWindowController.shared.showSettings(modelContainer:appState:)"
  - "Visual picker: ScreenEdgePicker with @Binding to @AppStorage raw value"
  - "Retention service: hourly Timer + SwiftData fetch/delete with image cleanup"

# Metrics
duration: 4min
completed: 2026-02-06
---

# Phase 5 Plan 1: Settings Window and General Tab Summary

**Settings window with 4-edge panel position, launch at login, hotkey recorder, visual edge picker, and hourly retention auto-purge**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-06T22:05:23Z
- **Completed:** 2026-02-06T22:09:00Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments

- PanelEdge enum replaces hard-coded right-edge math, enabling left/right/top/bottom panel positions
- Settings window accessible from both the panel header gear icon and menu bar popover
- General tab with all 4 settings: launch at login, hotkey recorder, visual panel position picker, history retention dropdown
- RetentionService auto-purges expired items hourly based on user-configured retention period

## Task Commits

Each task was committed atomically:

1. **Task 1: PanelEdge enum + PanelController refactor for 4 edges** - `da24cae` (feat)
2. **Task 2: Settings window, General tab, RetentionService, and access point wiring** - `edcbbab` (feat)

## Files Created/Modified

- `Pastel/Models/PanelEdge.swift` - Enum with left/right/top/bottom frame calculations
- `Pastel/Views/Settings/SettingsWindowController.swift` - Singleton NSWindow manager for settings
- `Pastel/Views/Settings/SettingsView.swift` - Root settings view with custom tab bar
- `Pastel/Views/Settings/GeneralSettingsView.swift` - General tab with 4 settings controls
- `Pastel/Views/Settings/ScreenEdgePicker.swift` - Visual screen diagram with clickable edge bars
- `Pastel/Services/RetentionService.swift` - History auto-purge based on retention UserDefaults
- `Pastel/Views/Panel/PanelController.swift` - Refactored to use PanelEdge for frame calculations
- `Pastel/App/AppState.swift` - Added retentionService and modelContainer properties
- `Pastel/PastelApp.swift` - Stores modelContainer on AppState, increased popover height
- `Pastel/Views/Panel/PanelContentView.swift` - Added gear icon in header
- `Pastel/Views/MenuBar/StatusPopoverView.swift` - Added Settings button in popover

## Decisions Made

- **SettingsWindowController accepts AppState:** The settings window needs AppState in the environment so GeneralSettingsView can call `appState.panelController.handleEdgeChange()` on edge change. Passing it alongside ModelContainer keeps the wiring clean.
- **stop() instead of deinit on RetentionService:** Swift 6 strict concurrency prevents @MainActor-isolated deinit from accessing the timer property. Since RetentionService lives for app lifetime, a stop() method is sufficient.
- **Panel recreation on orientation change:** When switching between vertical (left/right) and horizontal (top/bottom) edges, the panel is destroyed and recreated since content layout may differ.
- **Popover height increased to 200:** Adding the Settings button required 40pt more vertical space in the menu bar popover.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Popover height overflow from added Settings button**
- **Found during:** Task 2
- **Issue:** Adding Settings button to StatusPopoverView would overflow the 160pt popover height
- **Fix:** Increased popover frame height from 160 to 200 in PastelApp.swift
- **Files modified:** Pastel/PastelApp.swift
- **Verification:** Build succeeds, layout has room for all buttons
- **Committed in:** edcbbab (Task 2 commit)

**2. [Rule 1 - Bug] Swift 6 closure capture in OSLog string interpolation**
- **Found during:** Task 1
- **Issue:** `logger.info("...\\(currentEdge.rawValue)...")` in handleEdgeChange() failed because OSLog string interpolation creates a closure that requires explicit self capture in Swift 6
- **Fix:** Captured currentEdge in a local variable before the log call
- **Files modified:** Pastel/Views/Panel/PanelController.swift
- **Verification:** Build succeeds
- **Committed in:** da24cae (Task 1 commit)

**3. [Rule 1 - Bug] Swift 6 nonisolated deinit cannot access @MainActor timer**
- **Found during:** Task 2
- **Issue:** RetentionService deinit tried to invalidate timer, but Swift 6 prevents nonisolated deinit from accessing @MainActor-isolated properties
- **Fix:** Replaced deinit with explicit stop() method (service lives for app lifetime anyway)
- **Files modified:** Pastel/Services/RetentionService.swift
- **Verification:** Build succeeds
- **Committed in:** edcbbab (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (3 bugs -- Swift 6 concurrency + UI layout)
**Impact on plan:** All auto-fixes necessary for correct compilation under Swift 6 strict concurrency. No scope creep.

## Issues Encountered

- XcodeGen regeneration required after adding new files (standard workflow, not an issue)

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Settings window infrastructure complete, ready for Plan 02 (Labels tab + horizontal panel layout)
- Labels tab placeholder in place, SettingsView tab bar ready for LabelSettingsView
- PanelEdge isVertical property available for Plan 02 horizontal layout adaptation

---
*Phase: 05-settings-and-polish*
*Completed: 2026-02-06*
