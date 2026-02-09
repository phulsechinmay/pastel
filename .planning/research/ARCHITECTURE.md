# Architecture Research: v1.3 Power User Features

**Domain:** macOS clipboard manager -- paste-as-plain-text UI, app filtering, import/export, drag-and-drop
**Researched:** 2026-02-09
**Confidence:** HIGH (based on direct source code analysis of all 50+ Swift files in the Pastel codebase, verified macOS/SwiftUI API patterns, and Maccy reference implementation)

## Confidence Note

All integration points are derived from direct analysis of every service, model, and view file in the Pastel codebase. Architecture recommendations build on patterns the codebase already follows (@MainActor services, @AppStorage for preferences, @Observable for reactive UI, PanelActions callback bridge). Drag-and-drop recommendations use SwiftUI's `.onDrag` / `.draggable` modifiers which the codebase already uses for label chips (ChipBarView). App filtering logic is verified against Maccy's open-source implementation. Import/export patterns use standard Codable + NSSavePanel/NSOpenPanel which are well-documented macOS APIs. Paste-as-plain-text infrastructure already exists (PasteService.pastePlainText) -- this research focuses on UI integration points only.

---

## Existing Architecture Summary (Updated for v1.2)

```
PastelApp (@main)
    |
    +-- AppState (@Observable, @MainActor)
    |       |-- ClipboardMonitor (Timer polling -> classify -> deduplicate -> SwiftData insert)
    |       |-- PanelController (NSPanel lifecycle, show/hide, event monitors)
    |       |-- PasteService (pasteboard write + CGEvent Cmd+V, plain text mode)
    |       |-- RetentionService (hourly purge based on retention period)
    |       `-- modelContainer (SwiftData: ClipboardItem, Label)
    |
    +-- Models
    |       |-- ClipboardItem (@Model: textContent, htmlContent, rtfData, contentType,
    |       |                   imagePath, thumbnailPath, isConcealed, expiresAt,
    |       |                   contentHash (@Attribute(.unique)), title, labels[],
    |       |                   detectedLanguage, detectedColorHex, url metadata fields)
    |       |-- ContentType (enum: text, richText, url, image, file, code, color)
    |       |-- Label (@Model: name, colorName, emoji, sortOrder, items[])
    |       |-- LabelColor (enum: 12 preset colors)
    |       `-- PasteBehavior (enum: paste, copy, copyAndPaste)
    |
    +-- Services
    |       |-- ClipboardMonitor (@MainActor, 0.5s polling, SHA256 hashing, skipNextChange)
    |       |-- ImageStorageService (singleton, background DispatchQueue, PNG storage,
    |       |                        4K downscale, 200px thumbnails)
    |       |-- ExpirationService (60s auto-delete for concealed items)
    |       |-- RetentionService (hourly purge by retention days)
    |       |-- PasteService (writeToPasteboard, writeToPasteboardPlainText, simulatePaste)
    |       |-- CodeDetectionService, ColorDetectionService, URLMetadataService
    |       |-- AccessibilityService, AppIconColorService, MigrationService
    |       `-- [Missing: AppFilterService, ImportExportService]
    |
    +-- Views/Panel
    |       |-- PanelController -> SlidingPanel (NSPanel, .nonactivatingPanel)
    |       |-- PanelContentView (header + search + chips + filtered list)
    |       |-- FilteredCardListView (dynamic @Query, keyboard nav, quick paste hotkeys)
    |       |-- ClipboardCardView (dispatcher: header + contentPreview + footer + context menu)
    |       |-- [Type-specific cards: Text, Image, URL, File, Code, Color]
    |       |-- ChipBarView (label chips with .draggable), SearchFieldView
    |       |-- PanelActions (@Observable bridge: pasteItem, pastePlainTextItem, copyOnlyItem)
    |       `-- EditItemView + EditItemWindow (title + multi-label editing)
    |
    +-- Views/Settings
    |       |-- SettingsView (tabs: General, Labels, History)
    |       |-- GeneralSettingsView (startup, hotkey, position, retention, paste, URL previews)
    |       |-- LabelSettingsView (CRUD for labels)
    |       `-- HistoryBrowserView + HistoryGridView (search, filter, multi-select, bulk ops)
    |
    +-- Views/MenuBar
            `-- StatusPopoverView (monitoring toggle, show history, settings, clear all, quit)
```

### Key Architecture Patterns Already Established

1. **PanelActions callback bridge:** SwiftUI views call `panelActions.pasteItem?(item)` which routes through PanelController to AppState to PasteService. All paste variants (normal, plain text, copy-only) follow this pattern.
2. **PasteService already has plain text support:** `pastePlainText(item:)` and `writeToPasteboardPlainText(item:)` strip RTF and write only `.string` + `.html`. This is fully implemented and working via Cmd+Shift+1-9 hotkeys.
3. **Context menu pattern in ClipboardCardView:** Right-click context menu has Copy, Paste, Copy+Paste, Edit, Label submenu, and Delete. Adding new items is straightforward.
4. **Source app tracking already exists:** `ClipboardItem.sourceAppBundleID` and `sourceAppName` are captured at copy time via `NSWorkspace.shared.frontmostApplication`. This is the foundation for app filtering.
5. **SwiftUI drag already works:** ChipBarView uses `.draggable(label.persistentModelID.asTransferString)` with `PersistentIdentifier+Transfer` extension. The codebase has proven drag-and-drop patterns.
6. **@AppStorage for all preferences:** Every user-configurable setting uses `@AppStorage` with string keys.
7. **Dynamic @Query via view recreation:** FilteredCardListView takes search/filter params in init, constructs a #Predicate, and uses `.id()` on the parent to force recreation when filters change.

