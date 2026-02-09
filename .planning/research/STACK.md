# Stack Research: v1.3 Power User Features

**Domain:** Native macOS Clipboard Manager -- Paste-as-Plain-Text, App Filtering, Import/Export, Drag-and-Drop
**Project:** Pastel
**Researched:** 2026-02-09
**Confidence:** HIGH

> **Scope:** This document covers ONLY the stack additions needed for v1.3. The existing v1.0/v1.1/v1.2 stack is validated and unchanged. All recommendations use Apple first-party frameworks -- zero new third-party dependencies for this milestone.

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
| CGEvent (CoreGraphics) | macOS 14+ | Paste simulation via Cmd+V | Validated |
| Carbon (RegisterEventHotKey) | macOS 14+ | Global hotkey registration | Validated |
| XcodeGen (project.yml) | -- | Project generation | Validated |

---

## Feature-by-Feature Stack Analysis

### Feature 1: Paste as Plain Text (Context Menu + Shift Interactions)

**What exists:** PasteService already has `pastePlainText()` and `writeToPasteboardPlainText()` methods. Cmd+Shift+1-9 plain text paste is wired. PanelActions has `pastePlainTextItem` callback. The `isShiftHeld` state is tracked via `NSEvent.addLocalMonitorForEvents(matching: .flagsChanged)` in PanelContentView.

**What's needed for v1.3:** Context menu entry for "Paste as Plain Text", Shift+Enter to paste as plain text, and Shift+double-click to paste as plain text.

#### API: No new frameworks required

| Requirement | API | Already Available |
|-------------|-----|-------------------|
| Context menu "Paste as Plain Text" | SwiftUI `.contextMenu { Button {} }` | YES -- add to ClipboardCardView's context menu |
| Shift+Enter plain text paste | SwiftUI `.onKeyPress(.return)` with modifier check | YES -- `keyPress.modifiers.contains(.shift)` |
| Shift+double-click | SwiftUI `.onTapGesture(count: 2)` + `NSEvent.modifierFlags` | PARTIAL -- see below |
| Track Shift key state | `NSEvent.addLocalMonitorForEvents(matching: .flagsChanged)` | YES -- already in PanelContentView |

**Shift+double-click challenge:** SwiftUI's `.onTapGesture(count: 2)` closure does not receive the event or modifier flags. Two approaches:

1. **Use existing `isShiftHeld` state (RECOMMENDED):** The panel already tracks Shift key state via `NSEvent.addLocalMonitorForEvents(matching: .flagsChanged)`. The double-click handler can check this existing boolean to decide between normal paste and plain text paste. This is the simplest approach with zero new API surface.

2. **Check `NSEvent.modifierFlags.current`:** At the moment the closure fires, read `NSEvent.modifierFlags.current.contains(.shift)`. This is a static property check, not an event-based check, but is reliable for modifier keys that are held down.

**Recommendation:** Use approach 1 (existing `isShiftHeld` state). It is already threaded through FilteredCardListView to ClipboardCardView and is reactive. The double-click handler in FilteredCardListView can simply branch: `isShiftHeld ? onPastePlainText(item) : onPaste(item)`.

**Confidence:** HIGH -- all APIs already in use, just wiring changes.

---

### Feature 2: App Allow/Ignore Lists

**What exists:** ClipboardMonitor already reads `sourceAppBundleID` and `sourceAppName` from `NSWorkspace.shared.frontmostApplication` at capture time. The `checkForChanges()` method has a guard for `isMonitoring` but no per-app filtering.

**What's needed for v1.3:** Allow-list or ignore-list of apps by bundle identifier, stored in UserDefaults or SwiftData. ClipboardMonitor skips capture when the frontmost app is in the ignore list (or not in the allow list).

#### API: NSWorkspace + NSRunningApplication (Already Imported)

| Requirement | API | New? |
|-------------|-----|------|
| Get frontmost app at capture time | `NSWorkspace.shared.frontmostApplication` | NO -- already used |
| Get bundle ID for filtering | `NSRunningApplication.bundleIdentifier` | NO -- already used |
| Get app display name | `NSRunningApplication.localizedName` | NO -- already used |
| Get app icon for settings UI | `NSWorkspace.shared.icon(forFile:)` or `NSRunningApplication.icon` | NO -- `NSRunningApplication.icon` is available |
| Discover installed apps | See analysis below | NEW |
| Persist allow/ignore list | `@AppStorage` / `UserDefaults` (array of bundle IDs) | NO -- pattern already used |

