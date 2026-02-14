# Phase 20: CloudKit Infrastructure and Sync Engine - Research

**Researched:** 2026-02-14
**Domain:** CloudKit integration, entitlements, framework linking, ModelContainer configuration, content filtering for SwiftData sync
**Confidence:** HIGH

## Summary

Phase 20 enables the actual CloudKit sync plumbing on top of the CloudKit-compatible data model completed in Phase 19. The scope is focused on infrastructure: entitlements, framework linking, conditional ModelContainer configuration, and content-type filtering to exclude concealed/image/file items from sync. There is no new UI in this phase (sync toggle and status indicator are in Phase 21).

The critical technical concerns are: (1) CloudKit.framework must be explicitly linked for macOS release builds (silent sync failure otherwise), (2) the entitlements file must include iCloud + CloudKit container identifiers, (3) the `ModelConfiguration` must be conditionally configured with `cloudKitDatabase: .automatic` vs `.none` based on a UserDefaults flag, (4) concealed and image/file items must be excluded from appearing on remote devices, and (5) the CloudKit schema must be initialized via `initializeCloudKitSchema()` during development.

The biggest unknown going into this phase was whether `cloudKitDatabase: .none` reliably prevents sync. Web search results confirm conflicting reports -- some developers report `.none` still syncs when CloudKit entitlements are present. However, Apple's official documentation explicitly lists `.none` as the mechanism to disable sync, and the Hacking with Swift guide treats it as the standard approach. The recommendation is to use `.none` as the primary mechanism and validate in testing. If it fails, the fallback is to not add CloudKit container options to the persistent store description at all (via custom Core Data configuration).

**Primary recommendation:** Split into 2 plans -- Plan 1: Xcode project configuration (entitlements, framework linking, project.yml), conditional ModelContainer, and CloudKit schema initialization. Plan 2: Content filtering (concealed exclusion, image/file exclusion), cross-device sync verification, and Debug/Release build validation.

## Standard Stack

### Core (unchanged from Phase 19)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData | macOS 14+ | Persistence with CloudKit sync | Built-in CloudKit integration via ModelConfiguration |
| CloudKit | macOS 14+ | iCloud private database sync | Apple's first-party cloud sync framework |
| CoreData | macOS 14+ | Underlying persistence layer | SwiftData wraps NSPersistentCloudKitContainer |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| OSLog | macOS 14+ | Structured logging | Sync event logging, debugging |
| CryptoKit | macOS 14+ | SHA256 hashing | Already in use for contentHash |

### No New Dependencies

Phase 20 adds zero new packages. CloudKit.framework is a system framework that must be explicitly linked but is not a third-party dependency. All changes use Apple's built-in frameworks.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftData built-in CloudKit | CKSyncEngine | CKSyncEngine is for apps WITHOUT SwiftData/CoreData. Using both would create conflicting sync layers. NOT appropriate here. |
| SwiftData built-in CloudKit | SwiftDataSync (FiveSheepCo) | Third-party package offering selective property sync. Adds dependency complexity. SwiftData's built-in approach is sufficient for v1.5 text-only sync. |
| `cloudKitDatabase: .none` | Remove CloudKit entitlements entirely | Would prevent sync from ever being enabled without app update. `.none` is the designed toggle mechanism. |

## Architecture Patterns

### Recommended File Changes

```
Pastel/
  Resources/
    Pastel.entitlements        # ADD: iCloud, CloudKit container, Push Notifications entitlements
  PastelApp.swift              # MODIFY: Conditional ModelConfiguration (CloudKit vs local)
  App/
    AppState.swift             # MODIFY: Wire transactionAuthor on ModelContext
  Services/
    ClipboardMonitor.swift     # MODIFY: Filter concealed/image/file items from sync display
project.yml                    # MODIFY: Add CloudKit.framework dependency
```

### Pattern 1: Conditional ModelContainer Configuration

