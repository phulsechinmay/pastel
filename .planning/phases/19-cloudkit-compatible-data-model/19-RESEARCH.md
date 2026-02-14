# Phase 19: CloudKit-Compatible Data Model - Research

**Researched:** 2026-02-14
**Domain:** SwiftData schema migration for CloudKit compatibility (local-only, sync OFF)
**Confidence:** HIGH

## Summary

Phase 19 prepares Pastel's SwiftData models for CloudKit sync without actually enabling sync. This is a prerequisite phase: all schema changes must be finalized and tested locally before Phase 20 enables CloudKit, because once the CloudKit schema is deployed to production, it is permanent (add-only, no delete, no rename, no type changes).

The scope is focused: remove `@Attribute(.unique)` from `contentHash`, add default values to all non-optional properties, make relationship arrays optional, implement application-level hash deduplication to replace the unique constraint, add `originDeviceID` field, and update all call sites that access `.labels` or `.items` to use nil-safe patterns. The app must behave identically to v1.4 from the user's perspective -- no sync, no new UI, purely internal model preparation.

The highest-risk change is removing `@Attribute(.unique)` from `contentHash`. Currently, the save catch block in `ClipboardMonitor.processPasteboardContent()` (lines 308-313) silently handles non-consecutive duplicates by rolling back the insert when the unique constraint is violated. With the constraint removed, non-consecutive duplicates will be silently inserted. An application-level check using `fetchCount` with a predicate must be added before `modelContext.insert()` to replicate this behavior.

**Primary recommendation:** Use VersionedSchema with a SchemaMigrationPlan to make the migration explicit and testable, rather than relying on SwiftData's auto-migration, since removing `@Attribute(.unique)` is not listed among documented lightweight migration operations.

## Standard Stack

### Core (unchanged from v1.4)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData | macOS 14+ | Persistence | Already in use; schema changes only |
| CryptoKit | macOS 14+ | SHA256 content hashing | Already in use for contentHash |
| Swift 6 | 6.0 | Language | Project standard |

### Supporting (unchanged)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| OSLog | macOS 14+ | Structured logging | Migration logging, dedup logging |

### No New Dependencies

Phase 19 adds zero new frameworks or packages. All changes are internal to the existing SwiftData models and services.

## Architecture Patterns

### Recommended File Changes

```
Pastel/
  Models/
    ClipboardItem.swift     # Remove @Attribute(.unique), add defaults, make labels optional, add originDeviceID
    Label.swift             # Add defaults, make items optional
    SchemaVersions.swift    # NEW: VersionedSchema + SchemaMigrationPlan
  Services/
    ClipboardMonitor.swift  # Replace save-catch dedup with pre-insert hash check, stamp originDeviceID
    MigrationService.swift  # Minor: use safeLabels in label migration code
    ImportExportService.swift # Use safeLabels for export, safeLabels for import wire-up
  Utilities/
    DeviceIdentifier.swift  # NEW: Per-device UUID generation from UserDefaults
  App/
    AppState.swift          # Use safeLabels in clearAllHistory
  Views/ (multiple files)   # .labels -> .safeLabels throughout
  PastelApp.swift           # Wire SchemaMigrationPlan into ModelContainer
```

### Pattern 1: VersionedSchema Migration

**What:** Define explicit schema versions and a migration plan so SwiftData handles the v1.4->v1.5 transition deterministically.

**When to use:** When making changes that go beyond documented lightweight migration (removing unique constraint, making arrays optional).

**Why use it here:** Removing `@Attribute(.unique)` is NOT among the documented lightweight migration operations (those are: adding properties with defaults, renaming, deleting properties, adding/removing `.externalStorage`/`.allowsCloudEncryption`, adding `.unique` when values are unique, adjusting delete rules). While it likely works as an auto-migration (relaxing a constraint is logically safe), using VersionedSchema makes it explicit and testable.

**Example:**
```swift
// Source: Apple WWDC23 "Model your schema with SwiftData"
// + Hacking with Swift "How to create a complex migration using VersionedSchema"

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [ClipboardItemV1.self, LabelV1.self]

    @Model final class ClipboardItemV1 {
        @Attribute(.unique) var contentHash: String
        var labels: [LabelV1]
        var contentType: String
        var timestamp: Date
        var characterCount: Int
        var byteCount: Int
        var changeCount: Int
        var isConcealed: Bool
        // ... all other existing properties
    }

    @Model final class LabelV1 {
        var name: String
        var colorName: String
        var sortOrder: Int
        var emoji: String?
        var items: [ClipboardItemV1]
    }
}

enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] = [ClipboardItem.self, Label.self]
    // ClipboardItem and Label are the CURRENT model classes (modified)
}

enum PastelMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [SchemaV1.self, SchemaV2.self]

    static var stages: [MigrationStage] = [
        .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
    ]
}
```