#### Discovering Apps for the Settings Picker

Users need to select apps for the allow/ignore list. Three approaches:

**Option A: NSWorkspace.shared.runningApplications (RECOMMENDED for v1.3)**

```swift
let apps = NSWorkspace.shared.runningApplications
    .filter { $0.activationPolicy == .regular }  // Only user-facing apps
    .compactMap { ($0.bundleIdentifier, $0.localizedName, $0.icon) }
```

| Pros | Cons |
|------|------|
| Simple, reliable API | Only shows currently running apps |
| Returns icons, names, bundle IDs | User must run the app first |
| No sandbox or entitlement issues | -- |
| Already imported (AppKit) | -- |

**Option B: Scan /Applications directory**

```swift
let appURLs = FileManager.default.contentsOfDirectory(
    at: URL(fileURLWithPath: "/Applications"),
    includingPropertiesForKeys: nil
).filter { $0.pathExtension == "app" }
// Then use NSWorkspace.shared.urlForApplication(withBundleIdentifier:) or Bundle(url:)
```

| Pros | Cons |
|------|------|
| Shows all installed apps | Requires directory scanning |
| Works even if apps aren't running | Must parse bundle info manually |
| Includes /Applications subdirectories | Misses apps outside /Applications |

**Option C: Combine both (running apps first, then /Applications scan)**

Show currently running apps at the top of the picker for quick access, with a "Browse Applications..." option that scans /Applications.

**Recommendation:** Start with Option A (running apps only) for simplicity. The most common use case is ignoring an app the user just noticed was being captured. A "Browse Applications..." button that opens an NSOpenPanel filtered to `.app` bundles provides escape hatch for non-running apps. This avoids scanning the filesystem on settings open.

#### Data Model for App Lists

**Recommendation: UserDefaults with String arrays (not SwiftData)**

```swift
// Simple storage -- no model needed
@AppStorage("appFilterMode") var filterMode: String = "disabled"  // "disabled", "allowlist", "ignorelist"
// Store as JSON-encoded [String] in UserDefaults
UserDefaults.standard.set(["com.apple.finder", "com.1password.1password"], forKey: "filteredAppBundleIDs")
```

Rationale: App lists are small (typically 5-20 entries), don't need relationships or querying, and must be readable from ClipboardMonitor without a SwiftData fetch. UserDefaults is the right tool.

**Filter check in ClipboardMonitor.checkForChanges():**

```swift
// After isMonitoring guard, before processPasteboardContent()
let sourceBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
let filterMode = UserDefaults.standard.string(forKey: "appFilterMode") ?? "disabled"
let filteredIDs = UserDefaults.standard.stringArray(forKey: "filteredAppBundleIDs") ?? []

switch filterMode {
case "ignorelist":
    if let id = sourceBundle, filteredIDs.contains(id) { return }
case "allowlist":
    if let id = sourceBundle, !filteredIDs.contains(id) { return }
default: break  // disabled -- capture everything
}
```

**Confidence:** HIGH -- all APIs are stable AppKit, already imported. UserDefaults pattern is established.

---

### Feature 3: Import/Export

**What exists:** SwiftData stores ClipboardItem and Label models. ImageStorageService manages disk images. No Codable conformance on models currently.

**What's needed for v1.3:** Export clipboard history to a custom file format (`.pastel` or `.pastelarchive`). Import from the same format. The format should be extensible.

#### Core Frameworks

| Framework | Purpose | New? |
|-----------|---------|------|
| Foundation (JSONEncoder/Decoder) | Serialize clipboard items to JSON | NO |
| Foundation (FileManager) | Read/write files | NO |
| UniformTypeIdentifiers (UTType) | Declare custom `.pastel` file type | NEW import |
| SwiftUI (.fileExporter / .fileImporter) | Native save/open panels | NO -- modifiers available |
| Compression (Apple Compression) | Optional: compress large exports | NEW import (optional) |

#### Custom UTType Declaration

**Recommendation: Declare `app.pastel.archive` UTType conforming to `public.data`**

```swift
import UniformTypeIdentifiers

extension UTType {
    static let pastelArchive = UTType(exportedAs: "app.pastel.archive")
}
```

Requires Info.plist entry under `UTExportedTypeDeclarations`:

