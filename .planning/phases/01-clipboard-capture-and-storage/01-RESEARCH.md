# Phase 1: Clipboard Capture and Storage - Research

**Researched:** 2026-02-06
**Domain:** macOS clipboard monitoring, SwiftData persistence, menu bar app architecture
**Confidence:** HIGH

## Summary

Phase 1 establishes the invisible foundation of Pastel: a menu bar app that silently captures everything copied to the macOS clipboard, classifies it, deduplicates it, and persists it to disk. This phase has no panel, no paste-back, no organization -- just reliable silent capture with a status popover.

The standard approach is well-established in the macOS clipboard manager ecosystem (Maccy, Clipy, Paste all use identical patterns): poll `NSPasteboard.general.changeCount` on a 0.5-second timer, read all pasteboard types on change, classify by priority (image > URL > file > rich text > plain text), persist metadata to SwiftData with images stored as files on disk. The menu bar presence uses SwiftUI's `MenuBarExtra` with `.window` style for a custom popover.

Key research findings include: (1) macOS 16 will introduce pasteboard privacy prompts that require user permission for programmatic clipboard reading -- this is a critical future concern but does not affect macOS 14-15 targets; (2) `@Attribute(.unique)` works on macOS 14 but `#Index` and `#Unique` macros require macOS 15; (3) `CGImageSourceCreateThumbnailAtIndex` is 40x faster than NSImage resizing for thumbnail generation; (4) rich text should be stored alongside plain text for paste-back fidelity; (5) concealed/transient pasteboard types from password managers must be handled per the nspasteboard.org standard.

**Primary recommendation:** Build a timer-based `ClipboardMonitor` service using `@Observable` that polls every 0.5 seconds, reads all pasteboard types with smart priority classification, persists to SwiftData with images on disk via `CGImageSource` thumbnails, and surfaces state through a `MenuBarExtra(.window)` popover.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 6.0+ | Primary language | Native macOS development; Swift 6 concurrency checking valuable for background work |
| SwiftUI | macOS 14+ | UI framework (popover, settings) | MenuBarExtra for menu bar; @Observable for state |
| AppKit (bridged) | macOS 14+ | NSPasteboard, NSWorkspace, NSImage | Only API for clipboard access; SwiftUI cannot read pasteboard |
| SwiftData | macOS 14+ | Clipboard history persistence | @Model macro, @Query for views, automatic SwiftUI integration |
| ImageIO | macOS 14+ | Thumbnail generation | CGImageSourceCreateThumbnailAtIndex -- 40x faster than NSImage resize |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| KeyboardShortcuts (sindresorhus) | 2.4.0 | Global hotkey registration | Add as dependency now (Phase 3 use); sandboxed, Mac App Store compatible |
| LaunchAtLogin-Modern (sindresorhus) | 1.1.0 | Launch at login | Add as dependency now (Phase 5 use); uses ServiceManagement (macOS 13+) |

### Not Needed Yet (Future Phases)

| Library | Phase | Purpose |
|---------|-------|---------|
| NSPanel + NSHostingView | Phase 2 | Floating clipboard history panel |
| CGEvent | Phase 3 | Paste-back simulation |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftData | Core Data | More boilerplate, no @Model/@Query; fallback if SwiftData has issues |
| SwiftData | GRDB (SQLite) | Full SQL power + FTS5; no SwiftUI integration, more manual work |
| CGImageSource thumbnails | NSImage resize | 40x slower; simpler code but unacceptable for batch processing |
| Timer.scheduledTimer | DispatchSourceTimer | Better energy efficiency with leeway; slightly more complex lifecycle |

**Installation (Swift Package Manager in Xcode):**
```
https://github.com/sindresorhus/KeyboardShortcuts (2.4.0+)
https://github.com/sindresorhus/LaunchAtLogin-Modern (1.1.0+)
```

## Architecture Patterns

