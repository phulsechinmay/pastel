---
phase: quick-32
plan: 01
subsystem: ui
tags: [swiftui, context-menu, label-management, chip-bar, settings-deep-link]

# Dependency graph
requires:
  - phase: quick-31
    provides: "Drag-to-reorder labels in Settings LabelSettingsView"
provides:
  - "Right-click context menu on label chips with Edit, Reorder, Delete"
  - "Settings deep-linking via initialTab parameter and switchTab notification"
  - "Inline label edit palette (name, color, emoji) from chip bar"
affects: [ChipBarView, SettingsView, SettingsWindowController]

# Tech tracking
tech-stack:
  added: []
  patterns: [notification-based-tab-switching, context-menu-on-chips]

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/ChipBarView.swift
    - Pastel/Views/Settings/SettingsView.swift
    - Pastel/Views/Settings/SettingsWindowController.swift

key-decisions:
  - "SettingsTab enum made non-private for external deep-linking access"
  - "Notification-based tab switching for already-visible Settings window"
  - "SwiftUI.Label fully qualified to avoid conflict with data model Label type"

patterns-established:
  - "Settings deep-link: SettingsWindowController.shared.showSettings(initialTab:) for direct tab navigation"
  - "switchTab notification for tab changes when Settings window already visible"

requirements-completed: [QT-32]

# Metrics
duration: 5min
completed: 2026-02-26
---

# Quick Task 32: Add Right-Click Context Menu on Label Chips Summary

**Right-click context menu on label chips with Edit (inline palette), Reorder (deep-link to Settings Labels tab), and Delete actions**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-26T07:52:52Z
- **Completed:** 2026-02-26T07:58:16Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Right-click context menu on all label chips in both panel and History browser
- Inline edit palette for label name, color, and emoji changes directly from chip bar
- Settings deep-linking with initialTab parameter and notification-based tab switching
- Delete action removes label from database and clears it from chip bar selection

## Task Commits

Each task was committed atomically:

1. **Task 1: Enable deep-linking to Settings Labels tab** - `1266e9f` (feat)
2. **Task 2: Add right-click context menu to label chips in ChipBarView** - `9d7ad45` (feat)

## Files Created/Modified
- `Pastel/Views/Settings/SettingsView.swift` - Made SettingsTab non-private, added initialTab parameter, added switchTab notification listener
- `Pastel/Views/Settings/SettingsWindowController.swift` - Added initialTab parameter to showSettings, added switchTab notification constant, post notification for already-visible window
- `Pastel/Views/Panel/ChipBarView.swift` - Added context menu with Edit/Reorder/Delete, LabelEditPalette struct, deleteLabel method, AppState environment

## Decisions Made
- Made SettingsTab enum non-private (was private) to allow external code to reference tabs for deep-linking
- Used NotificationCenter for tab switching when Settings window is already visible, since SettingsView owns its @State internally and can't be mutated from outside
- Used SwiftUI.Label (fully qualified) in context menu items to avoid naming conflict with the data model Label type
- Used .sheet(item:) for edit palette since SwiftData @Model conforms to Identifiable via PersistentModel

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Initial build failure due to stale DerivedData from previous session (SPM packages not found in Debug-AppStore configuration). Resolved by cleaning DerivedData and using explicit configuration name `Debug-AppStore`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Context menu is functional on all label chips in both panel and History browser
- Settings deep-linking infrastructure can be reused for other tab navigation needs
- All changes build successfully on both Pastel AppStore and Pastel Sparkle schemes

## Self-Check: PASSED

All files exist, all commits verified.
