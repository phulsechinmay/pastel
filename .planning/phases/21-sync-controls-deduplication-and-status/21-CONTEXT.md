# Phase 21: Sync Controls, Deduplication, and Status - Context

**Gathered:** 2026-02-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can control iCloud sync via a dedicated Settings tab (toggle + status), duplicate items that arrive from other devices are automatically merged in the background, and sync status is visible in Settings so users know if sync is working or has errors.

New capabilities (device list management, per-item sync indicators, notification alerts) belong in other phases.

</domain>

<decisions>
## Implementation Decisions

### Sync tab design
- Tab label: "iCloud Sync" (matches macOS convention — iCloud Drive, iCloud Photos)
- Toggle label: "iCloud Sync" with a brief description below
- Show connected iCloud account email address below the toggle
- Show sync status with color dot: green = healthy, red = error
- "?" (help) icon next to the status section opens a popover/tooltip explaining:
  - What syncs: text, URLs, code snippets, color values, labels
  - What doesn't sync: images, files, passwords (concealed items)
  - Current device name (device identity surfaced here, not inline)
- No separate device list — keep the tab minimal

### Restart flow
- Toggle change triggers a **modal alert sheet** (not inline banner) — blocking and clear
- Alert has two actions: "Restart Now" and "Later"
- "Restart Now" quits and relaunches the app immediately via NSWorkspace.shared.open()
- Prompt appears **every time** the toggle changes, even if user flips it back to original state

### Status indicator placement
- Sync status lives **only in the Settings Sync tab** — no changes to menu bar icon or panel header
- **Silence = success**: no persistent indicator when sync is working normally
- Status indicator only surfaces in two cases:
  1. Actively syncing (brief "Syncing..." state)
  2. Error or offline (red dot with error message)

### Deduplication behavior
- Dedup is **completely silent** in production — no user-facing notifications
- Console/debug logging of merge events for development debugging
- Conflict resolution: **local device's version wins** (not earliest timestamp)
- Label conflict resolution: **merge (union)** — all labels from both devices are kept
- Dedup triggered when CloudKit delivers a new item whose contentHash matches an existing local item

### Claude's Discretion
- Exact modal alert copy (wording of restart prompt)
- Status dot animation when actively syncing (pulsing vs static)
- Debounce timing for sync status updates
- DeduplicationService architecture (polling vs CloudKit notification trigger)

</decisions>

<specifics>
## Specific Ideas

- Status section: green dot + "Synced" text when healthy; red dot + brief error when failing
- "?" popover should feel lightweight — not a full sheet — similar to macOS system preference info popovers
- iCloud account email gives the user confidence they're syncing to the right account

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 21-sync-controls-deduplication-and-status*
*Context gathered: 2026-02-15*