### Recommended Project Structure (Phase 1 Only)
```
Pastel/
  PastelApp.swift                    # @main, MenuBarExtra scene, modelContainer
  App/
    AppState.swift                   # @Observable, central state object
  Models/
    ClipboardItem.swift              # SwiftData @Model for clipboard entries
    ContentType.swift                # Enum: text, image, url, file
  Services/
    ClipboardMonitor.swift           # NSPasteboard polling + change detection
    ImageStorageService.swift        # Disk storage, thumbnail generation
    ExpirationService.swift          # Auto-expire concealed items after 60s
  Views/
    MenuBar/
      StatusPopoverView.swift        # Item count, monitoring toggle, quit
  Extensions/
    NSPasteboard+Reading.swift       # Typed pasteboard reading helpers
    NSImage+Thumbnail.swift          # CGImageSource thumbnail wrapper
  Resources/
    Assets.xcassets                  # App icon
    Info.plist                       # LSUIElement=true
    Pastel.entitlements              # App Sandbox (initially enabled)
```

### Pattern 1: Timer-Based Clipboard Polling
**What:** Poll `NSPasteboard.general.changeCount` every 0.5 seconds. When it changes, immediately read all pasteboard types and process the new content.
**When to use:** Always. There is no notification API for clipboard changes on macOS.
**Example:**
```swift
// Source: Maccy (github.com/p0deje/Maccy) + Apple NSPasteboard docs
@Observable
class ClipboardMonitor {
    var isMonitoring = true
    var itemCount = 0

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general

    // Flag to skip self-triggered changes (future paste-back)
    var skipNextChange = false

    func start() {
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func toggleMonitoring() {
        isMonitoring.toggle()
        if isMonitoring { start() } else { stop() }
    }

    private func checkForChanges() {
        guard isMonitoring else { return }
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if skipNextChange {
            skipNextChange = false
            return
        }

        // MUST read pasteboard immediately -- content can change before next poll
        processPasteboardContent()
    }

    private func processPasteboardContent() {
        // Read types, classify, check for concealed, check for duplicate
        // Persist to SwiftData
        // If image: save to disk, generate thumbnail on background queue
    }
}
```

### Pattern 2: Smart Content Type Classification
**What:** Each clipboard change produces ONE item classified by the "best" type. Priority: image > URL > file reference > rich text > plain text. This prevents duplicate entries from a single copy event.
**When to use:** Every time a clipboard change is detected.
**Example:**
```swift
// Source: Maccy clipboard reading patterns + nspasteboard.org type reference
enum ContentType: String, Codable {
    case text
    case richText
    case url
    case image
    case file
}

extension NSPasteboard {
    /// Classify the current pasteboard content by priority.
    /// Returns nil if pasteboard is empty or contains only ignored types.
    func classifyContent() -> ContentType? {
        guard let types = self.types else { return nil }

        // Check for concealed/transient markers first
        let typeStrings = types.map { $0.rawValue }
        let isConcealed = typeStrings.contains("org.nspasteboard.ConcealedType")
        let isTransient = typeStrings.contains("org.nspasteboard.TransientType")
        let isAutoGenerated = typeStrings.contains("org.nspasteboard.AutoGeneratedType")

        // Skip transient and auto-generated entirely
        if isTransient || isAutoGenerated { return nil }

        // Priority classification
        if types.contains(.tiff) || types.contains(.png) {
            return .image
        }
        if types.contains(.fileURL) {
            // Could be file OR URL -- check if it's a web URL
            if let urls = readObjects(forClasses: [NSURL.self]) as? [URL],
               let url = urls.first, url.scheme == "http" || url.scheme == "https" {
                return .url
            }
            return .file
        }
        if types.contains(.URL) {
            return .url
        }
        if types.contains(.string) {
            // Check if the string is actually a URL
            if let str = string(forType: .string),
               let url = URL(string: str),
               url.scheme == "http" || url.scheme == "https" {
                return .url
            }
            // Check for RTF/HTML (rich text)
            if types.contains(.rtf) || types.contains(.html) {
                return .richText
            }
            return .text
        }

        return nil
    }
}
```

