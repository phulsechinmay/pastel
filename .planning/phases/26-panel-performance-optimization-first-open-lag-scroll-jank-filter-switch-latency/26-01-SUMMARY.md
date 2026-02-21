---
phase: 26-panel-performance-optimization-first-open-lag-scroll-jank-filter-switch-latency
plan: 01
subsystem: ui
tags: [performance, caching, swiftui, nsimage, panel]

requires:
  - phase: 02-sliding-panel
    provides: PanelContentView with .id() refresh pattern and ClipboardCardView
provides:
  - showCount-based .id() refresh (no view recreation while panel hidden)
  - AppIconCache singleton for cached app icon lookups
  - Pre-warming of icon and color caches on clipboard capture
affects: [26-02, panel-views, clipboard-monitor]

tech-stack:
  added: []
  patterns: [AppIconCache singleton with @MainActor isolation, pre-warm caches at capture time]

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/PanelContentView.swift
    - Pastel/Extensions/NSWorkspace+AppIcon.swift
    - Pastel/Views/Panel/ClipboardCardView.swift
    - Pastel/Views/Settings/PrivacySettingsView.swift
    - Pastel/Services/ClipboardMonitor.swift

key-decisions:
  - "AppIconCache as @MainActor singleton (matches AppIconColorService pattern) rather than nonisolated static on NSWorkspace extension"
  - "Replaced NSWorkspace.appIcon extension entirely with AppIconCache -- all call sites go through cache"
  - "Pre-warm both icon and color caches in text AND image capture paths"

patterns-established:
  - "AppIconCache.shared.icon(forBundleID:) for all app icon lookups"
  - "Pre-warm caches after clipboard capture, before panel needs them"

duration: 2min
completed: 2026-02-21
---

# Phase 26 Plan 01: Panel Open Lag Reduction Summary

**showCount-based .id() refresh eliminates hidden-panel view recreation; AppIconCache and pre-warming eliminate per-card disk I/O on panel open**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-21T07:11:32Z
- **Completed:** 2026-02-21T07:13:40Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- PanelContentView .id() now uses panelActions.showCount instead of appState.itemCount -- clipboard captures while the panel is hidden no longer trigger view recreation
- AppIconCache provides in-memory caching for app icon lookups, eliminating redundant urlForApplication + icon(forFile:) disk I/O per card
- Pre-warming of both icon and color caches happens immediately after each clipboard capture, so panel cards render with zero disk I/O or CIFilter work

## Task Commits

Each task was committed atomically:

1. **Task 1: Replace itemCount with showCount in .id() and add app icon caching** - `599d24d` (perf)
2. **Task 2: Pre-warm icon and color caches on clipboard capture** - `8730d4b` (perf)

## Files Created/Modified
- `Pastel/Views/Panel/PanelContentView.swift` - .id() uses showCount instead of itemCount
- `Pastel/Extensions/NSWorkspace+AppIcon.swift` - Replaced NSWorkspace extension with AppIconCache singleton class
- `Pastel/Views/Panel/ClipboardCardView.swift` - Uses AppIconCache.shared.icon(forBundleID:) for source app icon
- `Pastel/Views/Settings/PrivacySettingsView.swift` - Updated to use AppIconCache for consistency
- `Pastel/Services/ClipboardMonitor.swift` - Pre-warms icon and color caches after item insertion

## Decisions Made
- **AppIconCache as @MainActor singleton:** Matches the existing AppIconColorService pattern. NSImage is not Sendable, so @MainActor isolation is required. Using a dedicated class rather than a static on NSWorkspace extension avoids actor-isolation issues with the extension method.
- **Replaced NSWorkspace extension entirely:** The old `appIcon(forBundleIdentifier:)` extension called disk I/O on every invocation. Rather than keeping both, all call sites now go through AppIconCache directly.
- **Pre-warm in both capture paths:** Both text/file and image capture paths pre-warm caches, ensuring complete coverage regardless of content type.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated PrivacySettingsView to use AppIconCache**
- **Found during:** Task 1 (app icon caching)
- **Issue:** PrivacySettingsView also used the removed NSWorkspace.appIcon extension, causing build failure
- **Fix:** Updated to use AppIconCache.shared.icon(forBundleID:)
- **Files modified:** Pastel/Views/Settings/PrivacySettingsView.swift
- **Verification:** Build succeeded
- **Committed in:** 599d24d (Task 1 commit)

**2. [Rule 1 - Bug] Removed NSWorkspace extension to avoid actor-isolation error**
- **Found during:** Task 1 (app icon caching)
- **Issue:** NSWorkspace extension method is nonisolated but AppIconCache is @MainActor, causing Swift 6 actor-isolation error
- **Fix:** Removed the extension entirely; all call sites use AppIconCache.shared directly
- **Verification:** Build succeeded
- **Committed in:** 599d24d (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both fixes were necessary for compilation. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Icon and color caches are warm for all previously-seen apps
- Panel open lag from view recreation and per-card I/O is eliminated
- Ready for 26-02 (scroll jank and filter switch latency improvements)

---
*Phase: 26-panel-performance-optimization-first-open-lag-scroll-jank-filter-switch-latency*
*Completed: 2026-02-21*

## Self-Check: PASSED
- All 5 modified files exist on disk
- Both task commits verified (599d24d, 8730d4b)
