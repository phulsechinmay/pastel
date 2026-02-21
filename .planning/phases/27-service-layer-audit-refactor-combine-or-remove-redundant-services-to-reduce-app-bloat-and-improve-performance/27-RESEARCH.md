# Phase 27: Service Layer Audit - Research

**Researched:** 2026-02-21
**Domain:** Swift service architecture refactoring (macOS, SwiftData, AppKit)
**Confidence:** HIGH

## Summary

The Pastel codebase has 19 files in `Services/`, plus 2 in `Utilities/` and 1 in `Extensions/` that function as services. Through 26 phases of iterative development, several concrete issues have accumulated: (1) duplicated item-deletion logic scattered across 5 call sites that each manually clean up images before deleting a ClipboardItem, (2) two separate timer-based cleanup services (ExpirationService and RetentionService) that share identical patterns but are not consolidated, (3) SHA256 hashing code duplicated in 3 places, (4) three color-related services that could be unified under one namespace, and (5) AppIconCache living in `Extensions/` despite being a service singleton.

However, the service layer is NOT severely bloated. Most services have clear, distinct responsibilities and correct boundaries. The audit should focus on the 5 concrete consolidation opportunities above, NOT on aggressive merging that could introduce coupling. The total service code is ~3,140 lines across 19 files -- quite reasonable for an app of this feature scope.

**Primary recommendation:** Extract a shared `ClipboardItemDeletionService` for the duplicated delete+image-cleanup pattern (most impactful), consolidate ExpirationService into RetentionService as a unified lifecycle service, extract SHA256 hashing into a shared utility, group the 3 color services under a `Color/` subfolder, and move AppIconCache from Extensions to Services.

## Standard Stack

This is a refactoring phase -- no new libraries needed. All work uses existing Swift/SwiftData patterns.

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Swift | 6.x | Language | Project standard |
| SwiftData | macOS 14+ | Persistence | Already in use |
| OSLog | macOS 14+ | Structured logging | Already in use across all services |

### Supporting
No new dependencies. This phase only reorganizes existing code.

## Architecture Patterns

### Current Service Layer Structure
```
Services/                          (19 files, 3140 lines)
  AccessibilityService.swift       (45 lines)  -- enum, static methods
  AppDiscoveryService.swift        (87 lines)  -- enum, static methods
  AppIconColorService.swift        (71 lines)  -- class, singleton
  ClipboardMonitor.swift           (447 lines) -- class, @Observable
  CodeDetectionService.swift       (176 lines) -- struct, static methods + actor cache
  ColorDetectionService.swift      (141 lines) -- struct, static methods
  ColorFormatService.swift         (103 lines) -- struct, static methods
  ColorToolController.swift        (63 lines)  -- class, singleton
  DeduplicationService.swift       (99 lines)  -- class, instance
  DragItemProviderService.swift    (73 lines)  -- enum, static methods
  ExpirationService.swift          (130 lines) -- class, instance
  ImageStorageService.swift        (265 lines) -- class, singleton
  ImportExportService.swift        (505 lines) -- class, @Observable
  PasteService.swift               (265 lines) -- class, instance
  RetentionService.swift           (98 lines)  -- class, instance
  SwiftDataHelpers.swift           (16 lines)  -- free function
  SyncMonitor.swift                (158 lines) -- class, @Observable
  URLMetadataService.swift         (360 lines) -- struct, static methods
  UpdaterService.swift             (38 lines)  -- class, #if SPARKLE

Extensions/
  NSWorkspace+AppIcon.swift        (33 lines)  -- AppIconCache singleton (misplaced)

Utilities/
  AppRelaunchService.swift         (14 lines)  -- enum, static method
  DeviceIdentifier.swift           (20 lines)  -- enum, static property
```