### Pattern 3: Source App Detection
**What:** Capture the frontmost application at the time of each clipboard change to record where the copy came from.
**When to use:** On every clipboard change detection.
**Example:**
```swift
// Source: Apple NSWorkspace docs + Maccy source
func captureSourceApp() -> (bundleID: String?, name: String?, icon: NSImage?) {
    guard let app = NSWorkspace.shared.frontmostApplication else {
        return (nil, nil, nil)
    }
    let bundleID = app.bundleIdentifier
    let name = app.localizedName
    let icon = app.icon  // NSImage, 32x32 default
    return (bundleID, name, icon)
}
```
**Note:** The frontmost app at poll time is a best-effort approximation. If the user copies and then switches apps within the 0.5s interval, the wrong source app may be recorded. This is acceptable -- all clipboard managers have this limitation.

### Pattern 4: SwiftData Model with @Observable Integration
**What:** Use `@Observable` for the app state object and SwiftData `@Model` for persistence. The app state owns the `ModelContainer` and services reference it.
**When to use:** For the entire data layer.
**Example:**
```swift
// Source: Apple SwiftData docs, Hacking with Swift SwiftData tutorials
@main
struct PastelApp: App {
    var body: some Scene {
        MenuBarExtra("Pastel", systemImage: "clipboard") {
            StatusPopoverView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

### Pattern 5: Concealed Item Auto-Expiration
**What:** Items from password managers (marked with `org.nspasteboard.ConcealedType`) are captured but automatically deleted after 60 seconds.
**When to use:** When a clipboard change contains the concealed type marker.
**Example:**
```swift
// Source: nspasteboard.org specification
func scheduleExpiration(for item: ClipboardItem) {
    guard item.isConcealed else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
        self?.deleteItem(item)
    }
}
```

### Anti-Patterns to Avoid
- **Reading pasteboard on a background thread:** NSPasteboard is NOT thread-safe. Always read on main thread; dispatch heavy processing (image save, thumbnail gen) to background.
- **Storing NSImage/image data in SwiftData:** Database bloats. Store file paths only.
- **Comparing only changeCount without reading immediately:** Content can be replaced before next poll cycle. Read content in the SAME callback that detects the change.
- **Creating a new ClipboardItem for every pasteboard type:** One copy event = one item. Multiple types are representations of the same content.
- **Polling faster than 0.5s:** Wastes CPU with no UX benefit. 0.5s is the community-proven sweet spot.
- **Polling slower than 1.0s:** Users copy and then copy again within 1s; the first copy gets missed.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Thumbnail generation | Custom NSImage resize logic | `CGImageSourceCreateThumbnailAtIndex` (ImageIO) | 40x faster, handles EXIF orientation, memory-efficient (no full decode) |
| Global keyboard shortcuts | Raw Carbon RegisterEventHotKey | KeyboardShortcuts (sindresorhus) 2.4.0 | SwiftUI recorder view, sandboxed, battle-tested, saves weeks |
| Launch at login | SMAppService.register() manual | LaunchAtLogin-Modern (sindresorhus) 1.1.0 | Handles all edge cases, SwiftUI Toggle included |
| Clipboard type detection | Manual UTI string comparison | NSPasteboard `types` array + `readObjects(forClasses:)` | Apple's type coercion handles format conversion automatically |
| Content deduplication | Custom hash computation | Compare `string(forType: .string)` with previous item's content | Simple equality check sufficient for consecutive dedup |
| App icon retrieval | Manual icon file parsing | `NSRunningApplication.icon` or `NSWorkspace.shared.icon(forFile:)` | System API handles all icon resolution, caching |

**Key insight:** macOS clipboard monitoring has exactly one approach (polling changeCount). Don't try to find a notification-based alternative -- it does not exist in the public API.

## Common Pitfalls

### Pitfall 1: Self-Paste Loop (CRITICAL for Phase 2+, design for it now)
**What goes wrong:** When paste-back writes to the pasteboard, ClipboardMonitor detects it as a "new" clipboard change and creates a duplicate entry.
**Why it happens:** The app writes to NSPasteboard.general for paste-back; the polling timer sees a changeCount increment.
**How to avoid:** Add a `skipNextChange` flag to ClipboardMonitor. Set it before writing to pasteboard. The next detected change resets the flag and skips processing.
**Warning signs:** Duplicate entries appearing after every paste operation.

### Pitfall 2: NSPasteboard Thread Safety
**What goes wrong:** Reading pasteboard types on a background thread causes random crashes or stale data.
**Why it happens:** NSPasteboard is not thread-safe. Multiple threads reading/writing simultaneously corrupts internal state.
**How to avoid:** ALWAYS read pasteboard on the main thread. After reading, dispatch image processing and disk I/O to a background queue.
**Warning signs:** EXC_BAD_ACCESS crashes in NSPasteboard methods; intermittent "wrong content" captures.

### Pitfall 3: Missing Pasteboard Types
**What goes wrong:** Only reading `.string` type misses images, file URLs, RTF, HTML, and other representations.
**Why it happens:** Developers test with plain text and assume that covers everything.
**How to avoid:** Read ALL relevant types on each capture: `.tiff`, `.png`, `.fileURL`, `.URL`, `.rtf`, `.html`, `.string`. Use the priority classification pattern to pick the "best" type.
**Warning signs:** User copies an image but nothing appears in history; copied file references are stored as plain text file paths.

### Pitfall 4: Concealed Type Not Respected
**What goes wrong:** Passwords from 1Password, Bitwarden, etc. are permanently stored in clipboard history as searchable plain text.
**Why it happens:** Developer doesn't check for `org.nspasteboard.ConcealedType` marker.
**How to avoid:** Check pasteboard types for concealed/transient markers on every capture. For concealed: capture but auto-expire after 60 seconds. For transient: skip entirely. For auto-generated: skip entirely.
**Warning signs:** Passwords visible in clipboard history indefinitely; security-conscious users avoid the app.

### Pitfall 5: SwiftData Background Insert Not Updating @Query
**What goes wrong:** ClipboardMonitor inserts items via a background `ModelActor`, but the SwiftUI view's `@Query` does not refresh.
**Why it happens:** SwiftData had bugs where background context inserts didn't notify the main context. Fixed in Xcode 15 beta 7, but edge cases may remain.
**How to avoid:** For Phase 1 (simple use case), insert on the main thread `ModelContext` directly since pasteboard reading already happens on the main thread. Only use `@ModelActor` for heavy background operations (e.g., batch image processing). If background inserts are needed, pass `PersistentModelID` across actor boundaries, not model objects.
**Warning signs:** New items don't appear in the status popover count until app restart.

### Pitfall 6: Image Storage Unbounded Growth
**What goes wrong:** Users who copy many screenshots fill disk without bound.
**Why it happens:** No retention policy or disk budget implemented.
**How to avoid:** Track total image storage size. Implement a default disk budget (e.g., 1GB). When exceeded, delete oldest images first (keep metadata entry but mark image as "expired"). Build this into Phase 1 storage service.
**Warning signs:** `~/Library/Application Support/Pastel/images/` grows to multi-GB within weeks of use.

### Pitfall 7: App Sandbox vs Clipboard Monitoring
**What goes wrong:** NSPasteboard reading works fine in sandbox (it's a system service). But CGEvent paste-back (Phase 3) does NOT work in sandbox. The user decided to "start with sandbox, test CGEvent limitation ourselves."
**Why it happens:** App Sandbox blocks Accessibility API access needed for CGEvent posting.
**How to avoid:** Phase 1 clipboard MONITORING works in sandbox -- no issue. Phase 3 paste-back will require removing sandbox. Design accordingly: clipboard monitoring and storage code should not depend on sandbox entitlements.
**Warning signs:** Everything works in Phase 1. The problem surfaces in Phase 3 when CGEvent paste is silently ignored.

### Pitfall 8: macOS 16 Pasteboard Privacy (FUTURE -- plan awareness)
**What goes wrong:** macOS 16 (Tahoe) will prompt users when apps programmatically read the pasteboard without user interaction. Clipboard managers that poll NSPasteboard will trigger repeated alerts.
**Why it happens:** Apple is adding clipboard privacy protection similar to iOS, announced in macOS 15.4 developer preview.
**How to avoid:** This does NOT affect macOS 14-15 targets today. But be aware: (1) New `detect` methods let apps check pasteboard types without triggering alerts. (2) `accessBehavior` property indicates per-app permission state. (3) Users can grant "Always Allow" in System Settings > Privacy & Security > Paste from Other Apps. (4) Test with `defaults write app.pastel.Pastel EnablePasteboardPrivacyDeveloperPreview -bool yes` to simulate.
**Warning signs:** On macOS 16, users see constant permission prompts. The app becomes unusable without granting "Always Allow."

## Code Examples

### SwiftData Model for Clipboard Items
```swift
// Source: Apple SwiftData documentation + WWDC23 "Meet SwiftData"
import SwiftData
import Foundation