---

## Feature 1: Paste-as-Plain-Text UI

### Current State

PasteService already has **full plain text paste support**:
- `PasteService.pastePlainText(item:clipboardMonitor:panelController:)` -- strips RTF, writes `.string` + `.html` only
- `PasteService.writeToPasteboardPlainText(item:)` -- the underlying pasteboard write
- `AppState.pastePlainText(item:)` -- delegates to PasteService
- `PanelActions.pastePlainTextItem` -- callback bridge from SwiftUI
- `PanelContentView.pastePlainTextItem(_:)` -- wired to PanelActions
- FilteredCardListView handles `Cmd+Shift+1-9` for plain text paste via `onPastePlainText` callback

**What is missing is only the UI entry points**: context menu items, Shift+Enter, and Shift+double-click.

### Integration Points

#### 1. Context Menu in ClipboardCardView (MODIFY)

**File:** `/Users/phulsechinmay/Desktop/Projects/pastel/Pastel/Views/Panel/ClipboardCardView.swift`
**Lines:** 163-222 (contextMenu block)

The current context menu has:
```
Copy
Paste
Copy + Paste
---
Edit...
---
Label >
---
Delete
```

Add "Paste as Plain Text" after "Copy + Paste":
```
Copy
Paste
Copy + Paste
Paste as Plain Text    <-- NEW
---
Edit...
---
Label >
---
Delete
```

**Implementation:** Call `panelActions.pastePlainTextItem?(item)` -- the callback already exists on PanelActions.

**Conditional visibility:** Only show "Paste as Plain Text" for text-based content types (.text, .richText, .code, .color). For .url, .image, .file it has no effect (PasteService already delegates to normal writeToPasteboard for non-text types).

#### 2. Shift+Double-Click in FilteredCardListView (MODIFY)

**File:** `/Users/phulsechinmay/Desktop/Projects/pastel/Pastel/Views/Panel/FilteredCardListView.swift`
**Lines:** 120-125 (vertical layout), 170-175 (horizontal layout)

Current pattern:
```swift
.onTapGesture(count: 2) { onPaste(item) }
.onTapGesture(count: 1) { selectedIndex = index }
```

**Challenge:** SwiftUI's `.onTapGesture` does not provide modifier key information. The `count: 2` handler receives no `NSEvent` to check for Shift.

**Solution approach:** Use `NSEvent.modifierFlags` (static property) to check current modifier state at the time of the gesture callback:

```swift
.onTapGesture(count: 2) {
    if NSEvent.modifierFlags.contains(.shift) {
        onPastePlainText(item)
    } else {
        onPaste(item)
    }
}
```

This pattern is already proven in the codebase: `HistoryGridView.handleTap()` uses `NSEvent.modifierFlags` to detect Cmd and Shift modifiers for multi-select behavior (line 160).

**Confidence:** HIGH -- the pattern works and is already used in HistoryGridView.

#### 3. Shift+Enter in FilteredCardListView (MODIFY)

**File:** `/Users/phulsechinmay/Desktop/Projects/pastel/Pastel/Views/Panel/FilteredCardListView.swift`
**Lines:** 230-235 (Return key handler)

Current handler:
```swift
.onKeyPress(.return) {
    if let index = selectedIndex, index < filteredItems.count {
        onPaste(filteredItems[index])
    }
    return .handled
}
```

**Solution:** The `.onKeyPress` handler receives a `KeyPress` value that has a `.modifiers` property. Check for `.shift`:

```swift
.onKeyPress(.return) { keyPress in
    guard let index = selectedIndex, index < filteredItems.count else { return .handled }
    if keyPress.modifiers.contains(.shift) {
        onPastePlainText(filteredItems[index])
    } else {
        onPaste(filteredItems[index])
    }
    return .handled
}
```

This pattern is already used in the Cmd+1-9 handler at lines 236-259, which checks `keyPress.modifiers.contains(.shift)` and `keyPress.modifiers.contains(.command)`.

**Confidence:** HIGH -- exact same modifier check pattern already in use.

### Data Model Changes

None. The plain text paste infrastructure is fully implemented. This is purely a UI wiring task.

### New Components

None. All changes are modifications to existing files.

### Files to Modify

| File | Change | Scope |
|------|--------|-------|
| `ClipboardCardView.swift` | Add "Paste as Plain Text" context menu item | ~8 lines added |
| `FilteredCardListView.swift` | Shift+double-click and Shift+Enter checks | ~10 lines modified |

---

## Feature 2: App Allow/Ignore Lists

### Architecture Decision: Where to Check

There are two architectural options for app filtering:

**Option A: Filter in ClipboardMonitor.checkForChanges()** (early filtering)
- Check `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` before processing
- Items from ignored apps never enter the capture pipeline
- Pro: No unnecessary work (no hashing, no SwiftData access)
- Con: Must check on every poll tick (0.5s), but the check is trivial (Set.contains)

**Option B: Filter in ClipboardMonitor.processPasteboardContent()** (late filtering)
- Check after content classification but before SwiftData insert
- Pro: Classification info available (could filter by content type per app)
- Con: Does unnecessary classification work before discarding

**Recommendation: Option A -- early filtering in checkForChanges().** The check is a single `Set.contains(bundleID)` operation. Filtering before `processPasteboardContent()` avoids all unnecessary work: no content reading, no hashing, no SwiftData queries. This matches Maccy's implementation pattern.

### Integration Points

#### 1. New Service: AppFilterService (NEW)

**File:** `Pastel/Services/AppFilterService.swift`