### Pattern 1: Extract ClipboardItem Deletion Helper
**What:** A centralized method that handles image cleanup + URL metadata cleanup + SwiftData delete for a ClipboardItem
**When to use:** Every time an item is deleted -- currently duplicated in 5 locations (RetentionService, ExpirationService, AppState.clearAllHistory, HistoryBrowserView, ClipboardCardView)
**Why high impact:** Each call site manually calls `ImageStorageService.shared.deleteImage` twice (once for image, once for URL metadata) then `modelContext.delete`. If a new image field is added, all 5 sites need updating.

**Current duplicated pattern (in 5 places):**
```swift
// This exact pattern appears in RetentionService, ExpirationService,
// AppState, HistoryBrowserView, and ClipboardCardView
ImageStorageService.shared.deleteImage(
    imagePath: item.imagePath,
    thumbnailPath: item.thumbnailPath
)
ImageStorageService.shared.deleteImage(
    imagePath: item.urlFaviconPath,
    thumbnailPath: item.urlPreviewImagePath
)
modelContext.delete(item)
```

**Recommended extraction:**
```swift
// Add to ClipboardItem as an instance method, or as a free function
@MainActor
func deleteClipboardItem(_ item: ClipboardItem, from modelContext: ModelContext) {
    // Clean up all associated disk images
    ImageStorageService.shared.deleteImage(
        imagePath: item.imagePath,
        thumbnailPath: item.thumbnailPath
    )
    ImageStorageService.shared.deleteImage(
        imagePath: item.urlFaviconPath,
        thumbnailPath: item.urlPreviewImagePath
    )
    // Clear label relationships for CloudKit compatibility
    item.safeLabels.removeAll()
    // Delete from SwiftData
    modelContext.delete(item)
}
```

### Pattern 2: Consolidate ExpirationService into RetentionService
**What:** Both services delete ClipboardItems on a schedule. ExpirationService handles concealed items (60s timer), RetentionService handles age-based purge (hourly timer). Merge into a unified `ItemLifecycleService`.
**When to use:** They share the same ModelContext dependency, same deletion pattern, and are both wired from the same init path (ClipboardMonitor creates ExpirationService, AppState creates RetentionService).

**Recommended structure:**
```swift
@MainActor
final class ItemLifecycleService {
    private let modelContext: ModelContext
    private var retentionTimer: Timer?
    private var pendingExpirations: [PersistentIdentifier: DispatchWorkItem] = [:]

    init(modelContext: ModelContext) { ... }

    // -- Retention (hourly purge) --
    func startPeriodicPurge() { ... }
    func purgeExpiredItems() { ... }

    // -- Concealed item expiration (60s) --
    func scheduleExpiration(for item: ClipboardItem) { ... }
    func cancelExpiration(for itemID: PersistentIdentifier) { ... }
    func expireOverdueItems() { ... }
}
```

### Pattern 3: SHA256 Hashing Utility
**What:** SHA256 content hashing is duplicated in ClipboardMonitor (line 243-244), ImportExportService (line 451-452), and ImageStorageService (line 201-204).
**Recommended extraction:**
```swift
// In SwiftDataHelpers.swift or a new ContentHashService
import CryptoKit

enum ContentHash {
    /// SHA256 hash of text content, returned as lowercase hex string
    static func hash(text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// SHA256 hash of first 4KB of data (for images), returned as lowercase hex string
    static func hash(imageData: Data) -> String {
        let prefix = imageData.prefix(4096)
        let digest = SHA256.hash(data: prefix)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
```

### Pattern 4: Group Color Services
**What:** Three separate files handle color-related functionality: ColorDetectionService (detects colors in clipboard text), ColorFormatService (converts hex to RGB/HSL/CMYK), ColorToolController (system color picker). They are distinct responsibilities but closely related.
**Recommended:** Move to a `Services/Color/` subfolder for organizational clarity. No code merging needed.