@Model
class ClipboardItem {
    // Core content
    var textContent: String?          // Plain text, URL string, or file path
    var htmlContent: String?          // HTML representation (if captured)
    var rtfData: Data?                // RTF data (if captured)
    var contentType: String           // "text", "richText", "url", "image", "file"

    // Metadata
    var timestamp: Date
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var characterCount: Int
    var byteCount: Int
    var changeCount: Int              // NSPasteboard changeCount at capture time

    // Image references (paths relative to app support dir)
    var imagePath: String?            // Full image file name (UUID.png)
    var thumbnailPath: String?        // Thumbnail file name (UUID_thumb.png)

    // Special handling
    var isConcealed: Bool             // From password manager
    var expiresAt: Date?              // Auto-expiry time for concealed items

    // Deduplication
    @Attribute(.unique) var contentHash: String  // Hash for dedup

    init(
        textContent: String? = nil,
        htmlContent: String? = nil,
        rtfData: Data? = nil,
        contentType: String,
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
        self.contentType = contentType
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
    }
}
```

### Thumbnail Generation with CGImageSource
```swift
// Source: Apple ImageIO docs + macguru.dev/fast-thumbnails-with-cgimagesource
import ImageIO
import AppKit

extension NSImage {
    /// Generate a thumbnail using CGImageSource (40x faster than NSImage resize).
    /// maxPixelSize is the largest dimension of the output.
    static func thumbnail(from imageData: Data, maxPixelSize: Int = 200) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
```

### Image Storage Service
```swift
// Source: Apple FileManager docs + established clipboard manager patterns
import Foundation
import AppKit

class ImageStorageService {
    static let shared = ImageStorageService()