```
@MainActor
@Observable
final class AppFilterService {
    /// List of bundle IDs in the user's configured list
    var appBundleIDs: [String]  // loaded from UserDefaults

    /// Whether the list acts as an allow-list or ignore-list
    var mode: FilterMode  // .allowList or .ignoreList

    enum FilterMode: String {
        case allowList = "allowList"   // ONLY capture from listed apps
        case ignoreList = "ignoreList" // capture from ALL EXCEPT listed apps
    }

    /// Check whether clipboard content from a given app should be captured
    func shouldCapture(bundleID: String?) -> Bool {
        guard let bundleID else { return true }  // Unknown app -> capture
        switch mode {
        case .ignoreList:
            return !appBundleIDs.contains(bundleID)
        case .allowList:
            return appBundleIDs.contains(bundleID)
        }
    }
}
```

**Persistence:** Store the app list in UserDefaults as a JSON-encoded `[String]` array, and the mode as a string. Use `@AppStorage` for the mode toggle and manual UserDefaults access for the array (since @AppStorage does not support arrays).

**Why a separate service instead of inline logic in ClipboardMonitor:**
- ClipboardMonitor is already 400 lines with complex responsibility
- AppFilterService encapsulates the allow/ignore logic and persistence
- Settings views can bind to AppFilterService.appBundleIDs directly
- Testable in isolation

#### 2. ClipboardMonitor Modification (MODIFY)

**File:** `/Users/phulsechinmay/Desktop/Projects/pastel/Pastel/Services/ClipboardMonitor.swift`
**Method:** `checkForChanges()` (lines 128-143)

Add filter check after the changeCount guard, before `processPasteboardContent()`:

```swift
private func checkForChanges() {
    guard isMonitoring else { return }
    let currentChangeCount = pasteboard.changeCount
    guard currentChangeCount != lastChangeCount else { return }
    lastChangeCount = currentChangeCount

    if skipNextChange {
        skipNextChange = false
        return
    }

    // NEW: App filtering
    let sourceApp = NSWorkspace.shared.frontmostApplication
    if let filterService = appFilterService,
       !filterService.shouldCapture(bundleID: sourceApp?.bundleIdentifier) {
        return
    }

    processPasteboardContent()
}
```

**Important consideration:** The `NSWorkspace.shared.frontmostApplication` call is already made later in `processPasteboardContent()` (line 223). Moving it earlier to `checkForChanges()` for filtering means it runs on every poll tick where the changeCount differs. This is safe -- it is a simple property access on the main thread with no performance concern.

However, there is a subtlety: if app filtering skips the content, `processPasteboardContent()` is never called, so the sourceApp info from `checkForChanges()` is discarded. If filtering passes, `processPasteboardContent()` re-reads `frontmostApplication`, which could theoretically return a different app if the user switched apps between the two calls (within the same 0.5s tick). This is an extremely unlikely edge case and not worth optimizing for.

#### 3. AppState Wiring (MODIFY)

**File:** `/Users/phulsechinmay/Desktop/Projects/pastel/Pastel/App/AppState.swift`

Add `appFilterService` property and pass it to ClipboardMonitor:

```swift
var appFilterService: AppFilterService?

func setup(modelContext: ModelContext) {
    let filter = AppFilterService()
    self.appFilterService = filter

    let monitor = ClipboardMonitor(modelContext: modelContext, appFilterService: filter)
    // ...
}
```

#### 4. Settings UI: App Filter Settings View (NEW)

**File:** `Pastel/Views/Settings/AppFilterSettingsView.swift`

This view needs:
- Toggle between Allow List mode and Ignore List mode
- List of currently configured apps (showing app name + icon + bundle ID)
- "Add App" button that shows a file picker for .app bundles (NSOpenPanel with /Applications as starting directory)
- Remove button per app entry
- Running apps list for quick selection (via `NSWorkspace.shared.runningApplications`)

**App discovery approach:**
- **Primary:** NSOpenPanel pointing to /Applications, filter for .app bundles. Read bundle ID from the selected app's Info.plist via `Bundle(url:)?.bundleIdentifier`.
- **Secondary:** Show a list of currently running applications (`NSWorkspace.shared.runningApplications`) filtered to `.activationPolicy == .regular` (excludes background agents and daemons). User taps to add.

**Integration with SettingsView:** Add a new "Apps" or "Privacy" tab, or add as a section within GeneralSettingsView. Given that the settings already have 3 tabs (General, Labels, History), adding a 4th "Apps" tab is reasonable and avoids overloading General.

#### 5. SettingsView Tab Addition (MODIFY)

**File:** `/Users/phulsechinmay/Desktop/Projects/pastel/Pastel/Views/Settings/SettingsView.swift`

Add `case apps` to `SettingsTab` enum:
```swift
private enum SettingsTab: String, CaseIterable {
    case general
    case labels
    case history
    case apps  // NEW
}
```

### Data Model Changes

None. App filter configuration lives entirely in UserDefaults, not SwiftData. The ClipboardItem model already has `sourceAppBundleID` for display purposes -- this is not used for filtering (filtering happens before item creation).

### New Components

| Component | Type | Purpose |
|-----------|------|---------|
| `AppFilterService` | @MainActor @Observable | Allow/ignore list logic and persistence |
| `AppFilterSettingsView` | SwiftUI View | UI for managing app lists |

### Files to Modify

| File | Change | Scope |
|------|--------|-------|
| `ClipboardMonitor.swift` | Add filter check in `checkForChanges()` | ~8 lines added, 1 init param |
| `AppState.swift` | Create and wire AppFilterService | ~5 lines |
| `SettingsView.swift` | Add `apps` tab | ~5 lines |

---

## Feature 3: Import/Export

### Architecture Decision: File Format

