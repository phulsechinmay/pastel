# Stack Research: v1.2 Storage & Security

**Domain:** Native macOS Clipboard Manager -- Storage Optimization & Sensitive Data Protection
**Project:** Pastel
**Researched:** 2026-02-07
**Confidence:** HIGH

> **Scope:** This document covers ONLY the stack additions needed for v1.2. The existing v1.0/v1.1 stack is validated and unchanged. All recommendations use Apple first-party frameworks -- zero new third-party dependencies for this milestone.

---

## Existing Stack (Validated, No Changes)

| Technology | Version | Purpose | Status |
|------------|---------|---------|--------|
| Swift 6.0 | 6.0 | Primary language | Validated |
| SwiftUI + AppKit hybrid | macOS 14+ | UI framework | Validated |
| SwiftData | macOS 14+ | Persistence | Validated |
| KeyboardShortcuts (sindresorhus) | 2.4.0 | Panel toggle hotkey + recorder | Validated |
| LaunchAtLogin-Modern (sindresorhus) | 1.1.0 | Login item | Validated |
| HighlightSwift | 1.1.0 | Syntax highlighting for code cards | Validated |
| CryptoKit | macOS 14+ | SHA256 hashing for deduplication | Validated |
| ImageIO (CGImageSource) | macOS 14+ | Image downscaling + thumbnails | Validated |
| NSPanel + NSHostingView | AppKit | Non-activating sliding panel | Validated |
| XcodeGen (project.yml) | -- | Project generation | Validated |

---

## New Stack Additions for v1.2

### 1. Image Compression: JPEG via CGImageDestination (ImageIO)

**Recommendation: Compress stored images as JPEG instead of PNG**

| Attribute | Value |
|-----------|-------|
| Framework | ImageIO (Apple first-party, already imported) |
| API | `CGImageDestinationCreateWithData` + `kCGImageDestinationLossyCompressionQuality` |
| Format | JPEG (not HEIC) |
| New dependency | None |
| Confidence | HIGH |

**Why JPEG over HEIC:**

HEIC offers ~50% better compression than JPEG at equivalent visual quality. However, for a clipboard manager, JPEG is the better choice:

| Criterion | JPEG (Recommended) | HEIC |
|-----------|-------------------|------|
| Paste compatibility | Universal -- every app accepts JPEG | Some older apps choke on HEIC |
| Encoding speed | Fast, hardware-accelerated everywhere | Fast on Apple Silicon, slower on older Intel |
| macOS encoding support | All macOS versions | macOS 10.13+ but edge case bugs in early versions |
| Storage savings vs PNG | 5-10x smaller at quality 0.8 | 10-20x smaller at quality 0.8 |
| Paste-back fidelity | No conversion needed for most apps | May need JPEG transcode for paste-back |
| Thumbnail compatibility | NSImage loads natively | NSImage loads natively |

**The critical insight:** Pastel currently stores images as PNG. A typical screenshot PNG is 2-5MB. The same image as JPEG at quality 0.85 is 200-800KB -- a 5-10x reduction with negligible visual difference for clipboard previews. This alone is the single biggest storage optimization available. Going from PNG to HEIC would save more, but introduces paste-back compatibility concerns that outweigh the incremental savings.

**Why NOT HEIC:** When users paste an image from clipboard history, the receiving app needs to decode it. JPEG is universally supported. HEIC can fail in older apps, CLI tools, non-Apple software, and web forms. For a clipboard manager, paste fidelity is more important than maximum compression.

**Compression strategy:**

```
New images (captured after v1.2):
  - Store as JPEG at quality 0.85 (configurable 0.7-1.0)
  - Thumbnails remain PNG (tiny files, lossless preferred for UI)

Existing images (migration):
  - Background job converts PNG -> JPEG on first launch after upgrade
  - Original PNG deleted after successful JPEG conversion
  - Track migration progress to avoid re-running
```

**Integration with existing ImageStorageService:**

The current `ImageStorageService.saveImage(data:)` writes PNG via `NSBitmapImageRep.representation(using: .png)`. Change to use `CGImageDestination` with JPEG type:

```swift
import ImageIO
import UniformTypeIdentifiers

private static func jpegData(from cgImage: CGImage, quality: CGFloat = 0.85) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data as CFMutableData,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    ) else { return nil }

    let options: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: quality
    ]
    CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}
```

