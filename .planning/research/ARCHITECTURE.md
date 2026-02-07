# Architecture Research: Storage Optimization & Sensitive Item Protection

**Domain:** macOS clipboard manager -- storage optimization, management tools, and sensitive data protection
**Researched:** 2026-02-07
**Confidence:** HIGH (based on direct source code analysis of all 40+ Swift files in the Pastel codebase, plus verified macOS/SwiftData API patterns)

## Confidence Note

All integration points are derived from direct analysis of every service, model, and view file in the Pastel codebase. Architecture recommendations are grounded in existing patterns the codebase already follows (singleton services, @MainActor services with ModelContext, @Observable for reactive UI, @AppStorage for preferences). Image compression recommendations use established macOS ImageIO and Core Graphics APIs. SwiftData batch deletion and aggregate query patterns are verified against Apple documentation and multiple credible sources. Sensitive content redaction uses SwiftUI's built-in `.redacted(reason:)` and `.blur()` modifiers -- HIGH confidence. SQLite VACUUM for database compaction is a well-documented technique, though SwiftData's direct support for it requires accessing the underlying Core Data store -- MEDIUM confidence for the exact API surface.

---

## Existing Architecture Summary

The current codebase has clean separation of concerns with well-defined component boundaries:

```
PastelApp (@main)
    |
    +-- AppState (@Observable, @MainActor)
    |       |-- ClipboardMonitor (Timer polling -> classify -> deduplicate -> SwiftData insert)
    |       |-- PanelController (NSPanel lifecycle, show/hide, event monitors)
    |       |-- PasteService (pasteboard write + CGEvent Cmd+V simulation)
    |       |-- RetentionService (hourly purge of items older than retention period)
    |       `-- modelContainer (SwiftData: ClipboardItem, Label)
    |
    +-- Models
    |       |-- ClipboardItem (@Model: textContent, htmlContent, rtfData, contentType,
    |       |                   imagePath, thumbnailPath, isConcealed, expiresAt,
    |       |                   contentHash (@Attribute(.unique)), label relationship,
    |       |                   detectedLanguage, detectedColorHex, url metadata fields)
    |       |-- ContentType (enum: text, richText, url, image, file, code, color)
    |       |-- Label (@Model: name, colorName/emoji, sortOrder)
    |       `-- LabelColor (enum: 8 preset colors)
    |
    +-- Services
    |       |-- ClipboardMonitor (main-thread polling at 0.5s, SHA256 hashing,
    |       |                     ExpirationService for concealed items)
    |       |-- ImageStorageService (singleton, background DispatchQueue, PNG storage,
    |       |                        4K downscale, 200px thumbnails, ~/Library/App Support/Pastel/images/)
    |       |-- ExpirationService (DispatchWorkItem timers, 60s auto-delete for concealed items)
    |       |-- RetentionService (hourly Timer, @AppStorage "historyRetention" in days)
    |       |-- PasteService (writeToPasteboard + simulatePaste, plain text mode)
    |       |-- CodeDetectionService (NLLanguageRecognizer, regex heuristics)
    |       |-- ColorDetectionService (regex for hex, rgb, hsl)
    |       |-- URLMetadataService (LPMetadataProvider, favicon/og:image caching)
    |       `-- AppIconColorService (dominant color extraction for card gradients)
    |
    +-- Views/Panel
    |       |-- PanelController -> SlidingPanel (NSPanel, .nonactivatingPanel)
    |       |-- PanelContentView (header + search + chips + filtered list)
    |       |-- FilteredCardListView (dynamic @Query with init-based predicates)
    |       |-- ClipboardCardView (dispatcher: header + contentPreview + footer)
    |       |-- TextCardView, ImageCardView, URLCardView, FileCardView, CodeCardView, ColorCardView
    |       |-- ChipBarView, SearchFieldView, EmptyStateView, AsyncThumbnailView
    |       `-- PanelActions (@Observable bridge for paste callbacks)
    |
    +-- Views/Settings
    |       |-- SettingsWindowController (NSWindow hosting SwiftUI)
    |       |-- SettingsView (tab bar: General, Labels)
    |       |-- GeneralSettingsView (launch, hotkey, position, retention, paste behavior, URL previews)
    |       `-- LabelSettingsView (CRUD for labels with emoji/color)
    |
    +-- Views/MenuBar
            `-- StatusPopoverView (monitoring toggle, show history, settings, clear all, quit)
```

### Key Architecture Patterns Already Established

1. **Service singletons for stateless work:** `ImageStorageService.shared`, `AppIconColorService.shared`
2. **@MainActor services for SwiftData access:** `ClipboardMonitor`, `RetentionService`, `ExpirationService` -- all hold a `ModelContext` and run on main thread
3. **Background DispatchQueue for I/O:** `ImageStorageService.backgroundQueue` at `.utility` QoS with completion handlers back to main
4. **@AppStorage for user preferences:** All settings use `@AppStorage` with string keys, read from `UserDefaults.standard` in services
5. **Fire-and-forget async post-processing:** Language detection and URL metadata fetch happen as `Task {}` after initial save
6. **@Observable + environment for reactive UI:** `AppState`, `PanelActions` injected via `.environment()`
7. **Dynamic @Query via init-based predicates:** `FilteredCardListView` rebuilds its `@Query` by being recreated with new init params