### Pattern 5: Move AppIconCache to Services
**What:** `AppIconCache` is a `@MainActor` singleton in `Extensions/NSWorkspace+AppIcon.swift`. It is NOT an NSWorkspace extension -- it's a standalone cache service.
**Recommended:** Move to `Services/AppIconCache.swift` alongside `AppIconColorService.swift`.

### Anti-Patterns to Avoid
- **Over-merging distinct services:** Do NOT combine CodeDetectionService with ColorDetectionService just because they're both "detection." They have zero shared logic and serve completely different code paths.
- **Creating a "god service":** Do NOT merge PasteService, ClipboardMonitor, and ImageStorageService into a single service. They have fundamentally different responsibilities and threading models.
- **Breaking singleton patterns mid-refactor:** Services like ImageStorageService and AppIconColorService are singletons accessed from multiple call sites. Changing their instantiation pattern would cascade across the entire codebase.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Logger boilerplate | Custom logging wrapper | OSLog Logger directly | Already consistent across all 9 service files; a wrapper adds indirection with no benefit |
| Service locator | Custom DI container | Direct singleton/init injection | App is single-process, services are stable; DI containers add complexity for no gain at this scale |
| Event bus | Custom pub/sub system | NotificationCenter + callbacks | Already in use (ClipboardMonitor uses callbacks, SyncMonitor uses NotificationCenter); works well |

**Key insight:** The app's service layer is already well-structured. The refactoring opportunities are about reducing duplication and improving organization, not about introducing new architectural patterns.

## Common Pitfalls

### Pitfall 1: Breaking the Delete + Image Cleanup Pairing
**What goes wrong:** If the deletion helper is extracted but one call site still uses the old manual pattern, images become orphaned on disk.
**Why it happens:** Search-and-replace misses a call site, or a new feature adds deletion without using the helper.
**How to avoid:** After extraction, grep for all `modelContext.delete` calls on `ClipboardItem` to verify none bypass the helper. Add a code comment on ClipboardItem noting the mandatory cleanup.
**Warning signs:** Growing `~/Library/Application Support/Pastel/images/` directory over time.

### Pitfall 2: ExpirationService Lifecycle During Merge
**What goes wrong:** ExpirationService is currently created by ClipboardMonitor's init and owns DispatchWorkItem references for pending expirations. If merged into a service that lives on AppState, the ownership chain changes.
**Why it happens:** ClipboardMonitor privately creates and holds ExpirationService. Moving it out requires rewiring who owns the merged service.
**How to avoid:** Create ItemLifecycleService in AppState.setup(), pass it to ClipboardMonitor as an init parameter, and have ClipboardMonitor call `lifecycleService.scheduleExpiration(for:)` instead of `expirationService.scheduleExpiration(for:)`.
**Warning signs:** Concealed items not expiring (no timer fires), or retain cycles from circular references.

### Pitfall 3: Forgetting safeLabels.removeAll() in Delete Helper
**What goes wrong:** CloudKit sync may fail or produce orphaned label relationships if labels are not cleared before item deletion.
**Why it happens:** AppState.clearAllHistory does `item.safeLabels.removeAll()` before delete, but other call sites do not. The delete helper must include this.
**How to avoid:** Include `item.safeLabels.removeAll()` in the centralized deletion helper. Verify all call sites switch to the helper.
**Warning signs:** CloudKit sync errors mentioning relationship integrity.

### Pitfall 4: Xcode Scheme Disruption During File Moves
**What goes wrong:** Moving files (e.g., AppIconCache from Extensions to Services) can break Xcode project references if xcodegen is run incorrectly.
**Why it happens:** The project uses xcodegen; file moves require regenerating the project.
**How to avoid:** Move files on disk first, run `xcodegen generate`, verify the Pastel scheme still exists.
**Warning signs:** Build errors about missing files, or the Pastel scheme disappearing.