**File naming change:** New images use `{UUID}.jpg` instead of `{UUID}.png`. The `imagePath` field in `ClipboardItem` already stores just the filename, so no database migration is needed -- existing `.png` paths still resolve correctly.

**Original data preservation:** For paste-back, keep the original raw pasteboard data (TIFF/PNG) in a separate file (`{UUID}_original.dat`) so paste-back sends the exact data the user copied. The JPEG is for display/storage only. This prevents quality degradation on repeated copy-paste cycles.

**Confidence:** HIGH. CGImageDestination with JPEG is a stable, well-documented Apple API available since macOS 10.4. The project already imports ImageIO.

---

### 2. Storage Size Calculation: FileManager + URLResourceValues

**Recommendation: FileManager enumerator with totalFileAllocatedSize**

| Attribute | Value |
|-----------|-------|
| Framework | Foundation (already imported) |
| API | `FileManager.enumerator(at:includingPropertiesForKeys:)` + `URLResourceValues.totalFileAllocatedSize` |
| New dependency | None |
| Confidence | HIGH |

**Why this approach:**

Calculating directory size requires walking the file tree and summing allocated sizes. Apple provides `URLResourceValues.totalFileAllocatedSize` which accounts for filesystem metadata and compression -- more accurate than raw `fileSize`.

**Implementation pattern:**

```swift
extension FileManager {
    /// Calculate total allocated size of a directory in bytes.
    /// Uses totalFileAllocatedSize (preferred) with fileAllocatedSize as fallback.
    func allocatedSize(of directoryURL: URL) throws -> UInt64 {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ]

        guard let enumerator = self.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: nil
        ) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        var totalSize: UInt64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { continue }

            if let size = values.totalFileAllocatedSize {
                totalSize += UInt64(size)
            } else if let size = values.fileAllocatedSize {
                totalSize += UInt64(size)
            }
        }
        return totalSize
    }
}
```

**Storage dashboard data sources:**

| Metric | Source | How |
|--------|--------|-----|
| Total images on disk | FileManager directory walk | `allocatedSize(of: imagesDirectory)` |
| SwiftData database size | FileManager file size | Size of `.store` file in Application Support |
| Item count by type | SwiftData `fetchCount` | Separate `FetchDescriptor` per `ContentType` |
| Total byte count in DB | SwiftData fetch + sum | Fetch all items, sum `byteCount` field |

**Why NOT SwiftData aggregate queries:** SwiftData's `#Expression` macro (iOS 18 / macOS 15) supports basic aggregation but has significant limitations -- `sum()`, `max()`, and `map()` are not yet supported in expressions. Since Pastel targets macOS 14+, and even macOS 15's support is limited, use Swift-side iteration: fetch items and compute sums in memory. For a clipboard manager with thousands (not millions) of items, this is fast enough.

**Performance consideration:** Run storage calculation on a background queue. Walking the images directory with hundreds of files takes <100ms. Cache results and refresh on demand (user opens storage dashboard) or on timer (every 5 minutes if dashboard is visible).

**Confidence:** HIGH. FileManager enumeration with URLResourceValues is a stable Foundation pattern used since macOS 10.6.

---

### 3. Content Deduplication: SHA256 (CryptoKit, Already Used)

**Recommendation: Extend existing `contentHash` deduplication**

| Attribute | Value |
|-----------|-------|
| Framework | CryptoKit (already imported) |
| Current behavior | `contentHash` is `@Attribute(.unique)` -- prevents exact duplicates from being inserted |
| Change needed | Remove consecutive-only limitation; detect non-consecutive duplicates |
| New dependency | None |
| Confidence | HIGH |

**Current dedup behavior (v1.0):**

The app currently does two things:
1. `@Attribute(.unique)` on `contentHash` -- SwiftData prevents any two items from having the same hash (insert fails with a caught error)
2. `isDuplicateOfMostRecent()` -- checks if the content hash matches the single most recent item

The current behavior already prevents all duplicates from being stored (via the `.unique` constraint). The `isDuplicateOfMostRecent` check is an optimization to avoid the insert-fail-rollback cycle for the most common case (consecutive same-copy).

**What v1.2 adds:**

