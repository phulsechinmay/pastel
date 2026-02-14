# Stack Research: v1.5 iCloud Sync

**Domain:** Native macOS Clipboard Manager -- iCloud Sync of Clipboard History Across Macs
**Project:** Pastel
**Researched:** 2026-02-14
**Confidence:** HIGH

> **Scope:** This document covers ONLY the stack additions/changes needed for v1.5 iCloud sync. The existing v1.0-v1.4 stack is validated and unchanged unless explicitly noted below. The core recommendation is to use SwiftData's built-in CloudKit sync (via `ModelConfiguration.cloudKitDatabase: .automatic`) because Pastel already uses SwiftData -- zero new persistence frameworks needed.

---

## Decision: SwiftData Built-in CloudKit Sync

### Options Evaluated

| Option | What It Is | Verdict |
|--------|-----------|---------|
| **SwiftData + CloudKit (automatic)** | Built-in sync via `ModelConfiguration(cloudKitDatabase: .automatic)` | **USE THIS** |
| NSPersistentCloudKitContainer | Core Data wrapper with CloudKit sync | REJECT -- would require migrating away from SwiftData |
| CKSyncEngine | Low-level CloudKit sync engine (iOS 17+/macOS 14+) | REJECT -- unnecessary complexity for this use case |
| Manual CKRecord management | Direct CloudKit API calls | REJECT -- enormous effort, reinvents the wheel |
| SwiftDataSync (third-party) | SPM package wrapping CKSyncEngine | REJECT -- adds dependency for something SwiftData does natively |

### Why SwiftData Built-in CloudKit Sync

1. **Zero migration cost.** Pastel already uses SwiftData with `@Model`, `@Query`, and `ModelContainer`. Enabling CloudKit sync is a configuration change, not an architecture change.

2. **Minimal code.** The core change is one line:
   ```swift
   // BEFORE (current)
   let container = try ModelContainer(for: ClipboardItem.self, Label.self)

   // AFTER (with iCloud sync)
   let config = ModelConfiguration(
       cloudKitDatabase: .automatic  // Syncs to user's private iCloud database
   )
   let container = try ModelContainer(for: ClipboardItem.self, Label.self, configurations: config)
   ```

3. **Uses user's own iCloud storage.** The `.automatic` configuration syncs to the **private** CloudKit database, which uses the user's iCloud quota. No server infrastructure, no developer CloudKit quota costs, no shared/public database setup.