---

## Integration Architecture for New Features

### Feature Group 1: Image Compression Service

#### Integration Point: ImageStorageService

The image compression feature slots directly into `ImageStorageService`, which already handles all image disk I/O on a background `DispatchQueue`.

**Current flow (capture):**
```
ClipboardMonitor.processImageContent()
    -> reads TIFF/PNG data from NSPasteboard (main thread)
    -> ImageStorageService.shared.saveImage(data:) (background queue)
        -> downscaleIfNeeded(data:, maxSize: 3840) -- 4K cap
        -> write PNG to ~/Library/App Support/Pastel/images/{UUID}.png
        -> generate 200px thumbnail as {UUID}_thumb.png
        -> completion(imageFilename, thumbnailFilename) on main thread
    -> ClipboardMonitor creates ClipboardItem with imagePath, thumbnailPath
    -> modelContext.insert + save
```

**Proposed change -- compress to JPEG instead of PNG:**

The key insight is that `ImageStorageService` already calls `downscaleIfNeeded(data:maxSize:)` which uses `CGImageSource` and `NSBitmapImageRep`. The modification is minimal: instead of always producing PNG output, compress to JPEG at a configurable quality level.

```
ImageStorageService.saveImage(data:)  // MODIFIED
    -> downscaleIfNeeded (existing)
    -> compressToJPEG(data:, quality: compressionQuality)  // NEW
    -> write as {UUID}.jpg instead of {UUID}.png
    -> thumbnail generation unchanged (already small)
    -> completion with new filename
```

**Implementation details:**

- Add `@AppStorage("imageCompressionQuality")` preference (default: 0.8, range 0.5-1.0)
- Modify `saveImage(data:)` to call `NSBitmapImageRep.representation(using: .jpeg, properties: [.compressionFactor: quality])` instead of `.png`
- File extension changes from `.png` to `.jpg` -- this is safe because the DB stores only filenames, and `resolveImageURL(_:)` just appends to the directory path
- Existing images remain as PNG -- no migration needed. The viewer (`AsyncThumbnailView`) loads via `NSImage(contentsOf:)` which handles both formats
- **Do NOT use HEIC** despite better compression ratios: HEIC decoding is 2.1x slower than JPEG, and clipboard managers need fast thumbnail loading. JPEG at quality 0.8 provides ~80% size reduction vs PNG with negligible decode overhead

**Why NOT compress on capture in the hot path:**
The current flow already does background I/O. JPEG compression is fast (< 10ms for typical clipboard images). Compression should happen inline during `saveImage()`, not as a separate background task. A separate "batch recompress" feature is unnecessary complexity.

**New component:** None needed -- modification to existing `ImageStorageService`

**Settings integration:** Add a "Storage" section to `GeneralSettingsView` (or a new Settings tab) with an image quality slider

#### Estimated storage savings

| Format | Typical screenshot (1920x1080) | Typical photo (4K) |
|--------|-------------------------------|-------------------|
| PNG (current) | ~3-5 MB | ~15-25 MB |
| JPEG @ 0.8 | ~200-400 KB | ~1-2 MB |
| Savings | ~90% | ~90% |

---

### Feature Group 2: Content Deduplication

#### Integration Point: ClipboardMonitor.isDuplicateOfMostRecent()

**Current deduplication:**
- `ClipboardItem.contentHash` is `@Attribute(.unique)` -- SwiftData enforces uniqueness at the database level
- `isDuplicateOfMostRecent(contentHash:)` checks only the single most recent item (consecutive duplicate prevention)
- If a non-consecutive duplicate is inserted, the `.unique` constraint causes `modelContext.save()` to throw, caught in the `catch` block with `modelContext.rollback()`

**The existing architecture already prevents true duplicates** via the `@Attribute(.unique)` constraint on `contentHash`. What happens today:
1. Copy "hello" -> saved with hash ABC
2. Copy "world" -> saved with hash DEF
3. Copy "hello" again -> `isDuplicateOfMostRecent` returns false (different from "world"), insert attempted, `.unique` constraint violation on hash ABC, rollback -- silently dropped

**This means deduplication is already fully implemented.** The `@Attribute(.unique)` constraint on `contentHash` prevents any item with the same content from being stored twice, regardless of when it was copied. The only behavior question is: should re-copying existing content update the timestamp of the existing item (bump it to the top)?

**Proposed enhancement -- bump-to-top on re-copy:**

Instead of silently dropping the duplicate (current behavior via rollback), detect the duplicate and update its timestamp:

```swift
// In ClipboardMonitor.processPasteboardContent(), after computing contentHash:

// Check for existing item with same hash (any position, not just most recent)
if let existing = try? findExistingItem(contentHash: contentHash) {
    existing.timestamp = .now
    existing.sourceAppBundleID = sourceAppBundleID
    existing.sourceAppName = sourceAppName
    try? modelContext.save()
    return  // Don't create a new item
}
```

**New method on ClipboardMonitor:** `findExistingItem(contentHash:) -> ClipboardItem?`

This replaces the current `isDuplicateOfMostRecent` with a broader lookup, and updates instead of dropping. The `@Attribute(.unique)` constraint remains as a safety net.

