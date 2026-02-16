# Phase 21: Sync Controls, Deduplication, and Status - Research

**Researched:** 2026-02-15
**Domain:** SwiftUI Settings UI, CloudKit sync monitoring, cross-device deduplication, app restart
**Confidence:** HIGH

## Summary

Phase 21 completes the v1.5 iCloud Sync milestone by adding user-facing controls. Three distinct subsystems are needed: (1) a new "iCloud Sync" settings tab with toggle, status display, and help popover; (2) a DeduplicationService that merges duplicate items arriving from CloudKit; and (3) a SyncMonitor that observes `NSPersistentCloudKitContainer.eventChangedNotification` to expose sync state.

The existing codebase provides strong foundations: the conditional ModelContainer (Phase 20-01) already reads `UserDefaults iCloudSyncEnabled`, the settings window already uses a tab-based layout with glass buttons, and the ClipboardItem model already has `contentHash` and `originDeviceID` fields ready for dedup. The primary technical challenges are: (a) iCloud email is NOT accessible via CloudKit APIs (privacy restriction), requiring a design adjustment; (b) app restart requires spawning a shell process before termination; and (c) dedup must handle CloudKit's eventual consistency model where items arrive asynchronously.

**Primary recommendation:** Build a custom ~60-line SyncMonitor using `NSPersistentCloudKitContainer.eventChangedNotification` (no external dependency), trigger dedup via `NSPersistentStoreRemoteChange` notifications, and use the shell-based `open` + `NSApp.terminate` pattern for restart.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Tab label: "iCloud Sync" (matches macOS convention -- iCloud Drive, iCloud Photos)
- Toggle label: "iCloud Sync" with a brief description below
- Show connected iCloud account email address below the toggle
- Show sync status with color dot: green = healthy, red = error
- "?" (help) icon next to the status section opens a popover/tooltip explaining what syncs/doesn't sync and current device name
- No separate device list -- keep the tab minimal
- Toggle change triggers a modal alert sheet (not inline banner) -- blocking and clear
- Alert has two actions: "Restart Now" and "Later"
- "Restart Now" quits and relaunches the app immediately via NSWorkspace.shared.open()
- Prompt appears every time the toggle changes, even if user flips it back to original state
- Sync status lives only in the Settings Sync tab -- no changes to menu bar icon or panel header
- Silence = success: no persistent indicator when sync is working normally
- Status indicator only surfaces when actively syncing or error/offline
- Dedup is completely silent in production -- no user-facing notifications
- Console/debug logging of merge events for development debugging
- Conflict resolution: local device's version wins (not earliest timestamp)
- Label conflict resolution: merge (union) -- all labels from both devices are kept
- Dedup triggered when CloudKit delivers a new item whose contentHash matches an existing local item

### Claude's Discretion
- Exact modal alert copy (wording of restart prompt)
- Status dot animation when actively syncing (pulsing vs static)
- Debounce timing for sync status updates
- DeduplicationService architecture (polling vs CloudKit notification trigger)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

## Standard Stack

### Core (already in project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData | macOS 14+ | Data persistence + CloudKit sync | Already the app's persistence layer |
| SwiftUI | macOS 14+ | Settings tab UI | Already used for all settings views |
| CloudKit | macOS 14+ | Sync infrastructure | Already linked in Phase 20-01 |
| CoreData | macOS 14+ | `NSPersistentCloudKitContainer.Event` access | Needed for sync event notifications |

### Supporting (system frameworks, no new dependencies)
| Library | Purpose | When to Use |
|---------|---------|-------------|
| `SystemConfiguration` (SCDynamicStore) | Get device computer name safely | For help popover device name display |
| `OSLog` | Structured logging for dedup events | Debug logging of merge operations |
| `CryptoKit` | SHA256 hashing | Already used for contentHash in ClipboardMonitor |

### No New Dependencies
The custom sync monitor (~60 lines) is simpler and more maintainable than adding the CloudKitSyncMonitor SPM package (which has 500+ lines, NWPathMonitor network monitoring, and features not needed here). The CONTEXT.md decision for "custom sync monitor" aligns with this.

## Architecture Patterns

### Recommended Project Structure
```
Pastel/
├── Services/
│   ├── SyncMonitor.swift          # NEW: Observes CloudKit sync events
│   └── DeduplicationService.swift # NEW: Cross-device dedup by contentHash
├── Views/Settings/
│   ├── SettingsView.swift         # MODIFIED: Add .iCloudSync tab case
│   └── SyncSettingsView.swift     # NEW: iCloud Sync tab content
└── Utilities/
    └── AppRelaunchService.swift   # NEW: Shell-based quit + relaunch
```

