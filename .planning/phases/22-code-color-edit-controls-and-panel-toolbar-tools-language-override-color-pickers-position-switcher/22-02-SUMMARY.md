---
phase: 22-code-color-edit-controls-and-panel-toolbar-tools-language-override-color-pickers-position-switcher
plan: 02
subsystem: ui
tags: [NSColorPanel, color-picker, panel-position, toolbar, Menu, AppKit-bridge]

requires:
  - phase: 05-settings-and-polish
    provides: PanelEdge model, handleEdgeChange(), AdaptiveGlassButtonStyle
provides:
  - ColorToolController service for standalone system color picking
  - Panel toolbar with eyedropper, position switcher, and settings buttons
affects: [panel-toolbar, color-workflow, settings]

tech-stack:
  added: []
  patterns:
    - "NSObject @MainActor singleton for AppKit target/action bridge"
    - "Shared toolbar computed property for dual-layout views"

key-files:
  created:
    - Pastel/Services/ColorToolController.swift
  modified:
    - Pastel/Views/Panel/PanelContentView.swift
    - Pastel.xcodeproj/project.pbxproj

key-decisions:
  - "NSColorPanel level set to .statusBar to match sliding panel level"
  - "NotificationCenter willClose observer cleans up target/action to avoid SwiftUI ColorPicker conflicts"
  - "Menu with .borderlessButton style and .fixedSize() for position dropdown"

patterns-established:
  - "Extracted toolbarButtons computed property: shared toolbar for both horizontal and vertical panel layouts"

duration: 4min
completed: 2026-02-19
---

# Phase 22 Plan 02: Panel Toolbar Tools Summary

**Standalone color picker via NSColorPanel with hex-to-clipboard, and position switcher dropdown with live panel edge switching**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-20T03:44:50Z
- **Completed:** 2026-02-20T03:49:11Z
- **Tasks:** 1
- **Files modified:** 3

## Accomplishments
- Created ColorToolController service that opens macOS system color wheel and copies hex values to clipboard on every color change
- Added eyedropper button, position switcher dropdown (Menu), and settings gear as a shared toolbar in both panel layout modes
- Wired position dropdown to PanelEdge.allCases with checkmark on current selection, triggering handleEdgeChange() on selection

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ColorToolController and add toolbar buttons to PanelContentView** - `a8f6395` (feat)

**Plan metadata:** (pending)

## Files Created/Modified
- `Pastel/Services/ColorToolController.swift` - NSObject singleton bridging NSColorPanel for standalone color picking with hex clipboard output
- `Pastel/Views/Panel/PanelContentView.swift` - Extracted shared toolbarButtons (eyedropper, position Menu, gear) for both layout modes; added .onChange(of: panelEdgeRaw) handler
- `Pastel.xcodeproj/project.pbxproj` - Added ColorToolController.swift to build sources

## Decisions Made
- Set NSColorPanel level to `.statusBar` to match the sliding panel level -- ensures the color wheel appears at the same layer
- Used `orderFront(nil)` instead of `makeKeyAndOrderFront` to avoid stealing focus from the sliding panel
- Used NotificationCenter `willCloseNotification` observer to clean up target/action, preventing conflicts when the edit modal's SwiftUI ColorPicker uses the same shared NSColorPanel
- Wrapped cleanup call in `Task { @MainActor in }` to satisfy Swift 6 concurrency requirements in NotificationCenter closure
- Used `.menuStyle(.borderlessButton)` and `.fixedSize()` on the Menu to prevent it from expanding and to match button appearance

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Swift 6 concurrency warning in NotificationCenter closure**
- **Found during:** Task 1
- **Issue:** NotificationCenter `addObserver(forName:)` closure is not @MainActor-isolated, but calls @MainActor-isolated `cleanupTarget()`
- **Fix:** Wrapped `self?.cleanupTarget()` in `Task { @MainActor in ... }`
- **Files modified:** Pastel/Services/ColorToolController.swift
- **Verification:** `swiftc -typecheck` passes with zero warnings
- **Committed in:** a8f6395

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential for Swift 6 strict concurrency compliance. No scope creep.

## Issues Encountered
- xcodebuild CLI cannot resolve SPM package dependencies (pre-existing issue unrelated to this plan). Verified syntax correctness via `swiftc -typecheck` on the new file and manual review of PanelContentView changes.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Panel toolbar now has three buttons (eyedropper, position, gear) ready for use
- ColorToolController is a clean singleton pattern that can be extended for additional color tool features
- Position switcher reuses existing PanelEdge/handleEdgeChange() infrastructure

---
*Phase: 22-code-color-edit-controls-and-panel-toolbar-tools-language-override-color-pickers-position-switcher*
*Completed: 2026-02-19*

## Self-Check: PASSED