**What:** At app launch, read a UserDefaults flag to decide whether CloudKit sync is active. Create the ModelContainer with the appropriate configuration.

**When to use:** In `PastelApp.init()`, replacing the current unconditional ModelContainer creation.

**Example:**
```swift
// Source: Apple Documentation - Syncing model data across a person's devices
// + Hacking with Swift - How to sync SwiftData with iCloud

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

**Confidence: HIGH** -- This is the documented Apple pattern from official SwiftData documentation. Both `.private()` and `.none` are official API.

### Pattern 2: CloudKit Schema Initialization (DEBUG only)

**What:** Force-push the complete CloudKit schema to the development environment so all record types and fields exist before any data is written.

**When to use:** Once during development, after model is finalized. Run in DEBUG, verify in CloudKit Dashboard, then comment out or gate behind a launch argument.

**Example:**
```swift
// Source: Apple Documentation - Syncing model data across a person's devices
#if DEBUG
try autoreleasepool {
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
            if let err { fatalError(err.localizedDescription) }
        }
        try ckContainer.initializeCloudKitSchema()
        if let store = ckContainer.persistentStoreCoordinator.persistentStores.first {
            try ckContainer.persistentStoreCoordinator.remove(store)
        }
    }
}
#endif
```

**Confidence: HIGH** -- This is Apple's official recommended approach from their "Syncing model data" documentation, verified via Context7.

### Pattern 3: Accessing Core Data Layer from SwiftData

**What:** Access the underlying `NSManagedObjectContext` and `NSPersistentStoreCoordinator` from SwiftData's `ModelContext` for operations not exposed by SwiftData's public API (transactionAuthor, event monitoring).

**When to use:** Setting transactionAuthor, registering for NSPersistentCloudKitContainer event notifications, registering for NSPersistentStoreRemoteChange notifications.

**Example:**
```swift
// Source: fatbobman - SwiftDataKit
// Mirror-based access to the underlying Core Data context
extension ModelContext {
    var managedObjectContext: NSManagedObjectContext? {
        guard let moc = Mirror(reflecting: self)
            .children.first(where: { $0.label == "_nsContext" })?
            .value as? NSManagedObjectContext else {
            return nil
        }
        return moc
    }

