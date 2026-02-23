# Phase 30: Enhanced iCloud Sync Status - Research

**Researched:** 2026-02-22
**Domain:** NSPersistentCloudKitContainer.Event metadata extraction, sync status UI, RelativeDateTimeFormatter, CloudKit error handling
**Confidence:** HIGH

## Summary

Phase 30 enriches the existing sync status display in SyncSettingsView by extracting more metadata from `NSPersistentCloudKitContainer.Event` notifications and surfacing it meaningfully. The scope is strictly limited to two files: `SyncMonitor.swift` (data extraction) and `SyncSettingsView.swift` (display). No new sync capabilities, no schema changes, no new files.

The key technical finding is that **`NSPersistentCloudKitContainer.Event` does NOT provide record counts** -- it only exposes `type` (setup/import/export), `startDate`, `endDate`, `succeeded`, and `error`. The user's CONTEXT.md decision calls for showing imported/exported counts (e.g., "Fully up to date (arrow-down 42 arrow-up 18 last sync)"). Since the Event API lacks this data, counts must be derived from a different source: **`NSPersistentStoreRemoteChange` notifications combined with item count diffing** or **Core Data persistent history transactions** (`NSPersistentHistoryTransaction`). However, persistent history on a CloudKit-enabled container is managed by CoreData itself, and manually processing those transactions risks interfering with CloudKit's internal bookkeeping. The safest approach is to **count items before and after each import/export cycle** using simple FetchDescriptor counts, or to **count `NSPersistentStoreRemoteChange` notifications as a proxy** for imported items.

The existing `SyncMonitor` already subscribes to `eventChangedNotification` and debounces the synced state transition. The enhancement requires: (1) extracting `event.type` to distinguish import/export/setup, (2) tracking `endDate` for the "Last synced: X ago" display, (3) accumulating per-cycle counts via remote change notifications, (4) detecting "initial sync" by checking whether this is the first import after app launch, and (5) mapping CloudKit errors to user-friendly messages.

**Primary recommendation:** Extend the existing SyncMonitor to extract full Event metadata (type, timestamps, errors), add a separate counter mechanism for import/export counts via `NSPersistentStoreRemoteChange` notification counting, and update SyncSettingsView with the richer status display. Use `RelativeDateTimeFormatter` (already in the codebase) for the "Last synced" relative time.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Distinguish between import and export operations: show "Importing..." when receiving, "Exporting..." when sending (not generic "Syncing...")
- Show "Setting up..." during the initial CloudKit setup phase (event.type == .setup)
- Show "Initial sync: Importing..." for the first sync after enabling -- sets expectations for potentially long duration (10+ minutes observed)
- Show "Last synced: 3 min ago" using RelativeDateTimeFormatter below the green dot
- Relative time only recalculates on view appear (no live timer)
- When sync is disabled, hide all sync info -- no residual "last synced" text
- Combined format: "Fully up to date (arrow-down 42 arrow-up 18 last sync)" when last cycle had activity
- When both counts are zero: just "Fully up to date" -- no zero counts shown
- Counts always visible (during sync and when idle), not hidden until synced
- During active sync, counts update in real-time as events complete
- Counts reflect last sync cycle only -- reset when a new sync cycle begins
- No persistence across app restarts (in-memory only)
- Red dot + "Sync error: [brief reason]" -- show enough detail to help user understand what's wrong
- Replaces the green dot and normal status text

### Claude's Discretion
- Exact layout/spacing of the status area
- How to detect "initial sync" vs subsequent syncs
- Debounce behavior for rapid event updates
- How to extract a brief, user-friendly error reason from CloudKit errors

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

## Standard Stack

### Core (already in project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| CoreData | macOS 14+ | `NSPersistentCloudKitContainer.Event` access, event type enum | Required for sync event metadata extraction |
| CloudKit | macOS 14+ | `CKError` type for error classification | Already linked; needed for user-friendly error messages |
| SwiftUI | macOS 14+ | SyncSettingsView display updates | Already used for all settings views |
| Foundation | macOS 14+ | `RelativeDateTimeFormatter` | Already used in ClipboardCardView for relative dates |
| OSLog | macOS 14+ | Structured logging | Already used in SyncMonitor |

