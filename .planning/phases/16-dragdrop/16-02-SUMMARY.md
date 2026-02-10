---
phase: 16-dragdrop
plan: 02
subsystem: ui
tags: [drag-and-drop, panel-state, isDragging, self-capture-prevention, event-monitors]

# Dependency graph
requires:
  - phase: 16-01-dragdrop
    provides: DragItemProviderService and .onDrag() on clipboard cards
  - phase: 03-paste
    provides: ClipboardMonitor.skipNextChange pattern for self-capture prevention
provides:
  - isDragging state on PanelController that suppresses panel dismissal during drag
  - onDragStarted callback chain from FilteredCardListView to ClipboardMonitor.skipNextChange
  - Global leftMouseUp monitor for automatic drag end detection
affects: [future drag preview customization, multi-item drag selection]

# Tech tracking
tech-stack:
  added: []
  patterns: ["onDragStarted callback chain for cross-layer drag state propagation", "One-shot NSEvent global monitor for drag end detection"]

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/PanelController.swift
    - Pastel/Views/Panel/FilteredCardListView.swift
    - Pastel/Views/Panel/PanelContentView.swift
    - Pastel/App/AppState.swift

key-decisions:
  - "Callback chain pattern (not NotificationCenter) for drag state: onDrag -> FilteredCardListView -> PanelActions -> PanelController -> AppState -> ClipboardMonitor"
  - "One-shot global leftMouseUp monitor for drag end detection, cleaned up immediately after firing"
  - "500ms delay before isDragging reset to allow receiving app to process drop and write to pasteboard"
  - "skipNextChange (not full monitor pause) for self-capture prevention -- matches existing paste-back pattern"

patterns-established:
  - "One-shot NSEvent.addGlobalMonitorForEvents pattern: install on event start, self-remove in handler"
  - "onDragStarted callback wired through PanelActions bridge (same pattern as onPasteItem)"

# Metrics
duration: 3min
completed: 2026-02-09
---

# Phase 16 Plan 02: Panel State and Self-Capture Prevention Summary

**isDragging state gates panel dismissal during drag, skipNextChange prevents duplicate history entries from dropped content**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-10T00:53:43Z
- **Completed:** 2026-02-10T00:56:41Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- PanelController.isDragging property gates the globalClickMonitor so panel stays visible during drag
- dragSessionStarted() installs a one-shot global leftMouseUp monitor for automatic drag end detection
- onDragStarted callback chain wired from FilteredCardListView through PanelActions to PanelController to AppState
- AppState sets clipboardMonitor.skipNextChange = true on drag start to prevent duplicate history entries
- isDragging resets after 500ms delay on mouse-up, giving receiving app time to process the drop
- dragEndMonitor cleaned up in removeEventMonitors() for safety when panel hides during drag

## Task Commits

Each task was committed atomically:

1. **Task 1: Add isDragging state to PanelController and guard dismiss logic** - `cf260ec` (feat)
2. **Task 2: Wire drag side effects to FilteredCardListView, PanelContentView, AppState** - `3272317` (feat)

## Files Modified
- `Pastel/Views/Panel/PanelController.swift` - isDragging property, dragSessionStarted(), onDragStarted callback, globalClickMonitor guard, dragEndMonitor lifecycle
- `Pastel/Views/Panel/FilteredCardListView.swift` - onDragStarted callback parameter, called from both .onDrag() closures
- `Pastel/Views/Panel/PanelContentView.swift` - Passes onDragStarted closure wiring to panelActions.onDragStarted
- `Pastel/App/AppState.swift` - Wires panelController.onDragStarted to set clipboardMonitor.skipNextChange

## Callback Chain

The full drag lifecycle callback chain:

1. User starts drag -> `.onDrag()` closure fires in FilteredCardListView
2. Closure calls `onDragStarted?()` (FilteredCardListView callback)
3. PanelContentView routes to `panelActions.onDragStarted?()`
4. PanelActions calls `panelController.dragSessionStarted()`
5. `dragSessionStarted()` sets `isDragging = true`, calls `onDragStarted?()` callback
6. AppState callback sets `clipboardMonitor?.skipNextChange = true`
7. Global `.leftMouseUp` monitor fires when drag ends
8. Monitor self-removes, then after 500ms delay `isDragging` resets to false

## Decisions Made
- **Callback chain over NotificationCenter:** Follows existing pattern (onPasteItem, onPastePlainText, onCopyOnlyItem) for consistency. Type-safe, no string-based notification names.
- **skipNextChange over full monitor pause:** The existing paste-back pattern uses skipNextChange for single-event suppression. Drag-drop needs the same: skip one pasteboard change from the receiving app's drop handler.
- **500ms delay on isDragging reset:** Matches the paste-back delay timing. Ensures the receiving app has written to pasteboard before monitor resumes normal operation.
- **One-shot monitor pattern:** dragEndMonitor removes itself in its handler to avoid accumulating monitors on repeated drags.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None - all 4 files compiled on first try, callback chain wired cleanly.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 16 (Drag-and-Drop from Panel) is now complete
- All 5 DRAG requirements delivered: drag initiation, multi-type support, correct UTTypes, panel visibility during drag, self-capture prevention
- End-to-end manual testing recommended: drag text/image/URL from panel to TextEdit/Finder/Safari

---
*Phase: 16-dragdrop*
*Completed: 2026-02-09*
