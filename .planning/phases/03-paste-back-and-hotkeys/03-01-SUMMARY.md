---
phase: 03-paste-back-and-hotkeys
plan: 01
subsystem: services
tags: [cgevent, accessibility, nspasteboard, paste-back, cgkeycode]

# Dependency graph
requires:
  - phase: 01-clipboard-capture-and-storage
    provides: ClipboardItem model, ClipboardMonitor with skipNextChange flag, ImageStorageService
  - phase: 02-sliding-panel
    provides: PanelController with show/hide, SlidingPanel with nonactivatingPanel, AppState wiring
provides:
  - AccessibilityService for Accessibility permission check/request
  - PasteService for pasteboard writing and CGEvent Cmd+V simulation
  - Sandbox removal enabling CGEvent posting
  - PanelController.previousApp tracking for paste-back target
  - PanelActions observable bridge for SwiftUI paste callbacks
  - AppState.paste(item:) entry point for all paste operations
affects: [03-02-PLAN, 04-search-and-management, 05-polish-and-preferences]

# Tech tracking
tech-stack:
  added: [CoreGraphics/CGEvent, ApplicationServices/AXIsProcessTrusted, Carbon/IsSecureEventInputEnabled]
  patterns: [PasteService write-skip-hide-simulate flow, PanelActions observable bridge for SwiftUI-AppKit callback]

key-files:
  created:
    - Pastel/Services/AccessibilityService.swift
    - Pastel/Services/PasteService.swift
  modified:
    - Pastel/Resources/Pastel.entitlements
    - Pastel/Views/Panel/PanelController.swift
    - Pastel/App/AppState.swift

key-decisions:
  - "String literal 'AXTrustedCheckOptionPrompt' instead of kAXTrustedCheckOptionPrompt constant to avoid Swift 6 concurrency error on shared mutable state"
  - "PanelActions @Observable class bridges paste actions to SwiftUI via .environment() rather than direct closure passing"
  - "Entitlements file uses empty dict rather than setting app-sandbox to false (cleaner, no unnecessary keys)"

patterns-established:
  - "PasteService flow: check accessibility -> check secure input -> write pasteboard -> set skipNextChange -> hide panel -> 50ms delay -> CGEvent Cmd+V"
  - "PanelActions observable: SwiftUI views get paste callback via @Environment without coupling to AppKit/PanelController"
  - "previousApp capture: always capture NSWorkspace.shared.frontmostApplication before panel.orderFrontRegardless()"

# Metrics
duration: 3min
completed: 2026-02-06
---

# Phase 3 Plan 01: Paste-Back Infrastructure Summary

**PasteService with CGEvent Cmd+V simulation, AccessibilityService permission flow, sandbox removal, and full callback chain from SwiftUI to paste-back**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-06T17:41:31Z
- **Completed:** 2026-02-06T17:44:56Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Removed App Sandbox from entitlements, enabling CGEvent posting for paste-back
- Created AccessibilityService with permission check, request prompt, and System Settings shortcut
- Created PasteService handling all 5 content types with CGEvent Cmd+V simulation and self-paste loop prevention
- Wired full callback chain: SwiftUI -> PanelActions -> PanelController.onPasteItem -> AppState.paste -> PasteService.paste
- PanelController now tracks previously active app before showing panel

## Task Commits

Each task was committed atomically:

1. **Task 1: Create AccessibilityService, PasteService, and remove sandbox** - `1b12cf8` (feat)
2. **Task 2: Wire PasteService into PanelController and AppState** - `629ab9c` (feat)

## Files Created/Modified
- `Pastel/Resources/Pastel.entitlements` - Removed sandbox keys (empty dict plist)
- `Pastel/Services/AccessibilityService.swift` - AXIsProcessTrusted check/request, open System Settings
- `Pastel/Services/PasteService.swift` - Pasteboard writing (5 types), CGEvent Cmd+V simulation, secure input fallback
- `Pastel/Views/Panel/PanelController.swift` - Added previousApp tracking, PanelActions observable, onPasteItem callback
- `Pastel/App/AppState.swift` - Added PasteService ownership, paste(item:) method, callback wiring in setupPanel

## Decisions Made
- Used string literal `"AXTrustedCheckOptionPrompt"` instead of `kAXTrustedCheckOptionPrompt.takeUnretainedValue()` to avoid Swift 6 strict concurrency error (shared mutable state). The string value is stable and documented.
- PanelActions uses `@Observable` class in SwiftUI `.environment()` rather than passing closures through view hierarchy -- cleaner separation between AppKit and SwiftUI layers.
- Entitlements file uses `<dict/>` (empty) rather than `app-sandbox = false` -- the key simply should not exist for non-sandboxed apps.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 concurrency error with kAXTrustedCheckOptionPrompt**
- **Found during:** Task 1 (AccessibilityService creation)
- **Issue:** `kAXTrustedCheckOptionPrompt` is a global mutable variable from the Accessibility framework. Swift 6 strict concurrency rejects accessing shared mutable state, causing a compilation error.
- **Fix:** Replaced `kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String` with the equivalent string literal `"AXTrustedCheckOptionPrompt" as CFString`. This is the documented string value of the constant.
- **Files modified:** `Pastel/Services/AccessibilityService.swift`
- **Verification:** Build succeeds with zero errors under Swift 6 strict concurrency.
- **Committed in:** `1b12cf8` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Single Swift 6 compatibility fix. No scope creep.

## Issues Encountered
None beyond the Swift 6 concurrency fix documented above.

## User Setup Required
None - no external service configuration required. Accessibility permission will be requested at first paste attempt.

## Next Phase Readiness
- PasteService is fully callable but has no UI triggers yet -- Plan 02 adds double-click, Enter-to-paste, and keyboard navigation
- PanelActions is passed into SwiftUI environment but PanelContentView does not yet consume it -- Plan 02 wires that
- All paste-back infrastructure is in place for Plan 02 to build on

---
*Phase: 03-paste-back-and-hotkeys*
*Completed: 2026-02-06*