The dedup infrastructure is already solid. What v1.2 needs is **user-facing dedup management**:

1. **Surface existing duplicates** -- Query for items sharing the same `contentHash` (which currently cannot exist due to `.unique`, but items with very similar content could be shown)
2. **Smart dedup on re-copy** -- When a user copies something they've copied before, instead of rejecting the duplicate, update the timestamp of the existing item to bring it to the top. This is a behavior change, not a stack change.

**For images:** The current `computeImageHash` only hashes the first 4KB for speed. This is a valid optimization for clipboard dedup (different screenshots will have different headers), but for true dedup across similar images, consider also storing image dimensions as part of the key.

**Confidence:** HIGH. CryptoKit SHA256 is already in use. No new stack needed.

---

### 4. Sensitive Item Display: SwiftUI `.blur()` + State Toggle

**Recommendation: Custom blur overlay with tap-to-reveal, not `.redacted(reason: .privacy)`**

| Attribute | Value |
|-----------|-------|
| Framework | SwiftUI (already used) |
| API | `.blur(radius:)` modifier + `@State` toggle |
| Availability | `.blur()` available since SwiftUI 1.0 (macOS 10.15+) |
| New dependency | None |
| Confidence | HIGH |

**Why `.blur()` over `.redacted(reason: .privacy)`:**

| Criterion | `.blur()` (Recommended) | `.redacted(reason: .privacy)` |
|-----------|------------------------|-------------------------------|
| Visual effect | Gaussian blur -- content shape visible but unreadable | Gray placeholder boxes -- looks like loading skeleton |
| User experience | Clearly communicates "hidden content here" | Looks like broken/loading UI |
| Tap-to-reveal | Natural -- reduce blur to 0 | Awkward -- toggle redaction reason |
| Image support | Works on any view including images | Redacts text but images may not blur properly |
| Customizability | Adjustable radius, can combine with overlays | Fixed appearance per redaction reason |
| macOS availability | macOS 10.15+ (SwiftUI 1.0) | `.privacy` reason requires macOS 12+ |

**The key difference:** `.redacted(reason: .privacy)` is designed for system-level privacy (lock screen widgets, always-on display). It produces gray placeholder boxes that look like skeleton loading states. For a clipboard manager where the user explicitly marks items as sensitive, a blur effect with a lock icon overlay communicates intent much better.

**Implementation pattern:**

```swift
struct SensitiveContentOverlay: ViewModifier {
    let isSensitive: Bool
    @State private var isRevealed: Bool = false

    func body(content: Content) -> some View {
        content
            .blur(radius: isSensitive && !isRevealed ? 10 : 0)
            .overlay {
                if isSensitive && !isRevealed {
                    VStack(spacing: 4) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 16))
                        Text("Click to reveal")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .onTapGesture {
                if isSensitive {
                    isRevealed.toggle()
                }
            }
    }
}

extension View {
    func sensitiveContent(_ isSensitive: Bool) -> some View {
        modifier(SensitiveContentOverlay(isSensitive: isSensitive))
    }
}
```

**Auto-hide behavior:** After revealing, automatically re-blur after 5 seconds of no interaction. Use `DispatchQueue.main.asyncAfter` or a `Timer` to reset `isRevealed = false`.

**Confidence:** HIGH. SwiftUI `.blur()` is one of the most basic view modifiers, available since the first version of SwiftUI.

---

### 5. Sensitive Item Model: SwiftData Optional Field

**Recommendation: Add `isSensitive: Bool` flag to ClipboardItem**

| Attribute | Value |
|-----------|-------|
| Framework | SwiftData (already used) |
| Change | New optional property on `ClipboardItem` |
| Migration | Automatic lightweight migration (Optional with nil default) |
| Confidence | HIGH |

**New ClipboardItem fields for v1.2:**

```swift
// Storage optimization
var isCompressed: Bool?           // Whether image was compressed to JPEG
var originalByteCount: Int?       // Original size before compression (for dashboard stats)

// Sensitive item support
var isSensitive: Bool?            // User-marked as sensitive (default nil = false)
var sensitiveExpiryDays: Int?     // Custom retention override for sensitive items (nil = use global)
```

**Why `isSensitive` as Optional Bool, not non-optional:**

