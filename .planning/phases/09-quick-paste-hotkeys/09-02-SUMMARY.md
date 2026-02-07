---
phase: 09-quick-paste-hotkeys
plan: 02
subsystem: ui
tags: [swiftui, keycap-badge, clipboard-card, quick-paste, visual-affordance]

# Dependency graph
requires:
  - phase: 09-quick-paste-hotkeys (plan 01)
    provides: quickPasteEnabled @AppStorage, Cmd+1-9 hotkey handling
provides:
  - KeycapBadge SwiftUI view (keyboard-key-styled shortcut indicator)
  - Badge overlay on ClipboardCardView gated by quickPasteEnabled
  - Badge position index passing from FilteredCardListView
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Nil-based visibility: FilteredCardListView controls badge display by passing nil vs Int to child view"

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/ClipboardCardView.swift
    - Pastel/Views/Panel/FilteredCardListView.swift

key-decisions:
  - "Badge visibility controlled by parent (FilteredCardListView) via nil badgePosition, not by @AppStorage in child"
  - "1-based badge numbers (1-9) matching Cmd+1-9 hotkeys, converted from 0-based array index"

patterns-established:
  - "Keycap badge pattern: muted white-on-dark styling (0.7 opacity text, 0.15 opacity background) for non-intrusive overlays"

# Metrics
duration: 1min
completed: 2026-02-07
---

# Phase 9 Plan 2: Quick Paste Badges Summary

**Keycap-style position badges (Cmd 1-9) on first 9 visible cards, visibility gated by quickPasteEnabled setting**

## Performance

- **Duration:** 1 min
- **Started:** 2026-02-07T08:11:11Z
- **Completed:** 2026-02-07T08:12:35Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- KeycapBadge view renders keyboard-key-styled badge with command symbol and digit (1-9)
- ClipboardCardView displays badge overlay in bottom-right corner when badgePosition is non-nil
- FilteredCardListView passes badge positions to first 9 cards in both horizontal and vertical layouts
- Badges automatically disappear when quick paste is disabled in Settings

## Task Commits

Each task was committed atomically:

1. **Task 1: Create KeycapBadge view and add badge overlay to ClipboardCardView** - `c60897a` (feat)
2. **Task 2: Pass badge position from FilteredCardListView to ClipboardCardView** - `df190e0` (feat)

## Files Created/Modified
- `Pastel/Views/Panel/ClipboardCardView.swift` - Added KeycapBadge struct, badgePosition property, and badge overlay
- `Pastel/Views/Panel/FilteredCardListView.swift` - Passes badge position (1-9 or nil) to ClipboardCardView in both layout branches

## Decisions Made
- Badge visibility controlled by parent view (FilteredCardListView) passing nil vs Int, keeping logic centralized rather than reading @AppStorage in child -- cleaner separation of concerns
- 1-based badge numbers matching Cmd+1-9 hotkeys, converted from 0-based array index with `index + 1`

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 9 (Quick Paste Hotkeys) is now complete with both plans delivered
- Plan 01 delivered hotkey handling (Cmd+1-9 normal paste, Cmd+Shift+1-9 plain text)
- Plan 02 delivered visual affordance (keycap badges on first 9 cards)
- Full feature: users see which number to press, press it, item pastes

---
*Phase: 09-quick-paste-hotkeys*
*Completed: 2026-02-07*