### No New Dependencies
This phase adds zero new packages or frameworks. All changes use APIs already available in the project's existing dependency set.

## Architecture Patterns

### Recommended Changes Structure
```
Pastel/
  Services/
    SyncMonitor.swift        # MODIFY: Extract full Event metadata, track counts, timestamps
  Views/Settings/
    SyncSettingsView.swift   # MODIFY: Rich status display with type, counts, relative time
```

### Pattern 1: Enhanced SyncState Enum with Metadata
**What:** Replace the simple `.syncing` case with typed cases that carry Event metadata (import/export/setup), and add associated data to `.synced` for last-sync timestamp and counts.
**When to use:** In SyncMonitor to expose richer state to the view.

```swift
// Source: Existing SyncMonitor.swift + NSPersistentCloudKitContainer.Event API
enum SyncState: Equatable {
    case disabled
    case synced(lastSyncDate: Date?, importCount: Int, exportCount: Int)
    case syncing(phase: SyncPhase)
    case error(String)
    case accountUnavailable
}

enum SyncPhase: Equatable {
    case setup
    case importing(isInitial: Bool)
    case exporting
}
```

### Pattern 2: Full Event Extraction from Notification
**What:** Extract the complete `NSPersistentCloudKitContainer.Event` object from the notification, including `type`, `startDate`, `endDate`, `succeeded`, and `error`.
**When to use:** In the `eventChangedNotification` handler.

```swift
// Source: Apple NSPersistentCloudKitContainer.Event API
// The Event has these properties:
// - type: NSPersistentCloudKitContainer.EventType (.setup | .import | .export)
// - startDate: Date (always present)
// - endDate: Date? (nil = in progress, non-nil = finished)
// - succeeded: Bool (meaningful only when endDate != nil)
// - error: Error? (present on failure)
// - storeIdentifier: String

private func handleSyncEvent(_ notification: Notification) {
    guard let event = notification.userInfo?[
        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
    ] as? NSPersistentCloudKitContainer.Event else { return }

    if event.endDate == nil {
        // Event started
        switch event.type {
        case .setup:
            state = .syncing(phase: .setup)
        case .import:
            state = .syncing(phase: .importing(isInitial: isInitialSync))
        case .export:
            state = .syncing(phase: .exporting)
        @unknown default:
            state = .syncing(phase: .importing(isInitial: false))
        }
    } else if let error = event.error {
        state = .error(friendlyErrorMessage(from: error))
    } else {
        // Event completed successfully
        if event.type == .import {
            lastImportEndDate = event.endDate
        } else if event.type == .export {
            lastExportEndDate = event.endDate
        }
        // Debounce transition to .synced
        scheduleTransitionToSynced()
    }
}
```

### Pattern 3: Import/Export Count Tracking via Remote Change Notifications
**What:** Since `NSPersistentCloudKitContainer.Event` does NOT provide record counts, track imported item counts by counting `NSPersistentStoreRemoteChange` notifications that fire during an import cycle, and track exported items by counting local saves during an export cycle.
**When to use:** For the "arrow-down 42 arrow-up 18" display.
**Critical insight:** `NSPersistentStoreRemoteChange` fires when CloudKit imports data into the local store. Each notification may represent one or more records. The notification does NOT carry a count -- it simply signals that remote data arrived.

**Recommended approach -- Item Count Diffing:**

```swift
// Track the total item count before and after each sync cycle
private var preImportItemCount: Int = 0
private var preExportItemCount: Int = 0
private var lastImportedCount: Int = 0
private var lastExportedCount: Int = 0

// When an import event starts:
preImportItemCount = (try? modelContext.fetchCount(FetchDescriptor<ClipboardItem>())) ?? 0

// When the import event ends (endDate != nil, succeeded):
let postCount = (try? modelContext.fetchCount(FetchDescriptor<ClipboardItem>())) ?? 0
let imported = max(0, postCount - preImportItemCount)
lastImportedCount += imported  // accumulate for the cycle
```

