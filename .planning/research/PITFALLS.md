# Pitfalls Research: v1.5 iCloud Sync

**Domain:** macOS clipboard manager -- adding iCloud sync (CloudKit via SwiftData) to existing local-only SwiftData app with clipboard monitoring, content hash deduplication, label relationships, and retention-based cleanup
**Researched:** 2026-02-14
**Confidence:** HIGH for model compatibility issues (verified with Apple documentation, fatbobman.com analysis, and developer forum reports); MEDIUM for sync loop and deduplication scenarios (architecture-specific to Pastel, based on CloudKit behavioral patterns); MEDIUM for privacy/storage recommendations (based on Apple iCloud security documentation and CloudKit quota behavior)

---

## Critical Pitfalls

Mistakes that cause data loss, app crashes on launch, or complete sync failure. Must be addressed before any sync code ships.

---

### Pitfall 1: @Attribute(.unique) on contentHash Is Incompatible with CloudKit

**What goes wrong:**
Pastel's `ClipboardItem` model declares `@Attribute(.unique) var contentHash: String`. CloudKit does not support unique constraints -- it cannot enforce atomic uniqueness across distributed devices. When SwiftData attempts to initialize the CloudKit-backed store with this attribute, the `ModelContainer` will refuse to load, crashing the app on launch. This is not a degraded-sync scenario; it is a hard crash that prevents the app from starting at all.

The current code in `ClipboardItem.swift` line 49:
```swift
@Attribute(.unique) var contentHash: String
```

**Why it happens:**
CloudKit is an eventually-consistent distributed system. Two devices can simultaneously create records with the same contentHash, and CloudKit has no mechanism to reject one atomically. Apple explicitly forbids unique constraints in CloudKit-synced models because enforcement is architecturally impossible.

**Specific risk in Pastel's architecture:**
- `contentHash` is the primary deduplication mechanism. `ClipboardMonitor.processPasteboardContent()` relies on the unique constraint to reject non-consecutive duplicates via the `modelContext.save()` catch block (line 308-313). Removing `@Attribute(.unique)` means duplicate items from different devices WILL be inserted without error.
- The `isDuplicateOfMostRecent()` method only checks the single most recent item. Non-consecutive duplicates across devices (Device A copies "hello", Device B copies "hello" 5 minutes later) will create two records.
- `ImportExportService.importHistory()` uses in-memory hash sets for dedup, but this only works for local import -- synced items arrive asynchronously via CloudKit background processing, bypassing this logic entirely.

**How to avoid:**
1. Remove `@Attribute(.unique)` from `contentHash` before enabling CloudKit.
2. Implement application-level deduplication using persistent history tracking: listen for `NSPersistentStoreRemoteChange` notifications, fetch incoming records, compare contentHash values against existing local records, and delete duplicates (keeping the record with the earliest timestamp or smallest UUID for deterministic winner selection across devices).
3. The dedup must be idempotent and deterministic -- all devices must converge to the same winner. Apple's recommended pattern: sort duplicates by a stable property (UUID), keep the first, delete the rest.

**Warning signs:**
- App crashes immediately on launch after enabling CloudKit with error: "CloudKit integration does not support unique constraints"
- `ModelContainer` initializer throws, hitting the `fatalError` in `PastelApp.init()`
- No crash in development but crash in TestFlight/App Store builds (different CloudKit environments)

**Consequences:** Complete app failure. Users cannot launch the app. Existing local data is inaccessible.
**Detection:** Attempt to create `ModelContainer` with `cloudKitDatabase: .automatic` -- crash is immediate.
**Phase to address:** Must be the first change in the model preparation phase, before any sync logic.

