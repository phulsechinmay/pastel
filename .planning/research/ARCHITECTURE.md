# Architecture Research: v1.5 iCloud Sync

**Domain:** iCloud sync integration into existing macOS clipboard manager
**Researched:** 2026-02-14
**Confidence:** HIGH for core approach (SwiftData built-in CloudKit), MEDIUM for implementation details (toggle mechanism, dedup timing)

## Confidence Note

Core architecture decisions are verified against Apple's official documentation, multiple independent guides (fatbobman, Hacking with Swift, Kodeco), and open-source reference implementations. Data model requirements (no unique constraints, optional relationships, default values) are universally documented and consistent across all sources. macOS-specific pitfalls (CloudKit.framework linking) are confirmed by both fatbobman and Apple Developer Forums. The transactionAuthor filtering approach is verified via fatbobman's persistent history tracking guide. Areas of MEDIUM/LOW confidence are explicitly marked.

---

## Existing Architecture Summary (Current State)

```
PastelApp (@main)
    |
    +-- ModelContainer (SwiftData: ClipboardItem, Label)
    |       NO CloudKit configuration
    |       Created with default ModelConfiguration
    |
    +-- AppState (@Observable, @MainActor)
    |       |-- ClipboardMonitor (Timer polling -> classify -> deduplicate -> SwiftData insert)
    |       |       contentHash uses @Attribute(.unique) for dedup
    |       |-- PanelController (NSPanel lifecycle, show/hide)
    |       |-- PasteService (pasteboard write + CGEvent Cmd+V)
    |       |-- RetentionService (hourly purge based on retention days)
    |       `-- modelContainer reference
    |
    +-- Models
    |       |-- ClipboardItem (@Model: 20+ fields, contentHash @Attribute(.unique),
    |       |                   labels: [Label] non-optional relationship)
    |       |-- Label (@Model: name, colorName, emoji, sortOrder,
    |       |          items: [ClipboardItem] non-optional inverse)
    |       `-- ContentType (enum: text, richText, url, image, file, code, color)
    |
    +-- Services
    |       |-- ClipboardMonitor (0.5s polling, SHA256 hashing, skipNextChange)
    |       |-- ImageStorageService (PNG on disk, thumbnails)
    |       |-- RetentionService (hourly purge)
    |       |-- ImportExportService (.pastel JSON export/import)
    |       |-- PasteService, ExpirationService, MigrationService
    |       `-- CodeDetectionService, ColorDetectionService, URLMetadataService
    |
    +-- Entitlements
            com.apple.security.app-sandbox = true
            com.apple.security.network.client = true
            com.apple.security.files.user-selected.read-write = true
```

---

## Recommended Architecture: SwiftData Built-in CloudKit Sync

### Why This Approach

Use SwiftData's native CloudKit integration via `ModelConfiguration(cloudKitDatabase:)` rather than building a custom sync engine with `CKSyncEngine`. SwiftData wraps `NSPersistentCloudKitContainer` under the hood, which automatically mirrors the local SwiftData store to the user's private CloudKit database.

**How it works:**
- Local writes happen instantly (local-first, unchanged from current behavior)
- NSPersistentCloudKitContainer automatically queues changed records for CloudKit export
- CloudKit sends silent push notifications to other devices when records change
- Other devices fetch changed records and merge into local SwiftData store
- @Query views auto-refresh when merged data appears
- Conflict resolution is last-writer-wins at the attribute level (built-in)

**Why NOT CKSyncEngine:** CKSyncEngine is designed for apps that bring their own persistence layer (not SwiftData/CoreData). Pastel already uses SwiftData, so the built-in integration is the correct and only sensible path. CKSyncEngine would require reimplementing the entire persistence-to-CloudKit bridge -- massive effort for zero benefit.

**Confidence: HIGH** -- Apple's official documentation and every authoritative source confirms this is the intended approach for SwiftData apps.

### System Diagram (Post-Sync)

```
Mac A (local capture)                      Mac B (receives sync)
+-------------------+                      +-------------------+
| ClipboardMonitor  |                      | ClipboardMonitor  |
| (polls NSPaste-   |                      | (polls NSPaste-   |
|  board 0.5s)      |                      |  board 0.5s)      |
| author="app"      |                      | author="app"      |
+--------+----------+                      +--------+----------+
         |                                          |
         v                                          v
+--------+----------+                      +--------+----------+
| SwiftData         |                      | SwiftData         |
| ModelContext       |                      | ModelContext       |
| (mainContext)      |                      | (mainContext)      |
+--------+----------+                      +--------+----------+
         |                                          ^
         v                                          |
+--------+----------+  iCloud Private DB   +--------+----------+
| NSPersistent-     |====================> | NSPersistent-     |
| CloudKitContainer |  (auto export)       | CloudKitContainer |
| (under SwiftData) |                      | (auto import)     |
+--------+----------+                      +--------+----------+
         |                                          |
         v                                          v
+--------+----------+                      +--------+----------+
| SyncMonitor-      |                      | SyncMonitor-      |
|  Service (NEW)    |                      |  Service (NEW)    |
| (event observer)  |                      | (event observer)  |
+-------------------+                      +--------+----------+
                                                    |
                                                    v
                                           +--------+----------+
                                           | Deduplication-    |
                                           |  Service (NEW)    |
                                           | (remote change    |
                                           |  handler)         |
                                           +-------------------+
