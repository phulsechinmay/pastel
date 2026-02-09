# Feature Research: v1.3 Power User Features

**Domain:** macOS Clipboard Manager (paste-as-plain-text, app filtering, import/export, drag-and-drop)
**Project:** Pastel
**Researched:** 2026-02-09
**Confidence:** MEDIUM-HIGH (paste-as-plain-text and app filtering are well-established patterns; import/export has no ecosystem standard; drag-and-drop from NSPanel has specific technical constraints)

> **Scope:** This document covers v1.3 features only: paste-as-plain-text UI expansion (PAST-20), allow/ignore app lists (PRIV-01), import/export (DATA-01), and drag-and-drop from panel (HIST-02). For earlier feature research, see git history.

---

## 1. Paste as Plain Text (PAST-20)

### What Already Exists in Pastel

Pastel already has the core plain-text paste mechanism fully built:

- **PasteService.pastePlainText()** -- Strips RTF data from the pasteboard write, keeping only `.string` and `.html` types. Receiving apps fall back to their default text styling.
- **PasteService.writeToPasteboardPlainText()** -- For non-text types (URL, image, file), delegates to normal write since they have no RTF to strip.
- **Cmd+Shift+1-9** -- Quick paste hotkeys with Shift modifier already paste as plain text (Phase 9, PAST-10b).
- **PanelActions.pastePlainTextItem** -- The SwiftUI-to-AppKit bridge for plain text paste exists and is wired through PanelContentView -> FilteredCardListView -> AppState.

**What is missing (PAST-20 scope):**
1. Context menu "Paste as Plain Text" option
2. Shift+Enter keyboard shortcut for plain text paste of the selected item
3. Shift+double-click mouse interaction for plain text paste

### How Competitors Handle Plain Text Paste