**Alternative approach -- Remote Change Notification Counting (simpler but less accurate):**

```swift
// Count NSPersistentStoreRemoteChange notifications as a rough proxy for imported records
// Not 1:1 with records but gives a ballpark
private var remoteChangeCount: Int = 0

// On each NSPersistentStoreRemoteChange during an active import:
remoteChangeCount += 1

// On import end: lastImportedCount = remoteChangeCount
```

**Recommendation:** Use the item count diffing approach. It provides actual record counts (not notification counts), is simple to implement, and aligns with the user's expectation of seeing meaningful numbers. The diff happens only twice per cycle (start and end of each import/export event), so the performance cost of `fetchCount` is negligible.

**For export counts:** Export events do not have a direct analog to `NSPersistentStoreRemoteChange`. The approach is to diff the total item count before and after the export -- but exports do not change the local count. An alternative is to track the number of local saves (via the existing `saveWithLogging` calls) between export start and end. However, this conflates user activity with sync exports. The simplest approach: **count new items created locally since the last sync cycle** (items where `originDeviceID == DeviceIdentifier.current` and `timestamp > lastSyncDate`).

### Pattern 4: Initial Sync Detection
**What:** Detect whether the current import is the first import after the app was launched (or sync was first enabled) to show "Initial sync: Importing..." instead of just "Importing...".
**When to use:** For the initial sync indicator per CONTEXT.md decision.

```swift
// Simple approach: track whether we've ever completed a successful import
private var hasCompletedFirstImport = false

// On import event end (succeeded):
if !hasCompletedFirstImport {
    hasCompletedFirstImport = true
    // This was the initial sync
}

// When showing status:
var isInitialSync: Bool { !hasCompletedFirstImport }
```

This is in-memory only (resets on app restart), which aligns with the CONTEXT.md decision that counts don't persist across restarts. Each app launch starts fresh -- the first import is always "initial."

### Pattern 5: RelativeDateTimeFormatter for "Last synced"
**What:** Use `RelativeDateTimeFormatter` to display "Last synced: 3 min ago" below the green status dot.
**When to use:** When state is `.synced` and `lastSyncDate` is available.

```swift
// Source: Already used in ClipboardCardView.swift line 309
private static let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full  // "3 minutes ago" not "3 min. ago"
    return f
}()

// Per CONTEXT.md: recalculate only on view appear (no live timer)
@State private var lastSyncedText: String = ""

.onAppear {
    if let date = syncMonitor?.lastSyncDate {
        lastSyncedText = Self.relativeFormatter.localizedString(
            for: date, relativeTo: Date.now
        )
    }
}
```

### Pattern 6: User-Friendly CloudKit Error Messages
**What:** Map `CKError` codes to brief, actionable messages instead of showing raw `localizedDescription`.
**When to use:** In SyncMonitor when an Event completes with an error.

```swift
// Source: CKError.Code Apple documentation + common CloudKit error patterns
private func friendlyErrorMessage(from error: Error) -> String {
    if let ckError = error as? CKError {
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return "No internet connection"
        case .notAuthenticated:
            return "Not signed in to iCloud"
        case .quotaExceeded:
            return "iCloud storage full"
        case .serviceUnavailable, .serverResponseLost:
            return "iCloud temporarily unavailable"
        case .requestRateLimited:
            return "Too many requests -- will retry"
        case .zoneBusy:
            return "iCloud busy -- will retry"
        case .partialFailure:
            // Check underlying errors for quota or auth issues
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                for (_, partialError) in partialErrors {
                    if let innerCK = partialError as? CKError, innerCK.code == .quotaExceeded {
                        return "iCloud storage full"
                    }
                }
            }
            return "Partial sync failure -- will retry"
        default:
            return "Sync error: \(ckError.localizedDescription)"
        }
    }
    // Non-CKError (rare but possible from NSPersistentCloudKitContainer internals)
    return error.localizedDescription
}
```