**Image deduplication:** Already handled -- `ImageStorageService.computeImageHash(data:)` hashes the first 4KB of image data, and the same `@Attribute(.unique)` constraint applies.

**Near-duplicate detection:** Not recommended for v1.1. Near-duplicate detection (fuzzy matching, edit distance) adds significant complexity with marginal user benefit. Exact hash matching is sufficient for a clipboard manager.

---

### Feature Group 3: Storage Usage Tracking & Dashboard

#### New Component: StorageStatsService

**Purpose:** Calculate and cache storage statistics for display in a Settings dashboard.

**Architecture decision -- compute on demand, not cached in DB:**

Storage stats should be computed when the user opens the storage dashboard, not maintained incrementally. Rationale:
1. Stats are only viewed occasionally (settings screen)
2. Computing file sizes is fast enough for the expected scale (< 10K images typical)
3. Incremental tracking adds complexity to every insert/delete path
4. SwiftData `fetchCount` with predicates is efficient for item counts

```swift
@MainActor
@Observable
final class StorageStatsService {

    struct StorageStats {
        var totalItems: Int
        var itemsByType: [ContentType: Int]
        var imagesDiskSize: Int64       // bytes, from FileManager
        var databaseSize: Int64         // bytes, from FileManager
        var totalDiskSize: Int64        // images + database
        var oldestItemDate: Date?
        var newestItemDate: Date?
    }

    func computeStats(modelContext: ModelContext) async -> StorageStats {
        // Item counts: SwiftData fetchCount with type predicates
        // Image disk size: FileManager enumerate ~/Library/App Support/Pastel/images/
        // Database size: FileManager attributesOfItem on .store file
    }
}
```

**Integration with Settings:**

Add a new "Storage" tab to `SettingsView` (alongside General and Labels):

```
SettingsTab enum:
    case general    // existing
    case labels     // existing
    case storage    // NEW
```

The `StorageSettingsView` displays:
- Total storage used (images + database)
- Breakdown by content type (pie chart or bar)
- Item count by type
- "Purge by Category" buttons
- "Compact Database" button
- Image compression quality slider

**Disk size calculation approach:**

```swift
// Image directory size -- enumerate files and sum
func imageDiskSize() -> Int64 {
    let fm = FileManager.default
    let imagesDir = ImageStorageService.shared.resolveImageURL("").deletingLastPathComponent()
    guard let enumerator = fm.enumerator(at: imagesDir,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]) else { return 0 }
    var total: Int64 = 0
    for case let url as URL in enumerator {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        total += Int64(size)
    }
    return total
}

// Database size -- find the .store file
func databaseSize() -> Int64 {
    // SwiftData stores in ~/Library/Application Support/default.store
    // Access via modelContainer.configurations.first?.url
}
```

**Why a new tab, not a section in General:**

GeneralSettingsView already has 6 sections (startup, hotkey, position, retention, paste behavior, URL previews). Adding storage stats + purge controls + compression settings would make it too long. A dedicated "Storage" tab with its own icon keeps settings organized and follows macOS conventions (System Settings uses separate panes for Storage).

---

### Feature Group 4: Purge-by-Category and Database Compaction

#### Integration Point: New methods on AppState or a dedicated PurgeService

**Purge-by-category:**

SwiftData provides `delete(model:where:)` for batch deletion with predicates. This is the correct API:

```swift
// Delete all images
let predicate = #Predicate<ClipboardItem> { $0.contentType == "image" }
try modelContext.delete(model: ClipboardItem.self, where: predicate)
try modelContext.save()
```

However, batch delete does NOT trigger cascade cleanup of disk files. Image, favicon, and preview files must be cleaned up manually before the batch delete. The existing `clearAllHistory()` on AppState already demonstrates this pattern: fetch items first, delete their disk files, then batch delete.

**Proposed implementation:**

```swift
// On AppState (follows existing clearAllHistory pattern)
func purgeByCategory(_ contentType: ContentType, modelContext: ModelContext) {
    do {
        let typeRaw = contentType.rawValue
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { $0.contentType == typeRaw }
        )
        let items = try modelContext.fetch(descriptor)

        // Clean up disk files
        for item in items {
            ImageStorageService.shared.deleteImage(imagePath: item.imagePath, thumbnailPath: item.thumbnailPath)
            ImageStorageService.shared.deleteImage(imagePath: item.urlFaviconPath, thumbnailPath: item.urlPreviewImagePath)
        }

        // Batch delete from SwiftData
        try modelContext.delete(model: ClipboardItem.self, where: #Predicate<ClipboardItem> { $0.contentType == typeRaw })
        try modelContext.save()

        // Update item count
        clipboardMonitor?.itemCount = try modelContext.fetchCount(FetchDescriptor<ClipboardItem>())
    } catch {
        modelContext.rollback()
    }
}
```

**Database compaction (VACUUM):**

After large deletes, SQLite does not automatically reclaim disk space. The database file retains its size with deleted pages marked as free. To reclaim space:

```swift
func compactDatabase() {
    guard let container = modelContainer else { return }
    // Access underlying Core Data store
    let coordinator = container.mainContext.managedObjectContext?.persistentStoreCoordinator
    // Or use direct SQLite access
    guard let storeURL = container.configurations.first?.url else { return }
    // Execute VACUUM via sqlite3
}
```