### Pattern 1: SyncMonitor via NotificationCenter
**What:** An @Observable class that subscribes to `NSPersistentCloudKitContainer.eventChangedNotification` and `CKAccountChanged`, then exposes a high-level sync state enum.
**When to use:** Always when sync is enabled -- initialized at app launch.
**Architecture:**

```swift
// Source: Apple TN3164, CloudKitSyncMonitor patterns
@MainActor
@Observable
final class SyncMonitor {
    enum SyncState {
        case disabled
        case synced
        case syncing
        case error(String)
        case accountUnavailable
    }

    var state: SyncState = .disabled

    private var eventObserver: Any?
    private var accountObserver: Any?

    func startMonitoring() {
        // 1. Subscribe to sync events
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSyncEvent(notification)
        }

        // 2. Subscribe to account changes
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAccountStatus()
            }
        }

        // 3. Initial account check
        Task { await checkAccountStatus() }
    }

    private func handleSyncEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else { return }

        if event.endDate == nil {
            // Event in progress
            state = .syncing
        } else if let error = event.error {
            state = .error(error.localizedDescription)
        } else {
            state = .synced
        }
    }

    private func checkAccountStatus() async {
        let status = try? await CKContainer(
            identifier: "iCloud.app.pastel.Pastel"
        ).accountStatus()
        if status != .available {
            state = .accountUnavailable
        }
    }
}
```

### Pattern 2: Deduplication via Remote Change Notification
**What:** A service that listens for `NSPersistentStoreRemoteChange` notifications (fired when CloudKit delivers new records) and deduplicates items by contentHash.
**When to use:** Only when sync is enabled.
**Key insight:** SwiftData automatically enables `NSPersistentStoreRemoteChangeNotificationPostOptionKey` when using CloudKit. The notification fires after CloudKit imports new records, which is the ideal trigger for dedup.

```swift
// Source: Apple WWDC, Core Data + CloudKit deduplication patterns
@MainActor
final class DeduplicationService {
    private var observer: Any?
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "app.pastel.Pastel", category: "Dedup")

    func startMonitoring() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.deduplicateItems()
            }
        }
    }

    private func deduplicateItems() {
        // Fetch items grouped by contentHash where count > 1
        // For each group: keep local device's item, merge labels, delete duplicates
    }
}
```

### Pattern 3: App Relaunch via Shell Process
**What:** Spawn a background shell process that waits briefly then opens the app bundle, followed by NSApp.terminate.
**When to use:** When user taps "Restart Now" after toggling sync.

```swift
// Source: Standard macOS relaunch pattern (cdfmr/2204627)
func relaunchApp() {
    let bundlePath = Bundle.main.bundlePath
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", "sleep 1; open \"\(bundlePath)\""]
    task.launch()
    NSApp.terminate(nil)
}
```

### Pattern 4: Adding a Settings Tab
**What:** Extend the existing `SettingsTab` enum with a new `.iCloudSync` case and add the corresponding view.
**Implementation detail:** The existing SettingsView uses a `SettingsTab` enum with `allCases`, so adding a new case automatically includes it in the tab bar.

### Anti-Patterns to Avoid
- **Do NOT use `Host.current().localizedName` on the main thread** -- it can hang for seconds when DNS is slow or the computer name contains special characters. Use `SCDynamicStoreCopyComputerName()` instead.
- **Do NOT try to get iCloud email via CloudKit APIs** -- Apple does not expose the user's iCloud email to third-party apps. Use the user's display name from `CKContainer.discoverUserIdentity` or show account status only. See "Critical Finding" below.
- **Do NOT poll for duplicates on a timer** -- wasteful and misses the event-driven nature of CloudKit imports. Use `NSPersistentStoreRemoteChange` notification instead.
- **Do NOT delete the "losing" duplicate immediately in the same save** -- SwiftData + CloudKit can cause merge conflicts. Merge label data first, then delete in a separate save pass.

## Critical Finding: iCloud Email NOT Accessible

**Confidence:** HIGH (verified across multiple official sources)

The CONTEXT.md decision says "Show connected iCloud account email address below the toggle." However, **Apple does not expose the iCloud account email to third-party apps.** This is a privacy restriction enforced at the API level.

