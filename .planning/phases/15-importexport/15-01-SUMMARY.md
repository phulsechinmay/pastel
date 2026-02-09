---
phase: 15-importexport
plan: 01
subsystem: data
tags: [json, codable, swiftdata, uttype, import, export]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: ClipboardItem and Label SwiftData models
  - phase: 11-itemmanagement
    provides: Multi-label relationship on ClipboardItem
provides:
  - ImportExportService with export/import methods
  - PastelExport, ExportedItem, ExportedLabel Codable transfer structs
  - ImportResult type with counts
  - UTType.pastelExport extension and Info.plist registration
affects: [15-02-PLAN (UI buttons calling these methods)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Codable transfer structs decoupled from SwiftData @Model"
    - "Pre-check deduplication via fetchCount before insert (avoid @Attribute(.unique) upsert)"
    - "Batch save every 50 items during import for memory control"
    - "Label resolution by name with automatic creation of missing labels"

key-files:
  created:
    - Pastel/Services/ImportExportService.swift
  modified:
    - Pastel/Resources/Info.plist
    - Pastel.xcodeproj/project.pbxproj

key-decisions:
  - "Separate Codable transfer structs instead of making @Model classes Codable"
  - "Pre-check fetchCount deduplication instead of relying on SwiftData upsert"
  - "Exclude concealed and image items from export"

patterns-established:
  - "Transfer struct pattern: ExportedItem mirrors ClipboardItem without SwiftData persistence"
  - "Batch save pattern: save every 50 items during import to control memory"

# Metrics
duration: 3min
completed: 2026-02-09
---

# Phase 15 Plan 01: Import/Export Service Summary

**ImportExportService with Codable transfer structs, JSON export filtering concealed/image items, pre-check dedup import with batch saves, and .pastel UTType registration**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-09T22:38:04Z
- **Completed:** 2026-02-09T22:41:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created ImportExportService with exportHistory and importHistory methods
- Defined PastelExport, ExportedItem, ExportedLabel Codable transfer structs decoupled from SwiftData
- Export filters out concealed and image-type items, encodes to JSON with ISO 8601 dates and base64 Data
- Import resolves labels by name (creating missing ones), pre-checks contentHash for deduplication, batch saves every 50 items
- ImportResult reports importedCount, skippedCount, labelsCreated for UI feedback
- Registered app.pastel.export UTType in Info.plist with .pastel file extension

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ImportExportService with Codable transfer structs and export/import logic** - `bfbed28` (feat)
2. **Task 2: Register .pastel UTType in Info.plist** - `0cc0d3f` (feat)

## Files Created/Modified
- `Pastel/Services/ImportExportService.swift` - Core export/import service with Codable structs, deduplication, batch insert, label resolution
- `Pastel/Resources/Info.plist` - UTExportedTypeDeclarations for app.pastel.export with .pastel extension
- `Pastel.xcodeproj/project.pbxproj` - Added ImportExportService.swift to Xcode project

## Decisions Made
- Used separate Codable transfer structs (ExportedItem, ExportedLabel) instead of making SwiftData @Model classes Codable -- prevents fragile serialization of persistence state
- Pre-check deduplication via fetchCount before insert -- avoids SwiftData's silent upsert on @Attribute(.unique) which would corrupt existing items
- Excluded concealed items and image items from export -- security-first (no password export) and images are disk-referenced (not portable)
- Label resolution by name during import -- preserves existing label customizations, only creates new labels for names that don't exist

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- ImportExportService is ready for Plan 02 to wire up UI (Export/Import buttons in Settings)
- Service exposes isProcessing, progress, and progressMessage for ProgressView binding
- NSSavePanel/NSOpenPanel integration is the next step (Plan 02)

---
*Phase: 15-importexport*
*Completed: 2026-02-09*