```

### Data Flow: Complete Sync Lifecycle

**1. Local Capture (unchanged path):**
```
NSPasteboard.general changed
    -> ClipboardMonitor.checkForChanges()
    -> processPasteboardContent()
    -> item = ClipboardItem(...)
    -> item.originDeviceID = DeviceIdentifier.current  // NEW
    -> item.isSynced = false  // NEW
    -> modelContext.insert(item)
    -> modelContext.save()
    -> SwiftData persists locally
    -> NSPersistentCloudKitContainer auto-queues for CloudKit export
```

**2. Export to Cloud (automatic, zero code):**
```
NSPersistentCloudKitContainer detects local save
    -> Serializes changed CKRecords
    -> Pushes to CloudKit private database
    -> Posts eventChangedNotification (.export)
    -> SyncMonitorService updates exportState
```

**3. Remote Notification & Import (automatic, zero code):**
```
CloudKit sends silent push to Mac B
    -> NSPersistentCloudKitContainer on Mac B wakes
    -> Fetches changed CKRecords from CloudKit
    -> Merges into local SwiftData store (last-writer-wins)
    -> Posts .NSPersistentStoreRemoteChange notification
    -> Posts eventChangedNotification (.import)
    -> @Query views auto-refresh (items appear in panel)
    -> SyncMonitorService updates importState
```

**4. Deduplication (new code):**
```
.NSPersistentStoreRemoteChange notification fires
    -> DeduplicationService.handleRemoteChanges()
    -> Scan for duplicate contentHash values
    -> Keep earliest timestamp item
    -> Merge labels from duplicates onto keeper
    -> Delete duplicates
    -> modelContext.save()
```

---

## Critical Data Model Changes

### Change 1: Remove @Attribute(.unique) from contentHash

**This is the single most impactful change in the entire sync integration.**

CloudKit does not support atomic uniqueness checks across devices. The `@Attribute(.unique)` on `contentHash` MUST be removed. Every authoritative source confirms this.

```swift
// BEFORE (current -- line 49 of ClipboardItem.swift)
@Attribute(.unique) var contentHash: String

// AFTER (CloudKit-compatible)
var contentHash: String = ""
```

**What this breaks:** Currently, if the same content is copied twice (non-consecutively), the unique constraint causes a save error which ClipboardMonitor handles gracefully by rolling back. Without the constraint, duplicates would be inserted.

**Mitigation:** The existing `isDuplicateOfMostRecent()` check handles consecutive dupes. For non-consecutive dupes, the DeduplicationService handles duplicates that arrive via CloudKit sync. For local non-consecutive dupes, add an application-level check:

```swift
// In ClipboardMonitor.processPasteboardContent(), replace the save/catch:
// Check for existing item with same hash (replaces @Attribute(.unique) behavior)
let existingDescriptor = FetchDescriptor<ClipboardItem>(
    predicate: #Predicate<ClipboardItem> { item in
        item.contentHash == contentHash
    }
)
if let existingCount = try? modelContext.fetchCount(existingDescriptor),
   existingCount > 0 {
    // Non-consecutive duplicate -- update timestamp of existing
    return
}
```

**Confidence: HIGH** -- Universal requirement. The contentHash-based dedup approach matches Apple's recommended pattern from the CoreDataCloudKitShare sample.

### Change 2: Default Values for All Non-Optional Properties

CloudKit requires all properties to be optional or have default values. Analysis of current model:

**ClipboardItem changes needed:**

| Property | Current | Fix |
|----------|---------|-----|
| `contentType` | `String` (set in init) | Add `= "text"` default |
| `timestamp` | `Date` (set in init) | Add `= Date()` default |
| `characterCount` | `Int` (set in init) | Add `= 0` default |
| `byteCount` | `Int` (set in init) | Add `= 0` default |
| `changeCount` | `Int` (set in init) | Add `= 0` default |
| `isConcealed` | `Bool` (set in init) | Add `= false` default |
| `contentHash` | `String` (set in init, unique) | Add `= ""`, remove unique |

Properties already CloudKit-compatible (optional or have defaults): `textContent`, `htmlContent`, `rtfData`, `sourceAppBundleID`, `sourceAppName`, `imagePath`, `thumbnailPath`, `expiresAt`, `label`, `title`, `detectedLanguage`, `detectedColorHex`, `urlTitle`, `urlFaviconPath`, `urlPreviewImagePath`, `urlMetadataFetched`.

**Label changes needed:**

| Property | Current | Fix |
|----------|---------|-----|
| `name` | `String` (set in init) | Add `= ""` default |
| `colorName` | `String` (set in init) | Add `= "blue"` default |
| `sortOrder` | `Int` (set in init) | Add `= 0` default |

**Confidence: HIGH** -- Straightforward requirement, well-documented.

### Change 3: Make Relationships Optional

CloudKit requires ALL relationships to be optional.

```swift
// ClipboardItem -- BEFORE
@Relationship(deleteRule: .nullify, inverse: \Label.items)
var labels: [Label]

