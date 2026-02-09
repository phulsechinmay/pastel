---
phase: 13-paste-as-plain-text
plan: 01
subsystem: ui, paste
tags: [nspasteboards, context-menu, shift-modifier, plain-text, swiftui]

# Dependency graph
requires:
  - phase: 05-settings-and-polish
    provides: PasteService with pastePlainText method and AppState wiring
  - phase: 12-history-browser
    provides: HistoryGridView and HistoryBrowserView with context menus
provides:
  - Fixed HTML bug in writeToPasteboardPlainText (PAST-23)
  - "Paste as Plain Text" context menu in panel card view (PAST-20)
  - Shift+Enter plain text paste in panel (PAST-21)
  - Shift+double-click plain text paste in panel (PAST-22)
  - "Paste as Plain Text" context menu in History browser
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "onKeyPress(keys:) variant for modifier-aware key handlers (vs onKeyPress(KeyEquivalent) which has no KeyPress parameter)"
    - "NSEvent.modifierFlags.contains(.shift) for detecting Shift in tap gesture handlers"

key-files:
  created: []
  modified:
    - Pastel/Services/PasteService.swift
    - Pastel/Views/Panel/ClipboardCardView.swift
    - Pastel/Views/Panel/FilteredCardListView.swift
    - Pastel/Views/Settings/HistoryGridView.swift
    - Pastel/Views/Settings/HistoryBrowserView.swift

key-decisions:
  - "Used onKeyPress(keys:) instead of onKeyPress(KeyEquivalent) for Return handler because the latter does not pass KeyPress to the closure"
  - "Bulk paste-as-plain-text intentionally excluded from multi-selection context menu per research recommendations"

patterns-established:
  - "onKeyPress(keys: [.return]) { keyPress in ... } pattern when modifier detection is needed on a key equivalent"

# Metrics
duration: 4min
completed: 2026-02-09
---

# Phase 13 Plan 01: Paste as Plain Text Summary

**Fixed HTML pasteboard bug and added paste-as-plain-text via context menu, Shift+Enter, and Shift+double-click in both panel and History browser**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-09T19:51:58Z
- **Completed:** 2026-02-09T19:55:47Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Fixed critical PAST-23 bug: `writeToPasteboardPlainText` no longer writes `.html` to pasteboard, ensuring truly plain text paste into formatting-aware apps like Google Docs
- Added 3 panel entry points for plain text paste: context menu button, Shift+Enter, Shift+double-click (both horizontal and vertical layout branches)
- Added History browser context menu "Paste as Plain Text" wired through AppState.pastePlainText

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix HTML bug and add panel paste-as-plain-text UI entry points** - `b9c039f` (feat)
2. **Task 2: Add paste-as-plain-text to History browser context menu** - `7b1e26a` (feat)

## Files Created/Modified

- `Pastel/Services/PasteService.swift` - Removed HTML write from writeToPasteboardPlainText; now writes ONLY .string type
- `Pastel/Views/Panel/ClipboardCardView.swift` - Added "Paste as Plain Text" button in context menu after "Copy + Paste"
- `Pastel/Views/Panel/FilteredCardListView.swift` - Added Shift+Enter via onKeyPress(keys:) and Shift+double-click via NSEvent.modifierFlags in both layout branches
- `Pastel/Views/Settings/HistoryGridView.swift` - Added onPastePlainText closure and "Paste as Plain Text" in single-item context menu
- `Pastel/Views/Settings/HistoryBrowserView.swift` - Wired onPastePlainText closure and added singlePastePlainText method

## Decisions Made

- **onKeyPress(keys:) vs onKeyPress(KeyEquivalent):** The `onKeyPress(.return) { ... }` overload uses `() -> KeyPress.Result` closure with no `KeyPress` parameter, so modifier detection is impossible. Switched to `onKeyPress(keys: [.return]) { keyPress in ... }` which passes the full `KeyPress` object including modifiers. This is a Swift API difference, not documented in Apple's guides.
- **No bulk plain text paste:** Multi-selection context menu in HistoryGridView intentionally does not include "Paste as Plain Text" per research recommendations -- bulk plain text is out of scope for Phase 13.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Used onKeyPress(keys:) instead of onKeyPress(KeyEquivalent) for Return handler**
- **Found during:** Task 1 (Shift+Enter implementation)
- **Issue:** Plan specified `onKeyPress(.return) { keyPress in ... }` but this overload's closure signature is `() -> KeyPress.Result` with no `KeyPress` parameter, causing compilation error
- **Fix:** Changed to `onKeyPress(keys: [.return]) { keyPress in ... }` which uses `(KeyPress) -> KeyPress.Result` closure
- **Files modified:** Pastel/Views/Panel/FilteredCardListView.swift
- **Verification:** Build succeeds, Shift modifier check compiles correctly
- **Committed in:** b9c039f (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** API-level fix necessary for compilation. No scope creep.

## Issues Encountered

- Entitlements file modification warning during build requires `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES` flag -- pre-existing project issue, not related to changes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 13 complete -- paste-as-plain-text fully functional across all surfaces
- Ready for Phase 14 (Pin/Favorite) or any subsequent v1.3 phase

---
*Phase: 13-paste-as-plain-text*
*Completed: 2026-02-09*