    private let fileManager = FileManager.default
    private let imagesDir: URL
    private let backgroundQueue = DispatchQueue(label: "app.pastel.imageStorage", qos: .utility)

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        imagesDir = appSupport.appendingPathComponent("Pastel/images", isDirectory: true)
        try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    /// Save image from pasteboard data. Returns (imagePath, thumbnailPath) filenames.
    func saveImage(data: Data, completion: @escaping (String?, String?) -> Void) {
        backgroundQueue.async { [self] in
            let uuid = UUID().uuidString
            let imageFileName = "\(uuid).png"
            let thumbFileName = "\(uuid)_thumb.png"

            // Downscale if larger than 4K (3840px)
            let processedData = downscaleIfNeeded(data: data, maxPixelSize: 3840)

            // Save full image
            let imageURL = imagesDir.appendingPathComponent(imageFileName)
            try? processedData.write(to: imageURL)

            // Generate and save thumbnail
            if let thumbImage = NSImage.thumbnail(from: processedData, maxPixelSize: 200),
               let thumbData = thumbImage.tiffRepresentation,
               let thumbBitmap = NSBitmapImageRep(data: thumbData),
               let pngData = thumbBitmap.representation(using: .png, properties: [:]) {
                let thumbURL = imagesDir.appendingPathComponent(thumbFileName)
                try? pngData.write(to: thumbURL)
            }

            DispatchQueue.main.async {
                completion(imageFileName, thumbFileName)
            }
        }
    }

    private func downscaleIfNeeded(data: Data, maxPixelSize: Int) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return data }

        if max(width, height) <= maxPixelSize { return data }

        // Use CGImageSource to create a downscaled version
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return data
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:]) ?? data
    }

    /// Delete image files for an item (call from background)
    func deleteImage(imagePath: String?, thumbnailPath: String?) {
        backgroundQueue.async { [self] in
            if let p = imagePath {
                try? fileManager.removeItem(at: imagesDir.appendingPathComponent(p))
            }
            if let p = thumbnailPath {
                try? fileManager.removeItem(at: imagesDir.appendingPathComponent(p))
            }
        }
    }
}
```

### MenuBarExtra with Status Popover
```swift
// Source: Apple MenuBarExtra docs + nilcoalescing.com menu bar tutorial
import SwiftUI