**Custom `.pastel` format (JSON-based):**

The export file should be a self-contained JSON document that includes:
- Metadata (export date, app version, item count)
- ClipboardItem data (all fields except SwiftData-specific identifiers)
- Label definitions (name, color, emoji, sort order)
- Item-to-label assignments
- Embedded image data (Base64-encoded) for image items

**Why JSON over alternatives:**
- **Plist:** More macOS-native but harder to extend. JSON is human-readable and debuggable.
- **SQLite dump:** Ties the format to SwiftData internals. Schema changes break imports.
- **Zip with separate files:** More complex to create/parse. Images are rare in clipboard history, so embedding Base64 is acceptable for most exports.
- **JSON:** Universal, Codable-friendly, extensible with versioning. Standard practice.

**Format structure:**

```json
{
    "version": 1,
    "exportDate": "2026-02-09T12:00:00Z",
    "appVersion": "1.3.0",
    "labels": [
        { "name": "Work", "colorName": "blue", "emoji": null, "sortOrder": 0 }
    ],
    "items": [
        {
            "textContent": "Hello world",
            "htmlContent": null,
            "rtfData": null,
            "contentType": "text",
            "timestamp": "2026-02-09T11:30:00Z",
            "sourceAppBundleID": "com.apple.Safari",
            "sourceAppName": "Safari",
            "characterCount": 11,
            "byteCount": 11,
            "isConcealed": false,
            "contentHash": "abc123...",
            "title": null,
            "labels": ["Work"],
            "detectedLanguage": null,
            "detectedColorHex": null,
            "imageData": null
        }
    ]
}
```

**Key decisions:**
- Labels referenced by name (not PersistentIdentifier) since IDs are not portable
- `imageData` is Base64-encoded PNG for image items (nullable for text items)
- RTF data is Base64-encoded when present
- `contentHash` is exported so import can skip duplicates
- No export of `imagePath`, `thumbnailPath`, `changeCount`, `expiresAt` (runtime-only fields)
- Concealed items are excluded by default (they are sensitive/temporary)
- URL metadata fields (urlTitle, urlFaviconPath, urlPreviewImagePath) are NOT exported -- they will be re-fetched on import if URL metadata fetching is enabled

### Integration Points

#### 1. New Service: ImportExportService (NEW)

**File:** `Pastel/Services/ImportExportService.swift`

```
@MainActor
final class ImportExportService {

    // MARK: - Export Types

    struct ExportDocument: Codable {
        let version: Int
        let exportDate: Date
        let appVersion: String
        let labels: [ExportLabel]
        let items: [ExportItem]
    }

    struct ExportLabel: Codable {
        let name: String
        let colorName: String
        let emoji: String?
        let sortOrder: Int
    }

    struct ExportItem: Codable {
        let textContent: String?
        let htmlContent: String?
        let rtfData: String?       // Base64
        let contentType: String
        let timestamp: Date
        let sourceAppBundleID: String?
        let sourceAppName: String?
        let characterCount: Int
        let byteCount: Int
        let isConcealed: Bool
        let contentHash: String
        let title: String?
        let labels: [String]       // Label names
        let detectedLanguage: String?
        let detectedColorHex: String?
        let imageData: String?     // Base64 PNG
    }

    // MARK: - Export

    func exportAll(modelContext: ModelContext) throws -> Data {
        // 1. Fetch all Labels
        // 2. Fetch all ClipboardItems (excluding concealed)
        // 3. For image items, read image file from disk and Base64-encode
        // 4. Map to ExportDocument
        // 5. JSONEncoder with .prettyPrinted + .iso8601 dateStrategy
        // 6. Return Data
    }

    // MARK: - Import

    func importFromData(_ data: Data, modelContext: ModelContext) throws -> ImportResult {
        // 1. JSONDecoder with .iso8601 dateStrategy
        // 2. Version check (handle migration if needed)
        // 3. Import labels: match by name (update existing, create new)
        // 4. Import items: skip if contentHash already exists in DB
        // 5. For image items: decode Base64, save via ImageStorageService
        // 6. Assign labels by name lookup
        // 7. Save in batches (per SwiftData best practices)
        // 8. Return ImportResult with counts
    }

    struct ImportResult {
        let itemsImported: Int
        let itemsSkipped: Int   // duplicates
        let labelsCreated: Int
        let labelsMatched: Int
    }
}
```

**SwiftData batch import considerations:**
- For large imports (1000+ items), split into batches of 500 to avoid memory spikes
- Call `modelContext.save()` after each batch
- Image items require async disk I/O via ImageStorageService -- process sequentially to avoid overwhelming the background queue
- Skip items where `contentHash` already exists (use `@Attribute(.unique)` constraint as guard)

#### 2. Export UI: NSSavePanel Integration (NEW)

**File:** `Pastel/Views/Settings/ImportExportView.swift` (or section in GeneralSettingsView)

```swift
func showExportPanel() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.init(filenameExtension: "pastel")!]
    panel.nameFieldStringValue = "Pastel Export \(dateFormatter.string(from: .now))"
    panel.canCreateDirectories = true

    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                let data = try importExportService.exportAll(modelContext: modelContext)
                try data.write(to: url)
            } catch {
                // Show error alert
            }
        }
    }
}
```

**Why NSSavePanel instead of SwiftUI .fileExporter:**
- `.fileExporter` requires conformance to `FileDocument` or `ReferenceFileDocument`, which adds unnecessary protocol machinery for a simple one-shot export
- NSSavePanel integrates cleanly with the existing AppKit hybrid (PanelController, SettingsWindowController)
- NSSavePanel provides more control over the initial directory and filename
- The app is not sandboxed, so NSSavePanel works without security-scoped bookmarks