**MEDIUM confidence warning:** Accessing SwiftData's underlying SQLite store for VACUUM is not officially supported. The safest approaches are:
1. **NSPersistentStoreCoordinator option:** Set `NSSQLiteManualVacuumOption` when adding the store
2. **Direct sqlite3:** Open the `.store` file with `sqlite3_open` and execute `VACUUM` -- but this requires the store to not be in use
3. **Deferred approach:** Skip VACUUM initially. SQLite reuses free pages for new data, so compaction is primarily a cosmetic concern for the storage dashboard display

**Recommendation:** Implement purge-by-category first. Add VACUUM as a follow-up only if users report storage dashboard showing large database files after purging. The free-page reuse means performance is not affected.

---

### Feature Group 5: Sensitive Item Flag (`isSensitive`)

#### Integration Point: ClipboardItem model + ClipboardMonitor capture pipeline

**Current sensitive content handling:**

The codebase already has a `isConcealed` field on `ClipboardItem`:
- Set to `true` when `org.nspasteboard.ConcealedType` is detected on the pasteboard (password managers)
- Concealed items get `expiresAt = Date.now + 60` seconds
- `ExpirationService` auto-deletes them after 60s
- Concealed items skip code/color detection (privacy)

**The new `isSensitive` flag is a different concept from `isConcealed`:**

| Aspect | `isConcealed` (existing) | `isSensitive` (new) |
|--------|------------------------|---------------------|
| Source | Auto-detected from pasteboard type | User-set flag OR heuristic detection |
| Duration | 60s auto-delete | User-configured retention (shorter than normal) |
| Visual | Currently no special rendering | Blurred/redacted card, click-to-reveal |
| Paste | Normal paste | Normal paste (content is accessible) |

**Model change:**

```swift
@Model
final class ClipboardItem {
    // ... existing fields ...

    /// Whether the item is marked as sensitive (user-set or auto-detected)
    var isSensitive: Bool    // NEW
}
```

**Why a separate field from `isConcealed`:**
- `isConcealed` has hardcoded 60s expiration behavior tied to `ExpirationService`
- `isSensitive` needs configurable retention and visual treatment
- A concealed item is always sensitive, but a sensitive item is not always concealed
- Keeping them separate avoids breaking the existing ExpirationService logic

**Auto-detection in ClipboardMonitor:**

Extend the capture pipeline to detect potentially sensitive content:

```swift
// In processPasteboardContent(), after content classification:
let isSensitive = isConcealed || SensitiveContentDetector.detect(primaryContent, sourceAppBundleID: sourceAppBundleID)
```

**SensitiveContentDetector (new service):**

```swift
struct SensitiveContentDetector {
    /// Check if content appears sensitive based on heuristics
    static func detect(_ content: String, sourceAppBundleID: String?) -> Bool {
        // 1. Source app is a known password manager
        if let bundleID = sourceAppBundleID,
           sensitiveAppBundleIDs.contains(bundleID) {
            return true
        }

        // 2. Content matches sensitive patterns (conservative)
        // - API key patterns: "sk-", "api_key=", "AKIA" (AWS)
        // - Token patterns: "ghp_", "Bearer ", "token="
        // NOT passwords (too many false positives with short strings)

        return false
    }

    private static let sensitiveAppBundleIDs: Set<String> = [
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.lastpass.LastPass",
        "org.keepassxc.keepassxc",
        "com.bitwarden.desktop",
    ]
}
```

**User-triggered sensitive flag:**

Add "Mark as Sensitive" / "Unmark as Sensitive" to the context menu in `ClipboardCardView`:

```swift
// In ClipboardCardView contextMenu
Button(item.isSensitive ? "Unmark as Sensitive" : "Mark as Sensitive") {
    item.isSensitive.toggle()
    try? modelContext.save()
}
```

**Sensitive item retention:**

The existing `RetentionService` reads `historyRetention` from UserDefaults. Add a separate `sensitiveRetention` setting:

```swift
// In RetentionService.purgeExpiredItems()
// After normal retention purge, also purge sensitive items with shorter retention
let sensitiveRetentionHours = UserDefaults.standard.integer(forKey: "sensitiveRetention")
guard sensitiveRetentionHours > 0 else { return } // 0 = same as normal

let sensitiveCutoff = Calendar.current.date(byAdding: .hour, value: -sensitiveRetentionHours, to: .now)!
let sensitiveDescriptor = FetchDescriptor<ClipboardItem>(
    predicate: #Predicate<ClipboardItem> { item in
        item.isSensitive == true && item.timestamp < sensitiveCutoff
    }
)
// ... fetch and delete with disk cleanup ...
```

**Settings integration:** Add to the new "Storage" tab or create a "Security" section in General.

---

### Feature Group 6: Redacted/Blurred Card Rendering

#### Integration Point: ClipboardCardView (the dispatcher view)

**The architectural decision is: where does the redaction wrapper go?**

Option A: Inside each card subview (TextCardView, ImageCardView, etc.)
Option B: In the dispatcher (ClipboardCardView), wrapping `contentPreview`
Option C: As a ViewModifier applied at the ClipboardCardView level