### Anti-Patterns to Avoid
- **Do NOT use a live timer for relative time** -- CONTEXT.md explicitly says "Relative time only recalculates on view appear (no live timer)". Using `Timer.publish` or `TimelineView` would waste resources.
- **Do NOT try to access record counts from Event** -- the API does not expose them. Do not assume `succeeded` carries count data.
- **Do NOT use persistent history tracking (NSPersistentHistoryTransaction) for counting** -- NSPersistentCloudKitContainer manages persistent history internally. Manually fetching/deleting transactions risks corrupting CloudKit's sync bookkeeping.
- **Do NOT persist counts to UserDefaults** -- CONTEXT.md says "No persistence across app restarts (in-memory only)."
- **Do NOT show sync status when sync is disabled** -- CONTEXT.md says "When sync is disabled, hide all sync info."
- **Do NOT use SwiftData History API for counting** -- it requires macOS 15+, but the project targets macOS 14.0.
- **Do NOT modify the SyncState enum to break Equatable** -- the `.synced` case with associated data needs proper Equatable implementation.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Relative date formatting | Custom "X minutes ago" string logic | `RelativeDateTimeFormatter` | Already in use in ClipboardCardView; handles localization automatically |
| Event type detection | String parsing of notification names | `event.type` enum (`.setup`, `.import`, `.export`) | Apple provides a typed enum |
| Error classification | Regex on error.localizedDescription | `CKError.code` switch | Typed enum with specific cases for each error condition |
| Sync cycle boundary detection | Custom timer-based polling | `NSPersistentCloudKitContainer.Event` start/end notifications | Events already signal cycle boundaries |

**Key insight:** The Event API provides just enough metadata (type + timestamps + errors) to build a rich status display. Record counts are the only piece that requires additional infrastructure.

## Common Pitfalls

### Pitfall 1: Event State Thrashing with Multiple Event Types
**What goes wrong:** During a normal sync cycle, CloudKit fires separate events for setup, import, AND export -- often overlapping. The status display rapidly flickers between "Importing...", "Exporting...", "Setting up..." as events start and end.
**Why it happens:** NSPersistentCloudKitContainer fires independent events for each operation type. An import may start before the previous export ends. Setup events fire on every app launch.
**How to avoid:** Track per-type state independently (like CloudKitSyncMonitor does with `setupState`, `importState`, `exportState`). Show the most "active" state in priority order: error > setup > importing > exporting > synced. Only transition to `.synced` when ALL active event types have completed (debounced).
**Warning signs:** Status flickering between different states during normal sync operations.

### Pitfall 2: Item Count Diff Includes Local Changes
**What goes wrong:** The count diff between pre-import and post-import includes items the user copied locally during the sync, inflating the "imported" count.
**Why it happens:** `fetchCount` returns ALL items, not just CloudKit-imported ones. If the user copies 5 items while an import is running, the diff shows 5 extra "imported" items.
**How to avoid:** Filter the count to items where `originDeviceID != DeviceIdentifier.current` (remote items only). Or accept the slight inaccuracy -- during a typical import, the user copies 0-2 items, so the error is small relative to a 42-item import.
**Warning signs:** Import count seems higher than expected after local clipboard activity.

### Pitfall 3: Setup Events Fire on Every App Launch
**What goes wrong:** The "Setting up..." message appears on every app launch, even though setup completed long ago.
**Why it happens:** NSPersistentCloudKitContainer fires a setup event every time the persistent store loads, even if the CloudKit zone already exists. This is normal behavior -- the setup just completes very quickly (< 1 second) when the zone already exists.
**How to avoid:** Only show "Setting up..." if the setup event takes more than a threshold (e.g., 2 seconds). If it completes within the threshold, skip directly to the import/export display. Alternatively, suppress the "Setting up..." display entirely after the first successful import, since setup is only meaningful on first launch.
**Warning signs:** Users seeing "Setting up..." briefly every time they open Settings, even though sync works fine.