@main
struct PastelApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            StatusPopoverView()
                .environment(appState)
                .frame(width: 260, height: 160)
        } label: {
            Image(systemName: "clipboard")  // SF Symbol for menu bar
        }
        .menuBarExtraStyle(.window)
    }
}

struct StatusPopoverView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clipboard.fill")
                    .font(.title2)
                Text("Pastel")
                    .font(.headline)
                Spacer()
            }

            Divider()

            Text("\(appState.itemCount) items captured")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle("Monitoring", isOn: Binding(
                get: { appState.clipboardMonitor.isMonitoring },
                set: { _ in appState.clipboardMonitor.toggleMonitoring() }
            ))

            Divider()

            Button("Quit Pastel") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
    }
}
```

### Consecutive Duplicate Detection
```swift
// Source: Common clipboard manager pattern
import CryptoKit

func computeContentHash(text: String?, imageData: Data?, fileURL: URL?) -> String {
    var hasher = SHA256()
    if let text = text {
        hasher.update(data: Data(text.utf8))
    }
    if let data = imageData {
        // Hash first 4KB for speed -- full hash is too slow for large images
        hasher.update(data: data.prefix(4096))
    }
    if let url = fileURL {
        hasher.update(data: Data(url.absoluteString.utf8))
    }
    let digest = hasher.finalize()
    return digest.map { String(format: "%02x", $0) }.joined()
}

// In ClipboardMonitor:
func isDuplicate(hash: String, context: ModelContext) -> Bool {
    // Check only against the most recent item (consecutive dedup)
    var descriptor = FetchDescriptor<ClipboardItem>(
        sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
    )
    descriptor.fetchLimit = 1

    guard let lastItem = try? context.fetch(descriptor).first else {
        return false
    }
    return lastItem.contentHash == hash
}
```

### Concealed/Transient Type Detection
```swift
// Source: nspasteboard.org specification
extension NSPasteboard.PasteboardType {
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let autoGenerated = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")

    // Legacy identifiers from specific apps
    static let onePassword = NSPasteboard.PasteboardType("com.agilebits.onepassword")
    static let transientLegacy = NSPasteboard.PasteboardType("de.petermaurer.TransientPasteboardType")
}