**What IS available:**
1. `CKContainer.accountStatus()` -- returns `.available`, `.noAccount`, `.restricted`, `.couldNotDetermine`
2. `CKContainer.fetchUserRecordID()` -- returns an opaque record ID (NOT email)
3. `CKContainer.discoverUserIdentity(withUserRecordID:)` -- returns `nameComponents` (given name + family name) but requires `.userDiscoverability` permission and the user must have opted in to discoverability

**Recommendation for the planner:**
- Show "iCloud Account: [Name]" using `discoverUserIdentity` if available
- Fall back to "iCloud Account: Available" with a green checkmark if name is not discoverable
- Show "iCloud Account: Not signed in" if account status is `.noAccount`
- This preserves the user's intent (confidence they're syncing to the right account) while respecting Apple's privacy model

**Sources:**
- [Apple Developer Forums - Check which Apple ID is logged in](https://developer.apple.com/forums/thread/89129)
- [CKContainer API Documentation](https://developer.apple.com/documentation/cloudkit/ckcontainer)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sync event parsing | Custom CloudKit notification parsing | `NSPersistentCloudKitContainer.Event` from notification userInfo | Apple provides the Event object with type/startDate/endDate/error |
| App restart | Custom IPC or XPC service | Shell `Process` with `/bin/sh -c "sleep 1; open bundlePath"` | Simple, proven pattern; no helper binary needed |
| Device name | `Host.current().localizedName` | `SCDynamicStoreCopyComputerName()` | Host.current() can hang; SCDynamicStore is immediate |
| Content hashing | Custom hash function | `CryptoKit SHA256` | Already used in ClipboardMonitor; consistent hashing |
| Account status monitoring | Polling CKContainer | `NotificationCenter.default + .CKAccountChanged` | System-level notification, zero polling overhead |

**Key insight:** CloudKit + SwiftData provide all the event hooks needed (eventChangedNotification, NSPersistentStoreRemoteChange, CKAccountChanged). The entire monitoring infrastructure is notification-driven with zero polling.

## Common Pitfalls

### Pitfall 1: Dedup Race Condition with CloudKit Imports
**What goes wrong:** CloudKit may deliver the same record multiple times during initial sync or conflict resolution. If dedup runs during an active import, it may process incomplete data or cause save conflicts.
**Why it happens:** `NSPersistentStoreRemoteChange` fires per batch, not per complete sync cycle. Multiple notifications arrive in rapid succession.
**How to avoid:** Debounce the dedup trigger (e.g., 2-3 second delay after last notification). Process dedup on the main context after imports settle.
**Warning signs:** Duplicate items appearing briefly then disappearing, or dedup removing items that were in the process of being updated.

### Pitfall 2: SwiftData Save Conflicts During Dedup
**What goes wrong:** Deleting a duplicate item while CloudKit is still processing related changes can cause merge conflicts or crashes.
**Why it happens:** SwiftData's CloudKit integration uses its own merge policies. Manual deletes can conflict with incoming CloudKit changes.
**How to avoid:** In the dedup method: (1) fetch duplicates, (2) merge labels onto the keeper, (3) save the merge, (4) THEN delete duplicates in a separate operation. Never merge + delete in one save.
**Warning signs:** `NSCocoaErrorDomain` merge conflict errors in console logs.

### Pitfall 3: SyncMonitor State Thrashing
**What goes wrong:** The status indicator rapidly flickers between "Syncing..." and "Synced" as multiple setup/import/export events fire.
**Why it happens:** CloudKit fires separate events for setup, import, and export. Each event has its own start/end notifications. During a normal sync cycle, you can get 6+ notifications in seconds.
**How to avoid:** Debounce state updates. Only show "Syncing..." if an event has been in-progress for >0.5s. Only show "Synced" after all event types have completed.
**Warning signs:** Green/orange dot flickering rapidly when sync is actually healthy.

### Pitfall 4: Restart Loop if UserDefaults Write Fails
**What goes wrong:** If the app terminates before UserDefaults persists the toggle change, the app relaunches with the old setting.
**Why it happens:** `UserDefaults.standard.set()` is asynchronous. `NSApp.terminate()` called immediately after may not flush.
**How to avoid:** Call `UserDefaults.standard.synchronize()` before spawning the relaunch process. Or better: write the UserDefaults value on toggle change (before showing the alert), not on restart.
**Warning signs:** App restarts but sync state hasn't changed.

### Pitfall 5: iCloud Account Status Changes
**What goes wrong:** User signs out of iCloud while app is running. Sync silently fails. No error shown.
**Why it happens:** CKAccountChanged notification may not arrive promptly. If not monitored, the UI shows stale "Synced" state.
**How to avoid:** Subscribe to `.CKAccountChanged` notification in SyncMonitor. Check account status on notification and update state to `.accountUnavailable` when not `.available`.
**Warning signs:** Settings shows "Synced" but no items are actually syncing.

### Pitfall 6: Dedup Deleting the Wrong Item
**What goes wrong:** Dedup keeps the remote item (which may have less metadata) and deletes the richer local item.
**Why it happens:** Not checking `originDeviceID` when deciding which item to keep.
**How to avoid:** The CONTEXT.md decision is "local device's version wins." Always keep the item where `originDeviceID == DeviceIdentifier.current`. If both are remote (synced from two other devices), keep the one with more labels or earlier timestamp.
**Warning signs:** Items losing their local-only metadata (source app name, image paths) after sync.

## Code Examples

### Getting Device Name Safely
```swift
// Source: SystemConfiguration framework
import SystemConfiguration

func getComputerName() -> String {
    // SCDynamicStoreCopyComputerName is synchronous and safe on main thread
    guard let name = SCDynamicStoreCopyComputerName(nil, nil) as String? else {
        return ProcessInfo.processInfo.hostName
    }
    return name
}
```

### Checking iCloud Account Status
```swift
// Source: Apple CKContainer documentation
import CloudKit

func checkiCloudStatus() async -> (available: Bool, name: String?) {
    let container = CKContainer(identifier: "iCloud.app.pastel.Pastel")

    guard let status = try? await container.accountStatus(),
          status == .available else {
        return (false, nil)
    }

    // Try to get user name (requires discoverability permission)
    if let recordID = try? await container.fetchUserRecordID(),
       let identity = try? await container.discoverUserIdentity(
           withUserRecordID: recordID
       ) {
        let name = identity.nameComponents.flatMap {
            PersonNameComponentsFormatter().string(from: $0)
        }
        return (true, name)
    }

    return (true, nil)
}
```

### Modal Alert Sheet Pattern (existing app pattern)
```swift
// Source: GeneralSettingsView.swift clear history alert
.alert("Restart Required", isPresented: $showingRestartAlert) {
    Button("Restart Now") {
        AppRelaunchService.relaunch()
    }
    Button("Later", role: .cancel) {}
} message: {
    Text("Pastel needs to restart to apply the sync change. Your clipboard history will be preserved.")
}
```

### Extracting Event from Sync Notification
```swift
// Source: Apple TN3164, NSPersistentCloudKitContainer documentation
import CoreData

func handleSyncEvent(_ notification: Notification) {
    guard let event = notification.userInfo?[
        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
    ] as? NSPersistentCloudKitContainer.Event else { return }

    // Event properties:
    // - event.type: .setup | .import | .export
    // - event.startDate: Date (always present)
    // - event.endDate: Date? (nil = in progress)
    // - event.succeeded: Bool (only meaningful when endDate != nil)
    // - event.error: Error? (present on failure)
    // - event.storeIdentifier: String
}
```

### Dedup Query Pattern
```swift
// Source: Adapted from existing ClipboardMonitor.isDuplicateByHash
func findDuplicateGroups(modelContext: ModelContext) -> [[ClipboardItem]] {
    let descriptor = FetchDescriptor<ClipboardItem>(
        sortBy: [SortDescriptor(\.timestamp, order: .forward)]
    )
    guard let allItems = try? modelContext.fetch(descriptor) else { return [] }

    // Group by contentHash
    var hashGroups: [String: [ClipboardItem]] = [:]
    for item in allItems where !item.contentHash.isEmpty {
        hashGroups[item.contentHash, default: []].append(item)
    }

    // Return only groups with duplicates
    return hashGroups.values.filter { $0.count > 1 }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CloudKitSyncMonitor SPM package | Custom ~60-line SyncMonitor | Project decision (CONTEXT.md) | No external dependency; simpler code |
| `@Attribute(.unique)` for dedup | Application-level hash dedup | Phase 19 (CloudKit incompatibility) | Already implemented in ClipboardMonitor |
| `Host.current().localizedName` | `SCDynamicStoreCopyComputerName` | Known hang issue documented | Prevents main thread hangs |
| iCloud email display | Account name via discoverUserIdentity | Apple privacy restriction | Cannot show email; show name instead |

**Deprecated/outdated:**
- `NSWorkspace.shared.launchApplication(_:)` -- deprecated in favor of `NSWorkspace.shared.open(_:configuration:completionHandler:)` for URL-based launching. However, for the relaunch pattern, the shell `Process` approach is more reliable since the app is terminating.

## Open Questions

1. **discoverUserIdentity permission prompt**
   - What we know: Getting the user's name requires `.userDiscoverability` permission, which shows a system dialog
   - What's unclear: Whether a clipboard manager should trigger this dialog just to show a name in Settings
   - Recommendation: Try fetching without showing a permission dialog first. If the name is available (user previously granted permission to another app), show it. Otherwise, fall back to "iCloud: Available" without prompting. Do NOT proactively request the permission.

2. **Dedup timing on first sync**
   - What we know: When a user enables sync for the first time on a second device, all existing items from the first device arrive at once
   - What's unclear: How many `NSPersistentStoreRemoteChange` notifications fire during bulk import (one per batch? one per record?)
   - Recommendation: Debounce dedup to run 3 seconds after the last remote change notification. This handles both trickle and bulk imports.

3. **Success criteria mismatch: "earliest timestamp kept" vs "local device's version wins"**
   - What we know: The roadmap success criteria says "earliest timestamp kept" but CONTEXT.md says "local device's version wins"
   - What's unclear: These can conflict (remote item may have earlier timestamp)
   - Recommendation: Follow CONTEXT.md (local wins). The planner should note this discrepancy and clarify with the user if needed. CONTEXT.md decisions override roadmap defaults.

## Sources

### Primary (HIGH confidence)
- [NSPersistentCloudKitContainer.Event](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/event) -- Event properties (type, startDate, endDate, error)
- [TN3164: Debugging NSPersistentCloudKitContainer](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer) -- Sync debugging and event monitoring
- [CKContainer.accountStatus()](https://developer.apple.com/documentation/cloudkit/ckcontainer/1399180-accountstatus) -- Account availability checking
- [Apple Developer Forums: iCloud email access](https://developer.apple.com/forums/thread/89129) -- Confirms email is not accessible
- Codebase: `Pastel/PastelApp.swift` -- Conditional ModelContainer with `iCloudSyncEnabled` UserDefaults key
- Codebase: `Pastel/Services/ClipboardMonitor.swift` -- Existing `isDuplicateByHash` pattern
- Codebase: `Pastel/Views/Settings/SettingsView.swift` -- Existing tab pattern with SettingsTab enum

### Secondary (MEDIUM confidence)
- [CloudKitSyncMonitor source code](https://github.com/ggruen/CloudKitSyncMonitor/blob/main/Sources/CloudKitSyncMonitor/SyncMonitor.swift) -- Reference implementation for sync state derivation
- [CrunchyBagel: NSPersistentCloudKitContainer findings](https://crunchybagel.com/nspersistentcloudkitcontainer/) -- Event lifecycle (start/end notifications)
- [GitHub Gist: Cocoa app relaunch](https://gist.github.com/cdfmr/2204627) -- Shell-based relaunch pattern
- [Fatbobman: Real-time switching of cloud sync status](https://fatbobman.com/en/posts/real-time-switching-of-cloud-syncs-status/) -- Dual container architecture reference

### Tertiary (LOW confidence)
- [Apple Developer Forums: SwiftData + CloudKit dedup](https://developer.apple.com/forums/thread/745329) -- Community patterns for dedup (not official guidance)
- [Swift Forums: Host.current() hang](https://forums.swift.org/t/grabbing-mac-computer-name-through-c-interop-hangs/68468) -- Host.current() blocking behavior reports

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all system frameworks, no new dependencies, patterns verified in codebase
- Architecture: HIGH -- SyncMonitor pattern well-documented by Apple and community; dedup follows existing codebase patterns
- Pitfalls: HIGH -- CloudKit sync pitfalls extensively documented; iCloud email limitation verified across multiple official sources
- Settings UI: HIGH -- follows existing tab pattern exactly; SettingsTab enum is straightforward to extend
- App restart: MEDIUM -- shell Process pattern is common but less well-documented officially; verified via community sources
- iCloud account info: HIGH -- confirmed that email is NOT accessible; name requires permission

**Research date:** 2026-02-15
**Valid until:** 2026-03-15 (stable APIs, no fast-moving changes expected)