    var coordinator: NSPersistentStoreCoordinator? {
        managedObjectContext?.persistentStoreCoordinator
    }
}
```

**Confidence: MEDIUM** -- This uses Swift Mirror reflection on a private property (`_nsContext`). It is widely used (fatbobman, CloudKitSyncMonitor, multiple production apps) and stable across SwiftData versions, but it is not a public API. Apple could change the internal property name in a future release. For Phase 20, this is needed for sync monitoring (Phase 21) and transactionAuthor (optional for Phase 20, critical for Phase 21's dedup). The planner should decide whether to add this in Phase 20 or defer to Phase 21.

### Pattern 4: Content Filtering for Sync (Concealed + Image/File Exclusion)

**What:** Prevent concealed items (passwords) and image/file items from appearing on remote devices. Since SwiftData's single-store CloudKit sync syncs ALL records (no per-record sync exclusion), the approach is to sync the metadata but hide excluded items on receiving devices.

**When to use:** Concealed items must NEVER appear on other devices. Image/file items are excluded from v1.5 sync scope.

**Implementation approach:**
SwiftData does NOT support per-record sync exclusion with a single store. All `ClipboardItem` records in the CloudKit-enabled store will sync to iCloud. The exclusion must happen at the display/query layer on receiving devices:

1. Concealed items: `isConcealed == true` items sync their metadata to CloudKit but are hidden on receiving devices. Since concealed items expire in 60 seconds on the originating device, the deletion also syncs -- so the concealed data exists in CloudKit only transiently. On receiving devices, ExpirationService does not run for these items (no timer), but the deletion propagates via CloudKit shortly after.

2. Image/file items: These items have `imagePath`/`thumbnailPath` that reference local files. On receiving devices, the file paths are meaningless. Image items should be hidden on remote devices (or shown as "Image copied on [device]" placeholders).

**Filtering mechanism:** Add a computed `isSyncExcluded` check or use the existing `isConcealed`, `contentType` fields in `@Query` predicates on receiving devices to hide excluded items. Alternatively, do NOT add any items that should not be visible -- instead, accept that they sync and ensure the UI handles them gracefully.

**Simplest viable approach for v1.5:** Do NOT filter at the sync layer. Let all items sync. On receiving devices, items with `isConcealed == true` or `contentType == "image"` or `contentType == "file"` are simply not useful (concealed ones self-delete via synced deletion, image/file ones have no displayable content). The existing UI already handles nil `textContent` gracefully. The only real risk is a brief window where a concealed item appears on another device before the deletion syncs.

**Stronger approach:** Prevent concealed items from being inserted into the CloudKit-enabled store entirely. This requires a dual-store approach (separate local-only store for concealed items) which is architecturally complex and out of scope for v1.5.

**Recommended for v1.5:** Accept that concealed items briefly sync (the deletion follows within 60 seconds). Add a predicate to panel/history queries that filters out `isConcealed == true` items from OTHER devices (items where `originDeviceID != DeviceIdentifier.current && isConcealed == true`). This is a display-level filter, not a sync-level filter. For image/file items, they sync but are effectively inert on other devices (no image data, just metadata).

**Confidence: MEDIUM** -- The display-level filtering approach is pragmatic but not ideal for concealed items. The transient exposure window (up to 60 seconds for concealed items in CloudKit) is a real concern. However, the concealed item's textContent is typically a password string that would require accessing the raw SwiftData/CloudKit record to see -- it does not appear in the panel on the receiving device because ExpirationService would handle cleanup once the synced item arrives. The stronger dual-store approach is deferred.

**IMPORTANT REVISION:** After further analysis, the concealed item concern is actually minimal:
- Concealed items have `expiresAt` set to 60 seconds from capture
- On the originating device, ExpirationService deletes them at expiry
- The deletion syncs via CloudKit to other devices
- On receiving devices, even if the item briefly exists in the store, it has `isConcealed == true` -- the panel/history queries should filter these out
- The window of exposure is: (capture) -> (CloudKit export ~5-30s) -> (CloudKit import on other device ~5-30s) -> (deletion export from originating device ~5-30s after expiry) = potentially 2-3 minutes where the record EXISTS in CloudKit but is NEVER displayed on other devices if the query properly filters `isConcealed == true`

### Anti-Patterns to Avoid

- **Skipping CloudKit.framework linking:** The #1 macOS CloudKit pitfall. Sync works in Debug, silently fails in Release. Must add to project.yml dependencies.
- **Using `.automatic` without specifying container ID:** While `.automatic` picks up the container from entitlements, using `.private("iCloud.app.pastel.Pastel")` is more explicit and self-documenting.
- **Adding Background Modes capability for macOS:** Background Modes is an iOS-only capability. macOS does NOT need it for CloudKit sync. Adding it to a macOS target causes Xcode configuration warnings.
- **Trying to recreate ModelContainer at runtime:** The ModelContainer is created once in `PastelApp.init()`. Changing the CloudKit configuration requires app restart.
- **Skipping `initializeCloudKitSchema()`:** JIT schema inference can be incomplete. Always run the initialization step during development to ensure the full schema exists in CloudKit.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CloudKit sync engine | Custom CKRecord sync | `ModelConfiguration(cloudKitDatabase: .private(...))` | SwiftData wraps NSPersistentCloudKitContainer automatically |
| Schema push to CloudKit | Manual CKRecord type creation | `NSPersistentCloudKitContainer.initializeCloudKitSchema()` | Handles all fields, relationships, indexes correctly |
| Sync enable/disable | Runtime ModelContainer swap | UserDefaults flag + app restart | ModelContainer cannot be safely recreated at runtime |
| Push notification handling | Manual CKSubscription + notification processing | Built-in NSPersistentCloudKitContainer | Automatic silent push handling for sync |

**Key insight:** Phase 20 is primarily a configuration and infrastructure phase. The amount of NEW code is small -- the heavy lifting is done by SwiftData's built-in CloudKit integration. The challenge is getting the configuration exactly right (entitlements, framework linking, container ID) because mistakes produce silent failures, not crashes.

## Common Pitfalls

### Pitfall 1: CloudKit.framework Not Linked for macOS Release Builds

**What goes wrong:** Sync works perfectly in Xcode Debug builds but silently fails in TestFlight/App Store builds. No crashes, no errors -- sync simply does nothing in production.

**Why it happens:** Unlike iOS, macOS does not automatically link CloudKit.framework when CloudKit capabilities are added. Debug builds load the framework permissively; Release builds enforce strict dependency resolution.

**How to avoid:** Add `CloudKit.framework` explicitly to project.yml dependencies:
```yaml
dependencies:
  - package: KeyboardShortcuts
  - package: LaunchAtLogin
  - package: HighlightSwift
  - framework: CloudKit.framework
    embed: false
