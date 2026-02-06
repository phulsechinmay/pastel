---
phase: 04-organization
plan: 03
subsystem: ui
tags: [swiftui, swiftdata, deletion, image-cleanup, context-menu, confirmation-dialog, clear-history]

# Dependency graph
requires:
  - phase: 04-organization-02
    provides: Context menu with basic Delete action on ClipboardCardView
  - phase: 01-clipboard-capture-and-storage
    provides: ImageStorageService.deleteImage, ExpirationService with guard-let no-op for deleted items
provides:
  - Robust individual delete with disk image cleanup via ImageStorageService
  - Clear All History method on AppState with batch delete, image cleanup, and itemCount reset
  - Confirmation dialog for destructive clear-all action in StatusPopoverView
  - Labels preserved through clear-all (only ClipboardItems deleted)
affects: [04-04 bulk operations, 05 settings and preferences]

# Tech tracking
tech-stack:
  added: []
  patterns: [confirmationDialog for destructive actions, fetch-before-batch-delete for cleanup]

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/ClipboardCardView.swift
    - Pastel/Views/MenuBar/StatusPopoverView.swift
    - Pastel/App/AppState.swift

key-decisions:
  - "Simpler delete approach: image cleanup in view, expiration timer no-ops via existing ExpirationService guard"
  - "Fetch all items before batch delete to collect image paths for disk cleanup"
  - "Labels preserved through clear-all (reusable organizational tools per CONTEXT.md)"
  - "confirmationDialog for clear-all instead of alert (better macOS UX for destructive actions)"

patterns-established:
  - "Fetch-then-batch-delete: always collect cleanup data before modelContext.delete(model:)"
  - "Defensive expiration: timers harmlessly no-op for already-deleted items via guard-let"

# Metrics
duration: 2min
completed: 2026-02-06
---

# Phase 4 Plan 3: Delete and Clear All History Summary

**Individual delete with disk image cleanup and clear-all-history with confirmation dialog preserving labels**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-06T20:04:17Z
- **Completed:** 2026-02-06T20:05:46Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Upgraded Delete context menu action to clean up image and thumbnail files from disk before SwiftData delete
- Added `clearAllHistory` method to AppState: fetches items for image path collection, deletes all disk images, batch deletes all ClipboardItems, resets itemCount to 0
- Added "Clear All History" button to StatusPopoverView with red destructive styling and trash icon
- Confirmation dialog with descriptive warning prevents accidental data loss
- Labels survive clear-all (only ClipboardItem.self is batch-deleted)
- Orphaned expiration timers for concealed items handled gracefully by existing ExpirationService guard

## Task Commits

Each task was committed atomically:

1. **Task 1: Robust individual delete with image cleanup** - `21e815b` (feat)
2. **Task 2: Clear all history with confirmation dialog** - `53aa70e` (feat)

## Files Created/Modified
- `Pastel/Views/Panel/ClipboardCardView.swift` - Added `deleteItem()` method that calls `ImageStorageService.shared.deleteImage` before `modelContext.delete`
- `Pastel/Views/MenuBar/StatusPopoverView.swift` - Added SwiftData import, modelContext environment, Clear All History button with red styling, confirmationDialog with destructive action
- `Pastel/App/AppState.swift` - Added `clearAllHistory(modelContext:)` method with fetch-then-batch-delete pattern, image cleanup loop, and itemCount reset

## Decisions Made
- Used simpler delete approach: image cleanup performed directly in ClipboardCardView, expiration timer cancellation skipped because ExpirationService already has a `guard let item = modelContext.model(for: itemID)` that safely no-ops for deleted items
- Fetch all items before `modelContext.delete(model: ClipboardItem.self)` to collect image paths -- batch delete clears the context so paths would be lost after
- Labels intentionally excluded from clear-all per CONTEXT.md guidance ("optionally keep Labels -- they are reusable")
- Used `.confirmationDialog` instead of `.alert` for the destructive action -- provides better platform-appropriate UX on macOS

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Full delete lifecycle complete: individual delete with image cleanup, clear-all with confirmation
- ORGN-05 (individual delete) and ORGN-06 (clear all) requirements satisfied
- Ready for 04-04 (final organization plan)
- ExpirationService defensive pattern proven: no need to explicitly cancel timers on manual delete

---
*Phase: 04-organization*
*Completed: 2026-02-06*