**Sources:**
- [Designing Models for CloudKit Sync (fatbobman.com)](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/)
- [Apple Developer Forums: CloudKit does not support unique constraints](https://developer.apple.com/forums/thread/656380)
- [SwiftData CloudKit Quirks (firewhale.io)](https://firewhale.io/posts/swift-data-quirks/)

---

### Pitfall 2: Non-Optional Properties Without Defaults Break CloudKit Store Initialization

**What goes wrong:**
CloudKit requires that ALL model attributes be either optional or have a default value. Pastel's `ClipboardItem` has several required non-optional properties without defaults in the model definition itself:

```swift
var contentType: String          // Non-optional, no default in @Model declaration
var timestamp: Date              // Non-optional, no default in @Model declaration
var characterCount: Int          // Non-optional, no default in @Model declaration
var byteCount: Int               // Non-optional, no default in @Model declaration
var changeCount: Int             // Non-optional, no default in @Model declaration
var isConcealed: Bool            // Non-optional, no default in @Model declaration
var contentHash: String          // Non-optional, no default in @Model declaration
```

While these properties have default values in the `init()` method, CloudKit requires defaults at the property declaration level (or optionality) because synced records may arrive from the cloud before all fields are populated -- CloudKit handles "partial data" scenarios where a record exists but not all fields have synced yet.

Similarly, `Label` has non-optional properties:
```swift
var name: String                 // Non-optional, no default
var colorName: String            // Non-optional, no default
var sortOrder: Int               // Non-optional, no default
```

**Why it happens:**
Core Data (which SwiftData wraps) validates the model schema against CloudKit requirements when the persistent store is configured. Init-time defaults are Swift-level constructs invisible to Core Data's schema analysis. The Core Data layer examines the property declarations themselves.

**Specific risk in Pastel's architecture:**
- The `ModelContainer` creation in `PastelApp.init()` will throw when CloudKit is enabled, hitting the `fatalError`.
- Both `ClipboardItem` and `Label` need modification, plus the `@Relationship` between them.
- The many-to-many relationship `var labels: [Label]` and inverse `var items: [ClipboardItem]` must become optional: `var labels: [Label]?` and `var items: [ClipboardItem]?`. This cascades to dozens of call sites that currently assume non-optional arrays.

**How to avoid:**
1. Add default values to all property declarations:
   ```swift
   var contentType: String = "text"
   var timestamp: Date = .now
   var characterCount: Int = 0
   var byteCount: Int = 0
   var changeCount: Int = 0
   var isConcealed: Bool = false
   var contentHash: String = ""
   ```
2. Make relationship arrays optional with computed accessors:
   ```swift
   @Relationship(deleteRule: .nullify, inverse: \Label.items)
   var _labels: [Label]?

   var labels: [Label] {
       get { _labels ?? [] }
       set { _labels = newValue }
   }
   ```
3. Add defaults to Label properties similarly.
4. These are lightweight migration-compatible changes (adding defaults to existing properties).

**Warning signs:**
- Error on launch: "CloudKit integration requires that all attributes be optional, or have a default value set"
- Works in development with `.none` CloudKit database but fails when CloudKit is enabled
- Works locally but crashes in TestFlight builds

**Consequences:** App crash on launch, identical to Pitfall 1.
**Detection:** Compile succeeds, but runtime ModelContainer creation fails.
**Phase to address:** Must be addressed in the same model preparation phase as Pitfall 1.

**Sources:**
- [SwiftData CloudKit integration requirements (Apple Developer Forums)](https://developer.apple.com/forums/thread/735349)
- [3 Things I Wish I Knew (Medium)](https://carolanelefebvre.medium.com/en-3-things-i-wish-i-knew-before-starting-with-swiftdata-cloudkit-bb53df9bb6b1)
- [SwiftData Quirks with CloudKit (firewhale.io)](https://firewhale.io/posts/swift-data-quirks/)

---

### Pitfall 3: Synced Items Trigger Clipboard Monitor, Creating Infinite Sync Loop

**What goes wrong:**
When a clipboard item syncs from Device A to Device B, it arrives as a new SwiftData record in Device B's store. If any code on Device B writes this synced content to `NSPasteboard` (e.g., for preview, for paste-back, or for any feature that touches the pasteboard), the `ClipboardMonitor`'s 0.5s polling timer detects a pasteboard change, processes the content, creates a NEW `ClipboardItem` with the same content, which then syncs back to Device A, which may write it to the pasteboard, which triggers its monitor... creating an infinite sync loop that rapidly fills the database and consumes CloudKit quota.

**Why it happens:**
Pastel's clipboard monitoring architecture polls `NSPasteboard.general.changeCount` every 0.5 seconds. It has no concept of "this content originated from sync" versus "this content was copied by the user." The existing `skipNextChange` flag (line 30 in `ClipboardMonitor.swift`) only handles self-paste prevention for a single event -- it is not designed for ongoing sync-originated changes.

**Specific risk in Pastel's architecture:**
- `PasteService.paste(item:)` writes to `NSPasteboard` before simulating Cmd+V. If a user pastes a synced item, the monitor sees the write, potentially creating a duplicate.
- The existing `skipNextChange = true` pattern handles this for local paste-back, but does NOT handle the case where Device A's paste triggers a pasteboard change that syncs a "new" item to Device B.
- With content hash deduplication removed (Pitfall 1), the duplicate protection is weaker. Two devices could generate the same contentHash but the records would both persist.
- The `isDuplicateOfMostRecent()` check only compares against the SINGLE most recent item. If items arrive out of order from sync, consecutive dedup fails.

**How to avoid:**
1. Never automatically write synced items to the local pasteboard. Synced items should appear in the history UI only -- they are already captured on the originating device.
2. When the user explicitly pastes a synced item, use the existing `skipNextChange` mechanism to prevent re-capture.
3. Add an `originDeviceID` field to `ClipboardItem` (e.g., using a per-installation UUID stored in UserDefaults). The monitor should NOT capture items that match content recently synced from another device. Compare incoming pasteboard content hash against recently-synced item hashes (items where `originDeviceID != localDeviceID` and `timestamp` is within the last 60 seconds).
4. Consider a `Set<String>` of recently-synced content hashes that are excluded from capture for a time window.

**Warning signs:**
- Item count grows rapidly without user copying anything
- Same item appears multiple times in history
- CloudKit quota exceeded errors appear in console
- Excessive network activity after initial sync

**Consequences:** Database bloat, CloudKit quota exhaustion, battery drain from constant sync activity, degraded app performance.
**Detection:** Monitor item count growth rate; alert if more than N items created per minute without pasteboard activity.
**Phase to address:** Core sync architecture phase -- must be designed before any sync is enabled.

---

### Pitfall 4: Schema Deployed to CloudKit Production Cannot Be Rolled Back

**What goes wrong:**
CloudKit schema changes are one-way. Once you deploy a schema to the production environment (which is required for App Store/TestFlight builds), you CANNOT:
- Delete entities or attributes
- Rename entities or attributes (CloudKit interprets rename as delete + create, causing data loss)
- Change attribute data types
- Add unique constraints (not that you can, per Pitfall 1)

If you ship a model with a mistake -- wrong field name, wrong type, unnecessary field that bloats storage -- it stays in the schema forever. You can only ADD new attributes/entities and deprecate old ones.

**Why it happens:**
CloudKit maintains backward compatibility across app versions. Users on older app versions must be able to read records created by newer versions (and vice versa). Removing or changing fields would break older clients. This is fundamentally different from local-only SwiftData where you control the migration path.

**Specific risk in Pastel's architecture:**
- Pastel has already shipped v1.0-v1.4 with a local-only schema. The v1.5 schema modifications (adding defaults, removing unique constraint, adding sync metadata fields like `originDeviceID`, `syncStatus`, etc.) will become the PERMANENT CloudKit schema.
- Any fields added for sync (e.g., `lastSyncedAt`, `originDeviceID`, `isSynced`) must be carefully named and typed because they can never be changed.
- The deprecated `label: Label?` property (marked for removal in v1.3+) still exists in the model. Once CloudKit is enabled, it becomes permanent. It should be removed BEFORE enabling CloudKit, not after.
- If RTF data (`rtfData: Data?`) or HTML content (`htmlContent: String?`) are included in the synced schema, they consume iCloud quota permanently for every record, even if sync is later limited to text-only.

**How to avoid:**
1. Finalize the model schema COMPLETELY before the first CloudKit deployment. Review every property name, type, and purpose.
2. Remove the deprecated `label: Label?` property before enabling CloudKit (do this migration while still local-only).
3. Consider which fields actually need to sync vs. which are local-only (e.g., `changeCount` is device-specific and meaningless on other devices).
4. Use a `#if DEBUG` guarded `initializeCloudKitSchema()` call to verify the schema in development before deploying to production.
5. Keep a written record of every schema version deployed to CloudKit production.
6. Consider a separate local-only model for device-specific metadata and a sync-only model for shared data.

**Warning signs:**
- Schema deployed with typos in field names
- Unnecessary large fields (rtfData, htmlContent) synced when only text is needed
- Deprecated fields locked in permanently

**Consequences:** Permanent schema pollution, wasted iCloud storage on unnecessary fields, inability to clean up mistakes.
**Detection:** Review CloudKit Dashboard schema after first deployment; compare against intended design.
**Phase to address:** Model preparation phase, before any CloudKit capability is enabled.

**Sources:**
- [Designing Models for CloudKit Sync (fatbobman.com)](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/)
- [Deploy SwiftData CloudKit Schema Changes (leojkwan.com)](https://www.leojkwan.com/swiftdata-cloudkit-deploy-schema-changes/)

---

### Pitfall 5: macOS Release Builds Silently Fail to Sync Without Explicit CloudKit.framework Linking

**What goes wrong:**
On macOS specifically, SwiftData/Core Data CloudKit sync works perfectly in Xcode Debug builds but silently fails in TestFlight and App Store builds. The app launches, data saves locally, but nothing syncs to iCloud. There are no crashes, no obvious errors -- just silent sync failure. Users report "sync doesn't work" but the app appears functional otherwise.

**Why it happens:**
On iOS, Xcode implicitly links `CloudKit.framework` when it detects CloudKit usage. On macOS, this automatic linking does not always occur, particularly with XcodeGen-generated projects or migrated configurations. During Debug builds, the permissive debugger environment loads the framework anyway. Release builds enforce strict dependency resolution, and the CloudKit initialization silently fails.

**Specific risk in Pastel's architecture:**
- Pastel uses XcodeGen (`project.yml`) for project generation, which does not automatically add framework dependencies based on capability detection.
- The current `project.yml` has no explicit `CloudKit.framework` dependency -- only `KeyboardShortcuts`, `LaunchAtLogin`, and `HighlightSwift` packages.
- This will cause sync to work in development and fail in every production build, which is extremely difficult to diagnose because there are no crashes or error messages.

**How to avoid:**
1. Explicitly add `CloudKit.framework` to the project's linked frameworks in `project.yml`:
   ```yaml
   dependencies:
     - framework: CloudKit.framework
       embed: false
   ```
2. Or add it in Xcode under Build Phases > Link Binary With Libraries.
3. Test sync in a Release build (Archive and install locally) BEFORE submitting to TestFlight.
4. Verify sync works in TestFlight before App Store release.

**Warning signs:**
- Sync works in Debug but not in Release/TestFlight
- No crash logs, no obvious errors in Console
- Local data saves fine, just doesn't appear on other devices
- CloudKit Dashboard shows no records being created

**Consequences:** Complete sync failure in production, invisible to developer testing.
**Detection:** Always test Archive builds. Check CloudKit Dashboard for record creation.
**Phase to address:** Project configuration phase, when enabling CloudKit capability.

**Sources:**
- [Fixing macOS SwiftData/Core Data Sync: CloudKit.framework Issue (fatbobman.com)](https://fatbobman.com/en/snippet/fix-synchronization-issues-for-macos-apps-using-core-dataswiftdata/)

---

### Pitfall 6: Development vs. Production CloudKit Schema Mismatch

**What goes wrong:**
CloudKit has completely separate Development and Production environments with separate data stores and separate schemas. Your app works perfectly during development (Xcode Debug builds use the Development environment), but when you ship to TestFlight or the App Store (Production environment), sync fails because the schema was never deployed to Production. Data stays on-device and never syncs.

**Why it happens:**
In the Development environment, CloudKit auto-generates schema from your model using JIT (Just-In-Time) inference -- when you first save a record, CloudKit creates the corresponding record type. In Production, this does NOT happen. You must manually deploy the schema from Development to Production via the CloudKit Dashboard before releasing.

**Specific risk in Pastel's architecture:**
- Pastel has never used CloudKit. There is no existing CloudKit container, no schema in either environment.
- The first schema deployment must include both `ClipboardItem` and `Label` record types with all their attributes and the many-to-many relationship.
- If the `initializeCloudKitSchema()` step is skipped in development, the schema may be incomplete (missing relationship metadata, missing newly-added fields). JIT inference only creates schema for fields that actually have data written to them.
- SwiftData's automatic schema inference may not create CloudKit record types for entities that have no instances (e.g., if Label has no records during development, its schema may not be created).

**How to avoid:**
1. During development, call `initializeCloudKitSchema()` via the Core Data escape hatch to force complete schema creation:
   ```swift
   #if DEBUG
   // Access underlying Core Data container
   let container = try NSPersistentCloudKitContainer(/* ... */)
   try container.initializeCloudKitSchema()
   #endif
   ```
2. After schema is initialized in Development, open CloudKit Dashboard, verify ALL record types and fields exist.
3. Deploy schema to Production BEFORE any TestFlight or App Store build.
4. Re-deploy schema every time you add new fields to the model.
5. Test with a Production build (Ad Hoc or TestFlight) to verify sync works in Production.

**Warning signs:**
- Everything works in Xcode Debug, nothing syncs in TestFlight
- CloudKit Dashboard shows empty schema in Production environment
- Console logs show CloudKit errors about unknown record types

**Consequences:** Complete sync failure in production, no user data syncs.
**Detection:** Check CloudKit Dashboard Production schema before every release.
**Phase to address:** Deployment preparation, after model is finalized.

**Sources:**
- [Fixing SwiftData CloudKit Sync: initializeCloudKitSchema (fatbobman.com)](https://fatbobman.com/en/snippet/resolving-incomplete-icloud-data-sync-in-ios-development-using-initializecloudkitschema/)
- [Deploy SwiftData CloudKit Schema (leojkwan.com)](https://www.leojkwan.com/swiftdata-cloudkit-deploy-schema-changes/)
- [Fix Core Data/SwiftData Cloud Sync in Production (fatbobman.com)](https://fatbobman.com/en/snippet/why-core-data-or-swiftdata-cloud-sync-stops-working-after-app-store-login/)

---

## Moderate Pitfalls

Issues that cause degraded functionality, poor UX, or data inconsistency but do not crash the app or completely break sync.

---

### Pitfall 7: Conflict Resolution is Last-Writer-Wins with No Customization

**What goes wrong:**
SwiftData with CloudKit uses a fixed "last writer wins" merge policy at the attribute level. There is no API to customize conflict resolution. If Device A edits an item's title to "Meeting Notes" and Device B edits the same item's title to "Work Notes" before sync completes, whichever device syncs last silently overwrites the other. The user on the losing device sees their edit disappear with no notification, no merge UI, no conflict marker.

For relationships, CloudKit uses "last writer wins + merge" -- relationship additions from both sides are merged, but if both sides modify the same relationship differently, last-writer-wins applies.

**Why it happens:**
SwiftData does not expose `NSMergePolicy` configuration. Core Data's `NSPersistentCloudKitContainer` hard-codes the merge policy. There is no delegate method, no callback, and no way to intercept merge decisions.

**Specific risk in Pastel's architecture:**
- Label assignments are the primary editable metadata on clipboard items. If a user assigns Label "Work" on Device A and Label "Personal" on Device B to the same item (identified by contentHash), the relationship merge behavior will combine both labels (additive merge for relationships), which is actually acceptable.
- However, if a user changes an item's `title` on both devices, one title silently disappears.
- The `isConcealed` flag is dangerous: if Device A marks an item concealed (triggering 60-second expiration) and Device B does not, the eventual merge could either expose or hide the item depending on timing.
- Deletion is also last-writer-wins: if Device A deletes an item while Device B edits it, the deletion wins after sync completes.

**How to avoid:**
1. Accept last-writer-wins as the reality. Design features to minimize conflicts rather than trying to resolve them.
2. For clipboard items, the primary content (`textContent`, `contentHash`) should be immutable after creation -- never edited, only created or deleted. This eliminates content conflicts entirely.
3. For editable fields (`title`, labels), use timestamps to show users when the last edit occurred and which device it came from.
4. For the `isConcealed` flag, do NOT sync it. Concealed items (passwords) should never sync to iCloud at all.
5. Consider making deletion a soft-delete (`isDeleted: Bool` + `deletedAt: Date`) so that sync conflicts between edit and delete can be resolved (item reappears if edited after soft-delete, purged after grace period).

**Warning signs:**
- User reports "my edits disappeared" or "I renamed this item but it changed back"
- Labels appear/disappear inconsistently across devices
- Concealed items appear in plaintext on another device

**Consequences:** Data loss (silent edit overwrite), privacy violation (concealed content exposed), user confusion.
**Detection:** Log merge events with device origin and timestamp; surface "last edited on [device] at [time]" in UI.
**Phase to address:** Sync architecture design phase.

**Sources:**
- [How do I resolve conflicts with SwiftData? (Apple Developer Forums)](https://developer.apple.com/forums/thread/751480)
- [NSMergePolicy (Apple Developer Documentation)](https://developer.apple.com/documentation/coredata/nsmergepolicy)

---

### Pitfall 8: Concealed/Sensitive Items Synced to iCloud Violate User Privacy Expectations

**What goes wrong:**
Pastel respects `org.nspasteboard.ConcealedType` for password managers (1Password, Bitwarden, etc.), capturing these items with `isConcealed = true` and auto-expiring them in 60 seconds locally. If iCloud sync is enabled, these concealed items sync to CloudKit BEFORE they expire locally. Once in CloudKit, they persist in iCloud's private database (encrypted at rest but accessible on all user devices), potentially surviving the local 60-second expiration. The user's password or sensitive credential ends up stored in iCloud permanently.

**Why it happens:**
CloudKit sync is asynchronous and operates on its own schedule. A concealed item created at T=0 may sync to CloudKit at T=5s, before the T=60s local expiration fires. When the local expiration deletes the item at T=60s, that deletion also syncs -- but there is a window where the sensitive data exists in iCloud, and on other devices it may have already been imported.

Worse: if the deletion sync is delayed (device goes offline, CloudKit throttles), the concealed item can persist on other devices indefinitely.

**Specific risk in Pastel's architecture:**
- The `ExpirationService.scheduleExpiration()` only runs on the device that captured the item. Other devices receiving the synced item have no scheduled expiration.
- The `isConcealed` flag syncs, but the expiration timer does NOT sync -- it is a local `Timer` in `ExpirationService`.
- If the user has "sync enabled" globally, ALL captured items sync, including concealed ones.

**How to avoid:**
1. NEVER sync items where `isConcealed == true`. Filter them out at the sync layer.
2. Add a sync predicate that excludes concealed items: only sync items where `isConcealed == false`.
3. If using `ModelConfiguration` with CloudKit, consider a separate local-only store for concealed items.
4. Alternatively, exclude `isConcealed` items from the CloudKit-synced entity entirely and use a local-only entity for concealed captures.
5. Document this behavior clearly: "Sensitive items detected from password managers are never synced to iCloud."

**Warning signs:**
- Passwords from 1Password/Bitwarden appear on other devices
- Concealed items show up in history on a device where they were not copied
- User reports seeing credentials they copied on another machine

**Consequences:** Privacy violation, credential exposure across devices, trust destruction.
**Detection:** Audit synced records in CloudKit Dashboard for `isConcealed == true` entries.
**Phase to address:** Sync filtering phase, before sync is enabled for users.

---

### Pitfall 9: iCloud Storage Quota Exhaustion from Unbounded Clipboard History

**What goes wrong:**
CloudKit private database counts against the user's iCloud storage quota (5GB free tier). A clipboard manager generates high-volume, continuous data. If a user copies 100 items per day with average 2KB per item (text + metadata), that is ~200KB/day, ~6MB/month, ~73MB/year. This sounds manageable, but:
- Rich text items with `htmlContent` and `rtfData` can be 10-100KB each
- URL metadata (titles, favicon paths, preview paths) adds per-item overhead
- With multiple devices syncing, the item count multiplies
- Users with "Forever" retention and years of history could have 10,000+ items

When the user's iCloud quota is exceeded, CloudKit returns `CKError.Code.quotaExceeded` and ALL sync stops -- not just for Pastel, but for ALL apps using that iCloud account (Photos, iCloud Drive, etc.). Users blame Pastel for breaking their iCloud.

**Why it happens:**
The free iCloud tier is only 5GB. Many users already use most of this for Photos, iCloud Drive, and device backups. A clipboard manager adding hundreds of records per week can tip users over the limit, especially if RTF/HTML data is synced.

**Specific risk in Pastel's architecture:**
- Current retention options include "Forever" -- unlimited history growth.
- `rtfData: Data?` can be large (formatted text from word processors).
- `htmlContent: String?` for web pages can be tens of KB per item.
- URL metadata images are stored on disk locally but if the paths are synced, the referenced files are orphaned on other devices (non-functional but schema-polluting).
- The `RetentionService` purges locally but has no concept of CloudKit quota.

**How to avoid:**
1. Enforce a separate, shorter sync retention limit (e.g., max 30 days for synced items, regardless of local retention setting).
2. Do NOT sync `rtfData` or `htmlContent` -- sync only `textContent` (plain text). This dramatically reduces per-item size.
3. Do NOT sync image-related paths (`imagePath`, `thumbnailPath`, `urlFaviconPath`, `urlPreviewImagePath`) -- they reference local files that do not exist on other devices.
4. Implement a sync item count cap (e.g., max 1,000 synced items). Oldest items beyond the cap are removed from CloudKit but retained locally.
5. Handle `CKError.quotaExceeded` gracefully: show a user-facing alert explaining their iCloud is full, suggest reducing sync retention, and pause sync (do not retry aggressively).
6. Show estimated iCloud usage in Settings so users understand the cost.

**Warning signs:**
- `CKError.quotaExceeded` in console logs
- User reports that Photos/iCloud Drive stopped syncing after installing Pastel
- Sync silently stops with no user feedback
- Database size grows unboundedly over months

**Consequences:** User's iCloud quota consumed, all iCloud services degraded, user blames Pastel, potential 1-star reviews.
**Detection:** Monitor for `CKError.quotaExceeded`; track synced item count; estimate storage usage.
**Phase to address:** Sync settings/configuration phase.

**Sources:**
- [CKError.quotaExceeded (Apple Developer Documentation)](https://developer.apple.com/documentation/cloudkit/ckerror/quotaexceeded)
- [CloudKit 101 (Rambo Codes)](https://www.rambo.codes/posts/2020-02-25-cloudkit-101)

---

### Pitfall 10: Existing Users' Local Data Migration to CloudKit-Compatible Schema

**What goes wrong:**
Existing Pastel users (v1.0-v1.4) have a local SwiftData store with the current schema: `@Attribute(.unique)` on contentHash, non-optional properties without defaults, non-optional relationship arrays. When they update to v1.5, the app must migrate this local store to a CloudKit-compatible schema (remove unique constraint, add defaults, make relationships optional). If this migration fails or is not lightweight-compatible, the app crashes on launch and users lose access to their entire clipboard history.

**Why it happens:**
SwiftData attempts lightweight migration automatically. However, the combination of removing `@Attribute(.unique)` and adding default values to multiple properties simultaneously may exceed lightweight migration's capabilities, depending on the exact Core Data migration rules applied. Additionally, once CloudKit is enabled on the container, Core Data attempts to validate the schema against CloudKit requirements BEFORE performing the migration, creating a chicken-and-egg problem.

**Specific risk in Pastel's architecture:**
- Pastel already has one migration (`MigrationService.migrateLabelsIfNeeded`) for the v1.1 label relationship change. Adding a second migration increases complexity.
- The deprecated `label: Label?` property still exists. If CloudKit is enabled first, this deprecated field becomes permanent in the CloudKit schema. It should be removed in a local migration BEFORE CloudKit is enabled.
- Users with large histories (10,000+ items) may experience long migration times on first launch after update.

**How to avoid:**
1. Use a two-phase migration strategy:
   - Phase A (local-only): Remove `@Attribute(.unique)`, add defaults, make relationships optional, remove deprecated `label` property. This is a local lightweight migration without CloudKit.
   - Phase B (enable CloudKit): After the schema is CloudKit-compatible, enable CloudKit syncing on subsequent launch.
2. Implement a fallback: if `ModelContainer` creation with CloudKit fails, fall back to `cloudKitDatabase: .none`, perform the migration, then enable CloudKit on next launch.
3. Test migration with a database created by v1.4 -- use a real user's database size and shape.
4. Back up the SQLite database before migration (copy the store file in Application Support).
5. Use `VersionedSchema` and `SchemaMigrationPlan` for explicit migration control rather than relying on auto-migration.

**Warning signs:**
- Crash on first launch after update
- Error: "CloudKit integration requires that all attributes be optional"
- Migration takes unexpectedly long on large databases
- Data appears to be missing after migration

**Consequences:** Loss of clipboard history for existing users, app unusable after update.
**Detection:** Test update path from v1.4 to v1.5 with populated database.
**Phase to address:** Model preparation phase, first step before any sync work.

**Sources:**
- [SwiftData CloudKit Migration Failure (Apple Developer Forums)](https://developer.apple.com/forums/thread/744491)
- [Local SwiftData to CloudKit Migration (Apple Developer Forums)](https://developer.apple.com/forums/thread/756538)

---

### Pitfall 11: Opt-In Sync Toggle Cannot Truly Disable CloudKit at Runtime

**What goes wrong:**
The v1.5 requirement specifies "opt-in sync toggle in Settings (off by default)." The natural implementation would be to read a UserDefaults flag and configure `ModelConfiguration(cloudKitDatabase: isSyncEnabled ? .automatic : .none)`. However, `ModelConfiguration` is set once at `ModelContainer` creation time (in `PastelApp.init()`). There is no API to change the CloudKit database configuration at runtime. Toggling the setting requires destroying and recreating the `ModelContainer`, which invalidates all `@Query` views, all `ModelContext` references, and all in-memory model objects.

**Why it happens:**
`ModelContainer` (and the underlying `NSPersistentContainer`) is designed to be created once and live for the app's lifetime. The persistent store configuration, including CloudKit sync, is fixed at creation. SwiftData does not support hot-swapping store configurations.

**Specific risk in Pastel's architecture:**
- `PastelApp.init()` creates the `ModelContainer` and passes it to `AppState`, `ClipboardMonitor`, `PanelController`, and the SwiftUI environment.
- `ClipboardMonitor` holds a `ModelContext` from this container. Recreating the container would require tearing down and recreating the monitor, retention service, and panel.
- `@Query` in views like `PanelContentView`, `HistoryBrowserView`, `ChipBarView` depend on the container in the SwiftUI environment. Changing it mid-session may cause crashes or stale data.

**How to avoid:**
1. **Approach A: Always-on CloudKit with sync filtering.** Configure `ModelContainer` with CloudKit always enabled. Use a local flag to control whether NEW items are synced. Items created while sync is "off" get a flag like `isSyncExcluded = true`. The CloudKit store is always active, but item-level filtering controls what syncs. Downside: CloudKit container exists even for users who never enable sync.
2. **Approach B: Require app restart.** When user toggles sync, save the preference and show "Restart Pastel to apply sync changes." On next launch, `PastelApp.init()` reads the flag and creates the appropriate `ModelContainer`. This is simple and reliable but poor UX.
3. **Approach C: Separate stores.** Use TWO `ModelConfiguration` instances -- one local-only, one CloudKit-synced. All items are created in the local store. A background process copies eligible items to the CloudKit store when sync is enabled. Downside: significant architectural complexity, duplicate data.
4. **Recommended: Approach B (restart required)** for v1.5. It is the simplest, most reliable approach. The sync toggle is a one-time setup, not a frequent toggle. Users expect to restart apps after enabling iCloud features.

**Warning signs:**
- User toggles sync on/off and nothing happens until restart
- Attempting to recreate ModelContainer at runtime causes crashes
- @Query views show stale data after container swap

**Consequences:** Poor UX if toggle appears instant but does nothing, or crashes if runtime container swap is attempted.
**Detection:** Test toggle behavior end-to-end; verify sync starts/stops correctly.
**Phase to address:** Sync settings UI phase.

**Sources:**
- [Disable automatic iCloud sync with SwiftData (Apple Developer Forums)](https://developer.apple.com/forums/thread/731375)
- [How to stop SwiftData syncing with CloudKit (Hacking with Swift)](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-stop-swiftdata-syncing-with-cloudkit)

---

### Pitfall 12: CloudKit Throttling Halts Sync During Rapid Clipboard Activity

**What goes wrong:**
CloudKit throttles applications that issue too many requests in a short period. A clipboard manager can generate bursts of 10-50 items in seconds (e.g., user rapidly copying from a spreadsheet, or a script writing to the clipboard). Each item creates a sync operation. If the rate exceeds CloudKit's limits (~40 requests/second for private database), CloudKit returns `CKError.requestRateLimited` and blocks ALL sync for a minimum of 30 seconds. During this block, no items sync in either direction.

**Why it happens:**
CloudKit enforces rate limits to protect its infrastructure and prevent a single app from degrading iCloud for other services. The limits are not well-documented, but developer reports indicate ~40 req/s per user for private database operations. A clipboard manager's bursty capture pattern is particularly prone to triggering throttles.

**Specific risk in Pastel's architecture:**
- `ClipboardMonitor` polls at 0.5s intervals and immediately saves captured items via `modelContext.save()`. Each save triggers a sync operation.
- Batch copies (copying cells from a spreadsheet row by row) can generate 10+ items in a few seconds.
- The `ImportExportService` batch-saves every 50 items during import. If sync is active during import, this generates 50+ sync operations rapidly.
- There is no batching or coalescing of sync operations in SwiftData's CloudKit integration -- each save is an independent sync event.

**How to avoid:**
1. Batch local saves: accumulate clipboard items in memory and flush to SwiftData every 5-10 seconds instead of on every capture. This reduces sync frequency.
2. During import operations, temporarily pause sync or use a local-only context.
3. Handle `CKError.requestRateLimited` gracefully: extract the retry-after interval from the error's `userInfo[CKErrorRetryAfterKey]`, show a "sync paused temporarily" indicator, and resume after the specified delay.
4. Implement exponential backoff for sync retries.
5. Accept that SwiftData/CloudKit integration handles some of this internally -- but monitor for throttle errors in production.

**Warning signs:**
- Console shows `CKError.requestRateLimited` errors
- Sync status indicator shows persistent "syncing" state that never resolves
- Items appear on other devices with significant delay after rapid copying

**Consequences:** Temporary sync halt, items delayed on other devices, poor user perception of sync reliability.
**Detection:** Monitor for `requestRateLimited` errors; track sync latency.
**Phase to address:** Sync architecture phase, batch saving design.

**Sources:**
- [Understanding CloudKit Throttles TN3162 (Apple Developer Documentation)](https://developer.apple.com/documentation/technotes/tn3162-understanding-cloudkit-throttles)
- [iCloud Does Throttle Data Syncing (Eclectic Light Company)](https://eclecticlight.co/2024/02/22/icloud-does-throttle-data-syncing-after-all/)
- [CloudKit Throttles and Debugging (mjtsai.com)](https://mjtsai.com/blog/2024/05/29/cloudkit-throttles-and-debugging/)

---

## Minor Pitfalls

Issues that cause inconvenience, UI confusion, or edge-case bugs but are not critical to core functionality.

---

### Pitfall 13: Entitlement and Provisioning Profile Configuration Errors

**What goes wrong:**
CloudKit requires specific entitlements in the app's `.entitlements` file:
- `com.apple.developer.icloud-services` with value `CloudKit`
- `com.apple.developer.icloud-container-identifiers` with the container ID (e.g., `iCloud.app.pastel.Pastel`)
- `com.apple.developer.icloud-container-environment` set to `Production` for release builds

Missing any of these causes silent sync failure (no crash, just no sync). Additionally:
- The App ID in the Apple Developer portal must have iCloud capability enabled with CloudKit selected.
- Provisioning profiles must be regenerated after adding iCloud capability.
- The container identifier must be registered in the CloudKit Dashboard.

**Specific risk in Pastel's architecture:**
- Current `Pastel.entitlements` only has `app-sandbox`, `network.client`, and `files.user-selected.read-write`. All CloudKit entitlements must be added.
- XcodeGen may not automatically add CloudKit entitlements when the capability is enabled -- they may need to be manually specified in `project.yml`.
- The `icloud-container-environment` key MUST be in the entitlements file, NOT in Info.plist. Putting it in the wrong file causes silent failure.
- If using Automatic code signing, Xcode may manage entitlements inconsistently when CloudKit is added via capabilities UI vs. manual entitlements editing.

**How to avoid:**
1. Add all required entitlements to `Pastel.entitlements`.
2. Register the iCloud container in the Apple Developer portal.
3. Regenerate provisioning profiles.
4. Verify entitlements in the signed app binary: `codesign -d --entitlements :- /path/to/Pastel.app`
5. Test sync in a signed build (not just Debug).

**Warning signs:**
- Sync works in Debug but not in signed builds
- Console shows "no iCloud container" or "missing entitlement" errors
- CloudKit Dashboard shows no containers

**Consequences:** Silent sync failure in production.
**Detection:** Verify entitlements in the built binary before submission.
**Phase to address:** Project configuration phase.

**Sources:**
- [Enabling CloudKit in Your App (Apple Developer Documentation)](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app)

---

### Pitfall 14: Synced Items Reference Local File Paths That Do Not Exist on Other Devices

**What goes wrong:**
`ClipboardItem` has several fields that reference local file paths: `imagePath`, `thumbnailPath`, `urlFaviconPath`, `urlPreviewImagePath`. These are filenames stored by `ImageStorageService` in the app's Application Support directory. When these fields sync to another device, the paths are meaningless -- the referenced files do not exist. Attempting to load an image from a synced path returns nil or throws, potentially causing UI glitches (missing thumbnails, broken URL previews).

**Specific risk in Pastel's architecture:**
- `AsyncThumbnailView` loads images using these paths. A synced image item would display a broken/missing thumbnail.
- `URLCardView` shows favicon and og:image from `urlFaviconPath`/`urlPreviewImagePath`. Synced URL items would show broken previews.
- The v1.5 scope says "images deferred, text only" -- but image items from the local store will still have their metadata synced if not explicitly excluded.

**How to avoid:**
1. Do NOT sync image-related fields. Either mark them as transient/local-only, or filter out image items from sync entirely.
2. For URL items: sync the URL text but not the cached metadata images. The receiving device can re-fetch URL metadata from the URL itself.
3. Add a sync predicate that excludes items where `contentType == "image"`.
4. For synced URL items, trigger a re-fetch of metadata on the receiving device if `urlMetadataFetched != true`.

**Warning signs:**
- Broken image thumbnails for synced items
- URL cards showing missing favicons/previews
- Console errors about missing files at paths

**Consequences:** Broken UI for synced items, wasted iCloud storage on useless path strings.
**Detection:** Check synced items on a second device for visual completeness.
**Phase to address:** Sync filtering phase.

---

### Pitfall 15: @Query Views May Not Refresh When Remote Changes Arrive

**What goes wrong:**
SwiftData's `@Query` property wrapper is designed to observe local changes and re-render. However, when changes arrive from CloudKit (remote changes merged into the persistent store), `@Query` may not immediately trigger a view update. This results in users opening the panel and not seeing items they copied on their other device until they interact with the UI (scroll, search, or switch tabs), which forces a re-render.

**Why it happens:**
Remote changes are merged into the underlying Core Data store by `NSPersistentCloudKitContainer` on a background context. SwiftData's `@Query` observes the main context. The notification path from background merge to main context to `@Query` is not always immediate, especially for relationship changes.

**Specific risk in Pastel's architecture:**
- The sliding panel uses `@Query` in `FilteredCardListView` (via `PanelContentView`) with complex predicates and `.id()` modifiers for filter reactivity. Remote changes may require the `@Query` to be fully re-executed, which the `.id()` pattern was designed for local filter changes, not remote data changes.
- The `HistoryBrowserView` grid also uses `@Query` and may show stale data.
- `itemCount` in `AppState` is manually synced from `ClipboardMonitor` -- remote items arriving via CloudKit would NOT increment this counter.

**How to avoid:**
1. Listen for `NSPersistentStoreRemoteChange` notifications and trigger a UI refresh.
2. When a remote change notification arrives, update `AppState.itemCount` by re-fetching the count.
3. Force `@Query` re-evaluation by toggling a state variable used in the view's `.id()` modifier.
4. Test with two devices side by side: copy on Device A, verify it appears on Device B within seconds without any interaction.

**Warning signs:**
- Synced items do not appear until user scrolls or switches filters
- Item count is wrong after synced items arrive
- User reports "sync doesn't work" when items actually did arrive but UI didn't update

**Consequences:** Poor sync UX, perception that sync is broken.
**Detection:** Two-device testing with no interaction on receiving device.
**Phase to address:** Sync UI integration phase.

**Sources:**
- [SwiftData CloudKit data not appearing (Apple Developer Forums)](https://developer.apple.com/forums/thread/730950)
- [SwiftData Architecture Patterns (AzamSharp)](https://azamsharp.com/2025/03/28/swiftdata-architecture-patterns-and-practices.html)

---

### Pitfall 16: Retention Service Deletes Synced Items Locally Without Propagating Delete Intent

**What goes wrong:**
The `RetentionService` runs hourly and deletes items older than the configured retention period. If Device A has retention set to "1 week" and Device B has retention set to "Forever," Device A will delete items older than 1 week. These deletions sync to CloudKit, which then propagates the deletions to Device B -- even though Device B's user wanted to keep them forever.

Conversely, if the deletion does NOT sync properly (offline device, sync delay), the items will be re-synced from Device B back to Device A, effectively undoing the retention cleanup and creating a "zombie item" loop.

**Specific risk in Pastel's architecture:**
- Retention is configured per-device via `UserDefaults.standard.integer(forKey: "historyRetention")`. There is no concept of sync-wide retention.
- `RetentionService.purgeExpiredItems()` deletes from the `ModelContext` and saves. With CloudKit enabled, this save propagates the deletion to all devices.
- A user who sets "1 week" retention on their work Mac but "Forever" on their home Mac will see their home Mac's history erased by the work Mac's retention service.

**How to avoid:**
1. Retention should be local-only: delete items from the LOCAL view but not from CloudKit. This requires distinguishing "local delete" from "sync delete."
2. Alternative: implement a sync-wide retention setting that applies to all devices. Store it as a CloudKit key-value pair rather than UserDefaults.
3. Add a "hidden locally" or "locally deleted" flag rather than hard-deleting synced items.
4. At minimum, document that retention settings affect all synced devices and warn users.

**Warning signs:**
- Items disappear on one device because another device has shorter retention
- Deleted items reappear after sync (zombie items)
- User on "Forever" retention loses old items unexpectedly

**Consequences:** Unexpected data loss on devices with longer retention settings.
**Detection:** Test with two devices having different retention settings.
**Phase to address:** Sync-aware retention design phase.

---

### Pitfall 17: First-Time Sync Downloads Entire History, Causing App Hang

**What goes wrong:**
When a user installs Pastel on a second Mac and enables sync, CloudKit downloads the entire synced history from the first device. If the first device has thousands of items, this initial sync can take minutes and cause the app to appear frozen. SwiftData processes incoming records on a background context, but the merge into the main context and subsequent `@Query` re-evaluations can block the main thread.

**Why it happens:**
CloudKit downloads all records in the user's private database for the app on first sync. There is no incremental "show me the last 100 items first" API when using SwiftData's automatic sync. The sync framework downloads everything and merges it in bulk.

**Specific risk in Pastel's architecture:**
- Users with months of clipboard history could have 5,000-20,000 items.
- The `@Query` in `PanelContentView` fetches ALL items matching the current filter. After initial sync, this query returns thousands of results, potentially causing a SwiftUI rendering spike.
- `ClipboardMonitor.itemCount` is loaded via `fetchCount` in `init()`. After bulk sync, this count may not update until the remote change notification is processed.
- No loading/progress indicator exists for sync operations.

**How to avoid:**
1. Show a sync progress indicator during initial sync ("Syncing clipboard history...").
2. Limit the initial sync window: when a new device is added, only sync the last N days or N items, not the full history.
3. Use `fetchLimit` on initial queries to avoid loading all synced items at once.
4. Process remote change notifications in batches, yielding the main thread between batches.
5. Use `CloudKitSyncMonitor` (third-party package) or listen to `NSPersistentCloudKitContainer.Event` to track sync progress and surface it in the UI.

**Warning signs:**
- App appears frozen for 30+ seconds on first launch with sync enabled
- Memory usage spikes during initial sync
- UI becomes unresponsive while thousands of items are merged

**Consequences:** App appears broken/frozen on first sync, user may force-quit.
**Detection:** Test initial sync with a populated database (1000+ items).
**Phase to address:** Sync UX phase.

**Sources:**
- [CloudKitSyncMonitor (GitHub)](https://github.com/ggruen/CloudKitSyncMonitor)

---

### Pitfall 18: changeCount Field Is Device-Specific and Meaningless When Synced

**What goes wrong:**
`ClipboardItem.changeCount` stores the `NSPasteboard.general.changeCount` at capture time. This value is a monotonically increasing integer local to each device's pasteboard. When synced to another device, this number is meaningless -- it does not correspond to anything on the receiving device's pasteboard. It wastes sync bandwidth and storage, and could confuse any logic that reads it.

**How to avoid:**
1. Mark `changeCount` as a local-only property that does not sync. Since SwiftData does not natively support per-property sync exclusion, either:
   - Remove `changeCount` from the synced model entirely and store it in a separate local-only entity.
   - Set it to 0 for synced items and ensure no logic depends on its value for synced items.
2. Consider whether `changeCount` is needed at all -- it is not displayed in the UI or used in any queries.

**Consequences:** Wasted sync storage, potential logic bugs if code reads changeCount on synced items.
**Phase to address:** Model cleanup phase.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Model preparation (CloudKit compatibility) | Pitfall 1 (unique constraint), Pitfall 2 (optionals), Pitfall 4 (permanent schema) | Remove @Attribute(.unique), add defaults, finalize schema before CloudKit |
| Existing user migration | Pitfall 10 (migration crash) | Two-phase migration: local cleanup first, then enable CloudKit |
| Project configuration | Pitfall 5 (CloudKit.framework), Pitfall 13 (entitlements) | Explicit framework linking, complete entitlement setup |
| Sync architecture design | Pitfall 3 (sync loop), Pitfall 7 (conflict resolution), Pitfall 12 (throttling) | originDeviceID field, skip synced content in monitor, batch saves |
| Privacy / content filtering | Pitfall 8 (concealed items), Pitfall 9 (quota), Pitfall 14 (file paths) | Never sync concealed items, cap sync retention, exclude file paths |
| Deployment to production | Pitfall 6 (dev/prod mismatch) | initializeCloudKitSchema in dev, deploy to prod before release |
| Sync UI / Settings | Pitfall 11 (toggle), Pitfall 15 (@Query refresh), Pitfall 17 (initial sync) | Restart-required toggle, remote change listeners, progress indicator |
| Retention integration | Pitfall 16 (cross-device retention) | Local-only retention or sync-wide setting |

---

## Integration Pitfalls: Existing Features + Sync

These pitfalls specifically arise from the interaction between existing Pastel features and new sync functionality.

### Import/Export + Sync Collision

**Risk:** If a user imports a `.pastel` file while sync is active, `ImportExportService` batch-inserts items via `modelContext.save()` every 50 items. Each save triggers a CloudKit sync operation. Importing 1,000 items generates 20+ sync bursts, likely triggering throttling (Pitfall 12). Additionally, these imported items sync to other devices, which may already have them (from a previous export/import cycle), creating duplicates since `@Attribute(.unique)` is removed.

**Prevention:** Pause sync during import operations. After import completes, let CloudKit sync the batch naturally. Implement hash-based deduplication on the receiving end to handle imported items that already exist.

### Self-Paste Prevention + Sync

**Risk:** The `skipNextChange` flag in `ClipboardMonitor` handles self-paste prevention for one event. But synced items arriving continuously could interact with the skip flag: if a remote change notification triggers right when `skipNextChange` is true, a legitimately new clipboard change might be skipped.

**Prevention:** The `skipNextChange` flag should be specific to paste-back events only, independent of sync state. Sync-originated items should be distinguished by `originDeviceID`, not by skip flags.

### App Ignore List + Synced Items

**Risk:** If a user has an app in their ignore list on Device A but not Device B, items from that app captured on Device B will sync to Device A. The user sees items from an app they explicitly chose to ignore, violating their privacy expectations.

**Prevention:** The ignore list filters capture, not display. For synced items, respect the ignore list during display/query rather than during capture. Show synced items even from ignored apps (since they were captured on a different device where the app is not ignored), but document this behavior. Alternatively, sync the ignore list itself.

### URL Metadata + Synced URL Items

**Risk:** URL items synced from another device have `urlMetadataFetched: nil` and empty metadata fields. The receiving device should re-fetch metadata, but `URLMetadataService` only runs during initial capture in `ClipboardMonitor.processPasteboardContent()`. Synced URL items will show as plain text cards without titles, favicons, or preview images.

**Prevention:** When processing remote change notifications, identify synced URL items without metadata and enqueue them for metadata fetching. Rate-limit these fetches to avoid overwhelming the network during initial sync of many URL items.

---

## Sources

### Apple Official
- [Syncing model data across a person's devices (Apple Developer Documentation)](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [Enabling CloudKit in Your App (Apple Developer Documentation)](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app)
- [CKError.quotaExceeded (Apple Developer Documentation)](https://developer.apple.com/documentation/cloudkit/ckerror/quotaexceeded)
- [Understanding CloudKit Throttles TN3162 (Apple Developer Documentation)](https://developer.apple.com/documentation/technotes/tn3162-understanding-cloudkit-throttles)
- [NSMergePolicy (Apple Developer Documentation)](https://developer.apple.com/documentation/coredata/nsmergepolicy)
- [Syncing a Core Data Store with CloudKit (Apple Developer Documentation)](https://developer.apple.com/documentation/coredata/syncing-a-core-data-store-with-cloudkit)
- [iCloud Data Security Overview (Apple Support)](https://support.apple.com/en-us/102651)
- [GDPR and CloudKit (Apple Developer Video)](https://developer.apple.com/videos/play/tech-talks/703/)

### Developer Analysis
- [Designing Models for CloudKit Sync (fatbobman.com)](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/)
- [Fixing SwiftData CloudKit Sync: initializeCloudKitSchema (fatbobman.com)](https://fatbobman.com/en/snippet/resolving-incomplete-icloud-data-sync-in-ios-development-using-initializecloudkitschema/)
- [Fixing macOS SwiftData/Core Data Sync: CloudKit.framework Issue (fatbobman.com)](https://fatbobman.com/en/snippet/fix-synchronization-issues-for-macos-apps-using-core-dataswiftdata/)
- [Fix Core Data/SwiftData Cloud Sync in Production (fatbobman.com)](https://fatbobman.com/en/snippet/why-core-data-or-swiftdata-cloud-sync-stops-working-after-app-store-login/)
- [SwiftData with CloudKit Quirks (firewhale.io)](https://firewhale.io/posts/swift-data-quirks/)
- [Deploy SwiftData CloudKit Schema Changes (leojkwan.com)](https://www.leojkwan.com/swiftdata-cloudkit-deploy-schema-changes/)
- [Syncing SwiftData with CloudKit (Hacking with Swift)](https://www.hackingwithswift.com/books/ios-swiftui/syncing-swiftdata-with-cloudkit)

### Community & Forums
- [CloudKit does not support unique constraints (Apple Developer Forums)](https://developer.apple.com/forums/thread/656380)
- [SwiftData CloudKit integration requirements (Apple Developer Forums)](https://developer.apple.com/forums/thread/735349)
- [SwiftData with CloudKit failing to migrate schema (Apple Developer Forums)](https://developer.apple.com/forums/thread/744491)
- [How do I resolve conflicts with SwiftData? (Apple Developer Forums)](https://developer.apple.com/forums/thread/751480)
- [Disable automatic iCloud sync with SwiftData (Apple Developer Forums)](https://developer.apple.com/forums/thread/731375)
- [CloudKit Throttles and Debugging (mjtsai.com)](https://mjtsai.com/blog/2024/05/29/cloudkit-throttles-and-debugging/)
- [iCloud Does Throttle Data Syncing (Eclectic Light Company)](https://eclecticlight.co/2024/02/22/icloud-does-throttle-data-syncing-after-all/)
- [CloudKitSyncMonitor (GitHub)](https://github.com/ggruen/CloudKitSyncMonitor)

### Tools
- [CloudKitSyncMonitor - Sync status monitoring for NSPersistentCloudKitContainer](https://github.com/ggruen/CloudKitSyncMonitor)
- [CloudSyncStatusView - SwiftUI sync status component](https://github.com/platadani/CloudSyncStatusView)