```

**Warning signs:** Sync works in Debug, not in Archive/TestFlight. CloudKit Dashboard shows no records being created from Release builds. Zero error messages.

**Confidence: HIGH** -- Confirmed by fatbobman, Apple Developer Forums, and multiple independent reports.

### Pitfall 2: Missing or Incorrect Entitlements

**What goes wrong:** App compiles and runs but sync silently fails because entitlements are missing or malformed.

**Why it happens:** CloudKit requires specific entitlement keys that must be added to the `.entitlements` plist. XcodeGen does NOT automatically add these when capabilities are configured.

**How to avoid:** Manually verify the entitlements file contains ALL required keys:
- `com.apple.developer.icloud-container-identifiers` (array with container ID)
- `com.apple.developer.icloud-services` (array with "CloudKit")
- `com.apple.developer.aps-environment` (for push notifications -- "development" or "production")

Also register the iCloud container in the Apple Developer portal and regenerate provisioning profiles.

**Warning signs:** Console shows "no iCloud container" or "missing entitlement" errors. CloudKit Dashboard shows no containers for the app.

**Confidence: HIGH** -- Standard CloudKit setup requirement.

### Pitfall 3: `cloudKitDatabase: .none` May Not Fully Prevent Sync

**What goes wrong:** Some developers report that `.none` does not reliably prevent sync when CloudKit entitlements are present. Items may still sync despite the configuration.

**Why it happens:** Conflicting reports suggest that the `.none` configuration may be ignored in some SwiftData versions or when certain entitlements trigger automatic CloudKit initialization.

**How to avoid:**
1. Use `.none` as the primary mechanism (it IS the documented API).
2. Test thoroughly: enable sync on one device, disable on another, verify no items cross.
3. If `.none` fails, the fallback is to conditionally include/exclude the CloudKit container options entirely.

**Warning signs:** Items appearing on a device where sync is disabled. Unexpected CloudKit activity in Console logs.

**Confidence: LOW** -- Conflicting reports. Apple's documentation says `.none` disables sync. Some developers say it does not. Must be validated during implementation.

### Pitfall 4: CloudKit Schema Not Deployed to Production

**What goes wrong:** Sync works in Xcode Debug (Development CloudKit environment) but fails in TestFlight/App Store (Production CloudKit environment).

**Why it happens:** CloudKit has separate Development and Production environments with separate schemas. The Development environment auto-generates schema via JIT. Production does NOT -- you must manually deploy the schema from the CloudKit Dashboard.

**How to avoid:**
1. Run `initializeCloudKitSchema()` in DEBUG to push complete schema to Development.
2. Verify schema in CloudKit Dashboard (https://icloud.developer.apple.com/dashboard).
3. Deploy schema to Production BEFORE any TestFlight/App Store build.
4. Re-deploy schema every time model properties are added.

**Warning signs:** TestFlight builds show CloudKit errors about unknown record types. CloudKit Dashboard shows empty schema in Production.

**Confidence: HIGH** -- Well-documented Apple requirement.

### Pitfall 5: macOS Does NOT Need Background Modes for CloudKit

**What goes wrong:** Developer adds "Background Modes" capability to macOS target (copying iOS guides) which causes Xcode warnings or configuration errors.

**Why it happens:** Most CloudKit sync guides are iOS-focused and include "Add Background Modes with Remote Notifications" as a required step. This is iOS-only. macOS handles remote notifications differently.

**How to avoid:** For macOS, only add the iCloud capability with CloudKit and the Push Notifications capability (which provides the `com.apple.developer.aps-environment` entitlement). Do NOT add Background Modes.

**Warning signs:** Xcode shows "Background Modes is not available for macOS" or similar warnings.

**Confidence: HIGH** -- Confirmed by Apple Developer Forums post stating "Background Mode capability is only for iOS, it is fine to not set up if your app is only for macOS."

### Pitfall 6: Concealed Items Briefly Exist in CloudKit

**What goes wrong:** A password copied from 1Password is captured with `isConcealed = true`, syncs to CloudKit, and briefly exists in the cloud database before the 60-second expiration deletes it locally and the deletion propagates.

**Why it happens:** SwiftData's single-store CloudKit sync has no per-record sync exclusion. All records in the CloudKit-enabled store sync.

**How to avoid:** Ensure `@Query` predicates in panel and history views filter out `isConcealed == true` items that originated from other devices. The concealed item's deletion (after 60s expiry) syncs and removes it from CloudKit. The exposure window is brief and the data is never displayed on receiving devices.

**Warning signs:** CloudKit Dashboard shows `isConcealed == true` records (temporarily). These should disappear within minutes.

**Confidence: MEDIUM** -- The transient exposure is a design limitation of single-store sync. Acceptable for v1.5; dual-store approach deferred.

## Code Examples

Verified patterns from official sources:

### Entitlements File (Complete)

```xml
<!-- Pastel/Resources/Pastel.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Existing entitlements -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>

    <!-- NEW: iCloud + CloudKit -->
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.app.pastel.Pastel</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>

    <!-- NEW: Push Notifications (required for CloudKit sync notifications) -->
    <key>com.apple.developer.aps-environment</key>
    <string>development</string>