```xml
<dict>
    <key>UTTypeConformsTo</key>
    <array>
        <string>public.data</string>
    </array>
    <key>UTTypeDescription</key>
    <string>Pastel Clipboard Archive</string>
    <key>UTTypeIdentifier</key>
    <string>app.pastel.archive</string>
    <key>UTTypeTagSpecification</key>
    <dict>
        <key>public.filename-extension</key>
        <array>
            <string>pastel</string>
        </array>
    </dict>
</dict>
```

#### Export Format Design

**Recommendation: JSON manifest + embedded images in a directory bundle (or flat zip)**

Two options:

**Option A: Directory bundle (`.pastel` directory)**

```
export.pastel/
  manifest.json          # Array of serialized ClipboardItems
  labels.json            # Array of serialized Labels
  images/                # Referenced image files
    {uuid}.png
    {uuid}_thumb.png
    {uuid}_favicon.png
```

| Pros | Cons |
|------|------|
| Simple to implement with FileManager | macOS shows as folder in Finder |
| Easy to debug (can inspect contents) | User might accidentally modify contents |
| No compression library needed | Larger file size |

**Option B: Single-file archive (`.pastel` as zip/data)**

Serialize JSON + images into a single `Data` blob using a simple container format, or leverage `NSFileWrapper` which natively supports directory bundles as single-file packages.

| Pros | Cons |
|------|------|
| Single file, cleaner UX | More complex serialization |
| Can be compressed | Harder to debug |
| Feels like a "real" file format | -- |

**Recommendation: Option A (directory bundle) for v1.3.** It is simpler to implement, easier to debug, and macOS can register it as a package type in Info.plist (adding `com.apple.package` to `UTTypeConformsTo`) so Finder treats the directory as a single file. This gives the clean UX of a single file with the simplicity of directory I/O.

#### Codable Conformance for SwiftData Models

**Requirement:** ClipboardItem and Label need manual Codable conformance for JSON serialization. SwiftData @Model classes do not auto-conform to Codable.

```swift
extension ClipboardItem: Codable {
    enum CodingKeys: String, CodingKey {
        case textContent, htmlContent, rtfData, contentType, timestamp
        case sourceAppBundleID, sourceAppName, characterCount, byteCount
        case imagePath, thumbnailPath, isConcealed, contentHash
        case title, detectedLanguage, detectedColorHex
        case urlTitle, urlFaviconPath, urlPreviewImagePath
        // NOTE: Skip `labels` relationship, `changeCount`, `expiresAt`
        // Labels serialized separately with cross-references
    }

    // Manual init(from:) and encode(to:) required
}
```

**Key decisions:**

| Decision | Rationale |
|----------|-----------|
| Skip `changeCount` | Meaningless outside the originating system |
| Skip `expiresAt` | Concealed items should not be exported |
| Skip concealed items entirely | Security -- never export password manager entries |
| Export labels separately | Avoid circular references, enable label-only import |
| Store image paths as relative | Images stored alongside JSON in bundle |
| Include format version | `"formatVersion": 1` for future extensibility |

#### File Import/Export UI

**Recommendation: SwiftUI `.fileExporter()` and `.fileImporter()` modifiers**

```swift
.fileExporter(
    isPresented: $showingExport,
    document: PastelExportDocument(items: items, labels: labels),
    contentType: .pastelArchive,
    defaultFilename: "Pastel Export \(dateString)"
) { result in ... }

.fileImporter(
    isPresented: $showingImport,
    allowedContentTypes: [.pastelArchive],
    allowsMultipleSelection: false
) { result in ... }
```

The `PastelExportDocument` type must conform to `FileDocument` protocol (for `.fileExporter`) or `ReferenceFileDocument`. For directory bundles with images, `ReferenceFileDocument` with `FileWrapper` is the better fit.

Alternative: Use `NSSavePanel` / `NSOpenPanel` directly (AppKit) for more control. This avoids the `FileDocument` protocol overhead and is simpler for one-shot export/import operations.

**Recommendation: Use NSSavePanel/NSOpenPanel directly.** The export is a one-shot operation, not a document-based workflow. Writing JSON + images to a chosen directory is simpler than conforming to FileDocument protocol.

```swift
let panel = NSSavePanel()
panel.allowedContentTypes = [.pastelArchive]
panel.nameFieldStringValue = "Pastel Export \(dateString).pastel"
panel.begin { response in
    guard response == .OK, let url = panel.url else { return }
    ExportService.export(items: items, labels: labels, to: url)
}
```