### Pitfall 5: Service Initialization Order
**What goes wrong:** Merged services may create initialization order dependencies. E.g., if ItemLifecycleService needs ImageStorageService.shared, and ImageStorageService init runs directory creation, the order matters.
**Why it happens:** ImageStorageService is a lazy singleton (created on first access), so it's safe. But if services were restructured to take dependencies in init, order could matter.
**How to avoid:** Keep singletons as singletons. For merged services, use the same init pattern as the original services.

## Code Examples

### Example 1: ClipboardItem Deletion Helper (recommended extraction)
```swift
// File: Services/SwiftDataHelpers.swift (add to existing file)
// Or: A new ClipboardItemHelpers.swift

/// Delete a ClipboardItem with full cleanup: disk images, URL metadata images,
/// label relationships, and SwiftData model.
///
/// Centralizes the deletion pattern used in RetentionService, ExpirationService,
/// AppState.clearAllHistory, HistoryBrowserView, and ClipboardCardView.
@MainActor
func deleteClipboardItemWithCleanup(_ item: ClipboardItem, from modelContext: ModelContext) {
    // Clean up clipboard image + thumbnail
    ImageStorageService.shared.deleteImage(
        imagePath: item.imagePath,
        thumbnailPath: item.thumbnailPath
    )
    // Clean up URL metadata images (favicon + og:image preview)
    ImageStorageService.shared.deleteImage(
        imagePath: item.urlFaviconPath,
        thumbnailPath: item.urlPreviewImagePath
    )
    // Clear label relationships for CloudKit compatibility
    item.safeLabels.removeAll()
    // Delete from SwiftData
    modelContext.delete(item)
}
```

### Example 2: Merged ItemLifecycleService
```swift
// File: Services/ItemLifecycleService.swift
// Replaces: ExpirationService.swift + RetentionService.swift

@MainActor
final class ItemLifecycleService {
    private let modelContext: ModelContext
    private var retentionTimer: Timer?
    private var pendingExpirations: [PersistentIdentifier: DispatchWorkItem] = [:]

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "ItemLifecycleService"
    )

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Retention (hourly purge of old items)

    func startPeriodicPurge() {
        purgeExpiredItems()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.purgeExpiredItems() }
        }
    }

    func purgeExpiredItems() {
        // ... existing RetentionService.purgeExpiredItems() logic
        // Use deleteClipboardItemWithCleanup() for each item
    }

    // MARK: - Concealed Item Expiration (60s auto-delete)

    func scheduleExpiration(for item: ClipboardItem) {
        // ... existing ExpirationService.scheduleExpiration() logic
    }

    func cancelExpiration(for itemID: PersistentIdentifier) {
        // ... existing ExpirationService.cancelExpiration() logic
    }

    func expireOverdueItems() {
        // ... existing ExpirationService.expireOverdueItems() logic
        // Use deleteClipboardItemWithCleanup() for each item
    }

    func stop() {
        retentionTimer?.invalidate()
        retentionTimer = nil
        pendingExpirations.values.forEach { $0.cancel() }
        pendingExpirations.removeAll()
    }
}
```

### Example 3: ContentHash Utility
```swift
// File: Services/SwiftDataHelpers.swift (add to existing file)
import CryptoKit

enum ContentHash {
    static func hash(text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    static func hash(imageData: Data) -> String {
        let prefix = imageData.prefix(4096)
        let digest = SHA256.hash(data: prefix)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
```

## Detailed Audit Findings