**Recommendation: Option B -- wrap in the dispatcher.** Rationale:
- Single point of change (one `if/else`, not 6 card views modified)
- The dispatcher already handles all cross-cutting concerns (hover, selection, context menu)
- Card subviews remain pure content renderers
- The header (source app icon, timestamp) should remain visible even when content is redacted

**Implementation in ClipboardCardView:**

```swift
@ViewBuilder
private var contentPreview: some View {
    if item.isSensitive && !isRevealed {
        // Redacted overlay
        sensitiveContentPlaceholder
    } else {
        switch item.type {
        case .text, .richText: TextCardView(item: item)
        case .url: URLCardView(item: item)
        case .image: ImageCardView(item: item)
        case .file: FileCardView(item: item)
        case .code: CodeCardView(item: item)
        case .color: ColorCardView(item: item)
        }
    }
}

@ViewBuilder
private var sensitiveContentPlaceholder: some View {
    HStack(spacing: 8) {
        Image(systemName: "eye.slash.fill")
            .foregroundStyle(.secondary)
        Text("Sensitive content")
            .font(.callout)
            .foregroundStyle(.secondary)
        Spacer()
        Text("Click to reveal")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, minHeight: 30)
}
```

**Why NOT use SwiftUI's `.redacted(reason: .privacy)`:**

The built-in redaction replaces text with gray rectangles of the same shape, which reveals the structure and length of the content. For a clipboard manager, this leaks information (a short redacted block suggests a password, a long one suggests a paragraph). A uniform placeholder with an icon is more appropriate and more visually consistent with the dark theme.

**Alternative: Gaussian blur over actual content:**

```swift
if item.isSensitive && !isRevealed {
    switch item.type {
    case .text, .richText: TextCardView(item: item)
    // ... all types ...
    }
    .blur(radius: 10)
    .allowsHitTesting(false)
    .overlay {
        Image(systemName: "eye.slash.fill")
            .font(.title2)
            .foregroundStyle(.white.opacity(0.7))
    }
}
```

**Recommendation:** Use the placeholder approach (not blur) for v1 because:
1. Blur still renders the actual content (accessibility tools may read it)
2. Blur requires rendering the full view then applying a filter (performance cost for images)
3. Placeholder communicates intent clearly
4. Blur looks odd on small cards

---

### Feature Group 7: Click-to-Reveal Interaction

#### Integration Point: ClipboardCardView state management

**Where does the "revealed" state live?**

| Option | Mechanism | Pros | Cons |
|--------|-----------|------|------|
| @State on ClipboardCardView | `@State private var isRevealed = false` | Simple, auto-resets on view recreation | Resets when scrolling (LazyVStack recycles), resets when query changes |
| Persisted on ClipboardItem | `var isRevealed: Bool` in SwiftData model | Survives scrolling | Persists across app launches (probably unwanted), pollutes model |
| EnvironmentObject tracking set | `Set<PersistentIdentifier>` on parent | Survives scrolling, resets on panel close | Slightly more complex wiring |

**Recommendation: @State on ClipboardCardView (Option 1).**

Rationale:
- Sensitive items should default to hidden every time the panel opens
- LazyVStack recycling actually *helps* -- scrolling away re-hides the content
- This is the simplest implementation and matches user expectations
- The panel is dismissed and recreated frequently (every toggle), so state is naturally reset

**Implementation:**

```swift
// In ClipboardCardView
@State private var isRevealed = false

// In the body, on the card's tap gesture:
.onTapGesture(count: 1) {
    if item.isSensitive && !isRevealed {
        withAnimation(.easeInOut(duration: 0.2)) {
            isRevealed = true
        }
        // Auto-hide after 10 seconds
        Task {
            try? await Task.sleep(for: .seconds(10))
            withAnimation(.easeInOut(duration: 0.2)) {
                isRevealed = false
            }
        }
    } else {
        selectedIndex = index  // normal selection behavior
    }
}
```

**Interaction design:**
- Single tap on a sensitive card: reveals content (no selection change)
- Single tap on a revealed sensitive card: normal selection behavior
- Double tap: paste (same as non-sensitive, works whether revealed or not)
- Auto-hide after 10 seconds of reveal
- Panel close: all reveals reset (natural from view recreation)

**Important: tap gesture interaction with existing gestures.**

The current `FilteredCardListView` attaches `.onTapGesture(count: 2)` and `.onTapGesture(count: 1)` to each `ClipboardCardView`. The reveal logic needs to be integrated into the single-tap handler:

```swift
// In FilteredCardListView, modify the single-tap:
.onTapGesture(count: 1) {
    if item.isSensitive {
        // Let ClipboardCardView handle its own reveal state
        // This requires moving tap handling INTO ClipboardCardView
    }
    selectedIndex = index
}
```

**Architecture consideration:** The tap gesture ownership may need to move from `FilteredCardListView` into `ClipboardCardView` itself, since `ClipboardCardView` is the component that knows about `isSensitive` and `isRevealed`. This is a minor refactor but important for clean separation.

---

### Feature Group 8: Sensitive Item Shorter Auto-Expiry

#### Integration Point: RetentionService