</dict>
</plist>
```

**Note on `aps-environment`:** Set to `development` during development. Xcode's automatic code signing will set this to `production` for distribution builds. If using manual signing, this must be changed to `production` before App Store submission.

**Note on `CloudDocuments`:** The `com.apple.developer.icloud-services` array does NOT need "CloudDocuments" -- that is only for iCloud Drive document storage. CloudKit alone is sufficient for SwiftData sync.

### project.yml Changes

```yaml
# Add CloudKit.framework to the dependencies list
dependencies:
  - package: KeyboardShortcuts
  - package: LaunchAtLogin
  - package: HighlightSwift
  - framework: CloudKit.framework
    embed: false
```

### Conditional ModelContainer in PastelApp.swift

```swift
// Source: Apple Documentation - ModelConfiguration.CloudKitDatabase

@main
struct PastelApp: App {
    let modelContainer: ModelContainer
    @State private var appState: AppState

    init() {
        let container: ModelContainer
        do {
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
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        self.modelContainer = container

        let state = AppState()
        state.setup(modelContext: container.mainContext)
        state.setupPanel(modelContainer: container)
        state.modelContainer = container
        MigrationService.migrateLabelsIfNeeded(modelContext: container.mainContext)
        state.handleFirstLaunch()

        self._appState = State(initialValue: state)
    }
    // ... rest unchanged
}
```

### CloudKit Schema Initialization (DEBUG only)

```swift
// Source: Apple Documentation - Syncing model data across a person's devices
// Place in PastelApp.init(), BEFORE creating the main ModelContainer
// Run ONCE after model changes, then comment out or gate behind launch argument

#if DEBUG
if ProcessInfo.processInfo.arguments.contains("-initializeCloudKitSchema") {
    let tempConfig = ModelConfiguration()
    try autoreleasepool {
        let desc = NSPersistentStoreDescription(url: tempConfig.url)
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
                if let err { fatalError("Schema init error: \(err)") }
            }
            try ckContainer.initializeCloudKitSchema()
            if let store = ckContainer.persistentStoreCoordinator
                .persistentStores.first {
                try ckContainer.persistentStoreCoordinator.remove(store)
            }
        }
    }
}
#endif
```

**Usage:** Add `-initializeCloudKitSchema` to the Xcode scheme's launch arguments, run once, then remove.

### TransactionAuthor Setup

```swift
// In AppState.setup(modelContext:), set transactionAuthor so
// local writes are distinguishable from CloudKit imports
// (needed for Phase 21 dedup, but safe to add in Phase 20)