### Pitfall 4: SyncState Equatable with Associated Values
**What goes wrong:** Adding `Date` and `Int` associated values to `SyncState.synced` breaks the existing manual `Equatable` conformance, or the auto-synthesized conformance triggers excessive view updates.
**Why it happens:** With `synced(lastSyncDate: Date?, importCount: Int, exportCount: Int)`, every sub-second timestamp difference makes states "not equal," causing unnecessary SwiftUI redraws.
**How to avoid:** Implement custom `Equatable` that ignores `lastSyncDate` for equality purposes (or rounds to the nearest second). Or store timestamp/counts as separate `@Observable` properties on SyncMonitor rather than as enum associated values.
**Warning signs:** SyncSettingsView body re-executing on every event notification even when nothing visually changes.

### Pitfall 5: Error State Sticking After Transient Failures
**What goes wrong:** A transient network blip shows "No internet connection" error, and the error state persists even after the network recovers and subsequent events succeed.
**Why it happens:** The current code sets `.error` on any event failure. If the next event (e.g., a retry that succeeds) arrives, it should clear the error -- but if the error event was for import and the success event is for export, the error may not be properly cleared.
**How to avoid:** Track errors per event type. A successful import clears import errors; a successful export clears export errors. Only show error state if the most recent event of ANY type has an error.
**Warning signs:** Red error dot persisting after sync resumes normally.

