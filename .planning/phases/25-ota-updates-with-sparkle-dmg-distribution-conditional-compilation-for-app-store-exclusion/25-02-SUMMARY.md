---
phase: 25-ota-updates-with-sparkle
plan: 02
subsystem: infra
tags: [sparkle, updater, dmg, notarization, conditional-compilation]

requires:
  - phase: 25-01
    provides: Dual-distribution build system with SPARKLE compilation condition
provides:
  - UpdaterService wrapping SPUStandardUpdaterController with auto-start
  - CheckForUpdatesView for menu bar popover
  - Conditional Sparkle wiring in PastelApp and StatusPopoverView
  - DMG build/sign/notarize/staple automation script
affects: [sparkle-releases, distribution]

tech-stack:
  added: []
  patterns: [environmentObject injection for conditional dependencies, auto-start updater in class init]

key-files:
  created:
    - Pastel/Services/UpdaterService.swift
    - Pastel/Views/MenuBar/CheckForUpdatesView.swift
    - scripts/build-dmg.sh
  modified:
    - Pastel/PastelApp.swift
    - Pastel/Views/MenuBar/StatusPopoverView.swift

key-decisions:
  - "UpdaterService auto-starts in init via DispatchQueue.main.async (avoids struct init escaping closure issue)"
  - "@StateObject for UpdaterService (not @State) to propagate @Published changes to @ObservedObject consumers"

patterns-established:
  - "#if SPARKLE guard pattern: entire files or property/method blocks wrapped for clean AppStore compilation"
  - "environmentObject for conditional dependency injection across #if SPARKLE boundaries"

duration: 3min
completed: 2026-02-20
---

# Phase 25 Plan 02: Sparkle Integration Layer Summary

**Sparkle updater service with auto-start, Check for Updates UI in menu bar popover, and DMG build/notarize script -- all gated behind #if SPARKLE conditional compilation**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-21T03:51:34Z
- **Completed:** 2026-02-21T03:55:08Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- UpdaterService wraps SPUStandardUpdaterController with publisher-based canCheckForUpdates and auto-start
- CheckForUpdatesView matches existing StatusPopoverView button style (HStack, icon, text, Spacer, .plain)
- PastelApp conditionally injects UpdaterService via @StateObject + .environmentObject
- StatusPopoverView shows "Check for Updates..." between Settings and Clear All History on Sparkle builds
- build-dmg.sh automates full release pipeline: archive, export, DMG create, codesign, notarize, staple, appcast

## Task Commits

Each task was committed atomically:

1. **Task 1: Create UpdaterService and CheckForUpdatesView** - `a93a533` (feat)
2. **Task 2: Wire Sparkle into PastelApp and StatusPopoverView, create DMG build script** - `2aba3d1` (feat)

## Files Created/Modified
- `Pastel/Services/UpdaterService.swift` - Sparkle updater wrapper with auto-start, canCheckForUpdates publisher
- `Pastel/Views/MenuBar/CheckForUpdatesView.swift` - SwiftUI button for triggering update check
- `Pastel/PastelApp.swift` - Conditional Sparkle import, @StateObject updaterService, .environmentObject injection
- `Pastel/Views/MenuBar/StatusPopoverView.swift` - Conditional @EnvironmentObject and CheckForUpdatesView placement
- `scripts/build-dmg.sh` - Full DMG release automation (build, sign, notarize, staple, appcast)

## Decisions Made
- Moved updater start from PastelApp.init to UpdaterService.init via DispatchQueue.main.async -- struct init cannot capture self in escaping closures, but class init can use weak self
- Used @StateObject (not @State) for UpdaterService because @State does not propagate @Published changes to downstream @ObservedObject consumers

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed escaping closure captures mutating self in struct init**
- **Found during:** Task 2 (wiring Sparkle into PastelApp)
- **Issue:** Plan placed `DispatchQueue.main.async { self.updaterService.startUpdater() }` in PastelApp.init() -- Swift structs cannot capture self in escaping closures during init
- **Fix:** Moved the startUpdater() call into UpdaterService.init() using `DispatchQueue.main.async { [weak self] in self?.startUpdater() }` which works because UpdaterService is a class
- **Files modified:** Pastel/Services/UpdaterService.swift, Pastel/PastelApp.swift
- **Verification:** Both Sparkle and AppStore schemes build successfully
- **Committed in:** 2aba3d1 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary fix for Swift struct/class semantics. No scope creep.

## Issues Encountered
None beyond the deviation documented above.

## User Setup Required
Before distributing DMGs, user must:
1. Run `xcrun notarytool store-credentials pastel-notarize` to store Apple ID and app-specific password
2. Set DEVELOPER_ID environment variable to their "Developer ID Application" signing identity
3. Run Sparkle's `generate_keys` and update SUPublicEDKey in Info.plist (from Plan 01)

## Next Phase Readiness
- Sparkle integration complete -- app checks for updates on launch, users can trigger manual check
- DMG build script ready for release workflow
- Phase 25 fully complete (both plans delivered)

## Self-Check: PASSED

All 5 files verified present. Both commit hashes (a93a533, 2aba3d1) confirmed in git log.

---
*Phase: 25-ota-updates-with-sparkle*
*Completed: 2026-02-20*