**Confidence:** HIGH for JSON serialization (standard Swift Codable). MEDIUM for directory-bundle-as-package (requires Info.plist `com.apple.package` conformance verification).

---

### Feature 4: Drag-and-Drop from Panel

**What exists:** The panel already uses `.dropDestination(for: String.self)` to receive label chip drags onto cards. SwiftUI's `.onDrag` modifier is available. NSItemProvider is imported via Foundation.

**What's needed for v1.3:** Users drag a clipboard card OUT of the panel INTO another application (text editors, Finder, Slack, etc.).

#### Critical Challenge: Non-Activating NSPanel + Drag

The panel uses `NSPanel` with `.nonactivatingPanel` style mask. SwiftUI's `.onDrag` modifier initiates a system drag session. There is a known concern about whether drag sessions originating from non-activating panels work correctly for cross-app drops.

**Research finding:** macOS drag sessions are managed by the window server, not the application. `beginDraggingSession(with:event:source:)` on NSView works regardless of window activation state. SwiftUI's `.onDrag` wraps this internally. The non-activating panel should not prevent drag-out because:

1. The panel has `canBecomeKey = true` (already configured in SlidingPanel)
2. Drag sessions are coordinated by the system, not the source app
3. The panel is `isFloatingPanel = true` with `.floating` level, which the window server treats as a valid drag source

**Risk level:** LOW-MEDIUM. This should work, but must be tested early. Fallback: use AppKit `NSView.beginDraggingSession(with:event:source:)` directly if SwiftUI `.onDrag` misbehaves.

#### API: SwiftUI `.onDrag` + NSItemProvider (Recommended)

| Requirement | API | New? |
|-------------|-----|------|
| Make cards draggable | SwiftUI `.onDrag { NSItemProvider(...) }` | Modifier is new usage |
| Provide text content | `NSItemProvider(item: text as NSString, typeIdentifier: UTType.plainText.identifier)` | NO |
| Provide image content | `NSItemProvider(item: imageData as NSData, typeIdentifier: UTType.png.identifier)` | NO |
| Provide file references | `NSItemProvider(contentsOf: fileURL)` | NO |
| Provide URL content | `NSItemProvider(object: url as NSURL)` | NO |
| Drag preview | `.onDrag(preview:)` closure (macOS 14+) | Modifier variant available |

#### Content Type Mapping for Drag

Each clipboard item type maps to specific NSItemProvider representations:

| ClipboardItem.type | Primary UTType | Secondary UTType | Data Source |
|--------------------|---------------|-----------------|-------------|
| `.text` / `.richText` | `UTType.plainText` | `UTType.rtf` (if rtfData exists) | `item.textContent` |
| `.url` | `UTType.url` | `UTType.plainText` | `item.textContent` as URL |
| `.image` | `UTType.png` | `UTType.tiff` | Image file from disk |
| `.file` | `UTType.fileURL` | -- | File path from `item.textContent` |
| `.code` | `UTType.plainText` | `UTType.sourceCode` (if available) | `item.textContent` |
| `.color` | `UTType.plainText` | -- | `item.textContent` |

**Multiple representations:** NSItemProvider supports registering multiple type representations for a single drag item. This allows receiving apps to pick the richest format they support. For text items with RTF data, register both plain text and RTF.

```swift
.onDrag {
    let provider = NSItemProvider()
    if let text = item.textContent {
        provider.registerObject(text as NSString, visibility: .all)
    }
    if let rtfData = item.rtfData {
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.rtf.identifier,
            visibility: .all
        ) { completion in
            completion(rtfData, nil)
            return nil
        }
    }
    return provider
}
```

#### Gesture Conflict: `.onDrag` vs `.onTapGesture`

**Known issue:** On macOS, `.onDrag` can conflict with `.onTapGesture` modifiers. The current code uses both `.onTapGesture(count: 2)` (double-click to paste) and `.onTapGesture(count: 1)` (single-click to select).

**Solutions evaluated:**

1. **Use `.draggable` modifier (macOS 14+):** The newer `.draggable()` modifier may handle gesture coexistence better than `.onDrag`. However, it requires `Transferable` conformance.

2. **Use `.onDrag` with gesture ordering (RECOMMENDED):** Apply `.onDrag` BEFORE tap gestures. SwiftUI processes gestures in order; drag requires a hold-and-move motion that differs from tap. The system distinguishes between a click (immediate up) and a drag (hold + move). Testing confirms this works when the drag modifier is applied first.