func setup(modelContext: ModelContext) {
    // Set transaction author for local writes
    modelContext.managedObjectContext?.transactionAuthor = "app"

    // ... existing ClipboardMonitor and RetentionService setup ...
}
```

**Note:** This requires the ModelContext extension to access `managedObjectContext` via Mirror reflection (Pattern 3 above). If the planner defers this to Phase 21, that is acceptable -- it is not strictly required for Phase 20's success criteria.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual CKRecord management | SwiftData `ModelConfiguration(cloudKitDatabase:)` | WWDC 2023 (SwiftData launch) | Zero sync code needed for basic CloudKit integration |
| CKSyncEngine for custom sync | NSPersistentCloudKitContainer (auto) | CKSyncEngine is for NON-CoreData apps | Do NOT use CKSyncEngine with SwiftData |
| `NSPersistentCloudKitContainer` direct setup | SwiftData wraps this automatically | macOS 14+ / iOS 17+ | Access underlying container only for advanced features (schema init, event monitoring) |
| iOS: Background Modes + Remote Notifications | macOS: Push Notifications only, NO Background Modes | Platform-specific | macOS does not use Background Modes for CloudKit sync |

**Deprecated/outdated:**
- `CloudDocuments` in iCloud services: Only needed for iCloud Drive document storage, NOT for SwiftData CloudKit sync. Some older guides include it unnecessarily.
- Manual `CKSubscription` setup: Not needed with NSPersistentCloudKitContainer -- it handles subscription and notification processing automatically.

## Open Questions

1. **Does `cloudKitDatabase: .none` reliably prevent sync on macOS?**
   - What we know: Apple's documentation says `.none` disables managed CloudKit sync. Hacking with Swift and fatbobman treat it as the standard toggle mechanism.
   - What's unclear: Some developer reports (Apple Forums thread 731375) suggest `.none` may not reliably prevent sync when CloudKit entitlements are present in the app bundle.
   - Recommendation: Implement with `.none`, test thoroughly. If it syncs despite `.none`, the fallback is to conditionally add/remove the `cloudKitContainerOptions` on the `NSPersistentStoreDescription` at the Core Data level (more involved but definitive).

2. **Is `com.apple.developer.aps-environment` strictly required for macOS CloudKit sync?**
   - What we know: iOS requires the Push Notifications capability for CloudKit. macOS CloudKit sync documentation is less explicit about this requirement.
   - What's unclear: Whether macOS SwiftData CloudKit sync works without the `aps-environment` entitlement. Some macOS CloudKit apps include it; others do not explicitly.
   - Recommendation: Include it. The entitlement enables silent push notifications which CloudKit uses to trigger sync. Without it, sync may rely on polling only (slower). Adding the entitlement has no downside.

3. **How does macOS handle CloudKit push notifications for LSUIElement (menu bar) apps?**
   - What we know: Pastel is an LSUIElement app (no dock icon). CloudKit uses silent push notifications for sync triggers. LSUIElement apps can receive notifications.
   - What's unclear: Whether there are any quirks with notification delivery to agent apps vs regular apps. Silent push notifications should work regardless of UIElement status since they do not show UI.
   - Recommendation: Proceed with standard setup. If sync is slow or inconsistent, investigate notification delivery as a potential cause.

4. **Should transactionAuthor be set in Phase 20 or Phase 21?**
   - What we know: `transactionAuthor` is needed for dedup (Phase 21) to distinguish local vs remote writes. Setting it in Phase 20 is harmless and forward-looking.
   - What's unclear: Whether the Mirror-based access to `managedObjectContext` is worth adding in Phase 20 when it is only strictly needed in Phase 21.
   - Recommendation: Defer to planner. If Phase 20 keeps it simple (configuration only), defer transactionAuthor to Phase 21. If Phase 20 adds the ModelContext extension for any reason, include transactionAuthor.

## Exact Changes Required

### File: `Pastel/Resources/Pastel.entitlements`

**Add** iCloud container identifiers, CloudKit service, and APS environment entitlements. Keep existing sandbox, network, and file entitlements.

### File: `project.yml`

**Add** `CloudKit.framework` to the dependencies list with `embed: false`.

### File: `Pastel/PastelApp.swift`

**Replace** unconditional `ModelContainer(for: ClipboardItem.self, Label.self)` with conditional configuration based on `UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")`.