SwiftData automatic lightweight migration requires new fields to be Optional with nil defaults. Making it `Bool?` with nil meaning "not sensitive" avoids VersionedSchema complexity. At the view layer, treat `nil` as `false`:

```swift
var markedSensitive: Bool {
    isSensitive ?? false
}
```

**Distinction from `isConcealed`:**

The model already has `isConcealed: Bool` which is set automatically for password manager items (detected via `org.nspasteboard.ConcealedType`). The new `isSensitive` is user-controlled:

| Field | Source | Behavior |
|-------|--------|----------|
| `isConcealed` | Automatic (pasteboard type) | Auto-expires after 60s |
| `isSensitive` | User marks manually | Blurred display, optional shorter retention |

These are independent. An item can be both concealed AND marked sensitive (though concealed items auto-expire so this is a rare case).

**Migration strategy:** All new fields are Optional. SwiftData handles automatic lightweight migration. No VersionedSchema needed, consistent with the v1.1 approach (confirmed in STATE.md decision [06-01]).

**Confidence:** HIGH. Same pattern used successfully for all v1.1 schema additions.

---

### 6. Storage Dashboard: SwiftUI Charts (Optional) + ByteCountFormatter

**Recommendation: SwiftUI bar chart or progress bars for storage visualization**

| Attribute | Value |
|-----------|-------|
| Framework | SwiftUI + Swift Charts (Apple first-party) |
| API | `Chart` view with `BarMark` for breakdown, `ByteCountFormatter` for sizes |
| Availability | Swift Charts: macOS 13+ (within our 14+ target) |
| New dependency | None |
| Confidence | HIGH |

**Why Swift Charts:**

The storage dashboard needs to show a breakdown of storage by content type (images, text, URLs, etc.). Swift Charts provides native, dark-mode-compatible bar charts that match Pastel's visual language without any third-party dependency.

However, Swift Charts may be overkill for a simple storage breakdown. A simpler approach using SwiftUI progress bars could achieve the same goal with less complexity:

**Recommended: Simple progress bar approach**

```swift
struct StorageBarView: View {
    let label: String
    let bytes: UInt64
    let totalBytes: UInt64
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(ByteCountFormatter.string(
                    fromByteCount: Int64(bytes),
                    countStyle: .file
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.3))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(bytes) / CGFloat(max(totalBytes, 1)))
                    }
            }
            .frame(height: 8)
        }
    }
}
```

**ByteCountFormatter:** Use `ByteCountFormatter.string(fromByteCount:countStyle:)` for human-readable sizes ("2.3 MB", "456 KB"). This is available since macOS 10.8. Use `.file` count style for consistency with Finder.

**Dashboard data model:**

```swift
struct StorageStats {
    var totalDiskUsage: UInt64       // Images directory size
    var databaseSize: UInt64          // SwiftData .store file size
    var imageCount: Int
    var imageBytes: UInt64
    var textCount: Int
    var urlCount: Int
    var codeCount: Int
    var colorCount: Int
    var fileRefCount: Int
    var sensitiveCount: Int

    var totalItems: Int {
        imageCount + textCount + urlCount + codeCount + colorCount + fileRefCount
    }
}
```

**Confidence:** HIGH. ByteCountFormatter and SwiftUI progress bars are basic, well-established APIs. Swift Charts is available if a more polished visualization is desired.

---

### 7. Storage Management: Batch Delete + SwiftData Predicates

**Recommendation: SwiftData batch operations with content-type predicates**

| Attribute | Value |
|-----------|-------|
| Framework | SwiftData (already used) |
| API | `FetchDescriptor` with `#Predicate`, `ModelContext.delete()` |
| New dependency | None |
| Confidence | HIGH |

**Purge by category:**

```swift
/// Delete all items of a specific content type
func purgeItems(ofType contentType: ContentType, modelContext: ModelContext) throws {
    let typeRaw = contentType.rawValue
    let descriptor = FetchDescriptor<ClipboardItem>(
        predicate: #Predicate<ClipboardItem> { item in
            item.contentType == typeRaw
        }
    )
    let items = try modelContext.fetch(descriptor)

    // Clean up disk files before database delete
    for item in items {
        ImageStorageService.shared.deleteImage(
            imagePath: item.imagePath,
            thumbnailPath: item.thumbnailPath
        )
        ImageStorageService.shared.deleteImage(
            imagePath: item.urlFaviconPath,
            thumbnailPath: item.urlPreviewImagePath
        )
    }

    for item in items {
        modelContext.delete(item)
    }
    try modelContext.save()
}
```