**Current retention architecture:**
- `RetentionService` runs hourly via `Timer.scheduledTimer(withTimeInterval: 3600)`
- Reads `historyRetention` from UserDefaults (in days): 7, 30, 90, 365, or 0 (forever)
- Fetches items with `timestamp < cutoffDate`, deletes them with disk cleanup

**Proposed change:**

Add a second pass in `purgeExpiredItems()` for sensitive items with a shorter retention:

```swift
func purgeExpiredItems() {
    // Pass 1: Normal retention (existing code, unchanged)
    purgeNormalItems()

    // Pass 2: Sensitive retention (NEW)
    purgeSensitiveItems()
}

private func purgeSensitiveItems() {
    let sensitiveHours = UserDefaults.standard.integer(forKey: "sensitiveRetention")
    guard sensitiveHours > 0 else { return } // 0 = no separate sensitive retention

    guard let cutoff = Calendar.current.date(byAdding: .hour, value: -sensitiveHours, to: .now) else { return }

    let descriptor = FetchDescriptor<ClipboardItem>(
        predicate: #Predicate<ClipboardItem> { item in
            item.isSensitive == true && item.timestamp < cutoff
        }
    )
    // ... fetch, clean up disk files, delete, save ...
}
```

**Sensitive retention options (for Settings picker):**
- 1 Hour
- 4 Hours
- 24 Hours
- Same as normal (default -- no separate treatment)

**Interaction with ExpirationService:**

The existing `ExpirationService` handles `isConcealed` items with a hardcoded 60-second timer. Concealed items are always sensitive, so they will be caught by `ExpirationService` first (60s) before `RetentionService`'s sensitive pass runs (1h+). No conflict.

**Timer frequency consideration:**

The current hourly timer is appropriate for normal retention (measured in days). For sensitive retention measured in hours, hourly is still fine -- worst case, a sensitive item lives 1 hour longer than configured. If more precision is needed, the timer can be changed to run every 15 minutes, but this is premature optimization.

---

## Component Dependency Graph

```
                    ┌─────────────────┐
                    │   ClipboardItem │
                    │   (@Model)      │
                    │ + isSensitive   │ ◄── NEW FIELD
                    └───────┬─────────┘
                            │
              ┌─────────────┼──────────────────┐
              │             │                  │
              v             v                  v
    ┌─────────────────┐ ┌──────────────┐ ┌───────────────┐
    │ClipboardMonitor │ │RetentionSvc  │ │ClipboardCard  │
    │+ SensitiveDetect│ │+ sensitive   │ │+ isRevealed   │
    │  (capture-time) │ │  purge pass  │ │+ redacted view│
    └────────┬────────┘ └──────────────┘ └───────────────┘
             │
             v
    ┌──────────────────┐     ┌──────────────────┐
    │ImageStorageService│     │StorageStatsService│ ◄── NEW
    │+ JPEG compression │     │+ disk size calc  │
    └──────────────────┘     │+ item counts     │
                             └──────────────────┘
                                      │
                                      v
                             ┌──────────────────┐
                             │StorageSettingsView│ ◄── NEW
                             │+ dashboard       │
                             │+ purge buttons   │
                             │+ compression     │
                             └──────────────────┘
```

---

## Data Flow Changes

### Capture Pipeline (Modified)

```
NSPasteboard.general
    │
    v
ClipboardMonitor.checkForChanges()
    │
    v
classifyContent() -> (contentType, isConcealed)
    │
    v
readContent (text/url/file/image)
    │
    v
CodeDetection / ColorDetection (existing)
    │
    ├── NEW: SensitiveContentDetector.detect(content, bundleID)
    │         -> sets isSensitive = true if detected
    │
    v
computeContentHash (SHA256)
    │
    ├── MODIFIED: findExistingItem(contentHash:)  -- bump-to-top dedup
    │             instead of isDuplicateOfMostRecent
    │
    v
[Image path] ImageStorageService.saveImage(data:)
    │           ├── MODIFIED: compress to JPEG @ configurable quality
    │           └── thumbnail generation (unchanged)
    │
    v
ClipboardItem(... isSensitive: isSensitive ...)  -- NEW field
    │
    v
modelContext.insert + save
    │
    v
[If concealed] ExpirationService.scheduleExpiration (unchanged)
[If code]      CodeDetectionService.detectLanguage (unchanged)
[If url]       URLMetadataService.fetchMetadata (unchanged)
```

### Rendering Pipeline (Modified)

```
FilteredCardListView (@Query)
    │
    v
ForEach items -> ClipboardCardView(item:)
    │
    ├── Header: sourceAppIcon + label + timestamp (UNCHANGED)
    │
    ├── Content: contentPreview
    │   ├── if item.isSensitive && !isRevealed:
    │   │       sensitiveContentPlaceholder (lock icon + "Click to reveal")
    │   └── else:
    │           TextCardView / ImageCardView / etc. (UNCHANGED)
    │
    ├── Footer: metadata + badge (UNCHANGED)
    │
    └── Context Menu:
        ├── existing items (Copy, Paste, Label, Delete)
        └── NEW: "Mark as Sensitive" / "Unmark as Sensitive"
```

### Retention Pipeline (Modified)

