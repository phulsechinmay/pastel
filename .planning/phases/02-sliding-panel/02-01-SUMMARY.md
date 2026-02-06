---
phase: 02-sliding-panel
plan: 01
subsystem: ui
tags: [nspanel, nsvisualeffectview, appkit, swiftui, swiftdata, keyboardshortcuts, animation]

# Dependency graph
requires:
  - phase: 01-clipboard-capture-and-storage
    provides: ClipboardItem SwiftData model, ModelContainer, AppState, ClipboardMonitor
provides:
  - NSPanel-based sliding panel with non-activating behavior
  - PanelController with show/hide animation and dismiss monitors
  - PanelContentView with @Query-driven clipboard item list
  - EmptyStateView for zero-item state
  - Cmd+Shift+V global hotkey for panel toggle
  - Menu bar "Show History" button
affects: [02-sliding-panel/02, 03-paste-back, 04-search-settings]

# Tech tracking
tech-stack:
  added: []
  patterns: [NSPanel non-activating panel, NSVisualEffectView dark material, NSHostingView SwiftUI bridge, NSAnimationContext slide animation, NSEvent global/local monitors]

key-files:
  created:
    - Pastel/Views/Panel/SlidingPanel.swift
    - Pastel/Views/Panel/PanelController.swift
    - Pastel/Views/Panel/PanelContentView.swift
    - Pastel/Views/Panel/EmptyStateView.swift
  modified:
    - Pastel/App/AppState.swift
    - Pastel/PastelApp.swift
    - Pastel/Views/MenuBar/StatusPopoverView.swift

key-decisions:
  - "NSVisualEffectView .sidebar material with .darkAqua appearance (deprecated .dark replaced with semantic material)"
  - "NSHostingView typed as NSView to handle conditional modelContainer branch (avoids opaque return type issue)"
  - "KeyboardShortcuts.onKeyUp with MainActor.assumeIsolated for Swift 6 concurrency safety"

patterns-established:
  - "AppKit-SwiftUI bridge: NSHostingView embedded in NSVisualEffectView with Auto Layout pinning"
  - "Panel lifecycle: PanelController owns SlidingPanel, manages show/hide/toggle"
  - "Event monitor pattern: global for click-outside, local for Escape key consumption"

# Metrics
duration: 3min
completed: 2026-02-06
---

# Phase 2 Plan 1: Panel Infrastructure Summary

**Non-activating NSPanel with 0.2s slide animation, dark vibrancy material, @Query-driven content, and Cmd+Shift+V global hotkey**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-06T16:37:33Z
- **Completed:** 2026-02-06T16:40:58Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- NSPanel subclass with `.nonactivatingPanel` style mask that never steals focus from active apps
- PanelController with smooth 0.2s ease-in/out slide animation from right screen edge
- Dismiss on Escape key (consumed event) or click-outside (global monitor)
- Panel appears on the screen where the mouse cursor is located
- PanelContentView with `@Query` driving a `ScrollView`/`LazyVStack` for clipboard items
- EmptyStateView shown when no clipboard items exist
- Cmd+Shift+V global shortcut and menu bar "Show History" button for panel toggle

## Task Commits

Each task was committed atomically:

1. **Task 1: Create SlidingPanel NSPanel subclass and PanelController with animation and dismiss** - `dabbb7a` (feat)
2. **Task 2: Create PanelContentView, EmptyStateView, wire into AppState and PastelApp** - `4358539` (feat)

## Files Created/Modified
- `Pastel/Views/Panel/SlidingPanel.swift` - Non-activating NSPanel subclass with borderless, floating, transparent config
- `Pastel/Views/Panel/PanelController.swift` - Panel lifecycle: show/hide animation, screen detection, event monitors
- `Pastel/Views/Panel/PanelContentView.swift` - Root SwiftUI view with @Query-driven ScrollView/LazyVStack
- `Pastel/Views/Panel/EmptyStateView.swift` - Friendly empty state with clipboard icon and instructions
- `Pastel/App/AppState.swift` - Added PanelController integration, togglePanel(), KeyboardShortcuts registration
- `Pastel/PastelApp.swift` - Wired setupPanel(modelContainer:) in init
- `Pastel/Views/MenuBar/StatusPopoverView.swift` - Added "Show History" button

## Decisions Made
- Used `.sidebar` material instead of deprecated `.dark` for NSVisualEffectView, with explicit `.darkAqua` appearance to ensure always-dark rendering
- Typed NSHostingView as `NSView` in createPanel() to avoid Swift opaque return type issues when conditionally applying `.modelContainer()`
- Used `MainActor.assumeIsolated` inside KeyboardShortcuts callback for Swift 6 strict concurrency compliance
- Created stub PanelContentView in Task 1 to unblock compilation (PanelController references it); replaced with full implementation in Task 2

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Stub PanelContentView for Task 1 compilation**
- **Found during:** Task 1
- **Issue:** PanelController references PanelContentView which is created in Task 2; Task 1 cannot compile without it
- **Fix:** Created minimal stub PanelContentView in Task 1, replaced with full implementation in Task 2
- **Files modified:** Pastel/Views/Panel/PanelContentView.swift
- **Verification:** Build succeeded
- **Committed in:** dabbb7a (Task 1 commit)

**2. [Rule 1 - Bug] Fixed opaque return type error with NSHostingView**
- **Found during:** Task 1
- **Issue:** `let hostingView: NSHostingView<some View>` cannot work with conditional branches producing different concrete types
- **Fix:** Typed as `NSView` and set `translatesAutoresizingMaskIntoConstraints` in each branch
- **Files modified:** Pastel/Views/Panel/PanelController.swift
- **Verification:** Build succeeded with no errors
- **Committed in:** dabbb7a (Task 1 commit)

**3. [Rule 1 - Bug] Replaced deprecated .dark NSVisualEffectView material**
- **Found during:** Task 1
- **Issue:** `.dark` material deprecated in macOS 10.14; compiler warning
- **Fix:** Used `.sidebar` material with `.darkAqua` appearance for equivalent dark vibrancy
- **Files modified:** Pastel/Views/Panel/PanelController.swift
- **Verification:** Build succeeded with no warnings in panel files
- **Committed in:** dabbb7a (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (1 blocking, 2 bugs)
**Impact on plan:** All auto-fixes necessary for compilation and warning-free build. No scope creep.

## Issues Encountered
None -- both tasks completed on first attempt after fixing compilation issues.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Panel infrastructure complete and ready for Plan 02-02 (card UI views)
- PanelContentView has placeholder item rows that Plan 02-02 replaces with proper card components
- `@Query` wiring confirmed working -- SwiftData ModelContainer passed through NSHostingView

---
*Phase: 02-sliding-panel*
*Completed: 2026-02-06*