**Compact database:** SwiftData sits on top of SQLite. The `.store` file can be compacted by calling `VACUUM` on the underlying SQLite database. However, SwiftData does not expose direct SQL access. The pragmatic approach:

1. After bulk deletes, call `modelContext.save()` -- SwiftData/SQLite handles internal page reclamation
2. True VACUUM requires dropping to Core Data's `NSPersistentStoreCoordinator` level, which is fragile with SwiftData
3. **Recommended approach:** Offer a "Compact Database" button that performs a delete-and-recreate migration -- export remaining items, delete the store, re-import. This is heavy-handed but reliable.
4. **Better approach:** Simply rely on SQLite's auto-vacuum behavior (default in WAL mode, which SwiftData uses). After significant deletes, the database file will shrink over time as pages are reused.

**Practical recommendation:** Skip the "Compact Database" button for v1.2 MVP. SQLite with WAL mode (SwiftData's default) handles space reclamation automatically. The real storage wins come from image compression and purge-by-category. Add compaction later only if users report database bloat.

**Confidence:** HIGH. FetchDescriptor with predicates and batch delete are core SwiftData patterns already used in RetentionService and AppState.clearAllHistory.

---

### 8. Sensitive Item Expiry: Extend RetentionService

**Recommendation: Add sensitive-item retention to existing RetentionService**

| Attribute | Value |
|-----------|-------|
| Framework | SwiftData + Foundation Timer (already used) |
| Change | Add a second purge pass in `RetentionService.purgeExpiredItems()` for sensitive items |
| New dependency | None |
| Confidence | HIGH |

**How it works:**

1. User marks an item as sensitive
2. User optionally configures "Sensitive item retention" in Settings (e.g., 1 hour, 1 day, 1 week, same as global)
3. If a shorter retention is configured, `RetentionService` applies it during hourly purge

**Integration with existing RetentionService:**

```swift
func purgeExpiredItems() {
    // Existing: purge items past global retention
    purgeByGlobalRetention()

    // NEW: purge sensitive items past their shorter retention
    purgeSensitiveItems()
}

private func purgeSensitiveItems() {
    let sensitiveRetentionHours = UserDefaults.standard.integer(forKey: "sensitiveRetention")
    guard sensitiveRetentionHours > 0 else { return }  // 0 = use global retention

    guard let cutoff = Calendar.current.date(
        byAdding: .hour, value: -sensitiveRetentionHours, to: .now
    ) else { return }

    let descriptor = FetchDescriptor<ClipboardItem>(
        predicate: #Predicate<ClipboardItem> { item in
            item.isSensitive == true && item.timestamp < cutoff
        }
    )
    // ... fetch and delete (same pattern as global purge)
}
```

**Sensitive retention options:**
- 1 hour
- 6 hours
- 1 day
- 1 week
- Same as global (default)

**Confidence:** HIGH. Extends the existing RetentionService with an additional predicate pass. No new architecture.

---

## Summary: New Dependencies

### Zero New Third-Party Dependencies

Every v1.2 capability uses Apple first-party frameworks already available on macOS 14+:

| Capability | Framework | Already Imported? |
|------------|-----------|-------------------|
| JPEG compression | ImageIO (`CGImageDestination`) | Yes (ImageStorageService) |
| Storage size calculation | Foundation (`FileManager`, `URLResourceValues`) | Yes |
| Content hashing | CryptoKit (`SHA256`) | Yes (ClipboardMonitor) |
| Blur/redaction UI | SwiftUI (`.blur()`) | Yes |
| Sensitive item model | SwiftData (optional field) | Yes |
| Storage dashboard | SwiftUI (progress bars, `ByteCountFormatter`) | Yes |
| Batch delete by type | SwiftData (`FetchDescriptor`, `#Predicate`) | Yes |
| Sensitive expiry | Foundation (`Timer`) + SwiftData | Yes |

**Total new third-party dependencies: 0**

---

## What NOT to Add

| Technology | Why Avoid | Use Instead |
|------------|-----------|-------------|
| HEIC encoding | Paste-back compatibility risk -- not all apps handle HEIC when pasting images | JPEG at quality 0.85 (universal, 5-10x smaller than PNG) |
| WebP encoding | Not natively supported by CGImageDestination; requires third-party library | JPEG (native ImageIO support) |
| SQLite.swift / GRDB | Direct SQL access for VACUUM is fragile with SwiftData | Let SQLite auto-vacuum handle space reclamation |
| Core Data direct access | Bypassing SwiftData to access NSPersistentStoreCoordinator is brittle | SwiftData batch operations |
| `.redacted(reason: .privacy)` | Designed for system redaction (lock screen), produces gray skeleton boxes | `.blur(radius:)` with icon overlay for visual clarity |
| Keychain storage for sensitive items | Over-engineering; items are temporary clipboard data, not credentials | Visual blur + shorter retention |
| Full-disk encryption of images | macOS FileVault already encrypts the disk; additional encryption adds complexity for clipboard data | FileVault + visual blur + auto-expiry |
| Swift Charts | Over-engineering for a simple storage breakdown view | SwiftUI progress bars + ByteCountFormatter |
| vImage framework | Lower-level image processing; CGImageDestination already handles compression | CGImageDestination with quality parameter |
| #Expression aggregate queries | macOS 15+ only, limited support for sum/avg; Pastel targets macOS 14+ | Fetch items + Swift-side sum |

---

## SwiftData Model Changes

### ClipboardItem new fields

```swift
// Storage optimization (v1.2)
var isCompressed: Bool?           // Whether stored image was compressed from PNG to JPEG
var originalByteCount: Int?       // Size before compression (for storage savings display)

// Sensitive item support (v1.2)
var isSensitive: Bool?            // User-marked as sensitive (nil = false)
var sensitiveExpiryDays: Int?     // Per-item retention override (nil = use global)
```

### Migration

All new fields are Optional with nil defaults. SwiftData automatic lightweight migration applies. No VersionedSchema needed.

---

## project.yml Changes

**None.** No new packages, no new dependencies. All v1.2 features use existing frameworks.

```yaml
# project.yml remains unchanged from v1.1
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: "2.4.0"
  LaunchAtLogin:
    url: https://github.com/sindresorhus/LaunchAtLogin-Modern
    from: "1.1.0"

targets:
  Pastel:
    dependencies:
      - package: KeyboardShortcuts
      - package: LaunchAtLogin
```

---

## Integration Points with Existing Code

### Files to Modify

| Existing File | Change Needed | Reason |
|---------------|---------------|--------|
| `Models/ClipboardItem.swift` | Add 4 new Optional fields (`isCompressed`, `originalByteCount`, `isSensitive`, `sensitiveExpiryDays`) | Storage + sensitive support |
| `Services/ImageStorageService.swift` | Add JPEG compression method; add directory size calculation; add bulk PNG-to-JPEG migration | Storage optimization core |
| `Services/RetentionService.swift` | Add `purgeSensitiveItems()` pass in hourly purge | Sensitive item auto-expiry |
| `Services/ClipboardMonitor.swift` | Save images as JPEG; store `originalByteCount` | Compress at capture time |
| `Views/Panel/ClipboardCardView.swift` | Apply `.sensitiveContent()` modifier based on `isSensitive`; add "Mark as Sensitive" context menu | UI integration |
| `Views/Panel/ImageCardView.swift` | Apply blur overlay for sensitive items | Sensitive image display |
| `Views/Panel/TextCardView.swift` | Apply blur overlay for sensitive items | Sensitive text display |
| `Views/Settings/GeneralSettingsView.swift` | Add "Storage" and "Privacy" sections | Settings UI |
| `App/AppState.swift` | Add storage stats computation; add mark-as-sensitive action | Coordination |

### New Files to Create

| File | Purpose | Dependencies |
|------|---------|--------------|
| `Services/StorageService.swift` | Calculate storage stats by type, manage compression migration, purge by category | ImageStorageService, SwiftData |
| `Views/Settings/StorageSettingsView.swift` | Storage dashboard with usage bars, purge buttons, compression stats | StorageService |
| `Views/Panel/SensitiveContentOverlay.swift` | Reusable blur + lock icon overlay with tap-to-reveal | SwiftUI |

---

## UserDefaults Keys (New)

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `sensitiveRetention` | Int | 0 | Sensitive item retention in hours (0 = same as global) |
| `imageCompressionQuality` | Double | 0.85 | JPEG compression quality (0.7 - 1.0) |
| `compressionMigrationComplete` | Bool | false | Whether existing PNG images have been migrated to JPEG |

---

## Confidence Assessment

| Area | Confidence | Reason |
|------|------------|--------|
| JPEG compression via CGImageDestination | HIGH | Already using ImageIO for downscaling; JPEG encoding is basic API |
| Storage size calculation | HIGH | Standard FileManager enumeration pattern |
| Blur/redact UI | HIGH | SwiftUI `.blur()` is first-version API; tested pattern |
| Sensitive item model | HIGH | Same Optional field migration pattern used in v1.1 |
| Storage dashboard | HIGH | ByteCountFormatter + SwiftUI progress bars |
| Batch delete by type | HIGH | Same pattern as existing clearAllHistory |
| Sensitive auto-expiry | HIGH | Extends existing RetentionService with one additional predicate |
| Deduplication upgrade | HIGH | CryptoKit SHA256 already in use |

---

## Verification Checklist (Before Implementation)

- [ ] JPEG quality 0.85: verify visual quality is acceptable for screenshots, photos, diagrams
- [ ] CGImageDestination with UTType.jpeg: verify on macOS 14 (should work, but sanity check)
- [ ] FileManager directory enumeration: verify performance with 1000+ image files
- [ ] `.blur(radius: 10)`: verify blur is sufficient to hide text at card preview sizes
- [ ] SwiftData Optional field migration: verify no data loss with new fields on existing database
- [ ] Sensitive item retention predicate: verify `#Predicate` with Optional Bool comparison works

---

## Sources

- [Apple Documentation: kCGImageDestinationLossyCompressionQuality](https://developer.apple.com/documentation/imageio/kcgimagedestinationlossycompressionquality) -- compression quality API
- [Apple Documentation: UTType.heic](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/heic) -- HEIC type identifier (considered, not recommended)
- [Apple Documentation: URLResourceValues](https://developer.apple.com/documentation/foundation/urlresourcevalues) -- file size properties
- [Apple Documentation: totalFileAllocatedSize](https://developer.apple.com/documentation/foundation/urlresourcevalues/1779751-totalfileallocatedsize) -- allocated size API
- [Apple Documentation: blur(radius:opaque:)](https://developer.apple.com/documentation/swiftui/view/blur(radius:opaque:)) -- SwiftUI blur modifier
- [AllocatedSizeOfDirectory.swift (Nikolai Ruhe)](https://gist.github.com/NikolaiRuhe/408cefb953c4bea15506a3f80a3e5b96) -- directory size calculation pattern
- [heic.swift (wata)](https://gist.github.com/wata/453a4e1673d9758812923d4755b110bd) -- HEIC encoding via CGImageDestination
- [HEIC vs JPEG comparison (Adobe)](https://www.adobe.com/creativecloud/file-types/image/comparison/heic-vs-jpeg.html) -- format comparison
- [HEIC vs JPEG comparison (Cloudinary)](https://cloudinary.com/guides/image-formats/jpeg-vs-heic) -- compression ratios
- [SwiftUI redacted modifier (Swift with Majid)](https://swiftwithmajid.com/2020/10/22/the-magic-of-redacted-modifier-in-swiftui/) -- redaction approaches
- [SwiftUI blur tutorial (Hacking with Swift)](https://www.hackingwithswift.com/quick-start/swiftui/how-to-blur-a-view) -- blur modifier usage
- [SwiftData Expressions (Use Your Loaf)](https://useyourloaf.com/blog/swiftdata-expressions/) -- aggregate query limitations
- [PNG compression comparison (DEV Community)](https://dev.to/junyu_fang_a216509a97501d/top-png-compression-methods-on-macos-compared-are-native-apis-useless-23n7) -- PNG vs JPEG compression
- [macOS file hierarchy size (MacPaw)](https://macpaw.com/news/calculate-macos-file-hierarchy-size) -- directory size best practices
- Pastel codebase -- direct inspection of all 44 source files for integration points

---
*Stack research for: Pastel v1.2 -- Storage & Security*
*Researched: 2026-02-07*