#### 3. Import UI: NSOpenPanel Integration (NEW)

```swift
func showImportPanel() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.init(filenameExtension: "pastel")!]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false

    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                let data = try Data(contentsOf: url)
                let result = try importExportService.importFromData(data, modelContext: modelContext)
                // Show result summary alert
            } catch {
                // Show error alert
            }
        }
    }
}
```

#### 4. Settings Integration (MODIFY)

The import/export buttons can be placed in:
- **Option A:** New section at bottom of GeneralSettingsView ("Data" section, which already has "Clear All History")
- **Option B:** New "Data" tab in SettingsView

**Recommendation: Option A -- add to GeneralSettingsView's existing "Data" section.** The Data section currently only has "Clear All History". Adding "Export..." and "Import..." buttons below it is natural. This avoids adding a 5th tab (with the "Apps" tab from Feature 2, we are already at 4 tabs).

```
Data section in GeneralSettingsView:
    Export History...      [button]
    Import History...      [button]
    ---
    Clear All History...   [existing button]
```

#### 5. ClipboardMonitor ItemCount Update (MODIFY)

After import, `clipboardMonitor.itemCount` must be updated. The import service should call:
```swift
clipboardMonitor?.itemCount = try modelContext.fetchCount(FetchDescriptor<ClipboardItem>())
```

### Data Model Changes

None. Import/export operates on the existing ClipboardItem and Label models via Codable mapping structs. No new fields needed.

### New Components

| Component | Type | Purpose |
|-----------|------|---------|
| `ImportExportService` | @MainActor service | Export/import logic with Codable mapping |
| Import/Export UI | SwiftUI section or buttons | NSSavePanel/NSOpenPanel triggers |

### Files to Modify

| File | Change | Scope |
|------|--------|-------|
| `GeneralSettingsView.swift` | Add Export/Import buttons to Data section | ~30 lines |
| `AppState.swift` | Add ImportExportService property, wire to model context | ~5 lines |

---

## Feature 4: Drag-and-Drop from Panel

### Architecture Decision: .onDrag vs .draggable

SwiftUI provides two approaches:
1. **`.onDrag { NSItemProvider(...) }`** -- older API, returns NSItemProvider
2. **`.draggable(value)`** -- newer API (macOS 13+), uses Transferable protocol

The codebase already uses `.draggable` in ChipBarView for label drag:
```swift
.draggable(label.persistentModelID.asTransferString) {
    LabelChipView(label: label)
}
```

However, for clipboard item drag-and-drop to external apps, **`.onDrag` with NSItemProvider is the better choice** because:
- External apps expect standard pasteboard types (UTType.plainText, UTType.png, UTType.fileURL)
- NSItemProvider supports multiple representations (text + URL, text + RTF) which `.draggable` with Transferable does not handle as cleanly for cross-app scenarios
- `.onDrag` allows lazy data loading (important for large images)
- `.draggable` with String conformance only provides text -- we need type-specific providers

### Critical Concern: NSPanel and Drag Sessions

The panel is a non-activating `NSPanel` with `hidesOnDeactivate = false`. When a drag session starts from the panel and the user moves the cursor outside the panel to drop in another app, several things happen:

1. The drag session is managed by the window server, not the panel
2. The panel does NOT hide -- `hidesOnDeactivate` is already `false`
3. The panel does NOT lose key status during the drag
4. Once the drop completes (or drag is cancelled), focus returns to the target app

**Key finding:** The panel's existing configuration (`hidesOnDeactivate = false`, `isFloatingPanel = true`, `collectionBehavior = .canJoinAllSpaces`) should work correctly with drag sessions. The panel stays visible during the drag. No modifications to SlidingPanel or PanelController are needed.

**MEDIUM confidence:** This assessment is based on the panel's configuration flags and macOS window server behavior. Testing with actual drag sessions is needed to confirm. If the panel does hide during drag, the fix would be to suppress the global click monitor during active drag sessions.

### Concern: .onDrag Conflicts with Existing Gestures

FilteredCardListView currently attaches these gestures to each ClipboardCardView:
```swift
.onTapGesture(count: 2) { onPaste(item) }
.onTapGesture(count: 1) { selectedIndex = index }
```

Adding `.onDrag` can conflict with click gestures on macOS. Known issues:
- `.onDrag` can consume mouse-down events, interfering with `.onTapGesture`
- Clicks on draggable content may not register

**Mitigation strategy:** Apply `.onDrag` to the ClipboardCardView body rather than at the FilteredCardListView level. This keeps gesture scoping clean. The existing `.onTapGesture` handlers at the FilteredCardListView level should take priority because they are attached higher in the view hierarchy.

If conflicts persist, the fallback is to use a longer press-and-drag threshold so that taps are distinguished from drags. SwiftUI's `.onDrag` has a built-in delay before initiating a drag session (it waits for the user to actually move the cursor), which should prevent most conflicts.

### Integration Points

#### 1. ClipboardCardView .onDrag (MODIFY)

**File:** `/Users/phulsechinmay/Desktop/Projects/pastel/Pastel/Views/Panel/ClipboardCardView.swift`

Add `.onDrag` to the card's body:

```swift
.onDrag {
    createItemProvider(for: item)
}
```

**NSItemProvider construction by content type:**

