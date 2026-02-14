---
phase: 19-cloudkit-compatible-data-model
plan: 02
subsystem: database
tags: [swiftdata, cloudkit, dedup, nil-safety, migration]

# Dependency graph
requires:
  - phase: 19-cloudkit-compatible-data-model
    plan: 01
    provides: "CloudKit-compatible models with optional relationships and safeLabels/safeItems accessors"
provides:
  - "Application-level hash deduplication replacing @Attribute(.unique) constraint"
  - "originDeviceID stamping on all captured items via DeviceIdentifier.current"
  - "Nil-safe .safeLabels access across all 22 call sites in 8 files"
  - "Fully compiling, running application with CloudKit-compatible behavior"
affects: [20-sync-infrastructure, 21-sync-controls]

# Tech tracking
tech-stack:
  added: []
  patterns: [application-level-dedup-via-fetchcount, defensive-origin-device-stamping]

key-files:
  created: []
  modified:
    - Pastel/Services/ClipboardMonitor.swift
    - Pastel/Views/Panel/ClipboardCardView.swift
    - Pastel/Views/Panel/FilteredCardListView.swift
    - Pastel/Views/Panel/EditItemView.swift
    - Pastel/Views/Settings/HistoryGridView.swift
    - Pastel/Views/Settings/HistoryBrowserView.swift
    - Pastel/Services/ImportExportService.swift
    - Pastel/Services/MigrationService.swift
    - Pastel/App/AppState.swift

key-decisions:
  - "isDuplicateByHash uses fetchCount (not fetch) for O(count) efficiency without loading model objects"
  - "Keep isDuplicateOfMostRecent as fast O(1) short-circuit; isDuplicateByHash catches non-consecutive duplicates"
  - "Defensive originDeviceID stamping after insert (redundant with init) for future-proofing"

patterns-established:
  - "Application-level dedup pattern: consecutive check (fast) -> hash check (thorough) -> insert"
  - "Mechanical find-and-replace for nil-safe accessor migration: item.labels. -> item.safeLabels."

# Metrics
duration: 2min
completed: 2026-02-14
---

# Phase 19 Plan 02: Call Site Updates & Application-Level Dedup Summary

**Application-level hash dedup replacing @Attribute(.unique), originDeviceID stamping on capture, and 21 .safeLabels call-site updates across 8 files for nil-safe CloudKit-compatible relationship access**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T18:14:58Z
- **Completed:** 2026-02-14T18:17:26Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- Added isDuplicateByHash() method to ClipboardMonitor for non-consecutive duplicate detection, replacing the removed @Attribute(.unique) constraint
- Wired isDuplicateByHash() call before every insert (both text and image capture paths)
- Added defensive originDeviceID = DeviceIdentifier.current stamping after every insert
- Updated all 21 .labels call sites across 8 files to use .safeLabels nil-safe accessor
- Updated save catch block comments to reflect post-unique-constraint behavior
- Project builds and runs with zero errors

## Task Commits

Each task was committed atomically:

1. **Task 1: Add application-level hash dedup and originDeviceID stamping** - `4922b80` (feat)
2. **Task 2: Update all .labels call sites to use .safeLabels** - `3465f02` (feat)

## Files Created/Modified
- `Pastel/Services/ClipboardMonitor.swift` - Added isDuplicateByHash(), non-consecutive dedup calls in both paths, originDeviceID stamping, updated error comments
- `Pastel/Views/Panel/ClipboardCardView.swift` - 8 .labels -> .safeLabels call sites
- `Pastel/Views/Panel/FilteredCardListView.swift` - 3 .labels -> .safeLabels call sites
- `Pastel/Views/Panel/EditItemView.swift` - 3 .labels -> .safeLabels call sites
- `Pastel/Views/Settings/HistoryGridView.swift` - 1 .labels -> .safeLabels call site
- `Pastel/Views/Settings/HistoryBrowserView.swift` - 1 .labels -> .safeLabels call site
- `Pastel/Services/ImportExportService.swift` - 2 .labels -> .safeLabels call sites (export map, import append)
- `Pastel/Services/MigrationService.swift` - 2 .labels -> .safeLabels call sites (contains, append)
- `Pastel/App/AppState.swift` - 1 .labels -> .safeLabels call site (clearAllHistory removeAll)

## Decisions Made
- **fetchCount over fetch for dedup:** isDuplicateByHash uses modelContext.fetchCount() which returns only the count without materializing model objects, more efficient than fetching and checking .isEmpty
- **Keep both dedup methods:** isDuplicateOfMostRecent provides fast O(1) short-circuit for the common rapid Cmd+C case; isDuplicateByHash catches the uncommon case of same content copied hours apart
- **Defensive origin stamping:** Added explicit originDeviceID assignment after insert even though ClipboardItem.init already sets it -- defense-in-depth for future-proofing if init changes

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None - all changes applied cleanly, build succeeded on first attempt.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 19 (CloudKit-Compatible Data Model) is fully complete
- Schema is CloudKit-ready: no unique constraints, all defaults, optional relationships, application-level dedup, device origin tracking
- Ready for Phase 20 (Sync Infrastructure): enable CloudKit sync via ModelConfiguration, add sync monitor, link CloudKit.framework
- No blockers

## Self-Check: PASSED

All files verified present. All commits verified in git log.

---
*Phase: 19-cloudkit-compatible-data-model*
*Completed: 2026-02-14*
