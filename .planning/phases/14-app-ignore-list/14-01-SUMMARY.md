---
phase: 14-app-ignore-list
plan: 01
subsystem: services
tags: [clipboard-monitor, app-discovery, userdefaults, ignore-list, password-manager]

# Dependency graph
requires:
  - phase: 01-core-clipboard
    provides: ClipboardMonitor with checkForChanges() polling loop
provides:
  - AppDiscoveryService with installed app enumeration and password manager detection
  - ClipboardMonitor ignore-list filtering via UserDefaults ignoredAppBundleIDs
affects: [14-02 (Privacy settings UI will consume AppDiscoveryService and write ignoredAppBundleIDs)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "UserDefaults direct read per poll cycle (no caching) for service-layer settings"
    - "Static enum service with @MainActor for utility classes"
    - "Bundle ID prefix matching for app family detection"

key-files:
  created:
    - Pastel/Services/AppDiscoveryService.swift
  modified:
    - Pastel/Services/ClipboardMonitor.swift
    - Pastel.xcodeproj/project.pbxproj

key-decisions:
  - "Ignore check in checkForChanges() not processPasteboardContent() -- filters ALL content types uniformly including images"
  - "Fresh UserDefaults read each 0.5s poll -- no caching, matches RetentionService pattern, avoids stale list"
  - "Set<String> for O(1) lookup on typically 5-20 entries"
  - "Shallow directory scan only -- .app bundles are directories, recursive would enter them"

patterns-established:
  - "ignoredAppBundleIDs UserDefaults key for [String] array of bundle IDs"
  - "AppDiscoveryService enum with static methods for app enumeration"
  - "DiscoveredApp struct as shared model between service and UI layers"

# Metrics
duration: 3min
completed: 2026-02-09
---

# Phase 14 Plan 01: App Ignore List Service Layer Summary

**AppDiscoveryService scans 3 system directories for installed apps with password manager prefix detection, ClipboardMonitor filters ALL content types via UserDefaults ignore list**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-09T21:31:45Z
- **Completed:** 2026-02-09T21:34:31Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- AppDiscoveryService discovers installed apps from /Applications, /System/Applications, ~/Applications with dedup and alphabetical sort
- Password manager detection via prefix matching against 12 known patterns (1Password, Bitwarden, Dashlane, LastPass, KeePassXC, Apple Passwords, etc.)
- ClipboardMonitor early-exit guard skips capture from ignored apps for ALL content types (text, image, URL, file, code, color)
- Ignore list reads fresh from UserDefaults each poll cycle -- settings changes take effect immediately

## Task Commits

Each task was committed atomically:

1. **Task 1: Create AppDiscoveryService** - `b73cc04` (feat)
2. **Task 2: Add ignore-list filtering to ClipboardMonitor** - `3cf4646` (feat)

## Files Created/Modified
- `Pastel/Services/AppDiscoveryService.swift` - DiscoveredApp model + app discovery + password manager detection
- `Pastel/Services/ClipboardMonitor.swift` - Added ignoredAppBundleIDs guard in checkForChanges()
- `Pastel.xcodeproj/project.pbxproj` - Added AppDiscoveryService.swift to Xcode project

## Decisions Made
- Placed ignore check in `checkForChanges()` (not `processPasteboardContent()`) so ALL content types are filtered uniformly, including images which take a separate code path
- Read UserDefaults directly each poll cycle rather than caching -- matches existing RetentionService pattern, avoids stale list after settings changes
- Used `Set<String>` for O(1) lookup -- negligible cost at 0.5s intervals for typically 5-20 entries
- Debug-level logging for ignored app skips to avoid log spam every 0.5s
- Guard on bundleIdentifier being non-nil -- nil means no frontmost app, allow capture

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None -- no external service configuration required.

## Next Phase Readiness
- Service layer complete, ready for Phase 14 Plan 02 (Privacy settings UI)
- AppDiscoveryService provides the data source for the app picker sheet
- PrivacySettingsView will write to `ignoredAppBundleIDs` UserDefaults key, which ClipboardMonitor already reads
- No blockers

---
*Phase: 14-app-ignore-list*
*Completed: 2026-02-09*