```swift
private func createItemProvider(for item: ClipboardItem) -> NSItemProvider {
    let provider = NSItemProvider()

    switch item.type {
    case .text, .richText, .code, .color:
        // Register plain text
        if let text = item.textContent {
            provider.registerObject(text as NSString, visibility: .all)
        }
        // Register RTF if available
        if let rtfData = item.rtfData {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.rtf.identifier,
                visibility: .all
            ) { completion in
                completion(rtfData, nil)
                return nil
            }
        }

    case .url:
        if let urlString = item.textContent, let url = URL(string: urlString) {
            provider.registerObject(url as NSURL, visibility: .all)
            // Also register as plain text for apps that don't accept URLs
            provider.registerObject(urlString as NSString, visibility: .all)
        }

    case .image:
        if let imagePath = item.imagePath {
            let imageURL = ImageStorageService.shared.resolveImageURL(imagePath)
            // Register as file URL (apps can read the image file)
            provider.registerFileRepresentation(
                forTypeIdentifier: UTType.png.identifier,
                visibility: .all
            ) { completion in
                completion(imageURL, true, nil)
                return nil
            }
        }

    case .file:
        if let filePath = item.textContent {
            let fileURL = URL(fileURLWithPath: filePath)
            provider.registerObject(fileURL as NSURL, visibility: .all)
        }
    }

    return provider
}
```

#### 2. Drag Preview (MODIFY)

SwiftUI's `.onDrag` supports a `preview:` parameter on macOS 13+. Provide a compact preview:

```swift
.onDrag {
    createItemProvider(for: item)
} preview: {
    dragPreview(for: item)
}
```

For text items, show a truncated text snippet in a small card. For images, show the thumbnail. For URLs, show the URL string. Keep previews small (max 200x60pt) to avoid obscuring drop targets.

#### 3. PanelController Global Click Monitor (POTENTIAL MODIFY)

**File:** `/Users/phulsechinmay/Desktop/Projects/pastel/Pastel/Views/Panel/PanelController.swift`
**Method:** `installEventMonitors()` (lines 198-216)

The global click monitor dismisses the panel on any click outside it:
```swift
globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
    matching: [.leftMouseDown, .rightMouseDown]
) { [weak self] _ in
    self?.hide()
}
```

**Risk:** If a drag-drop operation involves a mouse-down outside the panel (which it does -- the drop target is in another app), the global click monitor will hide the panel during the drag.

**Fix:** Track whether a drag session is active and suppress the hide:

```swift
var isDragging: Bool = false  // Set by ClipboardCardView's .onDrag

globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
    matching: [.leftMouseDown, .rightMouseDown]
) { [weak self] _ in
    guard self?.isDragging != true else { return }
    self?.hide()
}
```

**Communication mechanism:** The `isDragging` flag could be set via:
- A new callback on PanelActions (like `panelActions.onDragStarted` / `onDragEnded`)
- A published property on AppState
- Direct access to PanelController via environment

**Recommendation:** Add `isDragging: Bool` to PanelActions since it is already the bridge between SwiftUI views and PanelController. ClipboardCardView sets it, PanelController reads it.

However, SwiftUI's `.onDrag` does not provide start/end callbacks. Detecting drag state requires either:
- Using `NSDraggingSource` protocol methods (requires NSView subclass)
- Monitoring `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged)` to detect drag initiation

**Alternative approach:** Instead of tracking drag state, modify the global click monitor to only respond to `.leftMouseDown` events that are NOT drag-related. This is harder to distinguish at the event level.

**Pragmatic solution:** Simply do not hide the panel during drag. After the drag completes (drop or cancel), the user can dismiss the panel manually or it auto-hides on the next global click. The user experience is: drag from panel -> drop in target app -> panel stays open -> click elsewhere or press Escape to dismiss. This is actually better UX because users might want to drag multiple items.

**Simplest implementation:** Set `hidesOnDeactivate = false` (already done) and accept that the panel stays visible after a drag-drop. The existing Escape key handler and toggle hotkey provide explicit dismiss options.

### Data Model Changes

None.

### New Components

None. All changes are modifications to existing files.

### Files to Modify

| File | Change | Scope |
|------|--------|-------|
| `ClipboardCardView.swift` | Add `.onDrag` with NSItemProvider construction | ~40 lines added |
| `FilteredCardListView.swift` | May need gesture conflict resolution | ~5 lines if needed |
| `PanelController.swift` | Potentially modify global click monitor for drag compat | ~5 lines if needed |

---

## Component Dependency Graph (v1.3)

```
                    +---------------------+
                    |   ClipboardItem     |
                    |   (@Model)          |
                    |   (NO changes)      |
                    +---------+-----------+
                              |
            +-----------+-----+--------+------------+
            |           |              |            |
            v           v              v            v
  +-----------------+ +------------+ +----------+ +------------------+
  |ClipboardMonitor | |PasteService| |ClipCard  | |ImportExportSvc   |
  |+ appFilter check| |(unchanged) | |+ onDrag  | |+ export/import   |
  |  (checkForChgs) | |            | |+ ctx menu| |+ Codable mapping |
  +---------+-------+ +------------+ |+ shiftDbl| +--------+---------+
            |                        +----------+          |
            v                                              v
  +------------------+                          +------------------+
  |AppFilterService  | <-- NEW                  |GeneralSettingsVw |
  |+ shouldCapture() |                          |+ Export/Import   |
  |+ allow/ignore    |                          |  buttons         |
  +--------+---------+                          +------------------+
           |
           v
  +---------------------+
  |AppFilterSettingsView | <-- NEW
  |+ mode toggle        |
  |+ app list management|
  +---------------------+
```

---

## Data Flow Changes

### Clipboard Capture Pipeline (Modified for App Filtering)

```
NSPasteboard.general
    |
    v
ClipboardMonitor.checkForChanges()
    |
    +-- Guard: isMonitoring
    +-- Guard: changeCount changed
    +-- Guard: skipNextChange
    +-- NEW: Guard: AppFilterService.shouldCapture(bundleID)
    |         |
    |         +-- If ignore mode: skip if bundleID in list
    |         +-- If allow mode: skip if bundleID NOT in list
    |
    v
processPasteboardContent()  // unchanged from here down
```

