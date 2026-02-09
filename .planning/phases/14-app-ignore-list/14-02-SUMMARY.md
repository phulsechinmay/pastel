---
phase: 14-app-ignore-list
plan: 02
subsystem: ui
tags: [swiftui, settings, privacy, ignore-list, table, nsopenpanel, userdefaults, app-picker]

# Dependency graph
requires:
  - phase: 14-app-ignore-list
    provides: AppDiscoveryService with discoverInstalledApps() and detectInstalledPasswordManagers()
  - phase: 05-settings
    provides: SettingsView with custom tab bar and SettingsTab enum
provides:
  - PrivacySettingsView with sortable ignore list table, search, add/remove controls, password manager prompt
  - AppPickerView sheet with searchable installed app selection
  - Privacy tab wired into SettingsView (4 tabs total)
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Three-key UserDefaults persistence for composite data (IDs, dates, names)"
    - "SwiftUI Table with sortOrder binding and onDeleteCommand for keyboard-driven removal"
    - "NSOpenPanel for manual .app file browsing with UTType.application filter"

key-files:
  created:
    - Pastel/Views/Settings/AppPickerView.swift
    - Pastel/Views/Settings/PrivacySettingsView.swift
  modified:
    - Pastel/Views/Settings/SettingsView.swift
    - Pastel.xcodeproj/project.pbxproj

key-decisions:
  - "Three separate UserDefaults keys (IDs, dates, names) instead of Codable encoding -- simpler, debuggable"
  - "PrivacySettingsView uses same fixed-width layout as General/Labels (500px max), not expanding like History"

patterns-established:
  - "ignoredAppDates UserDefaults key for [String: Double] epoch timestamps"
  - "ignoredAppNames UserDefaults key for [String: String] display name cache"
  - "AppPickerView reusable sheet pattern with alreadyIgnored set and onSelect callback"

# Metrics
duration: 4min
completed: 2026-02-09
---

# Phase 14 Plan 02: Privacy Settings UI Summary

**Privacy tab with sortable ignore list table, searchable app picker sheet, NSOpenPanel manual browsing, and one-time password manager detection prompt**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-09T22:08:53Z
- **Completed:** 2026-02-09T22:13:11Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- AppPickerView sheet shows searchable list of all installed apps with icons, dimming already-ignored entries
- PrivacySettingsView with sortable Table (Name + Date Added columns), search filter, add/remove controls
- Privacy tab wired into SettingsView as 4th tab (General, Labels, Privacy, History) with hand.raised icon
- One-time password manager detection prompt on first Privacy tab visit
- NSOpenPanel integration for manually browsing .app files from non-standard locations
- Full UserDefaults persistence across three keys matching ClipboardMonitor's ignoredAppBundleIDs read

## Task Commits

Each task was committed atomically:

1. **Task 1: Create AppPickerView sheet** - `558e52f` (feat)
2. **Task 2: Create PrivacySettingsView with ignore list table and password manager prompt** - `a180bad` (feat)
3. **Task 3: Wire Privacy tab into SettingsView** - `7a59b5d` (feat)

## Files Created/Modified
- `Pastel/Views/Settings/AppPickerView.swift` - Searchable sheet listing installed apps for ignore list selection (117 lines)
- `Pastel/Views/Settings/PrivacySettingsView.swift` - Privacy settings tab with Table, controls, and persistence (260 lines)
- `Pastel/Views/Settings/SettingsView.swift` - Added .privacy case to SettingsTab enum and switch
- `Pastel.xcodeproj/project.pbxproj` - Added both new Swift files to Xcode project

## Decisions Made
- Used three separate UserDefaults keys (ignoredAppBundleIDs, ignoredAppDates, ignoredAppNames) rather than a single Codable-encoded blob -- simpler to debug, and ignoredAppBundleIDs is already read by ClipboardMonitor from Plan 01
- Privacy tab uses same 500px max-width constraint as General/Labels tabs -- it naturally falls into the else branch since only .history is special-cased for expanding layout
- App icons in the Table use NSWorkspace.shared.appIcon(forBundleIdentifier:) from the existing extension, while AppPickerView uses NSWorkspace.shared.icon(forFile:) directly since it has the URL

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None -- no external service configuration required.

## Next Phase Readiness
- Phase 14 (App Ignore List) is fully complete
- Privacy settings UI writes to the same ignoredAppBundleIDs key that ClipboardMonitor reads
- Settings changes take effect immediately on next poll cycle (0.5s)
- No blockers for subsequent phases

---
*Phase: 14-app-ignore-list*
*Completed: 2026-02-09*