// ClipboardItem -- AFTER
@Relationship(deleteRule: .nullify, inverse: \Label.items)
var labels: [Label]?

// Label -- BEFORE
var items: [ClipboardItem]

// Label -- AFTER
var items: [ClipboardItem]?
```

**Impact:** Every access to `.labels` and `.items` throughout the codebase needs nil-coalescing. Add convenience computed properties:

```swift
// On ClipboardItem:
var safeLabels: [Label] { labels ?? [] }

// On Label:
var safeItems: [ClipboardItem] { items ?? [] }
```

Then find-and-replace all `.labels` usage to `.safeLabels` and `.items` to `.safeItems` (except in the relationship declaration itself and the init).

**Scope of impact:** This touches ClipboardCardView, FilteredCardListView, ChipBarView, EditItemView, HistoryGridView, ImportExportService, ClipboardMonitor (for label migration), and any view that reads item labels or label items.

**Confidence: HIGH** -- Required by CloudKit. The `safeLabels` pattern is a clean mitigation.

### Change 4: New Fields for Sync

```swift
// Add to ClipboardItem:

/// UUID of the device that originally captured this item.
/// Generated per-device on first launch, stored in UserDefaults.
/// Used for: dedup (same content on different devices), UI badges ("from MacBook Pro"),
/// retention awareness (local vs synced items).
var originDeviceID: String = ""

/// Whether this item was synced from another device.
/// Stored (not computed) for efficient #Predicate use in @Query.
var isSynced: Bool = false

/// Whether this item should be excluded from CloudKit sync display on remote devices.
/// True for images, files, concealed items -- they sync to CloudKit (unavoidable
/// with single-store approach) but are hidden or shown as placeholders on other devices.
var syncExcluded: Bool = false
```

**Device ID implementation:**

```swift
enum DeviceIdentifier {
    private static let key = "pastelDeviceUUID"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
```

Store in UserDefaults (NOT NSUbiquitousKeyValueStore) so each device has its own unique ID that does not sync.

**Confidence: HIGH** for the need; MEDIUM for exact field design.

---

## New Components

### 1. SyncMonitorService (NEW)

**Purpose:** Observe NSPersistentCloudKitContainer events and expose sync status to UI.

```swift
import CloudKit
import CoreData
import OSLog

@MainActor
@Observable
final class SyncMonitorService {

    enum SyncState: Equatable {
        case disabled          // User has sync off
        case notStarted        // Sync enabled but hasn't run yet
        case syncing           // Import or export in progress
        case succeeded(Date)   // Last successful sync timestamp
        case failed(String)    // Error description
        case accountUnavailable // No iCloud account signed in
        case networkUnavailable // No network connection
    }

    var setupState: SyncState = .notStarted
    var importState: SyncState = .notStarted
    var exportState: SyncState = .notStarted

    /// Computed summary for UI display
    var overallState: SyncState {
        if case .failed = setupState { return setupState }
        if case .failed = importState { return importState }
        if case .failed = exportState { return exportState }
        if case .syncing = importState { return .syncing }
        if case .syncing = exportState { return .syncing }
        if case .succeeded(let date) = importState { return .succeeded(date) }
        if case .succeeded(let date) = exportState { return .succeeded(date) }
        return .notStarted
    }

    var isAccountAvailable: Bool = false

    private var eventObserver: Any?
    private let logger = Logger(subsystem: "app.pastel.Pastel", category: "SyncMonitor")

    func startMonitoring(coordinator: NSPersistentStoreCoordinator?) {
        guard let coordinator else { return }

        // Observe CloudKit container events (setup, import, export)
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: coordinator,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            self?.handleEvent(event)
        }

        // Check iCloud account status
        Task {
            let status = try? await CKContainer.default().accountStatus()
            isAccountAvailable = (status == .available)
        }
    }

    private func handleEvent(_ event: NSPersistentCloudKitContainer.Event) {
        let state: SyncState
        if let error = event.error {
            state = .failed(error.localizedDescription)
        } else if event.endDate == nil {
            state = .syncing
        } else {
            state = .succeeded(event.endDate ?? Date())
        }

        switch event.type {
        case .setup: setupState = state
        case .import: importState = state
        case .export: exportState = state
        @unknown default: break
        }
    }

    func stopMonitoring() {
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
            eventObserver = nil
        }
    }
}
```

**How to access the persistent store coordinator from SwiftData:** This requires reaching into the Core Data layer. The ModelContainer has a `mainContext` whose `managedObjectContext?.persistentStoreCoordinator` provides the coordinator needed for notification registration.

**Confidence: MEDIUM** -- The NSPersistentCloudKitContainer event API is well-documented for Core Data. Accessing it through SwiftData's Core Data bridge is validated by the CloudKitSyncMonitor open-source package.

### 2. DeduplicationService (NEW)

**Purpose:** Handle duplicate ClipboardItems that arrive via CloudKit sync when the same content is copied on multiple devices.

```swift
import SwiftData
import CoreData
import OSLog

@MainActor
final class DeduplicationService {