### Paste Flow (Modified for Plain Text UI)

```
User interaction:
    |
    +-- Double-click on card
    |       +-- Check NSEvent.modifierFlags.contains(.shift)
    |       +-- Shift held: onPastePlainText(item) -> PasteService.pastePlainText
    |       +-- No shift: onPaste(item) -> PasteService.paste
    |
    +-- Enter key
    |       +-- Check keyPress.modifiers.contains(.shift)
    |       +-- Shift: pastePlainText
    |       +-- No shift: paste
    |
    +-- Context menu "Paste as Plain Text"
    |       +-- panelActions.pastePlainTextItem?(item)
    |
    +-- Cmd+Shift+1-9 (existing, unchanged)
            +-- onPastePlainText(item)
```

### Drag-and-Drop Flow (New)

```
User long-presses and drags card:
    |
    v
ClipboardCardView.onDrag
    |
    +-- createItemProvider(for: item)
    |       +-- .text/.richText: NSString + RTF data
    |       +-- .url: NSURL + NSString fallback
    |       +-- .image: file representation (PNG from disk)
    |       +-- .file: NSURL (file URL)
    |
    v
macOS drag session (window server managed)
    |
    +-- Panel stays visible (hidesOnDeactivate = false)
    +-- User drags to target app
    +-- Drop: target app receives NSItemProvider data
    +-- Cancel: nothing happens, panel remains
```

### Import/Export Flow (New)

```
Export:
    User clicks "Export..." in Settings
        |
        v
    NSSavePanel -> user picks location
        |
        v
    ImportExportService.exportAll(modelContext:)
        |-- Fetch all Labels
        |-- Fetch all ClipboardItems (exclude concealed)
        |-- For image items: read from disk, Base64-encode
        |-- Encode to JSON
        |
        v
    Write .pastel file to disk

Import:
    User clicks "Import..." in Settings
        |
        v
    NSOpenPanel -> user picks .pastel file
        |
        v
    ImportExportService.importFromData(_:modelContext:)
        |-- Decode JSON
        |-- Version check
        |-- Import labels: match by name or create new
        |-- Import items: skip if contentHash exists (dedup)
        |-- For image items: decode Base64, save via ImageStorageService
        |-- Save in batches of 500
        |-- Update clipboardMonitor.itemCount
        |
        v
    Show result summary (X imported, Y skipped, Z labels)
```

---

## New vs Modified Components Summary

### New Components

| Component | Type | File | Purpose |
|-----------|------|------|---------|
| `AppFilterService` | @MainActor @Observable | `Services/AppFilterService.swift` | Allow/ignore list logic + persistence |
| `AppFilterSettingsView` | SwiftUI View | `Views/Settings/AppFilterSettingsView.swift` | App filter UI (mode toggle + app list) |
| `ImportExportService` | @MainActor service | `Services/ImportExportService.swift` | Export/import with Codable mapping |

### Modified Components

| Component | File | Change | Lines |
|-----------|------|--------|-------|
| `ClipboardCardView` | `Views/Panel/ClipboardCardView.swift` | Context menu + .onDrag | ~50 lines |
| `FilteredCardListView` | `Views/Panel/FilteredCardListView.swift` | Shift+Enter, Shift+double-click | ~15 lines |
| `ClipboardMonitor` | `Services/ClipboardMonitor.swift` | App filter check in checkForChanges | ~10 lines |
| `AppState` | `App/AppState.swift` | Wire AppFilterService + ImportExportService | ~10 lines |
| `GeneralSettingsView` | `Views/Settings/GeneralSettingsView.swift` | Export/Import buttons | ~30 lines |
| `SettingsView` | `Views/Settings/SettingsView.swift` | Add apps tab | ~5 lines |
| `PanelController` | `Views/Panel/PanelController.swift` | Drag compat (if needed) | ~5 lines |

### Unchanged Components

| Component | Why Unchanged |
|-----------|---------------|
| `PasteService` | Already has full plain text support; no new paste logic |
| `SlidingPanel` | Panel config already supports drag sessions |
| `ImageStorageService` | Used as-is for import image saving |
| `RetentionService` | No retention changes |
| `ExpirationService` | Unrelated to v1.3 features |
| All card subviews | No rendering changes |
| `Label`, `LabelColor`, `ContentType` | No model changes |
| `ChipBarView`, `SearchFieldView` | No interaction changes |
| `HistoryBrowserView`, `HistoryGridView` | No changes (drag-and-drop is panel-only for v1.3) |
| `EditItemView` | No changes |

---

## Suggested Build Order

Based on dependency analysis, complexity, and risk:

### Phase 1: Paste-as-Plain-Text UI

**Why first:**
- Zero dependencies on other v1.3 features
- All infrastructure already exists (PasteService.pastePlainText)
- Pure UI wiring task -- smallest scope, fastest to ship
- Low risk -- proven patterns (modifier key checks)
- Immediately useful

**Scope:** ~25 lines across 2 files

### Phase 2: App Allow/Ignore Lists

**Why second:**
- Independent of other features
- New service + settings view is moderate complexity
- User-facing privacy feature that should land before import/export (users want to configure filtering before importing large histories)
- Requires testing with real apps

**Scope:** ~200 lines across 4-5 files (2 new, 2-3 modified)

### Phase 3: Import/Export

**Why third:**
- Independent of other features but benefits from app filtering being done first (exported data respects user preferences)
- Most complex new feature (Codable mapping, batch insert, image encoding)
- Requires careful error handling and edge case testing
- Benefits from the two simpler phases being done first to warm up