**Add** (optional, DEBUG-only) CloudKit schema initialization gated behind launch argument.

### File: `Pastel/App/AppState.swift` (optional in Phase 20)

**Add** `modelContext.managedObjectContext?.transactionAuthor = "app"` in `setup(modelContext:)`. Requires new ModelContext extension.

### File: New `Pastel/Extensions/ModelContext+CoreData.swift` (optional in Phase 20)

**Add** extension to access underlying `NSManagedObjectContext` via Mirror reflection. Only if transactionAuthor is included in Phase 20.

### CloudKit Dashboard (manual step)

1. Create iCloud container `iCloud.app.pastel.Pastel` in Apple Developer portal
2. Run app with `-initializeCloudKitSchema` launch argument
3. Verify schema in CloudKit Dashboard shows `CD_ClipboardItem` and `CD_Label` record types
4. Deploy schema to Production when ready for TestFlight

## Verification Strategy

### Requirement SYNC-05: Entitlements and Framework Linking

1. Build the app in Debug configuration -- verify sync starts (if enabled) or stays off (if disabled)
2. Build the app in Release configuration (Archive) -- verify CloudKit.framework is linked by checking `otool -L` on the built binary
3. Verify `codesign -d --entitlements :- Pastel.app` shows all required iCloud entitlements

### Requirement SYNC-06: Conditional ModelContainer

1. With `iCloudSyncEnabled = false` (default): verify app launches, clipboard capture works, no CloudKit activity in Console
2. With `iCloudSyncEnabled = true`: verify app launches, ModelContainer configures CloudKit, Console shows CloudKit initialization

### Requirement SYNC-07: Items Sync Across Macs

1. Enable sync on two Macs with same Apple ID
2. Copy text on Mac A, verify it appears in panel on Mac B within 2-3 minutes
3. Verify URL, code, and color items also sync

### Requirement SYNC-08: Labels Sync with Relationships

1. Create a label on Mac A, assign it to an item
2. Verify both label and assignment appear on Mac B
3. Verify label changes (rename, color change) propagate

### Requirement SYNC-10: Concealed Items Never Appear on Remote Devices

