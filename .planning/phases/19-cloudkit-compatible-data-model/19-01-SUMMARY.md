---
phase: 19-cloudkit-compatible-data-model
plan: 01
subsystem: database
tags: [swiftdata, cloudkit, migration, data-model]

# Dependency graph
requires:
  - phase: 11-multi-label
    provides: "Many-to-many ClipboardItem <-> Label relationship"
provides:
  - "CloudKit-compatible ClipboardItem model (no unique constraints, all defaults, optional relationships)"
  - "CloudKit-compatible Label model (all defaults, optional relationship)"
  - "DeviceIdentifier utility for per-device UUID tracking"
  - "safeLabels/safeItems nil-safe accessors for optional relationships"
  - "originDeviceID field on ClipboardItem for cross-device sync"
affects: [19-02-callsite-updates, 20-sync-infrastructure, 21-sync-controls]

# Tech tracking
tech-stack:
  added: []
  patterns: [optional-relationship-with-safe-accessor, per-device-uuid-via-userdefaults]

key-files:
  created:
    - Pastel/Utilities/DeviceIdentifier.swift
  modified:
    - Pastel/Models/ClipboardItem.swift
    - Pastel/Models/Label.swift
    - Pastel.xcodeproj/project.pbxproj

key-decisions:
  - "Auto-migration approach (no VersionedSchema) -- SwiftData handles adding defaults, relaxing constraints, and adding properties"
  - "DeviceIdentifier stored in local UserDefaults (not NSUbiquitousKeyValueStore) so each device keeps distinct identity"
  - "Optional relationships with nil-safe computed accessors (safeLabels/safeItems) to minimize call-site disruption"

patterns-established:
  - "safeLabels/safeItems pattern: optional backing property with non-optional computed accessor"
  - "DeviceIdentifier.current: lazy-initialized stable UUID per device"

# Metrics
duration: 2min
completed: 2026-02-14
---

# Phase 19 Plan 01: CloudKit-Compatible Data Model Summary

**SwiftData models made CloudKit-compatible: removed unique constraint, added defaults to all non-optional properties, made relationships optional with nil-safe accessors, added originDeviceID for cross-device tracking**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T18:10:36Z
- **Completed:** 2026-02-14T18:13:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Removed @Attribute(.unique) from ClipboardItem.contentHash (required for CloudKit -- unique constraints cause crashes)
- Added inline default values to all 7 non-optional ClipboardItem properties and all 3 non-optional Label properties
- Made labels/items relationships optional with safeLabels/safeItems nil-safe computed accessors
- Added originDeviceID field on ClipboardItem for cross-device sync origin tracking
- Created DeviceIdentifier utility providing stable per-device UUID via UserDefaults

## Task Commits

Each task was committed atomically:

1. **Task 1: Update ClipboardItem and Label models for CloudKit compatibility** - `f077495` (feat)
2. **Task 2: Create DeviceIdentifier utility and update PastelApp ModelContainer** - `fdc6579` (feat)

## Files Created/Modified
- `Pastel/Models/ClipboardItem.swift` - Removed unique constraint, added defaults, optional labels, safeLabels accessor, originDeviceID field
- `Pastel/Models/Label.swift` - Added defaults to name/colorName/sortOrder, optional items, safeItems accessor
- `Pastel/Utilities/DeviceIdentifier.swift` - New enum providing stable per-device UUID from UserDefaults
- `Pastel.xcodeproj/project.pbxproj` - Regenerated to include new Utilities directory

## Decisions Made
- **Auto-migration over VersionedSchema:** SwiftData auto-migration handles adding defaults, relaxing unique constraints, and adding new properties. No VersionedSchema needed unless runtime testing reveals issues.
- **Local UserDefaults for device ID:** DeviceIdentifier stores UUID in local UserDefaults (not NSUbiquitousKeyValueStore) so each device retains distinct identity even with iCloud sync enabled.
- **Optional + computed accessor pattern:** Rather than making relationships non-optional (which CloudKit prohibits), used optional backing with non-optional computed accessor (safeLabels/safeItems) to keep call-site ergonomics clean.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None - all model changes applied cleanly. Build errors from call sites (EditItemView, MigrationService) accessing `.labels` directly are expected and will be resolved in Plan 02 (call-site updates).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Model schema is CloudKit-ready (no unique constraints, all defaults, optional relationships)
- Plan 02 must update all call sites that reference `.labels` and `.items` directly to use `.safeLabels` and `.safeItems`
- Plan 02 will also add the dedup logic (replacing the lost unique constraint with manual dedup)
- No blockers for Plan 02

## Self-Check: PASSED

All files verified present. All commits verified in git log.

---
*Phase: 19-cloudkit-compatible-data-model*
*Completed: 2026-02-14*
