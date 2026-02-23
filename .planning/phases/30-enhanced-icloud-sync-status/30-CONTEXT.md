# Phase 30: Enhanced iCloud Sync Status - Context

**Gathered:** 2026-02-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Enrich the sync status display in SyncSettingsView by extracting more metadata from NSPersistentCloudKitContainer.Event (event type, record counts, timestamps) and surfacing it meaningfully. Changes are limited to SyncMonitor.swift (data extraction) and SyncSettingsView.swift (display). No new sync capabilities, no schema changes.

</domain>

<decisions>
## Implementation Decisions

### Status text during active sync
- Distinguish between import and export operations: show "Importing..." when receiving, "Exporting..." when sending (not generic "Syncing...")
- Show "Setting up..." during the initial CloudKit setup phase (event.type == .setup)
- Show "Initial sync: Importing..." for the first sync after enabling — sets expectations for potentially long duration (10+ minutes observed)

### Status text when idle (synced)
- Show "Last synced: 3 min ago" using RelativeDateTimeFormatter below the green dot
- Relative time only recalculates on view appear (no live timer)
- When sync is disabled, hide all sync info — no residual "last synced" text

### Sync detail line (counts)
- Combined format: "Fully up to date (↓42 ↑18 last sync)" when last cycle had activity
- When both counts are zero: just "Fully up to date" — no zero counts shown
- Counts always visible (during sync and when idle), not hidden until synced
- During active sync, counts update in real-time as events complete

### Count accumulation behavior
- Counts reflect last sync cycle only — reset when a new sync cycle begins
- No persistence across app restarts (in-memory only)

### Error display
- Red dot + "Sync error: [brief reason]" — show enough detail to help user understand what's wrong
- Replaces the green dot and normal status text

### Claude's Discretion
- Exact layout/spacing of the status area
- How to detect "initial sync" vs subsequent syncs
- Debounce behavior for rapid event updates
- How to extract a brief, user-friendly error reason from CloudKit errors

</decisions>

<specifics>
## Specific Ideas

- The initial sync currently takes 10+ minutes — showing active import progress is important so users don't think the app is stuck
- Use ↓ and ↑ arrows for imported/exported counts (compact, universally understood)
- "Fully up to date" is the primary status message — counts are supplementary detail in parentheses

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 30-enhanced-icloud-sync-status*
*Context gathered: 2026-02-22*