func checkSpecialTypes() -> (isConcealed: Bool, isTransient: Bool, isAutoGenerated: Bool) {
    let types = NSPasteboard.general.types ?? []
    let typeStrings = Set(types.map { $0.rawValue })

    let isConcealed = typeStrings.contains("org.nspasteboard.ConcealedType")
        || typeStrings.contains("com.agilebits.onepassword")
    let isTransient = typeStrings.contains("org.nspasteboard.TransientType")
        || typeStrings.contains("de.petermaurer.TransientPasteboardType")
        || typeStrings.contains("com.typeit4me.clipping")
        || typeStrings.contains("Pasteboard generator type")
    let isAutoGenerated = typeStrings.contains("org.nspasteboard.AutoGeneratedType")

    return (isConcealed, isTransient, isAutoGenerated)
}
```

## Discretionary Decisions (Claude's Discretion Areas)

### 1. Rich Text Storage Strategy: Store BOTH plain text and RTF/HTML

**Recommendation:** Store both plain text AND rich text representations.

**Rationale:**
- When paste-back is implemented (Phase 3), users expect formatting to be preserved when pasting into rich text editors (Pages, Mail, Notes)
- Clipbook, Pastebot, and other established clipboard managers store multiple representations
- Storage cost is minimal: RTF/HTML is typically 2-10x the plain text size, but still kilobytes
- The `htmlContent: String?` and `rtfData: Data?` fields in the model are optional -- only populated when the source app provides them

**Implementation:** Store `textContent` (always), `htmlContent` (when `.html` type present), `rtfData` (when `.rtf` type present). On paste-back, write all stored representations to the pasteboard so the target app can choose the best one.

### 2. SF Symbol Choice: `clipboard` (or `clipboard.fill` for filled variant)

**Recommendation:** Use `clipboard` as the menu bar icon.

**Rationale:**
- Clean, recognizable, directly communicates clipboard function
- `doc.on.clipboard` is more detailed but reads poorly at 16px menu bar size
- `list.clipboard` and `list.clipboard.fill` are also options but less distinctive
- Use `clipboard.fill` as the "active/capturing" state variant

### 3. Polling Timer: Use `Timer.scheduledTimer` for Phase 1

**Recommendation:** Start with `Timer.scheduledTimer` with a `tolerance` property set.

**Rationale:**
- Simpler lifecycle management (invalidate on deinit)
- `DispatchSourceTimer` has tricky deallocation behavior that causes crashes if not handled correctly
- Setting `timer.tolerance = 0.1` (100ms) enables system timer coalescing for energy efficiency -- this is equivalent to the leeway benefit of DispatchSourceTimer
- Can migrate to DispatchSourceTimer later if needed (unlikely for 0.5s interval)

```swift
let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { ... }
timer.tolerance = 0.1  // Allow 100ms leeway for energy coalescing
```

### 4. Background Queue Strategy for Image Processing

**Recommendation:** Single dedicated serial queue at `.utility` QoS.

**Rationale:**
- Serial queue prevents concurrent writes to the same image directory
- `.utility` QoS is appropriate for user-initiated but not urgent work
- Image saves and thumbnail generation happen on this queue
- SwiftData inserts happen on the main thread (where pasteboard was read)

```swift
private let imageQueue = DispatchQueue(label: "app.pastel.imageProcessing", qos: .utility)
```

### 5. Popover Layout and Styling

**Recommendation:** Minimal status popover (260x160pt) with vibrancy.

**Rationale:**
- This is NOT the clipboard history panel (that's Phase 2)
- Show only: item count, monitoring toggle, quit button
- Match system popover styling (`.background` material for vibrancy)
- No recent items -- the user decided "that's the panel's job"

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Core Data + NSManagedObject | SwiftData @Model macro | WWDC 2023 (macOS 14) | Eliminates boilerplate, native SwiftUI integration |
| ObservableObject + @Published | @Observable macro | WWDC 2023 (macOS 14) | Simpler, no Combine, finer-grained updates |
| NSImage.resize() for thumbnails | CGImageSourceCreateThumbnailAtIndex | Available since macOS 10.4, but recently promoted | 40x performance improvement |
| NSStatusItem manual setup | MenuBarExtra scene | WWDC 2022 (macOS 13) | Declarative SwiftUI menu bar |
| @Attribute(.unique) per-property | #Unique macro (compound) | WWDC 2024 (macOS 15) | Compound uniqueness; NOT available on macOS 14 target |
| Manual FetchDescriptor sorting | #Index macro | WWDC 2024 (macOS 15) | Query optimization; NOT available on macOS 14 target |

**Deprecated/outdated:**
- `ObservableObject` + `@Published`: Still works but `@Observable` is preferred on macOS 14+
- `#Unique` and `#Index` macros: Require macOS 15; use `@Attribute(.unique)` on macOS 14
- `LSSharedFileListInsertItemURL`: Deprecated; use `SMAppService.register()` via LaunchAtLogin-Modern

**macOS 16 Pasteboard Privacy (upcoming):**
- macOS 16 will prompt users when apps read the pasteboard programmatically
- New APIs: `detect` methods, `accessBehavior` property
- Preview available in macOS 15.4 via developer defaults
- Clipboard managers will need "Always Allow" permission from users

## Open Questions