```
RetentionService.purgeExpiredItems() -- runs hourly
    │
    ├── Pass 1: Normal retention (UNCHANGED)
    │   └── Delete items where timestamp < (now - retentionDays)
    │
    └── Pass 2: Sensitive retention (NEW)
        └── Delete items where isSensitive == true
            AND timestamp < (now - sensitiveRetentionHours)
```

---

## New vs Modified Components

### New Components

| Component | Type | Purpose |
|-----------|------|---------|
| `SensitiveContentDetector` | Static service (struct) | Heuristic detection of sensitive content at capture time |
| `StorageStatsService` | @Observable service | Compute storage stats on demand for dashboard |
| `StorageSettingsView` | SwiftUI View | Storage dashboard, purge-by-category, compression settings |

### Modified Components

| Component | Change | Scope |
|-----------|--------|-------|
| `ClipboardItem` | Add `isSensitive: Bool` field | Model migration (lightweight, additive) |
| `ImageStorageService` | JPEG compression in `saveImage()` | ~20 lines changed in one method |
| `ClipboardMonitor` | Add sensitive detection call, improve dedup to bump-to-top | ~15 lines added |
| `RetentionService` | Add sensitive purge pass | ~25 lines added |
| `ClipboardCardView` | Add redacted view, isRevealed state, context menu item | ~30 lines added |
| `SettingsView` | Add `.storage` tab to SettingsTab enum | 3 lines |
| `GeneralSettingsView` | Possibly move compression setting here OR to new Storage tab | Minimal |
| `AppState` | Add `purgeByCategory()` method | ~20 lines |

### Unchanged Components

| Component | Why Unchanged |
|-----------|---------------|
| `PasteService` | Paste-back works identically for sensitive items (content is accessible) |
| `PanelController` / `SlidingPanel` | No panel behavior changes |
| `ExpirationService` | Concealed item auto-expire is orthogonal to sensitive flag |
| `TextCardView`, `ImageCardView`, etc. | Content rendering unchanged; redaction handled at dispatcher level |
| `FilteredCardListView` | Query predicates unchanged (no filtering by sensitivity) |
| `ChipBarView`, `SearchFieldView` | No interaction with sensitive/storage features |
| `Label`, `LabelColor` | No changes |

---

## SwiftData Migration

Adding `isSensitive: Bool` to `ClipboardItem` is a **lightweight migration** -- SwiftData handles additive fields automatically when using the default `ModelConfiguration`. The new field will default to `false` for existing items.

No explicit migration plan or versioned schema is needed. SwiftData's automatic lightweight migration handles:
- Adding new stored properties with default values
- The existing `@Attribute(.unique)` on `contentHash` is unaffected

---

## Settings Architecture

### New Settings Tab

```
SettingsView
    ├── General (existing)
    ├── Labels (existing)
    └── Storage (NEW)
        ├── Storage Usage section
        │   ├── Total disk usage (images + database)
        │   ├── Breakdown by content type
        │   └── Item count
        │
        ├── Image Compression section
        │   ├── Quality slider (0.5 - 1.0, default 0.8)
        │   └── Estimated savings text
        │
        ├── Sensitive Items section
        │   ├── Auto-detect sensitive content toggle
        │   ├── Sensitive item retention picker (1h, 4h, 24h, Same as normal)
        │   └── Excluded apps list (bundle IDs that always mark as sensitive)
        │
        └── Maintenance section
            ├── "Purge by Category" buttons (one per content type)
            ├── "Compact Database" button
            └── Each with confirmation dialog
```

### @AppStorage Keys

| Key | Type | Default | Used By |
|-----|------|---------|---------|
| `imageCompressionQuality` | Double | 0.8 | ImageStorageService |
| `sensitiveRetention` | Int | 0 (= same as normal) | RetentionService |
| `autoDetectSensitive` | Bool | true | ClipboardMonitor / SensitiveContentDetector |

---

## Suggested Build Order

Based on dependency analysis, the recommended implementation order is:

### Phase 1: Image Compression (Foundation)
**Why first:** Immediately reduces storage growth rate. No model changes. Isolated to `ImageStorageService`. Zero risk to existing features.

1. Modify `ImageStorageService.saveImage()` to output JPEG
2. Add `imageCompressionQuality` @AppStorage
3. Add quality slider to Settings (either General or new Storage tab shell)

### Phase 2: Sensitive Item Model + Detection (Core)
**Why second:** Adds the `isSensitive` field that rendering and retention depend on. Small model migration. Detection is additive to capture pipeline.

1. Add `isSensitive` field to `ClipboardItem`
2. Create `SensitiveContentDetector` service
3. Wire into `ClipboardMonitor.processPasteboardContent()` and `processImageContent()`
4. Add "Mark as Sensitive" context menu to `ClipboardCardView`

### Phase 3: Redacted Card Rendering + Click-to-Reveal (UI)
**Why third:** Depends on `isSensitive` field from Phase 2. Pure view-layer change.

1. Add `isRevealed` state to `ClipboardCardView`
2. Add `sensitiveContentPlaceholder` view
3. Wire tap gesture for reveal with auto-hide timer
4. Handle interaction between reveal tap and selection/paste tap