**Confidence: MEDIUM** -- VersionedSchema is the recommended Apple pattern for controlled migrations. However, whether removing `.unique` qualifies as lightweight is not explicitly documented. If it fails, the fallback is `.custom(fromVersion:toVersion:willMigrate:didMigrate:)` with a no-op body (the actual data is compatible, only the schema annotation changes). Testing will confirm which path works.

**IMPORTANT ALTERNATIVE:** If VersionedSchema adds too much complexity for a change that turns out to be auto-handled, the simpler approach is to just modify the models directly and let SwiftData auto-migrate. The VersionedSchema approach is the safer bet but not strictly required if manual testing confirms auto-migration works. The planner should consider starting with auto-migration and having VersionedSchema as a fallback.

### Pattern 2: Application-Level Hash Deduplication

**What:** Before inserting a new ClipboardItem, query for existing items with the same `contentHash` using `fetchCount`. Skip insertion if a match exists.

**When to use:** Replaces `@Attribute(.unique)` constraint behavior.

**Example:**
```swift
// In ClipboardMonitor.processPasteboardContent(), after computing contentHash:

// Application-level dedup: replaces @Attribute(.unique) constraint
let hashToCheck = contentHash
let existingDescriptor = FetchDescriptor<ClipboardItem>(
    predicate: #Predicate<ClipboardItem> { $0.contentHash == hashToCheck }
)
if let count = try? modelContext.fetchCount(existingDescriptor), count > 0 {
    Self.logger.debug("Non-consecutive duplicate detected by hash, skipping")
    return
}

// Existing consecutive dedup check remains (isDuplicateOfMostRecent)
// This new check catches non-consecutive duplicates that the old unique constraint caught
```

