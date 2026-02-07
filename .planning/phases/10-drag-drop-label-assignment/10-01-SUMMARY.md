---
phase: 10-drag-drop-label-assignment
plan: 01
subsystem: ui
tags: [swiftui, drag-and-drop, PersistentIdentifier, label-assignment, NSPanel]

# Dependency graph
requires:
  - phase: 05-settings-labels
    provides: Label model and ChipBarView with tap-to-filter
  - phase: 09-quick-paste-hotkeys
    provides: FilteredCardListView with badge positions and keyboard navigation
provides:
  - Drag-and-drop label assignment from chip bar to clipboard cards
  - PersistentIdentifier JSON serialization helpers for drag transfer
  - Visual drop target feedback on ClipboardCardView
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PersistentIdentifier JSON encode/decode for SwiftUI drag transfer"
    - "onTapGesture + .draggable replacing Button to avoid macOS gesture conflict"
    - ".dropDestination(for: String.self) for per-card drop targets"

key-files:
  created:
    - Pastel/Extensions/PersistentIdentifier+Transfer.swift
  modified:
    - Pastel/Views/Panel/ChipBarView.swift
    - Pastel/Views/Panel/ClipboardCardView.swift
    - Pastel/Views/Panel/FilteredCardListView.swift

key-decisions:
  - "Button replaced with onTapGesture + .draggable in labelChip to avoid macOS gesture conflict"
  - "PersistentIdentifier serialized as JSON string for drag payload (Codable conformance)"
  - "isDropTarget highest priority in cardBorderColor (above isSelected and isColorCard)"
  - "Drop target background uses accentColor at 0.15 opacity for subtle highlight"

patterns-established:
  - "PersistentIdentifier transfer: asTransferString/fromTransferString for drag-and-drop between views"
  - "Drop target state tracked via @State index in parent, passed as Bool to child card"

# Metrics
duration: 3min
completed: 2026-02-07
---

# Phase 10 Plan 01: Drag-and-Drop Label Assignment Summary

**Draggable label chips with PersistentIdentifier JSON transfer and per-card drop targets with accent highlight feedback**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-07T10:06:00Z
- **Completed:** 2026-02-07T10:08:38Z
- **Tasks:** 2
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments
- Label chips in ChipBarView are draggable with chip-shaped drag preview matching label appearance
- Dropping a label chip onto any clipboard card assigns the label and persists via SwiftData
- Cards show bright accent border and subtle accent background when a label chip hovers over them
- Tap-to-filter preserved via onTapGesture + contentShape(Capsule()) after Button removal
- Invalid payloads silently rejected (PersistentIdentifier decode fails, returns false)

## Task Commits

Each task was committed atomically:

1. **Task 1: PersistentIdentifier transfer helpers and draggable chip bar** - `ffe34f7` (feat)
2. **Task 2: Drop targets on cards with visual feedback** - `0adb61e` (feat)

## Files Created/Modified
- `Pastel/Extensions/PersistentIdentifier+Transfer.swift` - JSON encode/decode helpers for PersistentIdentifier drag transfer
- `Pastel/Views/Panel/ChipBarView.swift` - Label chips refactored from Button to onTapGesture + .draggable with drag preview
- `Pastel/Views/Panel/ClipboardCardView.swift` - isDropTarget property with accent border/background visual feedback
- `Pastel/Views/Panel/FilteredCardListView.swift` - Per-card .dropDestination in both horizontal and vertical layouts

## Decisions Made
- Replaced Button with onTapGesture + .draggable in labelChip -- required because Button and .draggable have a gesture conflict on macOS where drag consumes mouse-down before button click registers
- PersistentIdentifier serialized as JSON string via Codable -- lightweight, no custom Transferable needed
- isDropTarget takes highest priority in cardBorderColor (bright accent, no opacity) to clearly signal drop availability
- Drop target background at 0.15 opacity is subtle enough not to obscure card content while being visible

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness
- All v1.1 milestone features complete (phases 6-10)
- Runtime testing recommended: verify drag-and-drop works in NSPanel (non-activating window)
- If .dropDestination does not fire at runtime in NSPanel, fallback to .onDrop(of:isTargeted:) documented in research

---
*Phase: 10-drag-drop-label-assignment*
*Completed: 2026-02-07*
