# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-09)

**Core value:** Clipboard history is always one hotkey away, with instant paste-back into any app.
**Current focus:** v1.5 iCloud Sync -- Phase 20 Plan 01 complete, Plan 02 next

## Current Position

Phase: 20 of 21 (CloudKit Infrastructure and Sync Engine)
Plan: 1 of 2 complete
Status: Executing
Last activity: 2026-02-14 -- Completed 20-01 (CloudKit entitlements, framework, conditional ModelContainer)

### Roadmap Evolution
- Phase 17 added: Liquid Glass panel fix with iterative visual feedback loop
- Phase 18 added: Codebase Audit -- Anti-patterns, Performance, and Security (Encryption)
- Phases 19-21 added: v1.5 iCloud Sync (CloudKit-compatible model, sync infrastructure, sync controls)

## Previous Milestones

### v1.0 MVP
- 29/29 requirements delivered across 5 phases (13 plans)
- Total execution time: ~37 min
- 8 quick tasks completed post-v1.0

### v1.1 Rich Content & Enhanced Paste
- 15/15 requirements delivered across 5 phases (10 plans)
- 10 quick tasks completed during v1.1
- Features: code detection, color swatches, URL metadata, quick paste hotkeys, label emoji, drag-drop labels

### v1.2 Item Management
- Phases 11-12 complete (6 plans)
- Features: item titles, multi-label support, edit modal, history browser with grid view, multi-select, bulk operations

### v1.3 Power User Features
- Phases 13-16 complete (7 plans)
- Features: paste-as-plain-text, app ignore list, import/export, drag-and-drop from panel

### v1.4 Codebase Audit
- Phase 18 complete (3 plans), Phase 17 deferred
- Features: error handling, force unwrap fixes, import optimization, @Query cleanup, deprecated API replacement

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Key decisions from Phase 18 (Codebase Audit):

- [18-01]: Free function saveWithLogging() instead of ModelContext extension -- avoids polluting SDK type namespace
- [18-02]: Pre-load all content hashes into Set<String> for O(1) import dedup instead of O(n) fetchCount queries
- [18-03]: allLabels parameter on ClipboardCardView -- pass from parent @Query, not per-card @Query

Key decisions from Phase 19 (CloudKit-Compatible Data Model):

- [19-01]: Auto-migration (no VersionedSchema) -- SwiftData handles adding defaults, relaxing constraints, adding properties
- [19-01]: DeviceIdentifier in local UserDefaults (not iCloud KVS) -- each device keeps distinct identity
- [19-01]: Optional relationships + nil-safe computed accessors (safeLabels/safeItems) pattern for CloudKit compatibility
- [19-02]: isDuplicateByHash uses fetchCount for O(count) dedup without loading model objects
- [19-02]: Keep both dedup methods: isDuplicateOfMostRecent (fast O(1)) + isDuplicateByHash (thorough)
- [19-02]: Defensive originDeviceID stamping after insert (redundant with init for future-proofing)

Key decisions from Phase 20 (CloudKit Infrastructure):

- [20-01]: Use xcodegen `sdk` (not `framework`) dependency type for system frameworks -- correct SDKROOT sourceTree
- [20-01]: cloudKitDatabase: .private (not .automatic) for explicit container identifier control
- [20-01]: CloudKit schema init uses NSPersistentCloudKitContainer directly (CoreData API, not SwiftData)

Key architecture decisions for v1.5 (from research):

- SwiftData built-in CloudKit sync (ModelConfiguration cloudKitDatabase: .automatic), NOT CKSyncEngine
- Build own sync monitor (~60 lines), no CloudKitSyncMonitor dependency
- Restart required for sync toggle (UserDefaults + restart prompt)
- Text-only sync (images/files excluded), concealed items never sync
- Last-writer-wins conflict resolution (built into SwiftData CloudKit)

### Research Flags (v1.5)

- Phase 19: @Attribute(.unique) MUST be removed BEFORE enabling CloudKit (app crash otherwise)
- Phase 19: Schema is permanent once deployed to CloudKit production -- finalize model FIRST
- Phase 20: CloudKit.framework must be explicitly linked for macOS release builds (RESOLVED in 20-01: linked via sdk dependency)
- Phase 20: cloudKitDatabase: .none reliability needs validation (conflicting reports)
- Phase 20: managedObjectContext?.transactionAuthor access from SwiftData needs testing

### Pending Todos

- Final manual testing of full application before distribution

### Blockers/Concerns

None currently.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 018 | NSGlassEffectView for panel + settings cleanup | 2026-02-09 | 1af4890 | [018-liquid-glass-panel-settings-swiftui-26](./quick/018-liquid-glass-panel-settings-swiftui-26/) |
| 019 | Fix panel click dismissal + rounded corners | 2026-02-11 | 0d2385f | [19-fix-panel-click-dismissal-and-add-rounde](./quick/19-fix-panel-click-dismissal-and-add-rounde/) |
| 020 | Single-select label filter, card rearrange, color dot chips | 2026-02-12 | 760abf9 | [20-single-select-label-filter-rearrange-car](./quick/20-single-select-label-filter-rearrange-car/) |
| 021 | Key repeat navigation, rounded font, header padding | 2026-02-12 | 08a9412 | [21-enable-key-repeat-navigation-rounded-fon](./quick/21-enable-key-repeat-navigation-rounded-fon/) |
| 022 | Fix key repeat, All History chip, drag-paste dismiss | 2026-02-12 | 62903e4 | [22-fix-key-repeat-for-card-nav-add-all-hist](./quick/22-fix-key-repeat-for-card-nav-add-all-hist/) |

## Session Continuity

Last session: 2026-02-14
Stopped at: Completed 20-01-PLAN.md (CloudKit entitlements, framework, conditional ModelContainer)
Resume file: None