### Pitfall 6: Export Count Always Zero
**What goes wrong:** The export count shows 0 because there is no good mechanism to count exported records.
**Why it happens:** Export events do not trigger `NSPersistentStoreRemoteChange` (that fires only on IMPORT). The item count diff before/after export is always 0 (exports don't change local data). There is no `NSPersistentStoreLocalChange` notification.
**How to avoid:** For export counts, count locally-created items since the last sync cycle: items where `originDeviceID == DeviceIdentifier.current` and `timestamp > lastSyncDate`. This represents items that WILL be exported. Alternatively, when an export event succeeds, count how many local items have `timestamp > previousExportEndDate`.
**Warning signs:** Status always showing "arrow-down 42 arrow-up 0" even though items are clearly syncing to other devices.

## Code Examples

### Existing SyncMonitor Event Handler (current code, for reference)
```swift
// Source: Pastel/Services/SyncMonitor.swift (current implementation)
private func handleSyncChange(hasEnded: Bool, errorMessage: String?) {
    if !hasEnded {
        syncedWorkItem?.cancel()
        syncedWorkItem = nil
        state = .syncing
    } else if let errorMessage {
        syncedWorkItem?.cancel()
        syncedWorkItem = nil
        state = .error(errorMessage)
    } else {
        // Debounce transition to .synced (1s)
        syncedWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state = .synced
        }
        syncedWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }
}
```

### Enhanced Event Handler (proposed)
```swift
// Source: Research synthesis -- NSPersistentCloudKitContainer.Event + CKError APIs
private func handleSyncEvent(_ notification: Notification) {
    guard let event = notification.userInfo?[
        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
    ] as? NSPersistentCloudKitContainer.Event else { return }

    let eventType = event.type  // .setup | .import | .export

    if event.endDate == nil {
        // Event started -- update active state
        syncedWorkItem?.cancel()
        syncedWorkItem = nil

        switch eventType {
        case .setup:
            state = .syncing(phase: .setup)
        case .import:
            state = .syncing(phase: .importing(isInitial: !hasCompletedFirstImport))
            if preImportItemCount == 0 {
                preImportItemCount = currentItemCount()
            }
        case .export:
            state = .syncing(phase: .exporting)
        @unknown default:
            state = .syncing(phase: .importing(isInitial: false))
        }
    } else if let error = event.error {
        syncedWorkItem?.cancel()
        syncedWorkItem = nil
        state = .error(friendlyErrorMessage(from: error))
        logger.warning("Sync error (\(String(describing: eventType))): \(error.localizedDescription)")
    } else {
        // Event completed successfully
        if eventType == .import {
            let postCount = currentItemCount()
            lastImportedCount = max(0, postCount - preImportItemCount)
            preImportItemCount = 0
            hasCompletedFirstImport = true
        } else if eventType == .export {
            lastExportedCount = countLocalItemsSince(lastExportEndDate)
            lastExportEndDate = event.endDate
        }
        lastSyncDate = event.endDate

        // Debounce transition to .synced
        scheduleTransitionToSynced()
    }
}
```

### Existing RelativeDateTimeFormatter Pattern (from ClipboardCardView)
```swift
// Source: Pastel/Views/Panel/ClipboardCardView.swift line 309
private static let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated  // "3 min. ago"
    return f
}()
```

### CKError User-Friendly Mapping
```swift
// Source: CKError.Code Apple documentation
// Most relevant errors for a sync status display:
//
// .networkUnavailable / .networkFailure  -> "No internet connection"
// .notAuthenticated                      -> "Not signed in to iCloud"
// .quotaExceeded                         -> "iCloud storage full"
// .serviceUnavailable                    -> "iCloud temporarily unavailable"
// .requestRateLimited / .zoneBusy        -> "iCloud busy -- will retry"
// .partialFailure                        -> Check inner errors for specifics
// anything else                          -> Truncated localizedDescription
```

### SyncSettingsView Enhanced Status (proposed structure)
```swift
// Source: Research synthesis -- CONTEXT.md decisions
case .synced:
    VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
            Circle().fill(.green).frame(width: 8, height: 8)
            Text(statusText)        // "Fully up to date" or "Fully up to date (↓42 ↑18 last sync)"
                .foregroundStyle(.secondary)
        }
        if let lastSynced = lastSyncedText {
            Text("Last synced: \(lastSynced)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 16)  // Align under text, past the dot
        }
    }

case .syncing(let phase):
    HStack(spacing: 8) {
        Circle().fill(.orange).frame(width: 8, height: 8)
            .opacity(isPulsing ? 0.3 : 1.0)
            // ... existing pulsing animation
        VStack(alignment: .leading) {
            Text(syncingText(for: phase))  // "Importing..." or "Initial sync: Importing..." or "Exporting..."
            if importCount > 0 || exportCount > 0 {
                Text(countsText)           // "↓42 ↑18"
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

case .error(let message):
    HStack(spacing: 8) {
        Circle().fill(.red).frame(width: 8, height: 8)
        Text("Sync error: \(message)")
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Generic "Syncing..." for all events | Typed import/export/setup display | NSPersistentCloudKitContainer.EventType (macOS 11+) | Can distinguish sync phases in UI |
| Raw error.localizedDescription | CKError.code switch to user-friendly messages | Best practice since CKError introduction | Users see actionable error messages |
| CloudKitSyncMonitor SPM package (full featured) | Custom ~100-line SyncMonitor with enhanced metadata | Project decision | No external dependency; tailored to exact needs |
| SwiftData History API (macOS 15+) for change counting | Item count diffing + remote change notifications (macOS 14+) | macOS 14 deployment target constraint | Works on target OS version |

**Deprecated/outdated:**
- `NSPersistentCloudKitContainer.Event.succeeded` -- while documented, some community reports suggest this property is not always reliable for determining success. Checking `endDate != nil && error == nil` is the safer pattern.

## Open Questions

1. **Export count accuracy**
   - What we know: Export events do not change local item count and there is no per-record export callback. The Event API has no record count property.
   - What's unclear: Whether counting local items created since the last sync is an accurate proxy for "exported items."
   - Recommendation: For the initial implementation, count items with `originDeviceID == DeviceIdentifier.current` and `timestamp > lastExportEndDate`. If the number seems inaccurate in testing, consider showing only the import count (which is reliably measurable via count diff) and omitting export count when it would be zero.

2. **Setup event suppression after first sync**
   - What we know: Setup events fire on every app launch. The first setup on a fresh install is meaningful; subsequent ones complete in < 1 second.
   - What's unclear: The exact threshold for "meaningful" setup duration.
   - Recommendation: Show "Setting up..." only if the setup event has been in-progress for > 2 seconds. Otherwise skip directly to import/export state. This avoids a brief flash of "Setting up..." on every launch while still showing it during genuine first-time setup.

3. **Overlapping import and export events**
   - What we know: Import and export events can overlap -- an export may start while an import is still running.
   - What's unclear: The exact display priority when both are active simultaneously.
   - Recommendation: Show import state in preference to export (importing is more "interesting" to the user since it means new content is arriving). Only show exporting if no import is active. Track both states independently.

4. **Count diff includes dedup deletions**
   - What we know: DeduplicationService runs 3 seconds after NSPersistentStoreRemoteChange and may delete duplicate items, reducing the count.
   - What's unclear: Whether the item count diff will be taken before or after dedup runs.
   - Recommendation: Take the post-import count immediately when the import Event ends (before the 3-second dedup debounce fires). This captures the gross import count before dedup reduces it.

## Sources

### Primary (HIGH confidence)
- [NSPersistentCloudKitContainer.Event](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/event) -- Event properties: type, startDate, endDate, succeeded, error, storeIdentifier
- [NSPersistentCloudKitContainer.EventType](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/eventtype) -- `.setup`, `.import`, `.export` enum cases
- [CKError.Code](https://developer.apple.com/documentation/cloudkit/ckerror/code) -- All 33 error codes for user-friendly mapping
- [RelativeDateTimeFormatter](https://developer.apple.com/documentation/foundation/relativedatetimeformatter) -- Locale-aware relative time formatting (macOS 10.15+)
- [SwiftData HistoryTransaction](https://developer.apple.com/documentation/swiftdata/historytransaction) -- macOS 15+ only; NOT usable for this project's macOS 14 target
- Codebase: `Pastel/Services/SyncMonitor.swift` -- Existing event handler pattern with debouncing
- Codebase: `Pastel/Views/Settings/SyncSettingsView.swift` -- Existing status display with green/orange/red dots
- Codebase: `Pastel/Views/Panel/ClipboardCardView.swift` -- Existing `RelativeDateTimeFormatter` usage

### Secondary (MEDIUM confidence)
- [CloudKitSyncMonitor source code](https://github.com/ggruen/CloudKitSyncMonitor/blob/main/Sources/CloudKitSyncMonitor/SyncMonitor.swift) -- Per-type state tracking pattern (setupState/importState/exportState)
- [CrunchyBagel: NSPersistentCloudKitContainer findings](https://crunchybagel.com/nspersistentcloudkitcontainer/) -- Confirms Event does NOT have record counts; multiple consecutive events of same type are common
- [fatbobman: Core Data CloudKit troubleshooting](https://fatbobman.com/en/posts/coredatawithcloudkit-4/) -- Event lifecycle and debugging patterns
- [fatbobman: Persistent History Tracking in SwiftData](https://fatbobman.com/en/posts/persistent-history-tracking-in-swiftdata/) -- Transaction author filtering; warns against manually managing CloudKit's persistent history
- Phase 21 Research (`.planning/phases/21-sync-controls-deduplication-and-status/21-RESEARCH.md`) -- SyncMonitor architecture, debounce patterns, pitfalls
- Phase 20 Research (`.planning/phases/20-cloudkit-infrastructure-and-sync-engine/20-RESEARCH.md`) -- CloudKit infrastructure decisions

### Tertiary (LOW confidence)
- Item count diffing approach for import/export counts -- no official documentation; custom approach derived from API limitations. Needs validation in testing.
- Setup event timing threshold (2 seconds) -- arbitrary threshold based on observed behavior. May need tuning.

## Metadata

**Confidence breakdown:**
- Event type extraction (setup/import/export): HIGH -- well-documented API, verified across multiple sources
- RelativeDateTimeFormatter usage: HIGH -- already in the codebase, standard Apple API
- Error message mapping (CKError -> friendly text): HIGH -- CKError.Code is a well-documented enum
- Import count via item diffing: MEDIUM -- logical approach but not documented as a pattern; needs testing for accuracy
- Export count estimation: LOW -- no reliable mechanism; best-effort proxy using local item timestamps
- Initial sync detection: MEDIUM -- simple in-memory flag approach is reliable per-session but resets on restart (which matches CONTEXT.md)
- Setup event suppression: MEDIUM -- threshold-based approach is pragmatic but the 2-second value is untested

**Research date:** 2026-02-22
**Valid until:** 2026-03-22 (stable APIs, no fast-moving changes expected)