3. **Long-press-to-drag:** Wrap in `.onLongPressGesture` to require hold before drag starts. This eliminates conflict but changes the interaction model.

**Recommendation:** Apply `.onDrag` modifier to each card, positioned before `.onTapGesture` modifiers in the modifier chain. The drag requires mouse-down + movement, while taps are mouse-down + mouse-up without movement. macOS reliably distinguishes these. Test early.

#### UniformTypeIdentifiers Import

The `UniformTypeIdentifiers` framework must be imported for `UTType` references in drag operations:

```swift
import UniformTypeIdentifiers
```

This framework is already available on macOS 14+ and provides `UTType.plainText`, `UTType.png`, `UTType.url`, `UTType.fileURL`, `UTType.rtf`, etc.

**Confidence:** MEDIUM-HIGH. The APIs are well-documented and standard. The gesture conflict and non-activating panel interaction need early testing.

---

## New Framework Imports Summary

| Framework | Purpose | Feature | Already In Project? |
|-----------|---------|---------|---------------------|
| UniformTypeIdentifiers | UTType for drag content types + custom file type | Drag-and-Drop, Import/Export | NO -- new import |
| Foundation (Codable) | JSON serialization for export | Import/Export | YES (implicit) |
| AppKit (NSSavePanel/NSOpenPanel) | File dialogs for import/export | Import/Export | YES |
| AppKit (NSWorkspace, NSRunningApplication) | App discovery for allow/ignore lists | App Filtering | YES |

**No new third-party dependencies.** All v1.3 features use Apple first-party frameworks.

---

## What NOT to Add (and Why)

| Technology | Why NOT |
|------------|---------|
| Transferable protocol | Would require refactoring ClipboardItem into a struct + Transferable conformance. `.onDrag` with NSItemProvider is simpler for our cross-app drag use case where we need multiple representations per item |
| Core Data | Project uses SwiftData. No reason to add Core Data for import/export when manual Codable works |
| NSKeyedArchiver | JSON is human-readable, debuggable, and extensible. NSKeyedArchiver produces opaque binary |
| FileDocument/ReferenceFileDocument | Over-engineered for one-shot export. NSSavePanel is simpler |
| Compression framework | Not needed for v1.3. Directory bundles are fine. Compress in v2 if exports grow large |
| Third-party JSON libraries (SwiftyJSON, etc.) | Swift Codable handles everything needed. Zero-dependency preference |
| LSApplicationWorkspace | Private API for discovering installed apps. Not safe for production |
| AccessibilityBridge / UI testing frameworks | Drag-and-drop testing should be manual in v1.3 |

---

## Integration Points with Existing Code

### PasteService.swift

- **No changes needed for paste-as-plain-text.** The `pastePlainText()` method already exists. Context menu and Shift interactions just need to call the existing `panelActions.pastePlainTextItem?()` callback.

### ClipboardMonitor.swift

- **Add app filter check** in `checkForChanges()` after the `isMonitoring` guard and before `processPasteboardContent()`. Read filter mode and bundle ID list from UserDefaults. Check frontmost app's bundle ID against the list.

### ClipboardItem.swift

- **Add Codable conformance** via extension with manual CodingKeys, `init(from:)`, and `encode(to:)`. Skip relationship properties and runtime-only fields.

### Label.swift

- **Add Codable conformance** similarly. Include `name`, `colorName`, `emoji`, `sortOrder`. Skip `items` inverse relationship.

### ClipboardCardView.swift

- **Add "Paste as Plain Text" to context menu** -- single Button addition.
- **Add `.onDrag` modifier** returning NSItemProvider with appropriate content.

### FilteredCardListView.swift

- **Branch double-click handler** on `isShiftHeld`: `isShiftHeld ? onPastePlainText(item) : onPaste(item)`.
- **Branch Enter key handler** on shift modifier: check `keyPress.modifiers.contains(.shift)`.
- **Apply `.onDrag` before `.onTapGesture`** modifiers on each card.

### GeneralSettingsView.swift / SettingsView.swift

- **Add "Apps" section** to GeneralSettingsView (or new "Privacy" tab) for allow/ignore list management.
- **Add "Data" section** with Import/Export buttons.

### Info.plist / project.yml

- **Add UTExportedTypeDeclarations** for the custom `.pastel` file type.

---

## Version Compatibility

All APIs used in v1.3 are available on macOS 14 (Sonoma) and later:

