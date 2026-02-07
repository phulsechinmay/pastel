---
phase: quick
plan: 005
subsystem: ui
tags: [swiftui, clipboard-card, label-chip, context-menu, capsule]

requires:
  - phase: 06-data-model-label-enhancements
    provides: "Label model with emoji field and LabelColor enum"
provides:
  - "Label chip display on clipboard cards"
  - "Reliable context menu label rendering with concatenated text"
affects: []

tech-stack:
  added: []
  patterns:
    - "Emoji-or-dot conditional rendering pattern (shared with ChipBarView)"
    - "Concatenated text for macOS context menu items (avoids HStack layout issues)"

key-files:
  created: []
  modified:
    - "Pastel/Views/Panel/ClipboardCardView.swift"

key-decisions:
  - "Color dot Circle dropped from context menu -- macOS NSMenu does not reliably render SwiftUI shapes; name-only is sufficient since chip bar and card chip show the color"
  - "Label chip uses caption2 font and 9pt emoji to stay compact below content preview"

patterns-established:
  - "labelDisplayText helper for emoji+name concatenation in menus"

duration: 1min
completed: 2026-02-07
---

# Quick Task 005: Card Label Chips and Emoji Menu Fix Summary

**Label chip capsule (emoji-or-dot + name) on clipboard cards with concatenated-text context menu labels for macOS compatibility**

## Performance

- **Duration:** 1 min
- **Started:** 2026-02-07T02:43:53Z
- **Completed:** 2026-02-07T02:44:53Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Clipboard cards now show a small capsule chip below content preview when a label is assigned
- Cards without labels show no extra UI (no empty space or placeholder)
- Context menu Label submenu uses concatenated text ("emoji name") for reliable macOS rendering
- Checkmark indicator for currently assigned label preserved in context menu

## Task Commits

Each task was committed atomically:

1. **Task 1: Add label chip to card and fix context menu label text** - `f9037ee` (feat)

## Files Created/Modified
- `Pastel/Views/Panel/ClipboardCardView.swift` - Added label chip after contentPreview, replaced HStack label rendering with concatenated text, added labelDisplayText helper

## Decisions Made
- Dropped Circle color dot from context menu items -- macOS NSMenu-backed context menus do not reliably render SwiftUI shapes like Circle. The label name alone is sufficient identification in the menu since the chip bar and card chip already show the color dot visually.
- Label chip uses `caption2` font and 9pt emoji sizing to stay visually compact and not compete with the content preview above it.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Label visibility on cards complete; ready for Phase 7 (Code and Color Detection)
- No blockers introduced

---
*Quick task: 005*
*Completed: 2026-02-07*