### Phase 4: Sensitive Retention (Lifecycle)
**Why fourth:** Depends on `isSensitive` field. Extends existing `RetentionService`. Needs settings UI.

1. Add `purgeSensitiveItems()` to `RetentionService`
2. Add `sensitiveRetention` @AppStorage
3. Add sensitive retention picker to Settings

### Phase 5: Deduplication Enhancement (Optimization)
**Why fifth:** Improves existing behavior, not a new feature. Low risk. Can be done independently but placed here to avoid disrupting the capture pipeline while Phases 2-4 are being built.

1. Replace `isDuplicateOfMostRecent` with `findExistingItem` (bump-to-top)
2. Keep `@Attribute(.unique)` as safety net

### Phase 6: Storage Dashboard + Purge-by-Category (Management)
**Why last:** This is a reporting/management feature that benefits from all other features being in place. The dashboard shows data from features built in Phases 1-5.

1. Create `StorageStatsService`
2. Create `StorageSettingsView` with dashboard
3. Add `purgeByCategory()` to `AppState`
4. Add "Storage" tab to `SettingsView`
5. Wire purge buttons with confirmation dialogs
6. (Optional) Add database compaction

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Incremental Storage Tracking
**What:** Maintaining running totals of storage usage in SwiftData/UserDefaults, updated on every insert/delete.
**Why bad:** Creates coupling between every data mutation and the stats system. Race conditions. Stale data when files are deleted outside the app.
**Instead:** Compute stats on demand from FileManager + SwiftData queries. Cache briefly (30s) for the dashboard view.

### Anti-Pattern 2: HEIC for Clipboard Images
**What:** Using HEIC format for better compression ratios.
**Why bad:** HEIC decoding is 2.1x slower than JPEG. Clipboard managers need fast thumbnail loading for smooth scrolling. The compression savings (~10% better than JPEG) don't justify the decode performance hit.
**Instead:** JPEG at quality 0.8 provides ~90% reduction vs PNG with negligible decode overhead.

### Anti-Pattern 3: Blur-Based Redaction
**What:** Using `.blur(radius:)` on the actual content view for sensitive items.
**Why bad:** The content is still rendered (accessibility tools can read it). Performance cost for large images. Inconsistent appearance at different blur radii.
**Instead:** Don't render the content at all. Show a placeholder. Only render content when `isRevealed == true`.

### Anti-Pattern 4: Persisting Reveal State
**What:** Storing `isRevealed` in SwiftData so it survives app restarts.
**Why bad:** Sensitive items should always default to hidden. Persisting reveal state means a user who reveals content and quits has their sensitive data visible on next launch.
**Instead:** Use `@State` (ephemeral). Panel recreation on toggle naturally resets all reveals.

### Anti-Pattern 5: Near-Duplicate Detection
**What:** Using edit distance, fuzzy hashing, or NLP to detect "similar" clipboard content.
**Why bad:** High false positive rate (e.g., incrementing a version number in a URL would be detected as near-duplicate). Expensive computation on every clipboard change. User confusion when "different" items are merged.
**Instead:** Exact hash matching (already implemented) is sufficient. Let users manually delete items they consider duplicates.

### Anti-Pattern 6: Separate Database for Sensitive Items
**What:** Storing sensitive items in a separate encrypted SQLite database.
**Why bad:** Doubles the data access complexity. SwiftData doesn't support multiple stores cleanly. Encryption at rest is already handled by macOS FileVault.
**Instead:** Same database, same model. Sensitivity is a flag that affects rendering and retention, not storage.

---

## Sources

- Direct source code analysis of all Pastel Swift files (HIGH confidence)
- [SwiftData batch delete API](https://fatbobman.com/en/snippet/how-to-batch-delete-data-in-swiftdata/) -- batch delete with predicates
- [SwiftData batch delete (Apple)](https://developer.apple.com/documentation/swiftdata/modelcontext/delete(model:where:includesubclasses:)) -- official API reference
- [SQLite VACUUM documentation](https://sqlite.org/lang_vacuum.html) -- database compaction
- [Core Data VACUUM](https://blog.eidinger.info/keep-your-coredata-store-small-by-vacuuming/) -- practical implementation
- [HEIC performance benchmarks](https://pspdfkit.com/blog/2018/ios-heic-performance/) -- decode speed comparison
- [SwiftUI redacted modifier](https://swiftwithmajid.com/2020/10/22/the-magic-of-redacted-modifier-in-swiftui/) -- privacy redaction patterns
- [SwiftUI privacySensitive](https://www.hackingwithswift.com/quick-start/swiftui/how-to-mark-content-as-private-using-privacysensitive) -- built-in privacy modifier
- [FileManager directory size](https://gist.github.com/tmspzz/a75f589e6bd86aa2121618155cbdf827) -- disk size calculation patterns
- [Maccy clipboard manager](https://github.com/p0deje/Maccy) -- reference implementation for sensitive content handling
- [SaneClip](https://saneclip.com/) -- password detection patterns in clipboard managers
- [ByteCountFormatter](https://nemecek.be/blog/22/how-to-get-file-size-using-filemanager-formatting) -- formatting byte counts for display
- [SwiftData expressions (iOS 18+)](https://useyourloaf.com/blog/swiftdata-expressions/) -- aggregate query capabilities