**Scope:** ~400 lines across 2-3 files (1 new service, 1-2 modified views)

### Phase 4: Drag-and-Drop from Panel

**Why last:**
- Has the most uncertainty (NSPanel + drag session interaction)
- Potential gesture conflict with existing tap handlers
- Requires manual testing that cannot be automated
- If gesture conflicts arise, solutions may require refactoring gesture attachment points
- Least critical of the four features (users have copy+paste as alternative)

**Scope:** ~80 lines across 1-2 files, but higher testing overhead

### Parallel Build Opportunities

Phases 1 and 2 can be built in parallel -- they touch completely different files:
- Phase 1: ClipboardCardView, FilteredCardListView
- Phase 2: ClipboardMonitor, AppState, SettingsView, new AppFilterService + AppFilterSettingsView

Phase 3 (import/export) is independent and could theoretically parallel with Phase 2, but they both modify AppState and GeneralSettingsView, so sequential is safer.

Phase 4 (drag-and-drop) modifies ClipboardCardView which Phase 1 also touches, so it must come after Phase 1.

**Recommended order:** Phase 1 -> (Phase 2 can parallel) -> Phase 3 -> Phase 4

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Filtering in processPasteboardContent Instead of checkForChanges

**What:** Checking the app filter after content classification and before SwiftData insert.
**Why bad:** Unnecessary work -- reads pasteboard data, classifies content type, computes hash, all to discard the result. For ignore-listed apps that copy frequently (e.g., a terminal with rapid clipboard changes), this wastes CPU cycles on every poll tick.
**Instead:** Filter in `checkForChanges()` before entering `processPasteboardContent()`.

### Anti-Pattern 2: Using .draggable(String) for External Drag

**What:** Using SwiftUI's `.draggable("text content")` for dragging to external apps.
**Why bad:** `.draggable` with String only provides `UTType.plainText`. External apps that accept images, URLs, or rich text will not get the correct content type. No way to provide multiple representations.
**Instead:** Use `.onDrag { NSItemProvider(...) }` with explicit type registration per content type.

### Anti-Pattern 3: Storing Image Data in SwiftData for Export

**What:** Loading image data into a SwiftData field (e.g., `imageExportData: Data?`) before export.
**Why bad:** Bloats the database. Images are already on disk. Loading all images into memory for export can cause memory spikes.
**Instead:** Read images from disk during export, Base64-encode them directly into the JSON, and write to file. Stream if possible.

### Anti-Pattern 4: SwiftUI .fileExporter for One-Shot Export

**What:** Using SwiftUI's `.fileExporter(isPresented:document:)` modifier.
**Why bad:** Requires conforming to `FileDocument` protocol, which expects a read-write document lifecycle. Export is a one-shot operation -- there is no "document" to open and edit. The protocol machinery adds unnecessary complexity.
**Instead:** Use NSSavePanel directly. The app is not sandboxed, so NSSavePanel works without security-scoped bookmarks.

### Anti-Pattern 5: Re-Implementing Paste-as-Plain-Text Logic

**What:** Creating new paste methods or duplicating pasteboard write logic for the context menu.
**Why bad:** PasteService.pastePlainText already exists and is fully wired through AppState and PanelActions. Adding new code paths creates maintenance burden and potential for divergent behavior.
**Instead:** Call the existing `panelActions.pastePlainTextItem?(item)` callback from the new context menu item. One line.

### Anti-Pattern 6: Complex Drag State Tracking

**What:** Building an elaborate system to track drag session state (started, moved, ended, cancelled) to coordinate with PanelController.
**Why bad:** Over-engineering. SwiftUI's `.onDrag` does not provide reliable lifecycle callbacks. NSPanel with `hidesOnDeactivate = false` already handles the common case.
**Instead:** Accept that the panel stays visible during and after drag. Users dismiss it via Escape or hotkey toggle. If testing reveals the global click monitor hiding the panel during drag, add a simple flag -- but don't build the infrastructure until the problem is confirmed.

---

## Sources

- Direct source code analysis of all Pastel Swift files (HIGH confidence)
- [Maccy clipboard manager -- app filtering implementation](https://github.com/p0deje/Maccy/blob/master/Maccy/Clipboard.swift) -- shouldIgnore pattern with allow/ignore mode toggle
- [Maccy -- lightweight clipboard manager for macOS](https://github.com/p0deje/Maccy) -- reference for app filtering UX
- [SwiftUI drag and drop on macOS](https://eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more/) -- DropDelegate and NSItemProvider patterns
- [SwiftUI .onDrag conflicts with clicks on macOS](https://www.hackingwithswift.com/forums/swiftui/ondrag-conflicts-with-clicks-on-macos/8020) -- known gesture conflicts
- [Drag and Drop in SwiftUI](https://swiftwithmajid.com/2020/04/01/drag-and-drop-in-swiftui/) -- NSItemProvider patterns
- [SwiftUI Open and Save Panels](https://www.swiftdevjournal.com/swiftui-open-and-save-panels/) -- NSSavePanel/NSOpenPanel in SwiftUI apps
- [SwiftData batch insert](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-batch-insert-large-amounts-of-data-efficiently) -- batch import best practices
- [SwiftData Codable conformance](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-make-swiftdata-models-conform-to-codable) -- model serialization
- [NSRunningApplication bundleIdentifier](https://developer.apple.com/documentation/appkit/nsrunningapplication/bundleidentifier) -- returns nil for apps without Info.plist
- [NSPasteboard.org -- transient and concealed types](http://nspasteboard.org/) -- special pasteboard type conventions
