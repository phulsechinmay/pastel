---
phase: 12-history-browser-and-bulk-actions
plan: 03
subsystem: ui
tags: [swiftui, bulk-actions, nspasteboard, cgevent, swiftdata, delete, copy, paste]

# Dependency graph
requires:
  - phase: 12-02
    provides: HistoryGridView with multi-selection and selectedIDs binding
  - phase: 12-01
    provides: Resizable settings window with History tab shell
provides:
  - Bulk Copy (concatenate text with newlines to pasteboard)
  - Bulk Paste (copy + hide settings + simulate Cmd+V)
  - Bulk Delete (confirmation dialog + image/label/model cleanup)
  - Bottom action bar with selection count and Copy/Paste/Delete buttons
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "resolvedItems binding to expose @Query results from child to parent view"
    - "Bulk pasteboard write with self-paste loop prevention via skipNextChange"
    - "CGEvent Cmd+V simulation from settings window context with orderOut hide"
    - "SwiftData MTM cleanup (labels.removeAll) before model deletion"

key-files:
  created: []
  modified:
    - Pastel/Views/Settings/HistoryGridView.swift
    - Pastel/Views/Settings/HistoryBrowserView.swift

key-decisions:
  - "resolvedItems @Binding passes filteredItems from HistoryGridView to parent for bulk operations"
  - "bulkPaste uses orderOut(nil) for instant settings window hide (not miniaturize animation)"
  - "350ms delay before Cmd+V simulation (longer than panel's 250ms to account for focus switch)"
  - "Accessibility check before paste simulation -- falls back to copy-only if not granted"
  - "Non-text items (image, file) silently skipped during bulk copy/paste"

patterns-established:
  - "Child-to-parent data flow via @Binding for @Query results that parent cannot access directly"
  - "Bulk delete with full cleanup: disk images + MTM labels + model deletion + save + selection clear"

# Metrics
duration: 2min
completed: 2026-02-09
---

# Phase 12 Plan 03: Bulk Action Toolbar Summary

**Bulk Copy/Paste/Delete toolbar with confirmation dialog, image cleanup, MTM label teardown, and paste-back from settings window**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-09T06:07:32Z
- **Completed:** 2026-02-09T06:09:24Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- HistoryGridView exposes filteredItems to parent via resolvedItems binding, enabling bulk operations on selected items
- Bottom action bar appears when items are selected, showing "N items selected" with Copy, Paste, Delete buttons
- Bulk Copy concatenates text content of selected items with newlines, writes to NSPasteboard.general, sets skipNextChange for self-paste loop prevention
- Bulk Paste copies to pasteboard, checks Accessibility, hides settings window via orderOut, simulates Cmd+V after 350ms delay
- Bulk Delete shows confirmation alert with item count, cleans up disk images (imagePath, thumbnailPath, urlFaviconPath, urlPreviewImagePath), clears MTM label relationships, deletes models, saves context, and clears selection
- Non-text items (image, file) silently skipped during copy/paste operations

## Task Commits

Each task was committed atomically:

1. **Task 1: Expose filteredItems from HistoryGridView via resolvedItems binding** - `5315adb` (feat)
2. **Task 2: Add bulk action toolbar with Copy, Paste, Delete operations** - `3b1f596` (feat)

## Files Created/Modified
- `Pastel/Views/Settings/HistoryGridView.swift` - Added @Binding resolvedItems, updated init, synced via .onAppear and .onChange
- `Pastel/Views/Settings/HistoryBrowserView.swift` - Added bulk action bar, confirmation alert, bulkCopy/bulkPaste/bulkDelete methods, AppKit import, environment bindings

## Decisions Made
- resolvedItems binding pattern chosen over callback/closure approach for simplicity -- parent holds @State array, child syncs via .onAppear and .onChange(of: items)
- orderOut(nil) used for instant window hide instead of miniaturize(nil) which has animation delay; user can reopen settings from menu bar
- 350ms Cmd+V delay (vs panel's 250ms) because settings window focus transfer may take longer than panel hide
- Accessibility check in bulkPaste falls back to copy-only if not granted, matching PasteService pattern
- Image and file items silently excluded from bulk copy/paste (only text, richText, url, code, color have textContent)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Phase 12 Completion

All 3 plans complete. Phase 12 success criteria satisfied:
1. History tab shows clipboard cards in responsive grid that reflows on resize
2. Search bar and chip bar provide the same filtering as the panel
3. Multi-select via Cmd-click, Shift-click range, Cmd+A, Escape
4. Bulk Copy concatenates text content with newlines
5. Bulk Paste copies + hides settings + simulates Cmd+V
6. Bulk Delete shows confirmation dialog with item count

---
*Phase: 12-history-browser-and-bulk-actions*
*Completed: 2026-02-09*