    private let modelContext: ModelContext
    private var remoteChangeObserver: Any?
    private let logger = Logger(subsystem: "app.pastel.Pastel", category: "Dedup")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func startObserving() {
        let coordinator = modelContext.managedObjectContext?.persistentStoreCoordinator

        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: coordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.deduplicateItems()
            }
        }
    }

    /// Scan for and remove duplicate items by contentHash.
    /// Strategy: keep the item with the earliest timestamp, merge labels, delete rest.
    func deduplicateItems() {
        do {
            let allItems = try modelContext.fetch(FetchDescriptor<ClipboardItem>())

            // Group by contentHash
            var hashGroups: [String: [ClipboardItem]] = [:]
            for item in allItems {
                guard !item.contentHash.isEmpty else { continue }
                hashGroups[item.contentHash, default: []].append(item)
            }

            var totalRemoved = 0
            for (_, items) in hashGroups where items.count > 1 {
                // Sort by timestamp ascending (earliest first)
                let sorted = items.sorted { $0.timestamp < $1.timestamp }
                let keeper = sorted[0]
                let duplicates = sorted.dropFirst()

                // Merge labels from duplicates onto keeper
                for dup in duplicates {
                    for label in (dup.labels ?? []) {
                        if !(keeper.labels ?? []).contains(where: {
                            $0.persistentModelID == label.persistentModelID
                        }) {
                            keeper.labels?.append(label) ?? (keeper.labels = [label])
                        }
                    }
                    // Clean up image files if any
                    ImageStorageService.shared.deleteImage(
                        imagePath: dup.imagePath, thumbnailPath: dup.thumbnailPath
                    )
                    modelContext.delete(dup)
                    totalRemoved += 1
                }
            }

            if totalRemoved > 0 {
                try modelContext.save()
                logger.info("Dedup removed \(totalRemoved) duplicate items")
            }
        } catch {
            logger.error("Dedup failed: \(error.localizedDescription)")
            modelContext.rollback()
        }
    }

    func stopObserving() {
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            remoteChangeObserver = nil
        }
    }
}
```

**When dedup runs:**
1. On `.NSPersistentStoreRemoteChange` notification (CloudKit import completed)
2. On app launch (catch anything missed while app was closed)
3. Debounced -- multiple rapid remote changes should coalesce into one dedup scan

**Confidence: MEDIUM** -- The approach is sound and matches Apple's CoreDataCloudKitShare sample patterns. The O(N) full-scan is acceptable for typical clipboard history sizes (< 50K items). For very large histories, a targeted scan using persistent history tracking would be more efficient but adds complexity.

### 3. SyncSettingsView (NEW)

**Purpose:** Settings UI for the Sync tab.

**Elements:**
- Sync on/off toggle (stored in UserDefaults, requires app restart)
- Restart prompt dialog when toggle is changed
- Sync status indicator (derived from SyncMonitorService.overallState)
- Last synced timestamp
- iCloud account status warning (if not signed in)
- "What syncs" explanation text (text, URLs, code, colors -- not images or concealed)

**Placement:** New "Sync" tab in SettingsView, between General and Labels.

### 4. DeviceIdentifier (NEW utility)

Small utility enum for per-device UUID generation, as shown above. Single file, ~15 lines.

---

## Integration Points with Existing Components

### ClipboardMonitor: Why Sync Does NOT Cause Ghost Copies

**The concern:** When a synced item arrives from Mac B, will Mac A's ClipboardMonitor detect it as a new clipboard change and create a feedback loop?

**Answer: No.** ClipboardMonitor polls `NSPasteboard.general` -- the system pasteboard. Synced items arriving via CloudKit go directly into the SwiftData/SQLite store. They NEVER touch the system pasteboard. The ClipboardMonitor will never see them.

The only way a synced item reaches the pasteboard is if the user explicitly pastes it (via PasteService), which already sets `skipNextChange = true` to prevent self-capture.

**What IS needed in ClipboardMonitor:**

1. **Set transactionAuthor** so DeduplicationService can distinguish local vs remote changes:
```swift
// In ClipboardMonitor.init:
modelContext.managedObjectContext?.transactionAuthor = "app"
```

2. **Stamp origin device on new items:**
```swift
// In processPasteboardContent():
item.originDeviceID = DeviceIdentifier.current
item.isSynced = false
```

3. **Replace unique constraint dedup with application-level check:**
```swift
// Before modelContext.insert(item):
let hash = contentHash
let existing = FetchDescriptor<ClipboardItem>(
    predicate: #Predicate<ClipboardItem> { $0.contentHash == hash }
)
if (try? modelContext.fetchCount(existing)) ?? 0 > 0 {
    Self.logger.debug("Non-consecutive duplicate detected by hash, skipping")
    return
}
```

4. **Mark sync-excluded items:**
```swift
item.syncExcluded = (isConcealed || contentType == .image || contentType == .file)
```

**Confidence: HIGH** for the core insight (sync does not touch NSPasteboard). MEDIUM for the transactionAuthor bridge (requires Core Data layer access).

### RetentionService: Sync-Aware Retention

**Current behavior:** Deletes items older than N days. Simple and correct for local-only.

**With sync enabled:** When RetentionService deletes an item on Mac A, CloudKit propagates that deletion to Mac B. This is the correct default behavior -- retention should be consistent.

**Edge case:** Different retention settings on different devices. If Mac A has 30-day retention and Mac B has 7-day, Mac B deletes synced items at 7 days, and that deletion propagates back to Mac A (removing them despite Mac A's 30-day setting).

**Recommendation for v1.5:** Keep it simple. Each device applies its own retention locally. Deletions propagate via CloudKit (automatic). Document that the shortest retention across devices effectively wins. Consider syncing the retention setting via NSUbiquitousKeyValueStore in a future version.

**Changes to RetentionService:**
- None required for basic functionality -- it already works correctly with sync
- Optional improvement: skip deletion of items where `isSynced == true && timestamp > (cutoff - 1day)` to give a small grace period for synced items. This prevents a race where an item is deleted before the user has seen it on this device.

**Confidence: MEDIUM** -- Retention + sync interaction is a real design decision. The simple approach works but has documented edge cases.

### ImportExportService: No Changes Needed

The existing ImportExportService uses in-memory hash comparison (`existingHashes` Set) for dedup during import. This does NOT rely on the `@Attribute(.unique)` constraint. Removing the unique constraint does not break import.

**Confidence: HIGH** -- Verified by reading ImportExportService source code.

### PastelApp: ModelContainer Configuration Change

The most significant infrastructure change is in PastelApp.init, where the ModelContainer is created:

```swift
// BEFORE (current)
container = try ModelContainer(for: ClipboardItem.self, Label.self)