**Confidence: HIGH** -- `fetchCount` is documented as efficient (does not load objects into memory). This pattern is recommended by multiple sources for CloudKit-compatible dedup. Source: [Hacking with Swift forums](https://www.hackingwithswift.com/forums/swiftui/best-way-to-handle-unique-values-with-swiftdata-and-cloudkit/30145)

### Pattern 3: Nil-Safe Relationship Access via Computed Properties

**What:** Add `safeLabels` / `safeItems` computed properties that nil-coalesce optional arrays.

**When to use:** Every access to the relationship arrays throughout the codebase.

**Example:**
```swift
// On ClipboardItem:
extension ClipboardItem {
    var safeLabels: [Label] {
        get { labels ?? [] }
        set { labels = newValue }
    }
}

// On Label:
extension Label {
    var safeItems: [ClipboardItem] {
        get { items ?? [] }
        set { items = newValue }
    }
}
```

**Why settable:** Many call sites do `item.labels.append(label)`, `item.labels.removeAll()`, etc. Making `safeLabels` settable means call sites can use `item.safeLabels.append(label)` without needing separate nil-check logic. The setter writes through to the underlying optional.

**Confidence: HIGH** -- Standard Swift pattern. Simple and mechanical.

### Pattern 4: Per-Device UUID via UserDefaults

**What:** Generate a stable UUID per device installation, stored in UserDefaults (NOT iCloud KV store).

**When to use:** Stamped on every new ClipboardItem at capture time.

**Example:**
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

**Why UserDefaults, not NSUbiquitousKeyValueStore:** Each device must have its OWN unique ID. If stored in iCloud KV store, it would sync across devices, defeating the purpose.

**Confidence: HIGH** -- Simple, well-understood pattern.

### Anti-Patterns to Avoid

- **Leaving `@Attribute(.unique)` and hoping CloudKit handles it:** CloudKit will crash the ModelContainer on creation. This is a hard failure, not a degraded mode.
- **Using `_labels` backing + `labels` computed property trick:** SwiftData's `@Model` macro has issues with underscore-prefixed stored properties that have same-name computed wrappers. Use a clearly different name (`safeLabels`) for the computed property.
- **Removing the deprecated `label: Label?` property:** This property MUST remain until CloudKit is deployed. Once CloudKit schema is live, it is permanent. Removing it before CloudKit deployment (in this phase) is safe, but if removed after CloudKit is enabled it would cause schema issues. Since Phase 19 has no CloudKit, removal is safe here -- but the milestone research recommends keeping it for now. **Recommendation: keep `label: Label?` in Phase 19. Remove it later is a separate decision.**
- **Batch-modifying relationships without save:** SwiftData many-to-many relationships require explicit saves after modification. The existing `saveWithLogging()` pattern handles this.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Content hash dedup | Custom hash index or external DB | `fetchCount` with `#Predicate` on `contentHash` | SwiftData handles the SQLite index; fetchCount is optimized to COUNT() without loading objects |
| UUID generation | Custom device fingerprinting | `UUID().uuidString` + UserDefaults | Stable, simple, no privacy concerns. Hardware IDs are deprecated and require entitlements |
| Schema migration | Manual SQLite ALTER TABLE | SwiftData `SchemaMigrationPlan` or auto-migration | SwiftData manages the underlying Core Data migration machinery |
| Nil-safe collection access | Optional chaining everywhere | Computed property with nil-coalescing | One definition, used everywhere; settable for write-through |

**Key insight:** Phase 19 is a mechanical refactoring phase. The complexity is in the breadth of changes (touching many files) not the depth of any single change.

## Common Pitfalls

### Pitfall 1: Save Catch Block No Longer Catches Duplicates

**What goes wrong:** The current `ClipboardMonitor.processPasteboardContent()` (lines 308-313) has a `do { try modelContext.save() } catch { ... rollback() }` pattern where the catch block handles `@Attribute(.unique)` violations for non-consecutive duplicates. After removing the unique constraint, the save will NEVER fail for duplicates -- they will silently insert.

**Why it happens:** The unique constraint was doing double duty: schema-level dedup AND error handling. Removing the constraint removes both.

**How to avoid:** Add the `fetchCount` check BEFORE `modelContext.insert()`. The save catch block remains for general error handling but is no longer the dedup mechanism.

**Warning signs:** Same text appearing multiple times in history after non-consecutive copies (e.g., copy "hello", copy something else, copy "hello" again -- two "hello" entries appear instead of one).

### Pitfall 2: Image Content Hash Dedup in processImageContent

**What goes wrong:** `processImageContent()` (line 334) also relies on the unique constraint for non-consecutive image dedup. It has its own `isDuplicateOfMostRecent()` call but the save catch block (lines 376-379) catches unique constraint violations for non-consecutive image duplicates.

**Why it happens:** Same dual-duty pattern as Pitfall 1, but in a separate code path.

**How to avoid:** Add a `fetchCount` check before `modelContext.insert(item)` in `processImageContent()` as well, using the computed `contentHash`.

**Warning signs:** Duplicate image entries in history.

### Pitfall 3: Forgetting to Update a `.labels` Call Site

**What goes wrong:** After making `labels` optional (`[Label]?`), any direct access like `item.labels.count` will fail to compile (cannot call `.count` on optional). But some patterns are more subtle -- `item.labels.map(\.name)` on an optional array returns `Optional<[String]>`, not `[String]`. This can cause silent type mismatches or unexpected nil propagation.

**Why it happens:** There are 25+ call sites for `.labels` across 10 files. Missing even one causes a compile error (good) or a subtle runtime behavior change (bad).

**How to avoid:** Use `safeLabels` everywhere. Do a project-wide search for `.labels` and `.items` after the change to catch stragglers. The compiler will catch most issues since `[Label]?` and `[Label]` are different types.

**Warning signs:** Compiler errors (obvious). More dangerous: code that compiles but behaves differently because of optional chaining on the array.

### Pitfall 4: VersionedSchema Model Duplication Complexity

**What goes wrong:** VersionedSchema requires defining the FULL model for each schema version as nested classes. For ClipboardItem with 20+ properties, this means duplicating the entire class definition in SchemaV1. This is verbose and error-prone.

**Why it happens:** Apple's VersionedSchema design requires complete model snapshots per version.

**How to avoid:** Two options: (A) Accept the verbosity and carefully duplicate the v1.4 model as SchemaV1. (B) Skip VersionedSchema entirely and test auto-migration first -- if it works, no VersionedSchema needed. **Recommendation: try auto-migration first (just modify the models), test thoroughly. Only add VersionedSchema if auto-migration fails.**

**Warning signs:** Migration fails on launch with a v1.4 database.

### Pitfall 5: ImportExportService Line 122 Uses `.labels.map(\.name)`

**What goes wrong:** After making `labels` optional, `item.labels.map(\.name)` becomes `item.labels?.map(\.name)` which returns `Optional<[String]>` instead of `[String]`. The `ExportedItem` initializer expects `[String]` for `labelNames`.

**Why it happens:** Optional chaining through `.map` changes the return type.

**How to avoid:** Use `item.safeLabels.map(\.name)`.

### Pitfall 6: MigrationService.migrateLabelsIfNeeded Accesses `.labels` and `.label`

**What goes wrong:** The existing label migration code (lines 14-21 of MigrationService.swift) accesses `item.labels.contains()` and `item.labels.append()`. After making `labels` optional, these need nil-safety.

**Why it happens:** The migration code was written when `labels` was non-optional.

**How to avoid:** Update to `item.safeLabels.contains()` and `item.safeLabels.append()`.

## Code Examples

### Complete ClipboardItem Model (After Changes)

```swift
@Model
final class ClipboardItem {
    // Optional properties (already CloudKit-compatible)
    var textContent: String?
    var htmlContent: String?
    var rtfData: Data?
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var imagePath: String?
    var thumbnailPath: String?
    var expiresAt: Date?
    var label: Label?  // DEPRECATED: kept for migration compatibility
    var title: String?
    var detectedLanguage: String?
    var detectedColorHex: String?
    var urlTitle: String?
    var urlFaviconPath: String?
    var urlPreviewImagePath: String?
    var urlMetadataFetched: Bool?

    // Non-optional properties WITH defaults (CloudKit-compatible)
    var contentType: String = ContentType.text.rawValue
    var timestamp: Date = Date.now
    var characterCount: Int = 0
    var byteCount: Int = 0
    var changeCount: Int = 0
    var isConcealed: Bool = false
    var contentHash: String = ""  // No longer @Attribute(.unique)

    // NEW: Per-device origin tracking for sync
    var originDeviceID: String = ""

    // Relationship: optional for CloudKit compatibility
    @Relationship(deleteRule: .nullify, inverse: \Label.items)
    var labels: [Label]?

    // Computed: nil-safe access
    var safeLabels: [Label] {
        get { labels ?? [] }
        set { labels = newValue }
    }

    // Computed: ContentType enum convenience
    var type: ContentType {
        get { ContentType(rawValue: contentType) ?? .text }
        set { contentType = newValue.rawValue }
    }

    init(
        textContent: String? = nil,
        htmlContent: String? = nil,
        rtfData: Data? = nil,
        contentType: ContentType = .text,
        timestamp: Date = .now,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        characterCount: Int = 0,
        byteCount: Int = 0,
        changeCount: Int = 0,
        imagePath: String? = nil,
        thumbnailPath: String? = nil,
        isConcealed: Bool = false,
        expiresAt: Date? = nil,
        contentHash: String
    ) {
        self.textContent = textContent
        self.htmlContent = htmlContent
        self.rtfData = rtfData
        self.contentType = contentType.rawValue
        self.timestamp = timestamp
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.characterCount = characterCount
        self.byteCount = byteCount
        self.changeCount = changeCount
        self.imagePath = imagePath
        self.thumbnailPath = thumbnailPath
        self.isConcealed = isConcealed
        self.expiresAt = expiresAt
        self.contentHash = contentHash
        self.title = nil
        self.labels = []
        self.originDeviceID = DeviceIdentifier.current
    }
}
```

### Complete Label Model (After Changes)

```swift
@Model
final class Label {
    var name: String = ""
    var colorName: String = "blue"
    var sortOrder: Int = 0
    var emoji: String?

    var items: [ClipboardItem]?

    var safeItems: [ClipboardItem] {
        get { items ?? [] }
        set { items = newValue }
    }

    init(name: String, colorName: String, sortOrder: Int, emoji: String? = nil) {
        self.name = name
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.emoji = emoji
        self.items = []
    }
}
```

### Application-Level Hash Dedup in ClipboardMonitor

```swift
// Replace the save catch block dedup with pre-insert check.
// Add BEFORE the existing isDuplicateOfMostRecent() call (or after, as a second check):

/// Check if ANY item in history has the same content hash (non-consecutive dedup).
/// Replaces @Attribute(.unique) constraint behavior.
private func isDuplicateByHash(_ contentHash: String) -> Bool {
    let hashToCheck = contentHash
    let descriptor = FetchDescriptor<ClipboardItem>(
        predicate: #Predicate<ClipboardItem> { $0.contentHash == hashToCheck }
    )
    do {
        let count = try modelContext.fetchCount(descriptor)
        if count > 0 {
            Self.logger.debug("Non-consecutive duplicate detected by hash, skipping")
            return true
        }
    } catch {
        Self.logger.error("Hash dedup check failed: \(error.localizedDescription)")
        // Continue with insertion on error -- better to have a dup than lose data
    }
    return false
}

// Usage in processPasteboardContent():
// After computing contentHash:
if isDuplicateOfMostRecent(contentHash: contentHash) { return }
if isDuplicateByHash(contentHash) { return }  // NEW: replaces unique constraint
```

### DeviceIdentifier Utility

```swift
// Pastel/Utilities/DeviceIdentifier.swift
import Foundation

enum DeviceIdentifier {
    private static let key = "pastelDeviceUUID"

    /// Stable per-device UUID. Generated on first access, persisted in UserDefaults.
    /// NOT synced to iCloud -- each device must have its own unique ID.
    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
}
```

## Exact Call Sites Requiring `.labels` -> `.safeLabels` Changes

Comprehensive list from codebase grep (25 call sites across 10 files):

### ClipboardCardView.swift (6 sites)
- Line 66: `item.labels.prefix(3)` -> `item.safeLabels.prefix(3)`
- Line 70: `item.labels.count > 3` -> `item.safeLabels.count > 3`
- Line 71: `item.labels.count - 3` -> `item.safeLabels.count - 3`
- Line 174: `item.labels.contains` -> `item.safeLabels.contains`
- Line 179: `item.labels.removeAll` -> `item.safeLabels.removeAll`
- Line 183: `item.labels.append` -> `item.safeLabels.append`
- Line 197: `item.labels.isEmpty` -> `item.safeLabels.isEmpty`
- Line 200: `item.labels.removeAll()` -> `item.safeLabels.removeAll()`

### FilteredCardListView.swift (3 sites)
- Line 49: `item.labels.contains` -> `item.safeLabels.contains`
- Line 262: `item.labels.contains(where:)` -> `item.safeLabels.contains(where:)`
- Line 265: `item.labels.append(label)` -> `item.safeLabels.append(label)`

### EditItemView.swift (3 sites)
- Line 32: `item.labels.contains` -> `item.safeLabels.contains`
- Line 39: `item.labels.removeAll` -> `item.safeLabels.removeAll`
- Line 43: `item.labels.append` -> `item.safeLabels.append`

### HistoryGridView.swift (1 site)
- Line 74: `item.labels.contains` -> `item.safeLabels.contains`

### HistoryBrowserView.swift (1 site)
- Line 170: `item.labels.removeAll()` -> `item.safeLabels.removeAll()`

### ImportExportService.swift (2 sites)
- Line 122: `item.labels.map(\.name)` -> `item.safeLabels.map(\.name)`
- Line 252: `item.labels.append(label)` -> `item.safeLabels.append(label)`

### MigrationService.swift (2 sites)
- Line 15: `item.labels.contains(where:)` -> `item.safeLabels.contains(where:)`
- Line 18: `item.labels.append(singleLabel)` -> `item.safeLabels.append(singleLabel)`

### AppState.swift (1 site)
- Line 182: `item.labels.removeAll()` -> `item.safeLabels.removeAll()`

### ClipboardItem.swift (1 site, in init)
- Line 131: `self.labels = []` -- this stays as direct assignment to the backing property

### Label.swift (1 site, in init)
- Line 24: `self.items = []` -- this stays as direct assignment to the backing property

**Total: ~22 call sites to update in 8 files (excluding model init assignments).**

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@Attribute(.unique)` for dedup | Application-level hash check before insert | Required by CloudKit compatibility | Must change before sync enabled |
| Non-optional relationship arrays | Optional arrays with computed nil-safe accessors | Required by CloudKit compatibility | Ripples to 22+ call sites |
| No device ID on items | `originDeviceID` stamped at capture | Needed for cross-device dedup (Phase 21) | New field, defaulted for existing items |
| No VersionedSchema | VersionedSchema (optional, test auto-migration first) | SwiftData best practice for controlled migrations | Adds safety but also verbosity |

## Open Questions

1. **Does removing `@Attribute(.unique)` auto-migrate as lightweight?**
   - What we know: Adding `.unique` is documented as lightweight (when values are unique). Removing it is not explicitly documented.
   - What's unclear: Whether SwiftData/Core Data treats constraint relaxation as lightweight.
   - Recommendation: Test with a v1.4 database first. If auto-migration works, skip VersionedSchema. If it fails, add VersionedSchema with `.lightweight` stage. If that fails, use `.custom` stage.

2. **Should the deprecated `label: Label?` property be removed in this phase?**
   - What we know: It was marked "Remove in v1.3+" but is still present. Once CloudKit is enabled, it becomes permanent in the CloudKit schema.
   - What's unclear: Whether removing it breaks any existing user's migration path (users who haven't migrated from single-label to multi-label).
   - Recommendation: Keep it for now. The `MigrationService.migrateLabelsIfNeeded()` still references it. Removal is safe but adds risk to an already broad phase. Leave for a future cleanup or decide during planning.

3. **Should `isDuplicateOfMostRecent()` be consolidated with the new `isDuplicateByHash()`?**
   - What we know: `isDuplicateOfMostRecent` fetches 1 item (fast, O(1)). `isDuplicateByHash` does a fetchCount (fast but broader). Both check contentHash.
   - What's unclear: Whether the consecutive check adds meaningful performance benefit over just doing the full hash check.
   - Recommendation: Keep both. `isDuplicateOfMostRecent` is faster for the common case (rapid repeated Cmd+C). `isDuplicateByHash` catches the uncommon case (same content copied hours apart). The consecutive check short-circuits before the broader fetch.

4. **Performance of `fetchCount` on every clipboard capture.**
   - What we know: `fetchCount` is documented as efficient (translates to SQL `SELECT COUNT(*)`). The contentHash column is indexed by SwiftData.
   - What's unclear: Actual latency at 10K+ items. Is the index on contentHash maintained after removing `@Attribute(.unique)`?
   - Recommendation: SwiftData maintains indexes on properties used in predicates. Benchmark during implementation. If slow, consider keeping a local in-memory Set<String> of recent hashes (last 100) as a fast-path check.

## Sources

### Primary (HIGH confidence)
- **Codebase analysis** -- Direct reading of ClipboardItem.swift, Label.swift, ClipboardMonitor.swift, ImportExportService.swift, MigrationService.swift, AppState.swift, and all view files accessing `.labels`
- [fatbobman - Rules for Adapting Data Models to CloudKit](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/) -- Schema requirements (no unique, defaults, optional relationships)
- [Apple - Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) -- Official CloudKit schema requirements
- [Hacking with Swift - Lightweight vs complex migrations](https://www.hackingwithswift.com/quick-start/swiftdata/lightweight-vs-complex-migrations) -- What qualifies as lightweight migration
- [Apple WWDC23 - Model your schema with SwiftData](https://developer.apple.com/videos/play/wwdc2023/10195/) -- VersionedSchema and SchemaMigrationPlan
- [Hacking with Swift Forums - Best way to handle unique values with SwiftData and CloudKit](https://www.hackingwithswift.com/forums/swiftui/best-way-to-handle-unique-values-with-swiftdata-and-cloudkit/30145) -- Application-level dedup pattern

### Secondary (MEDIUM confidence)
- [Hacking with Swift - How to create a complex migration using VersionedSchema](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-create-a-complex-migration-using-versionedschema) -- Migration plan examples
- [fatbobman - Relationships in SwiftData](https://fatbobman.com/en/posts/relationships-in-swiftdata-changes-and-considerations/) -- Optional array relationship behavior
- [Apple Developer Forums - SwiftData + CloudKit deduplication](https://developer.apple.com/forums/thread/745329) -- Dedup strategies
- [Apple Developer Forums - SwiftData unversioned migration](https://developer.apple.com/forums/thread/761735) -- Auto-migration capabilities
- Milestone research files: `.planning/research/STACK.md`, `.planning/research/ARCHITECTURE.md`, `.planning/research/PITFALLS.md`

### Tertiary (LOW confidence)
- Whether removing `@Attribute(.unique)` auto-migrates as lightweight -- not explicitly documented by Apple, needs testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, purely internal changes
- Architecture: HIGH -- patterns are well-documented and verified against codebase
- Data model changes: HIGH -- requirements are universally documented for CloudKit
- Migration approach: MEDIUM -- removing `.unique` auto-migration behavior is not explicitly documented
- Call site enumeration: HIGH -- exhaustive grep of codebase with line numbers verified
- Pitfalls: HIGH -- derived from codebase analysis and milestone research

**Research date:** 2026-02-14
**Valid until:** 2026-03-14 (stable domain, no fast-moving dependencies)
