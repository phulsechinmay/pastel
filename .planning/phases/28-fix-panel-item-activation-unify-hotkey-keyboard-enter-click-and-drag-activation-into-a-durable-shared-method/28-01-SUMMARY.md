---
phase: 28-fix-panel-item-activation-unify-hotkey-keyboard-enter-click-and-drag-activation-into-a-durable-shared-method
plan: 01
subsystem: ui
tags: [nsevent, keyboard, nspanel, appkit, swiftui-focus, paste-activation]

# Dependency graph
requires:
  - phase: 09-quick-paste-hotkeys
    provides: "Cmd+1-9 and Cmd+Shift+1-9 quick paste feature (originally via .onKeyPress)"
  - phase: 26-panel-performance-optimization
    provides: "FilteredCardListView with installArrowKeyMonitor NSEvent pattern"
provides:
  - "Unified installKeyboardMonitor() handling arrows, Enter, and Cmd+digit activation via NSEvent"
  - "Layout-independent Cmd+digit handling via keyCode (works on non-US keyboards)"
affects: [panel-keyboard-handling, clipboard-activation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "NSEvent local monitor for all keyboard activation (not just arrows)"
    - "Static digitKeyCodeMap for physical key code to digit value mapping"
    - "keyCode-based digit detection (layout-independent, Cmd-modifier safe)"

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/FilteredCardListView.swift

key-decisions:
  - "Extend existing NSEvent monitor (not add second) for Enter + Cmd+digit handling"
  - "Use event.keyCode for digit detection (not event.characters which changes with Cmd modifier)"
  - "Keep .focusable() and type-to-search .onKeyPress handler per user decision"

patterns-established:
  - "NSEvent local monitor is the standard for all keyboard interaction in NSPanel context"
  - "digitKeyCodeMap static dictionary for physical key code to digit value mapping"

requirements-completed: [PNUI-09, PAST-10, PAST-10b]

# Metrics
duration: 13min
completed: 2026-02-21
---

# Phase 28 Plan 01: Fix Panel Item Activation Summary

**Unified keyboard activation via NSEvent monitor -- Enter, Cmd+1-9, Cmd+Shift+1-9 migrated from broken SwiftUI .onKeyPress to proven NSEvent local monitor pattern**

## Performance

- **Duration:** 13 min
- **Started:** 2026-02-21T21:06:41Z
- **Completed:** 2026-02-21T21:19:57Z
- **Tasks:** 2 (1 auto + 1 human-verify)
- **Files modified:** 1

## Accomplishments
- Migrated Enter/Return (0x24) and Keypad Enter (0x4C) activation to NSEvent monitor with Shift modifier for plain text paste
- Migrated Cmd+1-9 and Cmd+Shift+1-9 quick paste to NSEvent monitor using physical keyCode mapping (layout-independent)
- Removed three broken `.onKeyPress` handlers that never fired due to SwiftUI focus issues in NSPanel context
- Preserved type-to-search `.onKeyPress` handler and `.focusable()`/`.focusEffectDisabled()` per user decision

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend NSEvent monitor for Enter and Cmd+digit activation, remove broken .onKeyPress handlers** - `aa1b0de` (feat)
2. **Task 2: Verify keyboard activation works in the panel** - human-verify checkpoint (approved)

## Files Created/Modified
- `Pastel/Views/Panel/FilteredCardListView.swift` - Unified `installKeyboardMonitor()` replacing `installArrowKeyMonitor()`, added `digitKeyCodeMap`, removed 3 broken `.onKeyPress` handlers (net -8 lines: 41 added, 49 removed)

## Decisions Made
- **keyCode over characters for digit detection**: `event.keyCode` is used instead of `event.characters` because macOS modifies characters when Cmd is held. keyCode always reflects the physical key regardless of modifiers or keyboard layout.
- **Single monitor extension over separate monitor**: Extended the existing arrow key monitor rather than adding a second NSEvent monitor, avoiding event consumption ordering issues.
- **Keep .focusable() and type-to-search .onKeyPress**: Per user decision, the type-to-search handler remains on SwiftUI `.onKeyPress`. If it's confirmed broken in the future, it can be migrated to NSEvent separately.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- **Pre-existing xcodebuild CLI failure**: `xcodebuild` CLI fails with "Unable to find module dependency" for KeyboardShortcuts, HighlightSwift, and LaunchAtLogin on macOS 26 / Xcode 17. Confirmed pre-existing by reverting changes and observing the same failure. The project builds successfully from Xcode GUI. Syntax-only compilation (`swiftc -parse`) confirmed zero syntax errors in the modified file. This is an out-of-scope xcodebuild + SPM explicit module build environment issue.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All four panel activation methods now work reliably: Enter key, Cmd+1-9, double-click, and drag-and-drop
- Keyboard activation is fully unified in the NSEvent local monitor pattern
- No blockers or concerns

## Self-Check: PASSED

- FOUND: Pastel/Views/Panel/FilteredCardListView.swift
- FOUND: 28-01-SUMMARY.md
- FOUND: commit aa1b0de

---
*Phase: 28-fix-panel-item-activation-unify-hotkey-keyboard-enter-click-and-drag-activation-into-a-durable-shared-method*
*Completed: 2026-02-21*
