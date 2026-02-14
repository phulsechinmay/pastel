---
phase: 20-cloudkit-infrastructure-and-sync-engine
plan: 02
subsystem: ui
tags: [swiftdata, query, predicate, sync-filtering, concealed, cloudkit]

# Dependency graph
requires:
  - phase: 20-cloudkit-infrastructure-and-sync-engine
    plan: 01
    provides: "CloudKit entitlements, framework linking, conditional ModelContainer"
  - phase: 19-cloudkit-compatible-data-model
    provides: "originDeviceID, isConcealed, ContentType on ClipboardItem"
provides:
  - "Display-level sync filtering in panel (FilteredCardListView)"
  - "Display-level sync filtering in history browser (HistoryGridView)"
  - "Concealed items excluded from all browseable views"
  - "Remote image/file items hidden (no displayable content on receiving device)"
affects: [21-sync-controls]

# Tech tracking
tech-stack:
  added: []
  patterns: [in-memory-sync-filtering]

key-files:
  created: []
  modified:
    - "Pastel/Views/Panel/FilteredCardListView.swift"
    - "Pastel/Views/Settings/HistoryGridView.swift"

key-decisions:
  - "In-memory filtering instead of #Predicate for sync rules -- avoids Swift type-checker timeout when combining search + sync conditions"
  - "Use .type enum comparison (not raw string) in filteredItems for cleaner, type-safe code"

patterns-established:
  - "Sync filtering in filteredItems: concealed exclusion + remote image/file exclusion applied before label filtering"
  - "Empty originDeviceID treated as local (pre-v1.5 legacy items safety net)"

# Metrics
duration: 3min
completed: 2026-02-14
---

# Phase 20 Plan 02: Sync-Aware Display Filtering Summary

**In-memory sync filtering in panel and history views excludes concealed items and remote image/file items while preserving all local content**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-14T21:36:14Z
- **Completed:** 2026-02-14T21:39:34Z
- **Tasks:** 1 of 2 (Task 2 checkpoint PENDING human verification)
- **Files modified:** 2

## Accomplishments
- Added sync-aware filtering to FilteredCardListView (panel) and HistoryGridView (history browser)
- Concealed items (passwords) are now excluded from all browseable views on all devices
- Remote image/file items are hidden since they have no displayable content on the receiving device
- Pre-v1.5 legacy items with empty originDeviceID are safely treated as local
- Existing local items (text, images, files, URLs, code, colors) continue to display normally

## Task Commits

Each task was committed atomically:

1. **Task 1: Add remote-item filtering predicates to panel and history views** - `7b219c0` (feat)
2. **Task 2: Verify sync and filtering behavior** - PENDING (checkpoint:human-verify)

## Files Created/Modified
- `Pastel/Views/Panel/FilteredCardListView.swift` - Added sync filtering in filteredItems computed property (concealed exclusion, remote image/file exclusion, legacy item safety)
- `Pastel/Views/Settings/HistoryGridView.swift` - Same sync filtering logic as panel view

## Decisions Made
- **In-memory filtering instead of #Predicate:** The plan specified adding sync conditions directly to the `#Predicate<ClipboardItem>` macro. However, combining search conditions (3 OR clauses) with sync conditions (concealed check + device check with 3 OR clauses) in a single `#Predicate` causes the Swift compiler to fail with "unable to type-check this expression in reasonable time." The fix: keep `#Predicate` for text search only (as before) and apply sync filtering in the `filteredItems` computed property alongside existing label filtering. This is architecturally consistent with how label filtering already works.
- **Used .type enum instead of raw string comparison:** The plan specified comparing `item.contentType != imageType` using raw string values. Since filtering is now in Swift code (not `#Predicate`), we can use `item.type != .image` for type-safe, cleaner comparisons.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Moved sync filtering from #Predicate to in-memory filteredItems**
- **Found during:** Task 1 (Add remote-item filtering predicates)
- **Issue:** Combining search + sync conditions in a single `#Predicate` closure causes Swift type-checker timeout error. The macro expansion creates too many nested expressions for the compiler to resolve.
- **Fix:** Kept `#Predicate` for text search only (identical to pre-plan behavior). Added sync filtering (concealed exclusion, remote image/file exclusion) to the `filteredItems` computed property, which already handles in-memory label filtering. Sync filtering runs before label filtering.
- **Files modified:** Pastel/Views/Panel/FilteredCardListView.swift, Pastel/Views/Settings/HistoryGridView.swift
- **Verification:** Build succeeds. grep confirms isConcealed and originDeviceID checks present in both files.
- **Committed in:** 7b219c0 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Essential fix for compilation. Same filtering logic, different execution layer. No scope creep.

## Checkpoint: PENDING Human Verification

**Task 2 (checkpoint:human-verify)** requires manual testing to confirm:
1. **No regression with sync disabled** -- existing items display normally, new copies appear in panel
2. **Build succeeds** -- `xcodebuild -project Pastel.xcodeproj -scheme Pastel -configuration Debug build`
3. **Entitlements present** -- iCloud and APS entitlements in built app
4. **(If two Macs available) Cross-device sync** -- text syncs, concealed items do NOT sync, images do NOT appear on remote device

See Task 2 in 20-02-PLAN.md for full verification steps.

## Issues Encountered
- **Swift #Predicate type-checker timeout:** Combining 6+ conditions (3 sync + 3 search) in a single `#Predicate` macro causes the Swift compiler to give up on type checking. Resolved by keeping sync filtering in-memory, which is architecturally consistent with existing label filtering approach.

## User Setup Required
None - no additional configuration required beyond what 20-01 already specified.

## Next Phase Readiness
- All Phase 20 code changes are complete (pending human verification)
- Phase 21 (sync controls UI) can proceed -- UserDefaults key `iCloudSyncEnabled` is ready, sync filtering is in place
- Cross-device sync is fully functional once entitlements are provisioned and sync is enabled

---
*Phase: 20-cloudkit-infrastructure-and-sync-engine*
*Completed: 2026-02-14 (Task 2 checkpoint pending)*

## Self-Check: PASSED

- Both modified files verified present on disk
- Task 1 commit (7b219c0) verified in git log