### Services with CLEAR boundaries (no action needed)
| Service | Lines | Responsibility | Verdict |
|---------|-------|---------------|---------|
| AccessibilityService | 45 | TCC permission check | Clean enum, no overlap |
| AppDiscoveryService | 87 | Scan installed apps | Only used by PrivacySettingsView |
| ClipboardMonitor | 447 | Poll + classify + persist | Core service, well-scoped |
| CodeDetectionService | 176 | Detect code + language | Static struct + actor cache, clean |
| DragItemProviderService | 73 | NSItemProvider factory | Pure utility, no dependencies |
| ImageStorageService | 265 | Disk I/O for images | Singleton, well-scoped |
| ImportExportService | 505 | Import/export .pastel files | Large but self-contained |
| PasteService | 265 | Pasteboard write + Cmd+V | Clean, distinct responsibility |
| SyncMonitor | 158 | CloudKit sync state | Clean, only used when sync enabled |
| DeduplicationService | 99 | Cross-device dedup | Clean, only used when sync enabled |
| UpdaterService | 38 | Sparkle OTA updates | Conditionally compiled, minimal |
| URLMetadataService | 360 | Fetch URL title/favicon/og | Static struct, self-contained |
| SwiftDataHelpers | 16 | saveWithLogging() | Shared utility, good pattern |

### Services with CONSOLIDATION opportunities
| Service | Lines | Issue | Action |
|---------|-------|-------|--------|
| ExpirationService | 130 | Overlaps with RetentionService (both delete items on schedule) | Merge into ItemLifecycleService |
| RetentionService | 98 | Overlaps with ExpirationService | Merge into ItemLifecycleService |
| ColorDetectionService | 141 | Same domain as ColorFormatService and ColorToolController | Group in subfolder |
| ColorFormatService | 103 | Same domain as above | Group in subfolder |
| ColorToolController | 63 | Same domain as above | Group in subfolder |
| AppIconColorService | 71 | Related to AppIconCache (both serve icon display) | Consider grouping |

### Cross-cutting issues
| Issue | Locations | Action |
|-------|-----------|--------|
| Duplicated item deletion + image cleanup | 5 call sites | Extract deleteClipboardItemWithCleanup() |
| Duplicated SHA256 hashing | 3 call sites | Extract ContentHash enum |
| AppIconCache misplaced in Extensions/ | 1 file | Move to Services/ |
| Inconsistent safeLabels.removeAll() before delete | Only AppState.clearAllHistory does it | Include in deletion helper |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual delete + cleanup in each call site | Centralized deletion helper | This phase | Eliminates 5-way duplication |
| Separate Expiration + Retention services | Unified ItemLifecycleService | This phase | 2 files -> 1 file, shared ModelContext |
| SHA256 inline in each file | ContentHash utility | This phase | 3 duplicates -> 1 source of truth |

## Open Questions

1. **Should AppIconCache and AppIconColorService be merged?**
   - What we know: Both are @MainActor singletons that cache per-bundleID data. AppIconCache caches NSImage icons, AppIconColorService caches SwiftUI Color values (derived from icons).
   - What's unclear: AppIconColorService uses CIFilter which has different performance characteristics. Merging could create a single class with mixed concerns.
   - Recommendation: Keep separate but move AppIconCache to Services/ alongside AppIconColorService. They have distinct output types and consumers.

2. **Should color subfolder grouping wait for a larger restructure?**
   - What we know: The 3 color services total 307 lines. Moving them to a subfolder changes import paths for nothing.
   - What's unclear: Whether xcodegen handles subfolders within Sources cleanly for this project.
   - Recommendation: LOW priority. Only do if the team wants it. File organization is cosmetic here.

## Sources

### Primary (HIGH confidence)
- Direct codebase analysis of all 19 service files, 2 utility files, 1 misplaced extension
- Line-by-line reading of all service source code
- Grep analysis of cross-service dependencies and duplicated patterns

### Notes
- This is an internal refactoring phase. No external libraries, APIs, or documentation were needed.
- All findings are based on the actual codebase state as of 2026-02-21.

## Metadata

**Confidence breakdown:**
- Service inventory: HIGH - every file was read in full
- Consolidation opportunities: HIGH - based on direct code comparison
- Pitfalls: HIGH - based on actual codebase patterns and known project constraints
- Refactoring patterns: HIGH - standard Swift patterns, no novelty

**Research date:** 2026-02-21
**Valid until:** Until next phase adds/modifies services (no external dependency expiry)