4. **Automatic conflict resolution.** SwiftData+CloudKit uses a last-writer-wins merge policy at the record level. For clipboard items (which are immutable after creation -- users don't edit clipboard content), conflicts are effectively impossible. For labels (which users can rename/recolor), last-writer-wins is acceptable.

5. **Transparent to existing @Query views.** Once sync is enabled, remote changes from other devices automatically appear in `@Query` results. The existing `FilteredCardListView`, `HistoryGridView`, etc. will display synced items without modification.

**Confidence: HIGH** -- SwiftData CloudKit sync is documented by Apple, used in production by many apps, and matches Pastel's existing architecture. Sources: [Apple Documentation](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices), [Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-sync-swiftdata-with-icloud), [fatbobman](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/).

### Why NOT CKSyncEngine

CKSyncEngine (introduced macOS 14/iOS 17) is the right choice when you need fine-grained control over sync timing, custom conflict resolution, or you are NOT using SwiftData/Core Data. Pastel needs none of these:

- Sync timing: Automatic is fine -- clipboard items should sync ASAP.
- Conflict resolution: Last-writer-wins is acceptable for clipboard data.
- Persistence: Already using SwiftData.

CKSyncEngine would require building a manual translation layer between SwiftData models and CKRecords, handling zone management, scheduling sync batches, and implementing a `CKSyncEngineDelegate`. This is hundreds of lines of code to replicate what `cloudKitDatabase: .automatic` provides for free.

**Source:** [Apple Developer Forums - CKSyncEngine & SwiftData](https://developer.apple.com/forums/thread/731435), [Superwall CKSyncEngine Tutorial](https://superwall.com/blog/syncing-data-with-cloudkit-in-your-ios-app-using-cksyncengine-and-swift-and-swiftui/)

### Why NOT NSPersistentCloudKitContainer

NSPersistentCloudKitContainer is the Core Data equivalent. Since Pastel uses SwiftData (not Core Data), adopting NSPersistentCloudKitContainer would mean either:
- Migrating the entire persistence layer to Core Data (massive regression), or
- Maintaining dual persistence stacks (unnecessary complexity).

SwiftData's CloudKit integration uses NSPersistentCloudKitContainer under the hood. There is no benefit to dropping down to it directly.

---

## Critical Schema Changes Required

SwiftData CloudKit sync imposes strict constraints on the data model. Pastel's current models violate several of these. **These must be fixed before enabling sync.**

### Constraint 1: Remove @Attribute(.unique)

**Current code (INCOMPATIBLE):**
```swift
@Attribute(.unique) var contentHash: String  // Line 49 of ClipboardItem.swift
```

**Why:** CloudKit does not support atomic uniqueness checks across devices. Two Macs could create items with the same contentHash simultaneously, and CloudKit cannot enforce that constraint during sync. SwiftData will crash or silently fail if `@Attribute(.unique)` is present with CloudKit enabled.

**Fix:** Remove `@Attribute(.unique)`. Keep the `contentHash` property (it is still useful for local deduplication in `ClipboardMonitor`), but enforce uniqueness in application code rather than at the database level.

```swift
// AFTER
var contentHash: String  // No @Attribute(.unique)
```

**Deduplication without unique constraint:** The existing `isDuplicateOfMostRecent(contentHash:)` method in `ClipboardMonitor.swift` already checks the most recent item's hash before insertion. This application-level check remains sufficient for local deduplication. For cross-device dedup (two Macs copying the same text), the items will simply appear as separate entries -- this is acceptable behavior (each Mac has its own capture context: different timestamp, different source app).

**Confidence: HIGH** -- This is a hard requirement documented by Apple and verified by multiple community sources. Source: [fatbobman - Rules for Adapting Data Models to CloudKit](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/)

### Constraint 2: Make All Relationships Optional

**Current code:**
```swift
// ClipboardItem.swift
@Relationship(deleteRule: .nullify, inverse: \Label.items)
var labels: [Label]  // Non-optional array

// Label.swift
var items: [ClipboardItem]  // Non-optional array
```

**Why:** CloudKit needs to handle "partial data" synchronization. A ClipboardItem might sync before its associated Labels do. If the relationship is non-optional, SwiftData cannot create the item without the relationship populated.

**Fix:** Make relationships optional:
```swift
// ClipboardItem.swift
@Relationship(deleteRule: .nullify, inverse: \Label.items)
var labels: [Label]?  // Optional

// Label.swift
var items: [ClipboardItem]?  // Optional
```

**Impact:** Code that reads `item.labels` must change to `item.labels ?? []`. This is a mechanical change across the codebase.

**Confidence: HIGH** -- Hard requirement. Source: [Apple Documentation](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)

### Constraint 3: Default Values for All Properties

**Current code has these non-optional, no-default properties:**
```swift
var contentType: String     // Has no default in declaration (set in init)
var timestamp: Date         // Has no default in declaration (set in init)
var characterCount: Int     // Has no default in declaration (set in init)
var byteCount: Int          // Has no default in declaration (set in init)
var changeCount: Int        // Has no default in declaration (set in init)
var isConcealed: Bool       // Has no default in declaration (set in init)
var contentHash: String     // Has no default in declaration (set in init)
```

In Label.swift:
```swift
var name: String            // No default
var colorName: String       // No default
var sortOrder: Int          // No default
```

**Fix:** Add default values to all property declarations:
```swift
var contentType: String = ContentType.text.rawValue
var timestamp: Date = .now
var characterCount: Int = 0
var byteCount: Int = 0
var changeCount: Int = 0
var isConcealed: Bool = false
var contentHash: String = ""
```

**Note:** The `init()` still sets these explicitly. The defaults are needed for CloudKit's partial-sync scenarios where a record arrives before all fields are populated.

**Confidence: HIGH** -- Hard requirement. Source: [fatbobman - Rules for Adapting Data Models to CloudKit](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/)

### Constraint 4: Schema Migration is Add-Only After Deployment

Once the CloudKit schema is deployed to production, the "add-only, no-delete, no-change" principle applies:
- Do NOT delete entities or attributes
- Do NOT rename entities or attributes (CloudKit interprets rename as delete + add, causing data loss)
- Do NOT change attribute data types
- Only lightweight migration is supported

**Implication:** Get the schema right BEFORE the first production deployment. The existing deprecated `label: Label?` property on ClipboardItem must remain (it is already kept for migration). Any future v1.6+ schema changes must be additive only.

**Confidence: HIGH** -- Hard requirement. Source: [fatbobman](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/)

---

## Recommended Stack

### Core Framework (Changed)

| Technology | Version | Purpose | Change from v1.4 |
|------------|---------|---------|-------------------|
| SwiftData + CloudKit | macOS 14+ | Persistence with iCloud sync | **CHANGED** -- add `cloudKitDatabase: .automatic` to ModelConfiguration |
| CloudKit.framework | macOS 14+ | System framework for iCloud sync | **NEW** -- must be explicitly linked (macOS-specific requirement) |

### Infrastructure (New)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| CloudKit Dashboard | Web | Schema deployment to production | Required for App Store releases -- schema must be manually deployed from dev to prod |

### Supporting Libraries (New)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| CloudKitSyncMonitor | 3.0.0+ | Monitor sync state (setup/import/export events) | For sync status indicator in UI |

### Existing Stack (Unchanged)

| Technology | Version | Purpose | Status |
|------------|---------|---------|--------|
| Swift 6.0 | 6.0 | Primary language | Unchanged |
| SwiftUI + AppKit hybrid | macOS 14+ | UI framework | Unchanged |
| SwiftData | macOS 14+ | Persistence | **Modified config only** |
| KeyboardShortcuts | 2.4.0 | Panel toggle hotkey | Unchanged |
| LaunchAtLogin-Modern | 1.1.0 | Login item | Unchanged |
| HighlightSwift | 1.1.0 | Syntax highlighting | Unchanged |
| CryptoKit | macOS 14+ | SHA256 deduplication | Unchanged |
| XcodeGen (project.yml) | -- | Project generation | Unchanged |

---

## Entitlements and Capabilities Required

### New Entitlements (Pastel.entitlements)

The current entitlements file has:
```xml
<key>com.apple.security.app-sandbox</key>       <true/>
<key>com.apple.security.network.client</key>     <true/>
<key>com.apple.security.files.user-selected.read-write</key>  <true/>
```

**Add these entitlements:**

```xml
<!-- iCloud / CloudKit -->
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudDocuments</string>
    <string>CloudKit</string>
</array>

<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.app.pastel.Pastel</string>
</array>

<key>com.apple.developer.icloud-container-environment</key>
<string>Development</string>
<!-- Xcode automatically switches to Production for App Store/TestFlight builds -->

<!-- Push Notifications (required for CloudKit remote change notifications) -->
<key>com.apple.developer.aps-environment</key>
<string>development</string>
```

**Note on Background Modes:** macOS does NOT need the Background Modes capability. That is iOS-only. On macOS, remote change notifications from CloudKit work without it. Source: [Kodeco CloudKit Tutorial](https://www.kodeco.com/ios/paths/continuing-swiftui/45123174-data-persistence-with-swiftdata/04-extending-swiftdata-apps-cloudkit-support/02)

**Note on Push Notifications:** The `aps-environment` entitlement is required because CloudKit uses silent push notifications to notify devices of remote changes. This does NOT show user-facing notifications -- it simply wakes the sync engine. Source: [Apple Developer Forums](https://developer.apple.com/forums/thread/766519)

**Confidence: HIGH** -- Entitlements are well-documented. Source: [Apple - Enabling CloudKit in Your App](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app)

### XcodeGen project.yml Changes

```yaml
targets:
  Pastel:
    dependencies:
      - package: KeyboardShortcuts
      - package: LaunchAtLogin
      - package: HighlightSwift
      - sdk: CloudKit.framework        # NEW -- required for macOS CloudKit sync
```

**CRITICAL macOS gotcha:** On macOS, Xcode does NOT automatically link CloudKit.framework when CloudKit capabilities are enabled (unlike iOS). Without explicitly adding this SDK dependency, sync will work in Debug builds (the dynamic linker is permissive) but **silently fail in Release/TestFlight/App Store builds**. This is the single most common cause of "sync works in development but not production" on macOS.

Source: [fatbobman - Fixing macOS SwiftData/Core Data Sync](https://fatbobman.com/en/snippet/fix-synchronization-issues-for-macos-apps-using-core-dataswiftdata/)

### Apple Developer Portal Configuration

1. **Enable iCloud capability** on the App ID in the Apple Developer portal
2. **Enable Push Notifications capability** on the App ID (for CloudKit silent pushes)
3. **Create CloudKit container** named `iCloud.app.pastel.Pastel` in CloudKit Dashboard

---

## Sync Status Monitoring

### Approach: NSPersistentCloudKitContainer.eventChangedNotification

SwiftData uses NSPersistentCloudKitContainer under the hood. We can observe its sync events to build a status indicator:

```swift
import CoreData

NotificationCenter.default.addObserver(
    forName: NSPersistentCloudKitContainer.eventChangedNotification,
    object: nil,
    queue: .main
) { notification in
    guard let event = notification.userInfo?[
        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
    ] as? NSPersistentCloudKitContainer.Event else { return }

    // event.type: .setup, .import, .export
    // event.startDate, event.endDate
    // event.succeeded, event.error
}
```

**Important caveat:** This notification tells you the state of individual import/export events, not whether the entire store is fully synchronized. There may be pending changes on the server that have not yet been fetched.

### CloudKitSyncMonitor (Recommended for UI)

For a polished sync status indicator, use [CloudKitSyncMonitor](https://github.com/ggruen/CloudKitSyncMonitor) (SPM package, v3.0.0+). It wraps the raw notifications into published properties:

```swift
// In project.yml:
packages:
  CloudKitSyncMonitor:
    url: https://github.com/ggruen/CloudKitSyncMonitor
    from: "3.0.0"

// Usage:
import CloudKitSyncMonitor

SyncMonitor.default.startMonitoring()

// In SwiftUI view:
@ObservedObject var syncMonitor = SyncMonitor.default

var body: some View {
    switch syncMonitor.syncStateSummary {
    case .inProgress: Image(systemName: "arrow.triangle.2.circlepath")
    case .succeeded: Image(systemName: "checkmark.icloud")
    case .error: Image(systemName: "exclamationmark.icloud")
    case .notStarted, .noNetwork: Image(systemName: "icloud.slash")
    default: Image(systemName: "icloud")
    }
}
```

**Confidence: MEDIUM** -- CloudKitSyncMonitor is designed for NSPersistentCloudKitContainer which SwiftData wraps. Community reports confirm it works with SwiftData. However, this is a third-party dependency. Alternative: build a lightweight version using the raw notification (50-80 lines of code).

---

## Sync-Aware Opt-In Toggle

### Implementation: Dual ModelConfiguration

The user wants sync off by default with an opt-in toggle. SwiftData supports this by switching between two configurations:

```swift
func createModelContainer(syncEnabled: Bool) throws -> ModelContainer {
    let config: ModelConfiguration
    if syncEnabled {
        config = ModelConfiguration(
            cloudKitDatabase: .automatic
        )
    } else {
        config = ModelConfiguration(
            cloudKitDatabase: .none
        )
    }
    return try ModelContainer(
        for: ClipboardItem.self, Label.self,
        configurations: config
    )
}
```

**Critical consideration:** Toggling sync on/off requires recreating the `ModelContainer`. This means:
1. The toggle should prompt the user to restart the app (simplest approach), OR
2. The app reinitializes the entire SwiftData stack at runtime (complex but doable -- destroy old container, create new one, re-inject into views).

**Recommendation:** Require app restart on toggle change. A simple alert: "Restart Pastel to apply sync changes" with a "Restart Now" button that calls `NSApp.terminate(nil)` followed by relaunch. Store the sync preference in `UserDefaults` (read before `ModelContainer` creation).

```swift
@AppStorage("iCloudSyncEnabled") var iCloudSyncEnabled: Bool = false
```

**Confidence: HIGH** for the dual-config approach. Source: [Hacking with Swift - How to stop SwiftData syncing with CloudKit](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-stop-swiftdata-syncing-with-cloudkit)

---

## CloudKit Schema Initialization

### The Problem

SwiftData's automatic CloudKit schema inference can fail for complex models or on first launch. If the schema is not properly initialized, sync will silently fail.

### The Fix: initializeCloudKitSchema (DEBUG only)

During development, call `initializeCloudKitSchema()` via the Core Data layer to ensure the CloudKit schema matches the SwiftData models:

```swift
#if DEBUG
func initializeCloudKitSchemaIfNeeded(for config: ModelConfiguration) {
    let desc = NSPersistentStoreDescription(url: config.url)
    let opts = NSPersistentCloudKitContainerOptions(
        containerIdentifier: "iCloud.app.pastel.Pastel"
    )
    desc.cloudKitContainerOptions = opts
    desc.shouldAddStoreAsynchronously = false

    if let mom = NSManagedObjectModel.makeManagedObjectModel(
        for: [ClipboardItem.self, Label.self]
    ) {
        let container = NSPersistentCloudKitContainer(
            name: "Pastel",
            managedObjectModel: mom
        )
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, error in
            if let error { print("Schema init store load error: \(error)") }
        }
        do {
            try container.initializeCloudKitSchema()
            print("CloudKit schema initialized successfully")
        } catch {
            print("CloudKit schema init error: \(error)")
        }
        // Clean up to release file locks
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }
}
#endif
```

**Production deployment:** Before submitting to the App Store, log into [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/) and click "Deploy Schema Changes..." to push the development schema to production. **This is a mandatory manual step.** Without it, sync will work in development but fail for App Store users.

Source: [fatbobman - Fixing SwiftData & Core Data Sync: initializeCloudKitSchema](https://fatbobman.com/en/snippet/resolving-incomplete-icloud-data-sync-in-ios-development-using-initializecloudkitschema/), [leojkwan - Deploy CloudKit Schema](https://www.leojkwan.com/swiftdata-cloudkit-deploy-schema-changes/)

**Confidence: HIGH**

---

## Data That Should NOT Sync

| Data | Sync? | Reason |
|------|-------|--------|
| Text clipboard items | YES | Core feature |
| URL clipboard items | YES | Core feature |
| Code clipboard items | YES | Core feature |
| Color clipboard items | YES | Core feature |
| Image clipboard items | NO (v1.5) | Would consume significant iCloud storage; architecture supports future addition |
| Labels | YES | Users expect consistent organization across devices |
| Concealed items (isConcealed=true) | NO | Security -- password manager content should never leave the device |
| App ignore list | NO | Device-specific (different apps installed per Mac) -- keep in UserDefaults |
| Panel position/hotkey settings | NO | Device-specific preferences -- keep in UserDefaults |
| changeCount | Sync as data but meaningless cross-device | NSPasteboard changeCount is device-local |
| Image file paths (imagePath, thumbnailPath) | Sync as data but files won't exist on other device | Image sync deferred to future |

### Filtering Concealed Items from Sync

SwiftData's automatic CloudKit sync syncs ALL records. There is no built-in way to exclude specific records. Options:

1. **Separate ModelConfiguration for concealed items (RECOMMENDED).** Use two configurations -- one with CloudKit sync for normal items, one local-only for concealed items. This requires two stores but cleanly separates synced from unsynced data.

2. **Delete concealed items before sync.** The existing 60-second auto-expiry for concealed items means they are typically deleted before sync has a chance to upload them. This is "good enough" but not guaranteed.

3. **Accept that concealed items sync.** Since they auto-expire in 60 seconds, they exist in iCloud briefly. This is a privacy compromise.

**Recommendation:** Option 2 (rely on auto-expiry) for v1.5, with Option 1 (dual-store) as a future enhancement if privacy requirements tighten.

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Sync engine | SwiftData CloudKit (automatic) | CKSyncEngine | Unnecessary complexity; Pastel already uses SwiftData |
| Sync engine | SwiftData CloudKit (automatic) | Manual CKRecord management | Hundreds of lines of boilerplate for what SwiftData does automatically |
| Sync engine | SwiftData CloudKit (automatic) | NSPersistentCloudKitContainer | Would require migrating away from SwiftData to Core Data |
| Sync engine | SwiftData CloudKit (automatic) | SwiftDataSync (third-party) | Adds dependency; built-in sync is sufficient for private-only sync |
| Sync monitoring | CloudKitSyncMonitor (SPM) | Custom notification observer | CloudKitSyncMonitor is battle-tested; custom code is 50-80 lines but needs testing |
| Sync toggle | UserDefaults + app restart | Runtime container swap | App restart is simpler, lower risk, and acceptable UX for a rarely-changed setting |
| Conflict resolution | Last-writer-wins (built-in) | Custom merge policy | SwiftData does not expose custom merge policies; last-writer-wins is fine for clipboard data |
| Deduplication | Application-level hash check | @Attribute(.unique) | Unique constraints are incompatible with CloudKit |

---

## Installation / project.yml Changes

```yaml
# project.yml additions for v1.5

packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: "2.4.0"
  LaunchAtLogin:
    url: https://github.com/sindresorhus/LaunchAtLogin-Modern
    from: "1.1.0"
  HighlightSwift:
    url: https://github.com/appstefan/HighlightSwift
    from: "1.0.0"
  CloudKitSyncMonitor:                              # NEW
    url: https://github.com/ggruen/CloudKitSyncMonitor
    from: "3.0.0"

targets:
  Pastel:
    dependencies:
      - package: KeyboardShortcuts
      - package: LaunchAtLogin
      - package: HighlightSwift
      - package: CloudKitSyncMonitor                 # NEW
      - sdk: CloudKit.framework                      # NEW -- CRITICAL for macOS
```

### Entitlements File (Pastel.entitlements)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Existing -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>

    <!-- NEW: iCloud / CloudKit -->
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudDocuments</string>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.app.pastel.Pastel</string>
    </array>
    <key>com.apple.developer.icloud-container-environment</key>
    <string>Development</string>

    <!-- NEW: Push Notifications (for CloudKit remote change notifications) -->
    <key>com.apple.developer.aps-environment</key>
    <string>development</string>
</dict>
</plist>
```

---

## Integration Points with Existing Code

### PastelApp.swift (ModelContainer Creation)

The central change. Switch from bare `ModelContainer(for:)` to configured container:

```swift
// Current (line 13):
container = try ModelContainer(for: ClipboardItem.self, Label.self)

// New:
let syncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
let config = ModelConfiguration(
    cloudKitDatabase: syncEnabled ? .automatic : .none
)
container = try ModelContainer(for: ClipboardItem.self, Label.self, configurations: config)
```

### ClipboardItem.swift (Schema Changes)

- Remove `@Attribute(.unique)` from `contentHash`
- Add default values to all non-optional properties
- Make `labels` relationship optional: `var labels: [Label]?`
- Keep `label: Label?` (deprecated) -- cannot delete after CloudKit deployment

### Label.swift (Schema Changes)

- Make `items` relationship optional: `var items: [ClipboardItem]?`
- Add default values: `var name: String = ""`, `var colorName: String = "blue"`, `var sortOrder: Int = 0`

### ClipboardMonitor.swift

- No changes for basic sync functionality
- Existing `isDuplicateOfMostRecent()` continues working for local dedup
- Existing concealed item detection and 60-second expiry handles privacy

### All Views Using `item.labels`

- Change `item.labels` to `item.labels ?? []` throughout the codebase
- This is a mechanical search-and-replace

### Settings (New Sync Tab)

- Add "iCloud Sync" section with toggle, sync status indicator, and storage info
- Read `iCloudSyncEnabled` from `@AppStorage`
- Show restart prompt when toggled

---

## Version Compatibility

All APIs used in v1.5 are available on macOS 14 (Sonoma) and later:

| API | Minimum macOS | Notes |
|-----|--------------|-------|
| `ModelConfiguration(cloudKitDatabase:)` | macOS 14 | Core SwiftData CloudKit API |
| `ModelConfiguration.CloudKitDatabase.automatic` | macOS 14 | Private database sync |
| `ModelConfiguration.CloudKitDatabase.none` | macOS 14 | Disable sync |
| `NSPersistentCloudKitContainer.eventChangedNotification` | macOS 12 | Core Data notification (works with SwiftData) |
| `NSPersistentCloudKitContainer.Event` | macOS 12 | Sync event details |
| `NSPersistentStoreRemoteChangeNotification` | macOS 10.15 | Remote change detection |
| CloudKit.framework | macOS 10.10 | System framework |
| `CKContainer` | macOS 10.10 | CloudKit container |

No macOS 15-only APIs required. The macOS 14+ deployment target is sufficient.

---

## What NOT to Add (and Why)

| Technology | Why NOT |
|------------|---------|
| CKSyncEngine | Over-engineering -- SwiftData handles sync automatically; CKSyncEngine is for apps not using SwiftData/CoreData |
| Core Data (NSPersistentCloudKitContainer directly) | Pastel uses SwiftData; dropping to Core Data would be a regression |
| Manual CKRecord/CKDatabase operations | SwiftData abstracts this entirely; manual management is hundreds of lines of unnecessary code |
| CloudKit Sharing (CKShare) | v1.5 is single-user sync across own devices, not multi-user collaboration; SwiftData does not support shared database yet anyway |
| CloudKit public database | Clipboard history is private data; public database is for app-wide shared content |
| Third-party sync solutions (Realm Sync, Firebase, etc.) | Would require replacing SwiftData entirely; iCloud is the natural choice for a macOS-only app |
| Background Modes entitlement | macOS does NOT need Background Modes for CloudKit sync (that is iOS-only) |
| NSUbiquitousKeyValueStore | Only for small key-value data (1MB limit); clipboard history is too large |
| iCloud Drive (file-based sync) | Wrong tool -- SwiftData database sync is structured data, not file sync |
| @Attribute(.unique) | Incompatible with CloudKit; must be removed |
| Custom merge policies | SwiftData does not expose merge policy customization; last-writer-wins is sufficient |

---

## WWDC25 / macOS 26 SwiftData Updates

WWDC25 added **model inheritance** to SwiftData but did NOT add:
- Additional CloudKit sync options (shared/public databases)
- Custom conflict resolution for SwiftData
- Dynamic predicate adjustments

Apple DTS reportedly advises developers needing advanced CloudKit features (sharing, custom conflict resolution) to use Core Data + CloudKit + Sharing rather than SwiftData. For Pastel's use case (private-only sync, no sharing), SwiftData's built-in sync is fully sufficient.

Source: [Michael Tsai - SwiftData and Core Data at WWDC25](https://mjtsai.com/blog/2025/06/19/swiftdata-and-core-data-at-wwdc25/), [fatbobman WWDC25 First Impressions](https://fatbobman.com/en/posts/wwdc-2025-first-impressions/)

**Confidence: HIGH** -- No WWDC25 changes affect Pastel's sync approach.

---

## Sources

### Official Documentation (HIGH confidence)
- [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) -- Apple Developer Documentation
- [Enabling CloudKit in Your App](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app) -- Apple Developer Documentation
- [ModelConfiguration.CloudKitDatabase](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct) -- Apple Developer Documentation
- [NSPersistentCloudKitContainer.eventChangedNotification](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/eventchangednotification) -- Apple Developer Documentation
- [iCloud Services Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-services) -- Apple Developer Documentation
- [Merge Policies](https://developer.apple.com/documentation/coredata/merge-policies) -- Apple Developer Documentation
- [TN3164: Debugging the synchronization of NSPersistentCloudKitContainer](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer) -- Apple Technical Note

### Community Resources (MEDIUM-HIGH confidence, multiple sources agree)
- [fatbobman - Rules for Adapting Data Models to CloudKit](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/) -- Comprehensive schema constraint reference
- [fatbobman - Fixing macOS SwiftData/Core Data Sync: The CloudKit.framework Issue](https://fatbobman.com/en/snippet/fix-synchronization-issues-for-macos-apps-using-core-dataswiftdata/) -- macOS-specific framework linking fix
- [fatbobman - Fix Core Data/SwiftData Cloud Sync Issues in Production](https://fatbobman.com/en/snippet/why-core-data-or-swiftdata-cloud-sync-stops-working-after-app-store-login/) -- Production schema deployment
- [fatbobman - Fixing SwiftData & Core Data Sync: initializeCloudKitSchema](https://fatbobman.com/en/snippet/resolving-incomplete-icloud-data-sync-in-ios-development-using-initializecloudkitschema/) -- Schema initialization code
- [Hacking with Swift - How to sync SwiftData with iCloud](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-sync-swiftdata-with-icloud) -- Tutorial
- [Hacking with Swift - How to stop SwiftData syncing with CloudKit](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-stop-swiftdata-syncing-with-cloudkit) -- Opt-in toggle pattern
- [leojkwan - Deploy CloudKit Schema to Production](https://www.leojkwan.com/swiftdata-cloudkit-deploy-schema-changes/) -- Production deployment walkthrough
- [CloudKitSyncMonitor](https://github.com/ggruen/CloudKitSyncMonitor) -- Sync monitoring library

### Apple Developer Forums (MEDIUM confidence)
- [CKSyncEngine & SwiftData](https://developer.apple.com/forums/thread/731435) -- Why CKSyncEngine is not needed with SwiftData
- [SwiftData + CloudKit deduplication](https://developer.apple.com/forums/thread/745329) -- Dedup strategies without unique constraints
- [SwiftData CloudKit on Mac](https://developer.apple.com/forums/thread/766519) -- macOS-specific entitlement requirements

### WWDC / Blog Posts (MEDIUM confidence)
- [Michael Tsai - SwiftData and Core Data at WWDC25](https://mjtsai.com/blog/2025/06/19/swiftdata-and-core-data-at-wwdc25/) -- WWDC25 changes
- [fatbobman - WWDC 2025 First Impressions](https://fatbobman.com/en/posts/wwdc-2025-first-impressions/) -- SwiftData maturity assessment

---

*Researched: 2026-02-14*
*Confidence: HIGH overall. SwiftData built-in CloudKit sync is the clear choice for Pastel's architecture. Schema changes are well-documented hard requirements. The macOS CloudKit.framework linking gotcha is the most likely "silent failure" trap. CloudKitSyncMonitor is the only area at MEDIUM confidence (third-party dependency, but can be replaced with ~60 lines of custom code).*
