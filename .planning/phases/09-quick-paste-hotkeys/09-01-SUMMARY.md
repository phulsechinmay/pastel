---
phase: 09-quick-paste-hotkeys
plan: 01
subsystem: ui
tags: [swiftui, onKeyPress, pasteboard, NSPasteboard, keyboard-shortcuts, AppStorage]

# Dependency graph
requires:
  - phase: 01-core-clipboard
    provides: PasteService, PanelController, PanelActions callback chain
  - phase: 05-settings-polish
    provides: GeneralSettingsView Hotkey section, AppStorage pattern
provides:
  - pastePlainText method on PasteService (RTF-stripping pasteboard write)
  - pastePlainTextItem callback chain through PanelActions/PanelController/AppState
  - .onKeyPress(characters: .decimalDigits) handler for Cmd+1-9 / Cmd+Shift+1-9
  - quickPasteEnabled AppStorage toggle in Settings
affects: [09-02-number-badge-overlay]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "onKeyPress decimal digits with modifier check for panel-scoped hotkeys"
    - "writeToPasteboardPlainText omits .rtf, keeps .string and .html for paste-and-match-style"

key-files:
  created: []
  modified:
    - Pastel/Services/PasteService.swift
    - Pastel/App/AppState.swift
    - Pastel/Views/Panel/PanelController.swift
    - Pastel/Views/Panel/PanelContentView.swift
    - Pastel/Views/Panel/FilteredCardListView.swift
    - Pastel/Views/Settings/GeneralSettingsView.swift

key-decisions:
  - "Cmd+1-9 for normal paste, Cmd+Shift+1-9 for plain text (reversed from roadmap note -- Cmd+N is more natural for primary action)"
  - "Plain text omits .rtf only, keeps .string and .html -- receiving apps fall back to default styling"
  - "Non-text types (url, image, file) delegate to normal writeToPasteboard since no RTF to strip"
  - "quickPasteEnabled defaults to true -- feature is opt-out not opt-in"

patterns-established:
  - "onPastePlainText callback parameter pattern mirrors existing onPaste through the full chain"

# Metrics
duration: 2min
completed: 2026-02-07
---

# Phase 9 Plan 1: Quick Paste Hotkeys Summary

**Cmd+1-9 quick paste from panel with plain text variant via Cmd+Shift+1-9 and Settings toggle**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-07T08:06:03Z
- **Completed:** 2026-02-07T08:08:52Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- PasteService.pastePlainText writes to NSPasteboard without RTF data for paste-and-match-style behavior
- Full callback chain wired: FilteredCardListView -> PanelContentView -> PanelActions -> PanelController -> AppState -> PasteService for both normal and plain text paths
- .onKeyPress(characters: .decimalDigits) handler dispatches Cmd+1-9 (normal paste) and Cmd+Shift+1-9 (plain text paste) on the visible filtered items
- Settings toggle under Hotkey section enables/disables quick paste (defaults to enabled)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add pastePlainText to PasteService and wire callback chain** - `0da6706` (feat)
2. **Task 2: Add .onKeyPress handlers and Settings toggle** - `fe32a20` (feat)

## Files Created/Modified
- `Pastel/Services/PasteService.swift` - Added pastePlainText() and writeToPasteboardPlainText() methods
- `Pastel/App/AppState.swift` - Added pastePlainText(item:) coordination method, wired onPastePlainTextItem callback
- `Pastel/Views/Panel/PanelController.swift` - Added pastePlainTextItem to PanelActions, onPastePlainTextItem to PanelController
- `Pastel/Views/Panel/PanelContentView.swift` - Added onPastePlainText callback pass-through and pastePlainTextItem helper
- `Pastel/Views/Panel/FilteredCardListView.swift` - Added onPastePlainText parameter and .onKeyPress decimal digits handler
- `Pastel/Views/Settings/GeneralSettingsView.swift` - Added quickPasteEnabled toggle under Hotkey section

## Decisions Made
- Cmd+1-9 for normal paste, Cmd+Shift+1-9 for plain text -- Cmd+N is the more natural primary action binding
- writeToPasteboardPlainText omits only .rtf data; .string and .html are preserved so apps get text content
- Non-text types (url, image, file) use normal writeToPasteboard since they have no RTF to strip
- quickPasteEnabled defaults to true -- feature is discoverable and opt-out

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Quick paste hotkeys fully functional, ready for Plan 2 (number badge overlays on cards)
- The items array in FilteredCardListView is directly indexed by the hotkey handler, so badge overlays can use the same index

---
*Phase: 09-quick-paste-hotkeys*
*Completed: 2026-02-07*