| Manager | Context Menu | Keyboard Shortcut | Mouse Modifier | Source |
|---------|-------------|-------------------|----------------|--------|
| Paste (pasteapp.io) | "Paste as Plain Text" in right-click menu | Shift held during paste | N/A | [Paste Help Center](https://pasteapp.io/help/paste-on-mac) (MEDIUM) |
| PastePal | "Paste as Plain/Rich Text" toggle in context menu | N/A documented | N/A | [PastePal review](https://macsources.com/pastepal-clipboard-manager-for-macos-review/) (MEDIUM) |
| Maccy | N/A (paste-only menu) | Option+Shift+Enter | N/A | [Maccy README](https://github.com/p0deje/Maccy/blob/master/README.md) (HIGH) |
| ClipTools | N/A | Control+Shift during paste | N/A | [ClipTools guide](https://macmost.com/cliptools-using-the-clipboard-manager-functions.html) (MEDIUM) |
| macOS native | Edit > Paste and Match Style | Cmd+Shift+Option+V | N/A | Apple standard (HIGH) |

**Key pattern:** The dominant UX convention across the ecosystem is using a modifier key (Shift) combined with the normal paste trigger. Pastel's proposed Shift+Enter and Shift+double-click follow this convention naturally. The context menu option is table stakes -- every major clipboard manager with a context menu includes a plain text paste variant.

### Expected Behavior from User's Perspective

**Context menu "Paste as Plain Text":**
- Appears alongside existing "Paste" option in the right-click menu
- Strips all formatting (RTF, HTML styles) and pastes only raw text
- For non-text items (images, files), this option should either be disabled/hidden or behave identically to normal paste (since there is no formatting to strip)
- User expectation: the item is pasted into the frontmost app immediately, panel closes

**Shift+Enter:**
- When a card is selected via keyboard navigation (arrow keys), pressing Shift+Enter pastes it as plain text
- Without Shift, Enter pastes with original formatting (existing behavior)
- User expectation: instant muscle memory -- "Enter = paste, Shift+Enter = paste plain"

**Shift+double-click:**
- When double-clicking a card while holding Shift, paste as plain text
- Without Shift, double-click pastes with original formatting (existing behavior)
- User expectation: same modifier convention as Shift+Enter, but for mouse users

### Edge Cases to Consider

| Edge Case | Expected Behavior | Notes |
|-----------|-------------------|-------|
| Shift+Enter on an image item | Normal paste (no formatting to strip) | PasteService already handles this: `writeToPasteboardPlainText` delegates to `writeToPasteboard` for non-text types |
| Shift+Enter on a URL item | Paste URL string as plain text (no link formatting) | Already handled by PasteService |
| Shift+Enter on a code item | Paste code as plain text (no syntax highlighting, just raw text) | Code items are stored as `.string` -- stripping RTF has no extra effect, which is correct |
| Shift+Enter on a color item | Paste color string as plain text | Color items are plain strings already |
| Shift+double-click when Shift was held before click | Must detect Shift modifier at time of gesture | NSEvent.modifierFlags check |
| Context menu "Paste as Plain Text" on concealed item | Should still work -- concealed items have text content | No special handling needed |
| Shift+Enter when no card is selected | Ignore (no-op) | Same as Enter when no card selected |

### Integration with Existing Pastel Patterns

**Context menu addition is straightforward:** The existing context menu in `ClipboardCardView` already has "Copy", "Paste", "Copy + Paste". Adding "Paste as Plain Text" after "Paste" is a one-line addition using the existing `panelActions.pastePlainTextItem` callback.

**Shift+Enter in FilteredCardListView:** The existing `.onKeyPress(.return)` handler calls `onPaste(filteredItems[index])`. Adding a Shift modifier check to route to `onPastePlainText` is clean:

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

**Shift+double-click requires gesture modifier detection:** The current `.onTapGesture(count: 2)` in FilteredCardListView does not receive modifier flags. Two approaches:
1. Use `NSEvent.modifierFlags.contains(.shift)` at the time of the tap (check global modifier state)
2. Replace `onTapGesture` with a custom gesture that captures modifiers via `NSEvent.addLocalMonitorForEvents`

Approach 1 is simpler and sufficient -- Pastel already tracks `isShiftHeld` state via a flags monitor in PanelContentView and passes it to FilteredCardListView.

### Complexity Assessment

**LOW.** All infrastructure exists. This is wiring existing `pastePlainText` capability to three additional trigger points (context menu, Shift+Enter, Shift+double-click).

---

## 2. Allow/Ignore App Lists (PRIV-01)

### How Competitors Implement App Filtering

**Three distinct models exist in the ecosystem:**

#### Model 1: Ignore List (Blocklist) -- Most Common

Apps on the ignore list are excluded from clipboard monitoring. Everything else is captured.

| Manager | UI | Granularity | Default | Source |
|---------|-----|------------|---------|--------|
| Maccy | Preferences > Ignore > Add app | By bundle ID | Ignore 1Password, TypeIt4Me | [Maccy README](https://github.com/p0deje/Maccy/blob/master/README.md) (HIGH) |
| Paste | Settings > Exclude apps | By app | None | [Paste review](https://josephnilo.com/blog/paste-setapp-review/) (MEDIUM) |
| CopyClip 2 | Settings > Excluded apps | By app | None | WebSearch (MEDIUM) |
| BetterTouchTool | Clipboard settings | By app | None | [BTT forum](https://community.folivora.ai/t/exclude-apps-from-clipboard-manager-passwords/16601) (MEDIUM) |

#### Model 2: Allow List (Whitelist) -- Rare

Only apps on the allow list have their clipboard content captured. Everything else is ignored.

No major macOS clipboard manager uses this model by default. It is too restrictive for the general use case -- users copy from dozens of apps daily and maintaining a comprehensive allow list is burdensome.

#### Model 3: Dual Mode (Ignore + Allow) -- Ideal

User chooses between "monitor all except ignored" (default) or "monitor only allowed apps." Provides maximum flexibility.

No surveyed macOS clipboard manager currently offers this dual mode, but it is the logical evolution. Android clipboard managers (via LSPosed modules) support this pattern.

### Recommended Model for Pastel: Ignore List with Optional Allow List

**Primary mode: Ignore list (blocklist).** This matches user expectations and competitor norms. Default behavior remains "capture everything" -- the ignore list is opt-in.

**Secondary mode (stretch goal): Allow list.** Some power users in security-sensitive environments want the inverse: "only capture from these specific apps." This can be a settings toggle: "Monitor: All apps except ignored / Only allowed apps."

### Implementation: How It Works Technically

**Pastel already captures source app bundle ID.** In `ClipboardMonitor.processPasteboardContent()`:

```swift
let sourceApp = NSWorkspace.shared.frontmostApplication
let sourceAppBundleID = sourceApp?.bundleIdentifier
```

The ignore check must happen BEFORE content processing:

```swift
func checkForChanges() {
    guard isMonitoring else { return }
    // ... changeCount check ...

    // App filter check (NEW)
    let sourceApp = NSWorkspace.shared.frontmostApplication
    if let bundleID = sourceApp?.bundleIdentifier,
       isAppIgnored(bundleID) {
        return  // Skip this clipboard change entirely
    }

    processPasteboardContent()
}
```

**Important caveat (from Maccy issue #1072):** `NSWorkspace.shared.frontmostApplication` returns the currently active/frontmost app, which is NOT always the app that wrote to the clipboard. A background app (e.g., a script using `pbcopy`) can modify the clipboard while a different app is frontmost. This is a known limitation that Maccy also faces. For Pastel's use case (ignoring password managers, banking apps), this is acceptable because:
1. Password managers are typically frontmost when copying credentials
2. The false negative rate (capturing content that should be ignored) is very low
3. The alternative (no source identification at all via NSPasteboard API) would mean no app filtering is possible

### Settings UI Pattern

**How to build the app picker:**

| Approach | UX | Complexity | Competitors Use |
|----------|-----|-----------|----------------|
| Drag app from Finder / Applications | Natural macOS UX | MEDIUM (file drop zone) | Paste |
| Browse /Applications with file picker | Standard but clunky | LOW (NSOpenPanel) | Some |
| Running apps list with toggle | Shows only running apps | LOW | None surveyed |
| Running applications picker via NSWorkspace | List all installed apps | MEDIUM | Maccy (sort of -- uses defaults command) |

**Recommended approach:** A list in Settings showing currently ignored/allowed apps with an "Add App..." button that opens an NSOpenPanel pointed at `/Applications`. When the user selects an app bundle, extract its `bundleIdentifier` and `localizedName`. Display apps in the list with their icon (via `NSWorkspace.shared.icon(forFile:)`), name, and bundle ID.

**Additionally, offer a context menu shortcut from the clipboard panel:** When right-clicking a clipboard card, add "Ignore [Source App Name]" to the context menu. This lets users block an app directly from the card that triggered the annoyance. This is a UX pattern no surveyed competitor offers and would be a genuine differentiator.

### Data Model

```swift
// Stored in UserDefaults as an array of bundle IDs
@AppStorage("ignoredAppBundleIDs") private var ignoredAppsData: Data = Data()
// OR stored as a simple [String] in UserDefaults:
// defaults: ["com.1password.1password", "com.bitwarden.desktop"]
```

Using UserDefaults (not SwiftData) because:
1. The ignore list is small (typically 2-5 apps)
2. It is checked on every clipboard poll (0.5s) -- must be fast
3. It is app configuration, not user data
4. Does not need to be part of import/export (app-specific preference)

### Edge Cases

| Edge Case | Expected Behavior | Notes |
|-----------|-------------------|-------|
| User ignores the app they are currently using | Next copy from that app is skipped | No special handling |
| Copy via `pbcopy` in Terminal | Attributed to Terminal.app (or whatever is frontmost) | If Terminal is ignored, pbcopy clips are also ignored. Acceptable tradeoff |
| Universal Clipboard (copy on iPhone, paste on Mac) | Attributed to... nothing? Check frontmost app | May need `com.apple.is-remote-clipboard` pasteboard type check like Maccy |
| User removes an app from ignore list | Future copies are captured again; past captures remain as-is | No retroactive changes |
| Ignored app copies concealed content | Double-skip: both concealed AND ignored | Concealed check happens in classifyContent(); app check happens before that |
| Empty bundle ID (rare: some system processes) | Captured (not ignored) | Nil bundle ID should pass the ignore check |

### Pre-populated Defaults

**Recommended default ignore list:** Empty. Users should opt in to ignoring apps. However, display a helpful hint: "Consider adding password managers (1Password, Bitwarden) for privacy."

**Why not pre-populate?** Password managers already use `org.nspasteboard.ConcealedType` which Pastel respects (captures with auto-expiry after 60s). Pre-ignoring them would mean users lose the ability to re-paste a recently copied password, which some users actually want.

### Complexity Assessment

**MEDIUM.** Requires a new Settings section with app picker UI, a check in the clipboard monitoring hot path, and context menu integration. No model changes needed.

---

## 3. Import/Export (DATA-01)

### The Current Landscape: No Standard Format

**No macOS clipboard manager has established a standard import/export format.** This is a genuine gap in the ecosystem:

| Manager | Export? | Format | Import? | Source |
|---------|---------|--------|---------|--------|
| Maccy | No | N/A | No | [Maccy GitHub](https://github.com/p0deje/Maccy) (HIGH) |
| Paste | No (iCloud sync only) | Proprietary | No | WebSearch (MEDIUM) |
| PastePal | No (iCloud sync only) | Proprietary | No | [PastePal App Store](https://apps.apple.com/us/app/clipboard-manager-pastepal/id1503446680) (MEDIUM) |
| CopyClip | No | N/A | No | WebSearch (LOW) |
| CleanClip | No documented export | N/A | No | WebSearch (LOW) |
| Alfred Clipboard | Archive script (community) | JSON + files | No native import | [Alfred Gist](https://gist.github.com/pirate/6551e1c00a7c4b0c607762930e22804c) (MEDIUM) |
| PasteBar | Local storage only | N/A | No | WebSearch (LOW) |

**Key insight:** Since there is no standard, Pastel can define its own format. The goal is extensibility (could later support importing from other managers) and human-readability (JSON over binary).

### Recommended Format: .pastel Bundle (Directory)

A `.pastel` export is a directory bundle (like .app or .rtfd) containing:

```
export_2026-02-09.pastel/
    manifest.json          -- Metadata, version, item count
    items.json             -- Array of clipboard item records
    images/                -- Referenced image files
        <uuid>.png
        <uuid>_thumb.png
    favicons/              -- URL metadata images
        <uuid>_favicon.png
    previews/              -- og:image previews
        <uuid>_preview.png
```

**manifest.json:**
```json
{
    "format": "pastel-export",
    "version": 1,
    "exportDate": "2026-02-09T14:30:00Z",
    "appVersion": "1.3.0",
    "itemCount": 142,
    "imageCount": 23,
    "labelCount": 5
}
```

**items.json:**
```json
{
    "labels": [
        {
            "id": "uuid-string",
            "name": "Work",
            "colorName": "blue",
            "emoji": null,
            "sortOrder": 0
        }
    ],
    "items": [
        {
            "textContent": "Hello world",
            "htmlContent": null,
            "rtfData": null,
            "contentType": "text",
            "timestamp": "2026-02-09T14:25:00Z",
            "sourceAppBundleID": "com.apple.Safari",
            "sourceAppName": "Safari",
            "characterCount": 11,
            "byteCount": 11,
            "imagePath": null,
            "thumbnailPath": null,
            "isConcealed": false,
            "contentHash": "abc123...",
            "title": "My greeting",
            "labelIDs": ["uuid-string"],
            "detectedLanguage": null,
            "detectedColorHex": null,
            "urlTitle": null,
            "urlFaviconPath": null,
            "urlPreviewImagePath": null
        }
    ]
}
```

**Why a directory bundle, not a single file:**
- Images cannot be efficiently embedded in JSON (base64 bloats by 33%)
- A zip of the directory can be offered as a secondary option for sharing
- macOS treats directory bundles as single items in Finder (good UX)
- Separation of concerns: metadata in JSON, binary assets in their own directory

### Export UX

**Trigger:** Settings > General (or Data section) > "Export History..." button

**Flow:**
1. User clicks "Export History..."
2. NSSavePanel appears with default filename `Pastel Export YYYY-MM-DD.pastel`
3. Optional: filter dialog (export all, export labeled only, export date range)
4. Progress indicator during export (may take seconds for large histories with images)
5. Success confirmation with file size

**Scope options for export:**
| Scope | Complexity | Value |
|-------|-----------|-------|
| Export all items | LOW | Baseline |
| Export labeled items only | LOW | Users who organized items probably want those |
| Export date range | MEDIUM | Less useful -- retention handles age-based cleanup |
| Export specific labels | MEDIUM | Power user feature |

**Recommendation:** Start with "Export all" and "Export labeled items only." Date range and label-specific export are stretch goals.

### Import UX

**Trigger:** Settings > General (or Data section) > "Import..." button

**Flow:**
1. User clicks "Import..."
2. NSOpenPanel with file type filter for `.pastel` bundles
3. Preview: show item count, label count, date range of import
4. Conflict resolution dialog: "X items already exist in your history. Skip duplicates? / Import all?"
5. Progress indicator
6. Success summary: "Imported 95 items, 3 labels, skipped 47 duplicates"

**Conflict resolution strategy:**
- Use `contentHash` for deduplication (already exists on all items)
- If hash matches: skip (item already exists)
- If hash does not match: import as new item
- Labels: merge by name. If a label with the same name exists, reuse it. If not, create it.
- Images: copy to Pastel's image storage directory with new UUIDs to avoid filename conflicts

### Edge Cases

| Edge Case | Expected Behavior | Notes |
|-----------|-------------------|-------|
| Import from different machine (different image paths) | Images should be portable (bundled in export) | Image paths in items.json reference files within the bundle, not absolute paths |
| Import items with labels that do not exist locally | Create the labels during import | Match by name first, create if new |
| Import items with labels that exist locally (same name, different color) | Reuse existing local label | Name match takes precedence over color |
| Export includes concealed items | Export them (user chose to export) | But warn: "X concealed items included" |
| RTF data in export | Store as base64 string in items.json | RTF is binary Data, needs encoding |
| Corrupt .pastel bundle (missing manifest, bad JSON) | Graceful error: "Invalid export file" | Validate manifest version before processing |
| Export during active clipboard monitoring | Safe -- reads from SwiftData, not pasteboard | No race conditions |
| Import triggers duplicate detection in ClipboardMonitor | No -- import uses modelContext.insert directly, not the pasteboard | No skipNextChange needed |
| Very large export (10K+ items, 500+ images) | Show progress bar, use background task | May take 10-30 seconds |

### Future Extensibility: Importing from Other Managers

The format version field (`"version": 1`) allows for format evolution. A future `"version": 2` could add fields without breaking v1 imports. The manifest's `"format"` field could later support `"maccy-export"` or `"paste-export"` if we want to build importers for other managers' data.

**Maccy's data:** SQLite database at `~/Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite`. Text-only (no images). Could be imported by reading the SQLite directly.

**This is a v2+ concern.** For v1.3, focus on Pastel's own format.

### Complexity Assessment

**MEDIUM-HIGH.** Requires:
- JSON serialization/deserialization of the full data model
- File system operations (directory creation, image copying)
- NSSavePanel / NSOpenPanel integration
- Conflict resolution logic
- Progress reporting for large exports
- Error handling for corrupt imports

This is the most complex of the four v1.3 features.

---

## 4. Drag-and-Drop from Panel (HIST-02)

### How Competitors Implement Drag from Clipboard Manager

| Manager | Drag Support | Target | Content | Source |
|---------|-------------|--------|---------|--------|
| Pasta | Drag clippings to other apps | Any app | Text and files | [Pasta App Store](https://apps.apple.com/us/app/pasta-clipboard-manager/id1438389787?mt=12) (MEDIUM) |
| PasteNow | Drag and drop from list | Any app | Text, images, files | [PasteNow](https://pastenow.app/) (MEDIUM) |
| PastePal | Drag from sidebar | Any app | Text, images, files | [PastePal review](https://macsources.com/pastepal-clipboard-manager-for-macos-review/) (MEDIUM) |
| Clipboard Manager (App Store) | Quick panel drag | Any app | Various | [App Store listing](https://apps.apple.com/us/app/clipboard-manager/id1116697975) (LOW) |
| Maccy | No drag support | N/A | N/A | [Maccy GitHub](https://github.com/p0deje/Maccy) (HIGH) |

**Key finding:** Drag-and-drop is a differentiator, not table stakes. Maccy (the most popular free clipboard manager) does not support it. But premium managers (Pasta, PasteNow, PastePal) all do.

### Technical Implementation: SwiftUI .onDrag + NSItemProvider

**The standard SwiftUI approach:**

```swift
ClipboardCardView(item: item, ...)
    .onDrag {
        // Create NSItemProvider with appropriate content
        switch item.type {
        case .text, .richText, .code, .color:
            return NSItemProvider(object: (item.textContent ?? "") as NSString)
        case .url:
            if let urlString = item.textContent, let url = URL(string: urlString) {
                return NSItemProvider(object: url as NSURL)
            }
            return NSItemProvider(object: (item.textContent ?? "") as NSString)
        case .image:
            if let imagePath = item.imagePath {
                let imageURL = ImageStorageService.shared.resolveImageURL(imagePath)
                return NSItemProvider(contentsOf: imageURL) ?? NSItemProvider()
            }
            return NSItemProvider()
        case .file:
            if let filePath = item.textContent {
                let fileURL = URL(fileURLWithPath: filePath)
                return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
            }
            return NSItemProvider()
        }
    }
```

### Critical Technical Concern: NSPanel + Drag Interaction

**Pastel's panel is a non-activating NSPanel.** This creates a specific challenge for drag-and-drop:

1. **Non-activating panels do not steal focus.** This is essential for paste-back (the frontmost app stays focused so Cmd+V reaches it). But during drag, the user needs to:
   - Start the drag in the panel
   - Move the cursor to another app's window
   - Drop the content

2. **The panel may dismiss when the cursor leaves.** Pastel currently installs a global click monitor that hides the panel on clicks outside it. During a drag operation, the user's cursor leaves the panel area and enters another app's window. If the panel dismisses mid-drag, the drag data may be lost.

**Solutions:**

| Approach | Description | Complexity |
|----------|-------------|-----------|
| Suppress dismiss during drag | Detect drag start (via `.onDrag`), disable the global click monitor until drag ends | MEDIUM |
| Keep panel visible during drag | Do not auto-dismiss on focus loss during drag | LOW (flag toggle) |
| Let panel dismiss, preserve drag | NSItemProvider retains data even after source view disappears (OS manages drag data) | LOW (test needed) |

**Recommended approach:** Option 3 is the simplest and likely works. Once `.onDrag` creates the `NSItemProvider`, macOS takes ownership of the drag data. The panel can dismiss and the drag should still complete. However, this needs testing -- if the NSItemProvider references a file URL (for images), the file must still exist when the drop completes.

**Testing priority:** Verify that `NSItemProvider` drag data survives the source view (panel) being dismissed. If it does not survive, fall back to Option 1 (suppress dismiss during active drag).

### Content Type Mapping for Drag

| Pastel Content Type | NSItemProvider Object | UTType | Receiving App Gets |
|--------------------|-----------------------|--------|-------------------|
| .text | NSString | public.plain-text | Plain text |
| .richText | NSString (+ optionally NSAttributedString with RTF) | public.plain-text / public.rtf | Text with optional formatting |
| .url | NSURL | public.url | URL (clickable in supporting apps) |
| .image | NSItemProvider(contentsOf: imageFileURL) | public.image | Image data |
| .file | NSItemProvider(contentsOf: fileURL) | public.file-url | File reference |
| .code | NSString | public.plain-text | Code as plain text |
| .color | NSString | public.plain-text | Color string (e.g., "#FF5733") |

**Rich text drag (stretch goal):** For `.richText` items that have `rtfData`, the drag could provide both plain text and RTF representations. This allows RTF-aware apps (TextEdit, Pages) to receive formatted text while plain-text apps get the fallback. Implementation uses `NSItemProvider.registerDataRepresentation(forTypeIdentifier:)` with multiple UTTypes.

### Drag Preview

SwiftUI's `.onDrag` supports an optional preview parameter (macOS 13+):

```swift
.onDrag {
    NSItemProvider(object: text as NSString)
} preview: {
    Text(text)
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(6)
}
```

**Recommendation:** Show a compact preview during drag -- text snippet for text items, thumbnail for images, URL for URLs. This gives users visual feedback about what they are dragging.

### Edge Cases

| Edge Case | Expected Behavior | Notes |
|-----------|-------------------|-------|
| Drag an image item whose file was deleted (retention cleanup) | Drag fails gracefully (empty provider) | Check file existence before creating provider |
| Drag a file reference to a file that no longer exists | Drop delivers the path string, but target app cannot open it | Show visual indicator that file path may be stale |
| Drag a concealed item | Allow drag (user explicitly initiated it) | No special handling |
| Drag during horizontal panel layout (top/bottom edge) | Must work in both orientations | `.onDrag` is view-level, orientation-independent |
| Drag multiple items (multi-select + drag) | NOT required for v1.3 | Multi-drag is complex; defer to v2 |
| Drag from History Browser (Settings window) | Would be nice but NOT required | History grid uses same card views; could share drag logic |

### Integration with Existing Panel Behavior

**Panel auto-dismiss:** The panel currently hides on any global click outside it. A drag gesture starts inside the panel but the cursor moves outside. Two scenarios:
1. **Drag stays within panel bounds:** No issue. Normal drag within the panel (this is not the use case -- we want drag TO other apps).
2. **Drag moves outside panel:** Global click monitor fires when cursor enters another app. Panel may hide. The drag data needs to survive.

**Panel keyboard dismiss (Escape):** If user starts a drag then presses Escape, panel should dismiss and drag should cancel. This is the default macOS behavior.

**Panel toggle hotkey during drag:** If user presses the panel toggle hotkey (Cmd+Shift+V) during a drag, panel hides. Drag data should survive (same as auto-dismiss case).

### Complexity Assessment

**MEDIUM.** SwiftUI's `.onDrag` handles most of the heavy lifting. The main complexity is:
1. Creating correct NSItemProvider for each content type
2. Testing interaction with NSPanel dismiss behavior
3. Optional: drag preview customization
4. Edge case handling for missing files

---

## Feature Landscape Summary

### Table Stakes (Users Expect These)

Features users assume exist or will expect once they see the v1.3 changelog.

| Feature | Why Expected | Complexity | Integration Notes |
|---------|--------------|------------|-------------------|
| Context menu "Paste as Plain Text" | Every competitor with a context menu has this | LOW | Add to existing context menu in ClipboardCardView |
| Shift+Enter for plain text paste | Natural modifier convention (Shift = plain variant) | LOW | Modify existing .onKeyPress(.return) handler |
| Ignore app list in Settings | Paste, Maccy, CopyClip 2 all offer this | MEDIUM | New Settings section + ClipboardMonitor check |
| Ignore password managers specifically | Primary use case for app filtering | LOW | Part of ignore list; default hint in UI |
| Export clipboard history | Data portability is a user right; users expect backup | MEDIUM-HIGH | New file format, NSSavePanel, serialization |
| Import clipboard history | Restore from backup completes the export story | MEDIUM-HIGH | NSOpenPanel, deserialization, conflict resolution |

### Differentiators (Competitive Advantage)

Features that set Pastel apart from competitors.

| Feature | Value Proposition | Complexity | Integration Notes |
|---------|-------------------|------------|-------------------|
| Shift+double-click for plain text paste | No competitor offers modifier-click for plain text | LOW | Modifier detection in tap gesture |
| "Ignore [App Name]" from card context menu | No competitor offers in-context ignore | LOW | Read sourceAppBundleID from the card's item |
| Allow list mode (monitor only specific apps) | No macOS clipboard manager offers dual mode | LOW | Settings toggle; inverse of ignore logic |
| Drag-and-drop items to other apps | Only premium managers support this; Maccy does not | MEDIUM | .onDrag on card views |
| Drag preview with content snippet | Visual feedback during drag | LOW | .onDrag preview parameter |
| Extensible export format (versioned JSON) | Future-proofs for cross-manager import | LOW | Built into format design |
| Export with label preservation | No competitor exports organized history | MEDIUM | Part of export format |
| Import with duplicate detection via hash | Smart merge, not blind append | MEDIUM | Use existing contentHash |

### Anti-Features (Things to Deliberately NOT Build)

| Feature | Why It Seems Appealing | Why Problematic | Alternative |
|---------|----------------------|-----------------|-------------|
| Auto-detect sensitive apps (heuristic) | "Automatically ignore password managers!" | False negatives for lesser-known managers; false positives for legitimate apps; ConcealedType already handles this for compliant apps | Manual ignore list + existing ConcealedType handling |
| iCloud sync for clipboard history | "Sync between my Macs!" | Massive complexity: conflict resolution, storage costs, privacy concerns. Apple's Universal Clipboard handles basic cross-device | Export/import for manual transfer between machines |
| Import from other clipboard managers (v1.3) | "Let me switch from Maccy easily!" | Each manager has a different storage format; reverse-engineering proprietary formats is fragile | Define Pastel's own format first; add importers in v2+ |
| Drag multiple items at once | "I want to drag 5 items to a text editor!" | Multi-drag UX is confusing (what order? concatenated or separate?); SwiftUI multi-drag support is limited | Single item drag in v1.3; multi-drag in v2 |
| Export as CSV / plain text | "I want my clipboard history in a spreadsheet!" | Lossy: cannot preserve images, RTF, labels, metadata | JSON-based .pastel format preserves everything; users can extract text from JSON if needed |
| Global "paste as plain text" hotkey (outside panel) | "I want Cmd+Shift+V to ALWAYS paste plain text, even without the panel!" | Conflicts with macOS system shortcuts and other apps; fundamentally different feature (system-wide text processing) | In-panel plain text paste covers the primary use case |
| Real-time ignore/allow (mid-capture cancel) | "If I copy from an ignored app, undo the capture in progress" | Capture is atomic (0.5s poll interval); by the time we detect the copy, it's already a complete operation | Check ignore list before processing (which we do) |
| Encrypted export | "Encrypt my clipboard export for security!" | Adds key management complexity; users have FileVault for disk encryption | Rely on macOS FileVault and user's own file security practices |

---

## Feature Dependencies

```
[Paste as Plain Text UI (PAST-20)]
    |-- requires --> [PasteService.pastePlainText] (DONE in Phase 9)
    |-- requires --> [PanelActions.pastePlainTextItem] (DONE in Phase 9)
    |-- requires --> [Context menu infrastructure] (DONE in Phase 4)
    |-- requires --> [Keyboard navigation + .onKeyPress] (DONE in Phase 3)
    |-- no model changes needed
    |-- INDEPENDENT of other v1.3 features

[Allow/Ignore App Lists (PRIV-01)]
    |-- requires --> [ClipboardMonitor] (DONE in Phase 1)
    |-- requires --> [Settings window infrastructure] (DONE in Phase 5)
    |-- requires --> [NSWorkspace frontmostApplication] (already used in ClipboardMonitor)
    |-- new: UserDefaults storage for bundle ID lists
    |-- new: Settings UI with app picker
    |-- new: Context menu "Ignore [App]" option
    |-- INDEPENDENT of other v1.3 features

[Import/Export (DATA-01)]
    |-- requires --> [SwiftData model] (DONE in Phase 1+)
    |-- requires --> [ImageStorageService] (DONE in Phase 1)
    |-- requires --> [Settings window] (DONE in Phase 5)
    |-- requires --> [Label model with relationships] (DONE in Phase 11)
    |-- new: Codable serialization of ClipboardItem + Label
    |-- new: File format definition (.pastel bundle)
    |-- new: NSSavePanel / NSOpenPanel integration
    |-- new: Conflict resolution logic
    |-- INDEPENDENT of other v1.3 features

[Drag-and-Drop (HIST-02)]
    |-- requires --> [ClipboardCardView] (DONE in Phase 2+)
    |-- requires --> [ImageStorageService for image URLs] (DONE in Phase 1)
    |-- requires --> [NSItemProvider / SwiftUI .onDrag] (framework)
    |-- needs testing: NSPanel dismiss during drag
    |-- INDEPENDENT of other v1.3 features
```

**Key observation:** All four features are independent of each other. They can be built in any order and in parallel. No feature blocks another.

---

## Implementation Priority and Phase Ordering

| Feature | User Value | Implementation Cost | Risk | Recommended Order |
|---------|------------|---------------------|------|-------------------|
| Paste as Plain Text (PAST-20) | HIGH (daily use) | LOW (infrastructure exists) | LOW | 1st (quick win) |
| Allow/Ignore App Lists (PRIV-01) | HIGH (privacy) | MEDIUM (new Settings UI) | LOW | 2nd (standalone) |
| Drag-and-Drop (HIST-02) | MEDIUM (power users) | MEDIUM (NSPanel interaction risk) | MEDIUM (NSPanel dismiss) | 3rd (needs testing) |
| Import/Export (DATA-01) | MEDIUM (infrequent use) | MEDIUM-HIGH (most code) | LOW-MEDIUM (format design) | 4th (most work, least urgency) |

**Rationale:**
1. **PAST-20 first:** Lowest effort, highest daily impact. All infrastructure exists. Can ship in one plan.
2. **PRIV-01 second:** Important for privacy-conscious users. Self-contained Settings work.
3. **HIST-02 third:** Needs testing with NSPanel behavior. Medium complexity, medium value.
4. **DATA-01 fourth:** Most implementation work, least frequently used (export once, import once). The format design requires careful thought but low time pressure.

---

## Competitor Feature Matrix

| Feature | PastePal | Paste 2 | Maccy | Pastel v1.2 (current) | Pastel v1.3 (planned) |
|---------|----------|---------|-------|----------------------|----------------------|
| Paste as plain text (context menu) | Yes | Yes | Yes (keyboard only) | No (Cmd+Shift+1-9 only) | Yes (context menu + Shift+Enter + Shift+dbl-click) |
| App ignore list | Filter by app | Exclude apps | Ignore pasteboard types | No | Yes (ignore list + context menu shortcut) |
| App allow list | No | No | No | No | Yes (optional mode) |
| Export history | No | No | No | No | Yes (.pastel format) |
| Import history | No | No | No | No | Yes (with dedup) |
| Drag to other apps | Yes | Unknown | No | No | Yes |
| Drag preview | Unknown | Unknown | N/A | No | Yes |

**Pastel's v1.3 competitive position:** These four features fill the remaining gaps between Pastel and premium competitors while adding novel capabilities (context menu app ignore, allow list mode, versioned export format) that no competitor currently offers.

---

## Sources

- [Paste Help Center](https://pasteapp.io/help/paste-on-mac) -- Paste as plain text UX, exclude apps (MEDIUM confidence)
- [Maccy README / GitHub](https://github.com/p0deje/Maccy/blob/master/README.md) -- Ignore pasteboard types, no drag support (HIGH confidence)
- [Maccy Issue #241](https://github.com/p0deje/Maccy/issues/241) -- Ignore by app feature request and implementation (HIGH confidence)
- [Maccy Issue #79](https://github.com/p0deje/Maccy/issues/79) -- Sensitive app clipboard handling (HIGH confidence)
- [Maccy Issue #1072](https://github.com/p0deje/Maccy/issues/1072) -- frontmostApplication vs actual clipboard source limitation (HIGH confidence)
- [PastePal App Store](https://apps.apple.com/us/app/clipboard-manager-pastepal/id1503446680) -- Feature list, filter by app (MEDIUM confidence)
- [PastePal Review](https://macsources.com/pastepal-clipboard-manager-for-macos-review/) -- Drag-and-drop, plain text paste (MEDIUM confidence)
- [Pasta App Store](https://apps.apple.com/us/app/pasta-clipboard-manager/id1438389787?mt=12) -- Drag clippings to other apps (MEDIUM confidence)
- [PasteNow](https://pastenow.app/) -- Drag and drop from list (MEDIUM confidence)
- [Paste Review](https://josephnilo.com/blog/paste-setapp-review/) -- Exclude apps, privacy controls (MEDIUM confidence)
- [BetterTouchTool Forum](https://community.folivora.ai/t/exclude-apps-from-clipboard-manager-passwords/16601) -- Exclude apps from clipboard manager (MEDIUM confidence)
- [SwiftUI Drag and Drop - Eclectic Light](https://eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more/) -- NSItemProvider patterns, background thread gotchas (MEDIUM confidence)
- [SwiftUI onDrag - Swift with Majid](https://swiftwithmajid.com/2020/04/01/drag-and-drop-in-swiftui/) -- NSItemProvider usage patterns (MEDIUM confidence)
- [NSWorkspace frontmostApplication](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication) -- Apple API docs (HIGH confidence)
- [Alfred Clipboard Archive Script](https://gist.github.com/pirate/6551e1c00a7c4b0c607762930e22804c) -- JSON export pattern for clipboard history (MEDIUM confidence)

**Gaps requiring phase-specific research:**
- NSPanel drag behavior: Verify that NSItemProvider data survives panel dismiss during an active drag operation. Test with each content type.
- SwiftUI `.onDrag` on non-activating NSPanel: Confirm that .onDrag modifier works correctly inside an NSHostingView hosted in a non-activating NSPanel. No documentation specifically addresses this combination.
- RTF data in NSItemProvider: Test whether rich text items can provide both plain text and RTF representations through a single NSItemProvider for maximum receiving-app compatibility.
- Export file size: Profile the export of a large history (5K+ items, 500+ images) to determine if streaming or chunked writing is needed for memory management.

---
*Feature research for: Pastel v1.3 -- Power User Features*
*Researched: 2026-02-09*