1. **App Sandbox + NSPasteboard reading behavior**
   - What we know: NSPasteboard reading works in sandbox (it's a system pasteboard). CGEvent paste does NOT work in sandbox.
   - What's unclear: Whether macOS 16 pasteboard privacy prompts behave differently for sandboxed vs non-sandboxed apps.
   - Recommendation: Start with sandbox as decided. Test clipboard monitoring. Document findings for Phase 3 sandbox removal decision.

2. **SwiftData autosave timing**
   - What we know: SwiftData batches saves automatically. "SwiftData quietly groups multiple changes together to save in one pass."
   - What's unclear: Exact timing of autosave. If the app crashes between a clipboard capture and the autosave, the item is lost.
   - Recommendation: Call `modelContext.save()` explicitly after each clipboard item insert to guarantee persistence. This is a clipboard manager -- data loss is unacceptable.

3. **NSRunningApplication.icon memory**
   - What we know: `NSRunningApplication.icon` returns an NSImage.
   - What's unclear: Whether storing this icon (or its data) for every clipboard item is appropriate. Could consume significant memory/disk for thousands of items.
   - Recommendation: Store only `sourceAppBundleID` and `sourceAppName` in the model. Resolve icons on-demand at display time using `NSWorkspace.shared.icon(forFile:)` with the bundle path. Cache icons in memory keyed by bundleID.

4. **Timer behavior during system sleep**
   - What we know: Timers may fire irregularly or not at all during system sleep.
   - What's unclear: Whether missed clipboard changes during sleep could cause issues on wake.
   - Recommendation: On wake from sleep (observe `NSWorkspace.willSleepNotification` / `didWakeNotification`), re-read the current `changeCount` and process if it changed during sleep.

## Sources

### Primary (HIGH confidence)
- [Apple NSPasteboard Documentation](https://developer.apple.com/documentation/appkit/nspasteboard) -- pasteboard API, types, changeCount
- [Apple SwiftData Documentation](https://developer.apple.com/documentation/swiftdata) -- @Model, @Query, ModelContainer
- [Apple MenuBarExtra Documentation](https://developer.apple.com/documentation/swiftui/menubarextra) -- menu bar app scene
- [Apple CGImageSourceCreateThumbnailAtIndex](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)) -- fast thumbnail generation
- [nspasteboard.org](https://nspasteboard.org/) -- ConcealedType, TransientType, AutoGeneratedType specifications
- [Maccy Clipboard.swift](https://github.com/p0deje/Maccy/blob/master/Maccy/Clipboard.swift) -- open-source clipboard monitoring implementation
- [KeyboardShortcuts 2.4.0](https://github.com/sindresorhus/KeyboardShortcuts) -- verified current version, SPM URL, sandbox compatibility
- [LaunchAtLogin-Modern 1.1.0](https://github.com/sindresorhus/LaunchAtLogin-Modern) -- verified current version, macOS 13+ requirement

### Secondary (MEDIUM confidence)
- [Hacking with Swift SwiftData tutorials](https://www.hackingwithswift.com/quick-start/swiftdata) -- @Model patterns, relationships
- [Use Your Loaf SwiftData background tasks](https://useyourloaf.com/blog/swiftdata-background-tasks/) -- @ModelActor patterns
- [Michael Tsai Blog - Pasteboard Privacy](https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4/) -- macOS 16 clipboard privacy details
- [Nilcoalescing menu bar tutorial](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) -- MenuBarExtra .window style
- [Apple Energy Efficiency Guide - Timer Usage](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html) -- Timer tolerance/coalescing

### Tertiary (LOW confidence)
- macOS 16 pasteboard privacy enforcement timeline -- unclear whether enforcement is in macOS 16.0 or later; test with developer preview
- SwiftData @Attribute(.unique) crash reports on iOS 17.0 -- some reports of crashes with unique constraints in early SwiftData; likely fixed in macOS 14.2+, but should be tested

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Apple first-party frameworks (AppKit, SwiftUI, SwiftData, ImageIO) are stable and well-documented. Third-party library versions verified via GitHub.
- Architecture: HIGH -- Clipboard polling via changeCount is the universal pattern. Verified against Maccy source code and Apple docs.
- Pitfalls: HIGH -- Based on Maccy/Clipy patterns, nspasteboard.org specification, and Apple developer forums. macOS 16 privacy concern is MEDIUM (timeline uncertain).
- SwiftData schema: MEDIUM -- @Attribute(.unique) has known edge cases on early macOS 14. #Index not available on macOS 14 target.
- Discretionary decisions: MEDIUM -- Rich text storage and timer choice based on ecosystem analysis and tradeoff reasoning.

**Research date:** 2026-02-06
**Valid until:** 2026-03-08 (30 days -- stable domain, but monitor macOS 16 pasteboard privacy developments)