// AFTER (sync-aware)
let syncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")

let config: ModelConfiguration
if syncEnabled {
    config = ModelConfiguration(
        cloudKitDatabase: .private("iCloud.app.pastel.Pastel")
    )
} else {
    config = ModelConfiguration(
        cloudKitDatabase: .none
    )
}

container = try ModelContainer(
    for: ClipboardItem.self, Label.self,
    configurations: config
)
```

**Default: OFF.** Sync is opt-in. First launch creates a local-only container. This preserves existing behavior for users who do not want sync.

**Toggle requires restart:** Changing the sync setting requires recreating the ModelContainer, which effectively means restarting the app. The SyncSettingsView should show a dialog: "Sync changes take effect after restarting Pastel."

**Caveat (LOW confidence):** Some reports indicate `cloudKitDatabase: .none` may not reliably prevent sync when CloudKit entitlements are present in the app. This MUST be validated during implementation. If `.none` is unreliable, the fallback approach is to conditionally set the `cloudKitContainerIdentifier` based on user preference plus iCloud account status check.

**Confidence: MEDIUM** -- The conditional configuration pattern is standard, but the `.none` reliability is a known concern.

### AppState: Wire New Services

```swift
// Add to AppState:
var syncMonitorService: SyncMonitorService?
var deduplicationService: DeduplicationService?

func setup(modelContext: ModelContext) {
    // ... existing ClipboardMonitor and RetentionService setup ...

    // Set transaction author for all local writes
    modelContext.managedObjectContext?.transactionAuthor = "app"

    // Sync services (only if sync is enabled)
    if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
        let syncMonitor = SyncMonitorService()
        syncMonitor.startMonitoring(
            coordinator: modelContext.managedObjectContext?.persistentStoreCoordinator
        )
        self.syncMonitorService = syncMonitor

        let dedup = DeduplicationService(modelContext: modelContext)
        dedup.startObserving()
        dedup.deduplicateItems()  // Run on launch to catch missed items
        self.deduplicationService = dedup
    }
}
```

---

## Entitlements and Project Configuration

### New Entitlements

```xml
<!-- Add to Pastel.entitlements -->
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.app.pastel.Pastel</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudDocuments</string>
    <string>CloudKit</string>
</array>
<!-- For syncing preferences (retention setting, sync state) across devices -->
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)app.pastel.Pastel</string>
```

### project.yml Changes

```yaml
targets:
  Pastel:
    # ... existing config ...
    settings:
      base:
        # ... existing settings ...
    dependencies:
      - package: KeyboardShortcuts
      - package: LaunchAtLogin
      - package: HighlightSwift
      - framework: CloudKit.framework   # CRITICAL for macOS release builds
    entitlements:
      # Xcode manages this via Signing & Capabilities, but ensure
      # the entitlements file path stays correct
