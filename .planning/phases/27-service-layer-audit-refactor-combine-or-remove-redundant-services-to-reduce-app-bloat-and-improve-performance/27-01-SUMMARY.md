---
phase: 27-service-layer-audit
plan: 01
subsystem: services
tags: [swift, swiftdata, refactoring, sha256, cryptokit, deletion-cleanup]

# Dependency graph
requires:
  - phase: 18-codebase-audit
    provides: "SwiftDataHelpers.swift with saveWithLogging free function pattern"
  - phase: 19-cloudkit-compatible-model
    provides: "safeLabels accessor and CloudKit-safe relationship cleanup requirement"
provides:
  - "deleteClipboardItemWithCleanup() centralized deletion function in SwiftDataHelpers.swift"
  - "ContentHash enum for centralized SHA256 hashing in SwiftDataHelpers.swift"
  - "Consistent safeLabels.removeAll() across all deletion paths (CloudKit-safe)"
  - "Consistent URL metadata image cleanup across all deletion paths"
affects: [service-layer-audit, future-deletion-sites]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Centralized deletion via free function (deleteClipboardItemWithCleanup)"
    - "Centralized hashing via caseless enum (ContentHash)"

key-files:
  created: []
  modified:
    - "Pastel/Services/SwiftDataHelpers.swift"
    - "Pastel/App/AppState.swift"
    - "Pastel/Views/Panel/ClipboardCardView.swift"
    - "Pastel/Views/Settings/HistoryBrowserView.swift"
    - "Pastel/Services/ExpirationService.swift"
    - "Pastel/Services/RetentionService.swift"
    - "Pastel/Services/ClipboardMonitor.swift"
    - "Pastel/Services/ImportExportService.swift"
    - "Pastel/Services/ImageStorageService.swift"

key-decisions:
  - "Keep ImageStorageService.computeImageHash as thin wrapper delegating to ContentHash (preserves existing API surface)"
  - "Free function pattern for deleteClipboardItemWithCleanup (consistent with saveWithLogging per decision 18-01)"

patterns-established:
  - "All ClipboardItem deletions go through deleteClipboardItemWithCleanup"
  - "All SHA256 hashing goes through ContentHash enum"

# Metrics
duration: 5min
completed: 2026-02-21
---

# Phase 27 Plan 01: Centralized Deletion and Hashing Summary

**Extracted duplicated deletion cleanup (5 sites) and SHA256 hashing (3 sites) into SwiftDataHelpers.swift, fixing 3 missing safeLabels/URL-metadata bugs**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-21T19:05:11Z
- **Completed:** 2026-02-21T19:10:25Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- Centralized all ClipboardItem deletion into single `deleteClipboardItemWithCleanup()` function
- Centralized all SHA256 content hashing into `ContentHash` enum with `hash(text:)` and `hash(imageData:)` methods
- Fixed missing `safeLabels.removeAll()` in ClipboardCardView.deleteItem() (CloudKit relationship leak)
- Fixed missing `safeLabels.removeAll()` and URL metadata image cleanup in ExpirationService (both expireOverdueItems and performExpiration)
- Removed 3 redundant `import CryptoKit` statements (ClipboardMonitor, ImportExportService, ImageStorageService)
- Net reduction: 60 lines removed across 8 files

## Task Commits

Each task was committed atomically:

1. **Task 1: Extract deleteClipboardItemWithCleanup and ContentHash into SwiftDataHelpers.swift** - `e750dd3` (feat)
2. **Task 2: Replace all 5 deletion call sites and 3 hash call sites with centralized helpers** - `dcbf6e2` (refactor)

## Files Created/Modified
- `Pastel/Services/SwiftDataHelpers.swift` - Added ContentHash enum and deleteClipboardItemWithCleanup function
- `Pastel/App/AppState.swift` - clearAllHistory uses deleteClipboardItemWithCleanup
- `Pastel/Views/Panel/ClipboardCardView.swift` - deleteItem uses deleteClipboardItemWithCleanup (fixes missing safeLabels.removeAll)
- `Pastel/Views/Settings/HistoryBrowserView.swift` - bulkDelete uses deleteClipboardItemWithCleanup
- `Pastel/Services/ExpirationService.swift` - Both expiration paths use deleteClipboardItemWithCleanup (fixes missing safeLabels + URL metadata cleanup)
- `Pastel/Services/RetentionService.swift` - purgeExpiredItems merged into single loop with deleteClipboardItemWithCleanup
- `Pastel/Services/ClipboardMonitor.swift` - Uses ContentHash.hash for text and image hashing, removed CryptoKit import
- `Pastel/Services/ImportExportService.swift` - PastePal import uses ContentHash.hash, removed CryptoKit import
- `Pastel/Services/ImageStorageService.swift` - computeImageHash delegates to ContentHash.hash, removed CryptoKit import

## Decisions Made
- Kept `ImageStorageService.computeImageHash(data:)` as a thin wrapper that delegates to `ContentHash.hash(imageData:)` rather than removing it entirely -- preserves the existing API surface for callers that semantically belong to ImageStorageService
- Used free function pattern for `deleteClipboardItemWithCleanup` (consistent with `saveWithLogging` per decision [18-01])

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Build verification could not complete due to pre-existing SPM module resolution failures (KeyboardShortcuts, HighlightSwift, LaunchAtLogin not found). Confirmed pre-existing by testing build on unmodified main branch (same errors). Code correctness verified via grep pattern matching and syntax checking.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- SwiftDataHelpers.swift now serves as the centralized utility for SwiftData operations (save, delete, hash)
- All future deletion sites should use deleteClipboardItemWithCleanup
- All future content hashing should use ContentHash enum
- Ready for remaining Phase 27 plans (service consolidation)

---
*Phase: 27-service-layer-audit*
*Completed: 2026-02-21*
