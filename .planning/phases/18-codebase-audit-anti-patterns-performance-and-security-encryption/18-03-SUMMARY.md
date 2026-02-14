---
phase: 18-codebase-audit-anti-patterns-performance-and-security-encryption
plan: 03
subsystem: views
tags: [swiftui, swiftdata, query-optimization, viewbuilder, deprecated-api, nsimage]

# Dependency graph
requires:
  - phase: 18-01
    provides: saveWithLogging() utility used in FilteredCardListView cardView helper
  - phase: 18-02
    provides: Safe unwrap patterns in PanelContentView
provides:
  - "ClipboardCardView without @Query -- receives allLabels as parameter from parent"
  - "Optimized .id() modifier excluding itemCount (no full view rebuild on clipboard capture)"
  - "Modern NSImage(size:flipped:drawingHandler:) replacing deprecated lockFocus/unlockFocus"
  - "Shared @ViewBuilder cardView(for:at:) helper eliminating horizontal/vertical card duplication"
  - "A5 #Predicate { _ in true } documented as accepted limitation for label post-filtering"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pass shared data as parameter to ForEach child views instead of per-instance @Query"
    - "Use @ViewBuilder helpers to DRY up layout-variant rendering (horizontal vs vertical)"
    - "Exclude auto-observed properties from .id() to prevent unnecessary view recreation"

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/ClipboardCardView.swift
    - Pastel/Views/Panel/FilteredCardListView.swift
    - Pastel/Views/Panel/PanelContentView.swift
    - Pastel/Views/Settings/HistoryGridView.swift
    - Pastel/Views/Settings/HistoryBrowserView.swift

key-decisions:
  - "allLabels parameter with default empty array on ClipboardCardView -- backward compatible, no breakage"
  - "EditItemView keeps its own @Query (standalone modal, single subscription -- not N-per-card)"
  - "A5 #Predicate { _ in true } accepted: fetchLimit would break in-memory label post-filtering"
  - "Exclude itemCount from .id() -- @Query auto-observes item additions/deletions"
  - "NSImage(size:flipped:drawingHandler:) with flipped:false matches default coordinate system"

patterns-established:
  - "Parameter drilling for shared data: parent @Query -> child parameter, not per-child @Query"
  - "@ViewBuilder helper for layout variants: shared card logic, caller applies layout-specific modifiers"

# Metrics
duration: 2min
completed: 2026-02-14
---

# Phase 18 Plan 03: View Layer Refactoring Summary

**Eliminated N-per-card @Query subscriptions, removed itemCount-triggered view rebuilds, replaced deprecated NSImage.lockFocus, and extracted shared @ViewBuilder card helper**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T05:59:26Z
- **Completed:** 2026-02-14T06:01:37Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments
- Removed @Query(sort: \Label.sortOrder) from ClipboardCardView -- labels now passed as `allLabels` parameter from parent views, eliminating N redundant SwiftData subscriptions per visible card
- Removed `appState.itemCount` from PanelContentView `.id()` modifier -- prevents full FilteredCardListView destruction/recreation on every clipboard capture (scroll reset, selection loss, flicker)
- Replaced deprecated `NSImage.lockFocus/unlockFocus` with modern `NSImage(size:flipped:drawingHandler:)` in ClipboardCardView.menuIcon(for:)
- Extracted ~90 lines of duplicated card rendering into shared `cardView(for:at:)` @ViewBuilder helper -- horizontal/vertical branches now share a single rendering path
- Documented A5 `#Predicate { _ in true }` pattern as accepted limitation (required for in-memory label post-filtering since SwiftData cannot .contains() on to-many relationships)

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove @Query from ClipboardCardView and pass labels as parameter from all parents** - `5f52b33` (feat)
2. **Task 2: Remove itemCount from .id() modifier and replace deprecated NSImage.lockFocus** - `83e3804` (fix)
3. **Task 3: Extract duplicated horizontal/vertical card rendering into shared @ViewBuilder** - `df9b378` (refactor)

## Files Created/Modified
- `Pastel/Views/Panel/ClipboardCardView.swift` - Removed @Query, added allLabels parameter, modern NSImage drawing
- `Pastel/Views/Panel/FilteredCardListView.swift` - Added allLabels parameter passthrough, extracted cardView(for:at:) @ViewBuilder helper, A5 documentation comment
- `Pastel/Views/Panel/PanelContentView.swift` - Passes allLabels: labels to FilteredCardListView, removed itemCount from .id(), added explanatory comment
- `Pastel/Views/Settings/HistoryGridView.swift` - Added allLabels parameter, passes to ClipboardCardView
- `Pastel/Views/Settings/HistoryBrowserView.swift` - Passes allLabels: labels to HistoryGridView

## Decisions Made
- ClipboardCardView gets `allLabels: [Label] = []` with default empty array for backward compatibility
- EditItemView retains its own @Query -- it is a standalone modal (not in ForEach), so only one subscription exists
- A5 `#Predicate { _ in true }` fetch-all pattern accepted: adding fetchLimit would silently exclude items from in-memory label post-filtering (decision [11-03] established this filtering strategy)
- `appState.itemCount` excluded from `.id()` because SwiftData @Query already auto-observes item additions/deletions without needing view recreation
- `NSImage(size:flipped:drawingHandler:)` uses `flipped: false` to match the default AppKit coordinate system (origin at bottom-left)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All 3 plans in Phase 18 are now complete
- Anti-patterns (18-01), force unwraps (18-02), and view layer optimizations (18-03) all resolved
- Codebase audit phase is complete

## Self-Check: PASSED

- All 5 modified files verified present on disk
- All 3 commit hashes (5f52b33, 83e3804, df9b378) verified in git log
- SUMMARY.md created at expected path