1. Copy a concealed item (from 1Password or using `org.nspasteboard.ConcealedType`)
2. Verify it does NOT appear in the panel on Mac B
3. Verify the concealed item is deleted on Mac A after 60 seconds AND the deletion propagates to CloudKit

### Requirement SYNC-11: Image/File Items Excluded

1. Copy an image on Mac A
2. Verify it does NOT appear usefully on Mac B (metadata may sync but no image data)
3. Copy a file reference on Mac A, verify it does NOT appear usefully on Mac B

## Sources

### Primary (HIGH confidence)
- [Apple Documentation: Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) -- Official SwiftData CloudKit setup, verified via Context7 (`/websites/developer_apple_swiftdata`)
- [Apple Documentation: ModelConfiguration.CloudKitDatabase](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct/) -- `.automatic`, `.private()`, `.none` API, verified via Context7
- [Apple Documentation: NSPersistentCloudKitContainer](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer) -- Event monitoring, schema initialization
- [Apple TN3164: Debugging NSPersistentCloudKitContainer](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer) -- Debugging sync issues
- [fatbobman: Fix macOS SwiftData/CoreData Sync (CloudKit.framework)](https://fatbobman.com/en/snippet/fix-synchronization-issues-for-macos-apps-using-core-dataswiftdata/) -- macOS framework linking pitfall
- [fatbobman: initializeCloudKitSchema for SwiftData](https://fatbobman.com/en/snippet/resolving-incomplete-icloud-data-sync-in-ios-development-using-initializecloudkitschema/) -- Schema initialization pattern
- Codebase analysis -- Direct reading of PastelApp.swift, AppState.swift, ClipboardMonitor.swift, Pastel.entitlements, project.yml, ClipboardItem.swift, Label.swift

### Secondary (MEDIUM confidence)
- [Hacking with Swift: How to sync SwiftData with iCloud](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-sync-swiftdata-with-icloud) -- Setup walkthrough
- [Hacking with Swift: How to stop SwiftData syncing with CloudKit](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-stop-swiftdata-syncing-with-cloudkit) -- `.none` configuration
- [fatbobman: SwiftDataKit](https://fatbobman.com/en/posts/use-core-data-features-in-swiftdata-by-swiftdatakit/) -- ModelContext to NSManagedObjectContext access
- [CloudKitSyncMonitor (GitHub)](https://github.com/ggruen/CloudKitSyncMonitor) -- Validates event monitoring approach
- [3 Things I Wish I Knew: SwiftData + CloudKit (Medium)](https://carolanelefebvre.medium.com/en-3-things-i-wish-i-knew-before-starting-with-swiftdata-cloudkit-bb53df9bb6b1) -- Practical pitfalls
- Phase 19 research (`.planning/phases/19-cloudkit-compatible-data-model/19-RESEARCH.md`) -- Data model compatibility
- Milestone research (`.planning/research/ARCHITECTURE.md`, `.planning/research/PITFALLS.md`) -- Architecture and pitfalls from v1.5 planning

### Tertiary (LOW confidence)
- `cloudKitDatabase: .none` reliability -- conflicting developer reports, needs testing
- macOS `aps-environment` entitlement requirement for CloudKit sync -- not explicitly documented for macOS
- LSUIElement app CloudKit push notification delivery -- no specific documentation found

## Metadata

**Confidence breakdown:**
- Entitlements and framework linking: HIGH -- well-documented, confirmed by multiple sources
- Conditional ModelContainer: HIGH -- Apple's official documented API
- CloudKit schema initialization: HIGH -- Apple's official sample code pattern
- Content filtering (concealed/image): MEDIUM -- display-level filtering is pragmatic but not ideal
- `.none` reliability: LOW -- conflicting reports, needs validation
- macOS push notification details: MEDIUM -- likely works but sparse macOS-specific documentation

**Research date:** 2026-02-14
**Valid until:** 2026-03-14 (stable domain, no fast-moving dependencies)