```

### CRITICAL macOS Pitfall: CloudKit.framework

**Unlike iOS, macOS does NOT automatically link CloudKit.framework when you add the iCloud capability.** The app will compile and sync will work perfectly in Debug builds, but sync will **silently fail in Release/TestFlight/App Store builds** without explicitly linking the framework.

This is the most commonly reported iCloud sync issue for macOS apps. It produces zero errors or warnings -- sync simply does nothing in production.

**Fix:** Explicitly add CloudKit.framework to "Link Binary With Libraries" in Build Phases. In XcodeGen/project.yml, add it as a framework dependency.

**Confidence: HIGH** -- Confirmed by fatbobman, Apple Developer Forums, and multiple independent developers.

### CloudKit Schema Initialization

CloudKit's "Just-In-Time" schema inference often fails with complex relationships or empty databases. Explicitly push the schema during development:

```swift
#if DEBUG
// Drop to Core Data layer to initialize CloudKit schema
func initializeCloudKitSchema(config: ModelConfiguration) {
    let desc = NSPersistentStoreDescription(url: config.url)
    let opts = NSPersistentCloudKitContainerOptions(
        containerIdentifier: "iCloud.app.pastel.Pastel"
    )
    desc.cloudKitContainerOptions = opts
    desc.shouldAddStoreAsynchronously = false

    if let mom = NSManagedObjectModel.makeManagedObjectModel(
        for: [ClipboardItem.self, Label.self]
    ) {
        let ckContainer = NSPersistentCloudKitContainer(
            name: "Pastel", managedObjectModel: mom
        )
        ckContainer.persistentStoreDescriptions = [desc]
        ckContainer.loadPersistentStores { _, err in
            if let err { print("Schema init error: \(err)") }
        }
        try? ckContainer.initializeCloudKitSchema()
        if let store = ckContainer.persistentStoreCoordinator.persistentStores.first {
            try? ckContainer.persistentStoreCoordinator.remove(store)
        }
    }
}
#endif
```

Run once after model changes, verify in CloudKit Dashboard (https://icloud.developer.apple.com/dashboard), then comment out.

**Confidence: HIGH** -- Standard approach from fatbobman's guide.

---

## Items That Should NOT Sync

| Item Type | Should Sync? | Reason |
|-----------|-------------|--------|
| Text | Yes | Core use case |
| Rich Text | Yes | Preserves formatting |
| URL | Yes | Core use case, metadata can re-fetch |
| Code | Yes | Useful across devices |
| Color | Yes | Useful across devices |
| Image | **No** | Binary data too large, file paths are device-local |
| File | **No** | File paths are device-local, meaningless on other devices |
| Concealed | **No** | Security-sensitive, should be ephemeral and local-only |

**Implementation:** Use the `syncExcluded` flag. These items still physically sync to CloudKit (unavoidable with single-store SwiftData), but:
- The data footprint is small (no image binary data -- only metadata)
- On receiving devices, items with `syncExcluded == true` are hidden from the panel and history
- Users only see text-based synced items

**Why not dual ModelConfiguration:** SwiftData requires different @Model types per configuration. Splitting ClipboardItem into SyncableClipboardItem and LocalClipboardItem would require duplicating the entire model, all views, all services. The complexity is not worth it for v1.5.

**Confidence: MEDIUM** -- The flag-based approach is pragmatic. A cleaner architecture would use dual stores, but the refactor cost is prohibitive.

---

## Schema Migration Strategy

### Critical Rule: Add-Only After CloudKit Is Enabled

Once CloudKit sync is active in production:
- **Cannot** rename entities or attributes (CloudKit sees rename as delete+create = data loss)
- **Cannot** delete entities or attributes
- **Cannot** change attribute types
- **Can only** add new optional attributes with defaults

### Implication for Build Order

**Ship the CloudKit-compatible model BEFORE enabling sync.** This means:
1. Phase A: Migrate the data model to be CloudKit-compatible (remove unique, add defaults, make relationships optional, add sync fields) -- but keep CloudKit OFF
2. Phase B: Enable CloudKit infrastructure -- now the schema is locked

If the model migration and CloudKit enablement happen in the same phase, any model bugs require painful CloudKit schema recreation.

### Lightweight Migration

All the changes needed (adding defaults, making relationships optional, adding new fields) are lightweight migrations that SwiftData handles automatically. No custom MigrationPlan is needed.

**Confidence: HIGH** -- Well-documented constraint. Build order recommendation follows from the constraint.

---

## Patterns to Follow

### Pattern 1: Transaction Author Stamping

**What:** Set `transactionAuthor` on every ModelContext to distinguish local saves from CloudKit imports.
**When:** In every service that writes to SwiftData (ClipboardMonitor, RetentionService, ImportExportService, DeduplicationService).
**Why:** CloudKit imports have nil/empty author. This enables filtering remote-only changes.

```swift
modelContext.managedObjectContext?.transactionAuthor = "app"
```

### Pattern 2: Observe Remote Changes Specifically

**What:** Use `.NSPersistentStoreRemoteChange` to react to CloudKit imports only.
**When:** DeduplicationService -- should run after CloudKit import, not after every local save.

```swift
NotificationCenter.default.addObserver(
    forName: .NSPersistentStoreRemoteChange,
    object: coordinator,
    queue: .main
) { _ in deduplicateItems() }
```

### Pattern 3: Device ID Stamping

**What:** Assign a stable per-device UUID to every ClipboardItem at creation time.
**When:** In ClipboardMonitor when creating new items.
**Why:** Enables "from MacBook Pro" UI badges, targeted retention, dedup awareness.

### Pattern 4: Nil-Coalescing Relationship Access

**What:** After making relationships optional, use convenience computed properties.
**When:** Every `.labels` and `.items` access throughout the codebase.

```swift
extension ClipboardItem {
    var safeLabels: [Label] { labels ?? [] }
}
extension Label {
    var safeItems: [ClipboardItem] { items ?? [] }
}
```

### Pattern 5: Launch-Time Sync Configuration

**What:** Configure CloudKit at ModelContainer creation, not at runtime.
**When:** In PastelApp.init, reading UserDefaults to decide cloudKitDatabase.
**Why:** ModelContainer cannot be safely recreated at runtime.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Building CKSyncEngine on Top of SwiftData

**What:** Using CKSyncEngine or manual CKRecord management alongside SwiftData.
**Why bad:** SwiftData already wraps NSPersistentCloudKitContainer. Two sync layers would conflict.
**Instead:** Use SwiftData's built-in CloudKit sync exclusively.

### Anti-Pattern 2: Keeping @Attribute(.unique)

**What:** Leaving the unique constraint on contentHash and hoping CloudKit handles it.
**Why bad:** CloudKit silently ignores unique constraints. You get duplicates with no errors, or worse, sync failures.
**Instead:** Remove the constraint, implement application-level dedup.

### Anti-Pattern 3: Runtime ModelContainer Recreation

**What:** Destroying and recreating ModelContainer when user toggles sync.
**Why bad:** Invalidates all @Query subscriptions, all ModelContext references. SwiftData was not designed for this.
**Instead:** Configure at launch, require restart for sync toggle.

### Anti-Pattern 4: Syncing Image Binary Data

**What:** Attempting to sync images via CloudKit.
**Why bad:** CKAsset is not directly supported by SwiftData's auto-sync. Image data bloats CloudKit storage (5GB free limit). File paths are device-local.
**Instead:** Mark images as syncExcluded. Defer image sync to a future version.

### Anti-Pattern 5: Syncing Concealed Items

**What:** Allowing password manager items (isConcealed) to sync.
**Why bad:** Sensitive credentials should never leave the originating device.
**Instead:** Mark concealed items as syncExcluded.

### Anti-Pattern 6: Complex Retention Coordination Across Devices

**What:** Building a distributed consensus system for retention policies.
**Why bad:** Over-engineering. CloudKit automatically propagates deletions.
**Instead:** Each device applies its own retention. Deletions propagate naturally.

---

## Component Boundary Summary

### New Components

| Component | File | Type | Purpose |
|-----------|------|------|---------|
| `SyncMonitorService` | `Services/SyncMonitorService.swift` | @MainActor @Observable | Track sync status via NSPersistentCloudKitContainer events |
| `DeduplicationService` | `Services/DeduplicationService.swift` | @MainActor | Remove duplicate items after CloudKit import |
| `SyncSettingsView` | `Views/Settings/SyncSettingsView.swift` | SwiftUI View | Sync toggle, status display, account info |
| `DeviceIdentifier` | `Utilities/DeviceIdentifier.swift` | Enum | Per-device UUID generation |

### Modified Components

| Component | File | Changes |
|-----------|------|---------|
| `ClipboardItem` | `Models/ClipboardItem.swift` | Remove @Attribute(.unique), add defaults, add originDeviceID/isSynced/syncExcluded |
| `Label` | `Models/Label.swift` | Add defaults, make items optional |
| `PastelApp` | `PastelApp.swift` | Conditional ModelConfiguration for CloudKit |
| `ClipboardMonitor` | `Services/ClipboardMonitor.swift` | Set transactionAuthor, stamp deviceID, app-level dedup, mark syncExcluded |
| `AppState` | `App/AppState.swift` | Wire SyncMonitorService and DeduplicationService |
| `SettingsView` | `Views/Settings/SettingsView.swift` | Add Sync tab |
| `Pastel.entitlements` | `Resources/Pastel.entitlements` | Add iCloud, CloudKit, KV store entitlements |
| `project.yml` | Root | Add CloudKit.framework dependency |
| **All views using .labels/.items** | Multiple | Change to .safeLabels/.safeItems |

### Unchanged Components

| Component | Why Unchanged |
|-----------|---------------|
| `PasteService` | Does not interact with sync layer |
| `RetentionService` | Works correctly as-is (deletions propagate via CloudKit) |
| `ImportExportService` | Already uses application-level dedup (hash Set) |
| `ImageStorageService` | Images are local-only, not synced |
| `ExpirationService` | Concealed items are local-only |
| `PanelController`, `SlidingPanel` | UI infrastructure unchanged |
| All card views | Rendering unchanged (except .safeLabels access) |

---

## Suggested Build Order

### Phase A: CloudKit-Compatible Data Model (sync OFF)

**Goal:** Get the data model CloudKit-ready without actually enabling sync.

1. Remove `@Attribute(.unique)` from ClipboardItem.contentHash
2. Add default values to all non-optional properties on both models
3. Make `labels` and `items` relationships optional
4. Add `safeLabels`/`safeItems` computed properties
5. Update ALL call sites for optional relationship access (find-and-replace)
6. Add `originDeviceID`, `isSynced`, `syncExcluded` fields with defaults
7. Add application-level contentHash dedup in ClipboardMonitor (replace unique constraint behavior)
8. Stamp `originDeviceID = DeviceIdentifier.current` and `syncExcluded` in ClipboardMonitor
9. Verify everything works locally with zero sync

**Rationale:** This is the highest-risk change -- it touches the data model and ripples through every file that accesses relationships. Do it first, test thoroughly, ship it before adding CloudKit complexity. If something breaks, the debugging surface is pure local SwiftData, not distributed sync.

### Phase B: CloudKit Infrastructure

**Goal:** Get CloudKit plumbing working. Basic sync between two Macs.

1. Add iCloud + CloudKit entitlements to Pastel.entitlements
2. Add CloudKit.framework to linked frameworks in project.yml
3. Add NSUbiquitousKeyValueStore entitlement
4. Conditional `ModelConfiguration` in PastelApp.init based on UserDefaults
5. CloudKit schema initialization code (DEBUG only)
6. Set `transactionAuthor = "app"` on ModelContext
7. Build, run on two Macs with same Apple ID, verify items sync
8. Verify CloudKit Dashboard shows correct schema

**Rationale:** Pure infrastructure, no new UI. Gets the plumbing working and verifiable before building user-facing features.

### Phase C: Sync Services and UI

**Goal:** Dedup, monitoring, and settings UI.

1. SyncMonitorService -- observe events, expose sync status
2. DeduplicationService -- remote change handler, contentHash dedup
3. SyncSettingsView -- toggle (with restart prompt), status, account info
4. Add Sync tab to SettingsView
5. Wire SyncMonitorService and DeduplicationService into AppState
6. Sync status indicator in menu bar StatusPopoverView

**Rationale:** Builds on working infrastructure. Each service is independently testable.

### Phase D: Polish and Edge Cases

**Goal:** Handle real-world scenarios.

1. Handle offline -> online sync resume (verify automatic)
2. Handle iCloud account sign-out mid-session
3. First-sync with large existing history (performance testing)
4. syncExcluded item handling on receiving devices (hide or placeholder)
5. "From [device name]" badges on synced items (optional UI polish)
6. NSUbiquitousKeyValueStore for syncing sync-related preferences
7. Edge case testing across network conditions

**Rationale:** Edge cases that only matter once core sync is working correctly.

---

## Scalability Considerations

| Concern | At 1K items | At 10K items | At 100K items |
|---------|------------|-------------|---------------|
| Dedup scan time | Instant | ~100ms | ~500ms (consider batching) |
| Initial sync (first enable) | Seconds | 1-2 minutes | 10+ minutes |
| CloudKit storage | ~1MB (text only) | ~10MB | ~100MB (within 5GB free) |
| @Query performance | No impact | No impact | No impact (local SQLite) |
| Remote change batching | Individual | System batches | System batches |

**Storage note:** CloudKit private database counts against the user's iCloud storage (shared 5GB free tier). Text-only clipboard items average ~1KB each. Even at 100K items, that is ~100MB -- well within typical iCloud quotas. Image sync would quickly approach limits, further justifying text-only sync.

---

## Sources

### HIGH Confidence
- [Apple: Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [Hacking with Swift: How to sync SwiftData with iCloud](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-sync-swiftdata-with-icloud)
- [Hacking with Swift: How to stop SwiftData syncing](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-stop-swiftdata-syncing-with-cloudkit)
- [fatbobman: Rules for Adapting Data Models to CloudKit](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/)
- [fatbobman: Fix macOS SwiftData/CoreData Sync (CloudKit.framework)](https://fatbobman.com/en/snippet/fix-synchronization-issues-for-macos-apps-using-core-dataswiftdata/)
- [fatbobman: initializeCloudKitSchema for SwiftData](https://fatbobman.com/en/snippet/resolving-incomplete-icloud-data-sync-in-ios-development-using-initializecloudkitschema/)
- [fatbobman: Persistent History Tracking in SwiftData](https://fatbobman.com/en/posts/persistent-history-tracking-in-swiftdata/)
- [fatbobman: Data Tracking and Notifications](https://fatbobman.com/en/posts/mastering-data-tracking-and-notifications-in-core-data-and-swiftdata/)
- [Apple: NSPersistentCloudKitContainer](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer)
- [Apple: Debugging NSPersistentCloudKitContainer (TN3164)](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer)
- [Apple: NSMergePolicy (conflict resolution)](https://developer.apple.com/documentation/coredata/nsmergepolicy)

### MEDIUM Confidence
- [CloudKitSyncMonitor package](https://github.com/ggruen/CloudKitSyncMonitor) -- validates event monitoring approach
- [fluffy.es: Toggle iCloud sync](https://fluffy.es/toggle-icloud-sync-nspersistentcloudkitcontainer/) -- Core Data toggle pattern
- [Apple Forums: SwiftData CloudKit deduplication](https://developer.apple.com/forums/thread/745329)
- [Apple Forums: Disable automatic iCloud sync](https://developer.apple.com/forums/thread/731375)
- [Superwall: CKSyncEngine guide](https://superwall.com/blog/syncing-data-with-cloudkit-in-your-ios-app-using-cksyncengine-and-swift-and-swiftui/) -- confirms CKSyncEngine is NOT for SwiftData

### LOW Confidence (needs validation during implementation)
- `cloudKitDatabase: .none` reliability for preventing sync -- conflicting reports
- SwiftData History API for processing remote changes -- limited real-world validation
- `managedObjectContext?.transactionAuthor` access from SwiftData ModelContext -- works per guides, needs testing in Pastel's setup