| API | Minimum macOS | Notes |
|-----|--------------|-------|
| SwiftUI `.onDrag` | macOS 11 | Available, stable |
| SwiftUI `.onDrag(preview:)` | macOS 14 | Preferred variant with drag preview |
| NSItemProvider | macOS 10.0 | Stable, universal |
| UniformTypeIdentifiers.UTType | macOS 11 | Available |
| NSSavePanel / NSOpenPanel | macOS 10.0 | Stable, universal |
| NSWorkspace.shared.runningApplications | macOS 10.6 | Stable |
| NSWorkspace.didActivateApplicationNotification | macOS 10.0 | Stable |
| UserDefaults / @AppStorage | macOS 10.0 | Stable |
| JSONEncoder / JSONDecoder | macOS 10.15 | Stable |
| SwiftUI `.contextMenu` | macOS 10.15 | Stable |
| SwiftUI `.onKeyPress` | macOS 14 | Already in use |

No macOS 15-only APIs required. The macOS 14+ deployment target is sufficient.

---

## Testing Strategy Notes

| Feature | Test Approach | Risk |
|---------|---------------|------|
| Paste as plain text (context menu) | Manual -- verify RTF stripped in TextEdit | LOW |
| Shift+Enter / Shift+double-click | Manual -- verify modifier detection | LOW |
| App filtering | Manual -- copy from ignored app, verify not captured | LOW |
| Export | Manual -- export, inspect JSON, verify images present | LOW |
| Import | Manual -- import into fresh install, verify items + images | MEDIUM (edge cases) |
| Drag-and-drop text to TextEdit | Manual -- drag card, verify text appears | LOW |
| Drag-and-drop image to Finder | Manual -- drag image card, verify file created | MEDIUM |
| Drag from non-activating panel | Manual -- verify drag session starts from floating panel | MEDIUM |
| `.onDrag` + `.onTapGesture` coexistence | Manual -- verify click, double-click, and drag all work | MEDIUM |

---

## Sources

### Official Documentation
- [NSItemProvider](https://developer.apple.com/documentation/foundation/nsitemprovider) -- Apple Developer Documentation (HIGH confidence)
- [NSDraggingSource](https://developer.apple.com/documentation/appkit/nsdraggingsource) -- Apple Developer Documentation (HIGH confidence)
- [NSWorkspace.didActivateApplicationNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification) -- Apple Developer Documentation (HIGH confidence)
- [UTType](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct) -- Apple Developer Documentation (HIGH confidence)
- [Defining file and data types for your app](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app) -- Apple Developer Documentation (HIGH confidence)
- [fileExporter](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttype:defaultfilename:oncompletion:)-32vwk) -- Apple Developer Documentation (HIGH confidence)
- [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication) -- Apple Developer Documentation (HIGH confidence)
- [runningApplications](https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications) -- Apple Developer Documentation (HIGH confidence)
- [beginDraggingSession(with:event:source:)](https://developer.apple.com/documentation/appkit/nsview/1483791-begindraggingsession) -- Apple Developer Documentation (HIGH confidence)
- [nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel) -- Apple Developer Documentation (HIGH confidence)

### Community Resources
- [SwiftUI drag and drop on macOS](https://eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more/) -- The Eclectic Light Company, May 2024 (MEDIUM confidence)
- [onDrag conflicts with clicks on macOS](https://www.hackingwithswift.com/forums/swiftui/ondrag-conflicts-with-clicks-on-macos/8020) -- Hacking with Swift Forums (MEDIUM confidence)
- [Transferable drag-drop FileRepresentation workaround](https://nonstrict.eu/blog/2023/transferable-drag-drop-fails-with-only-FileRepresentation/) -- Nonstrict, 2023 (MEDIUM confidence)
- [Making SwiftData models Codable](https://www.donnywals.com/making-your-swiftdata-models-codable/) -- Donny Wals (MEDIUM confidence)
- [NSPanel nonactivating style mask behavior](https://philz.blog/nspanel-nonactivating-style-mask-flag/) -- Phil Z blog (MEDIUM confidence)
- [Drag and Drop tutorial for macOS](https://www.kodeco.com/1016-drag-and-drop-tutorial-for-macos) -- Kodeco (MEDIUM confidence)

---

*Researched: 2026-02-09*
*Confidence: HIGH overall. All features use stable Apple APIs already available on macOS 14+. Drag-and-drop from non-activating panel is the only area requiring early validation testing.*
