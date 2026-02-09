# Pitfalls Research: v1.3 Power User Features

**Domain:** macOS clipboard manager -- adding paste-as-plain-text UI (PAST-20), app filtering (PRIV-01), import/export (DATA-01), and drag-and-drop from panel (HIST-02) to existing v1.0/v1.1/v1.2 system
**Researched:** 2026-02-09
**Confidence:** MEDIUM-HIGH (verified against existing codebase, Apple documentation, Maccy open-source patterns, and NSPasteboard behavior research; some drag-and-drop interaction claims based on developer community reports)

---

## Critical Pitfalls

Mistakes that cause broken paste behavior, data loss during import/export, or fundamental feature failures.

### Pitfall 1: writeToPasteboardPlainText Still Writes HTML, Defeating Plain Text Intent

**What goes wrong:**
The existing `PasteService.writeToPasteboardPlainText(item:)` method at lines 218-240 strips `.rtf` data but **still writes `.html` content** to the pasteboard. When a user invokes "Paste as plain text" via Shift+Enter, Shift+double-click, or the context menu, receiving apps like Pages, Notes, and Google Docs see the `.html` type on the pasteboard and render it with full rich formatting -- bold, links, font sizes, colors. The user explicitly asked for plain text but gets rich text. This makes the entire paste-as-plain-text feature appear broken.

The current code:
```swift
// Write string and HTML only -- NO .rtf data
if let text = item.textContent {
    pasteboard.setString(text, forType: .string)
}
if let html = item.htmlContent {
    pasteboard.setString(html, forType: .html)  // <-- THIS DEFEATS PLAIN TEXT
}
```

NSPasteboard supports multiple representations simultaneously. When both `.string` and `.html` are present, most macOS apps will prefer the richer `.html` representation. The result: what claims to be "plain text paste" actually delivers formatted HTML to the receiving app.

**Why it happens:**
The v1.1 implementation of `pastePlainText` was designed for the quick-paste hotkey (Cmd+Shift+1-9) where the primary concern was stripping RTF (formatted text from word processors). HTML was kept as a secondary text representation without considering that HTML itself carries formatting. The logic was "remove the richest format" when it should have been "keep ONLY the plainest format."

**Specific risk in Pastel's architecture:**
- `ClipboardMonitor.processPasteboardContent()` captures `htmlContent` separately from `textContent`. When the item was originally rich text (from a web page, email, or formatted document), `htmlContent` contains full HTML markup with `<b>`, `<font>`, `<span style="...">` tags.
- The `writeToPasteboardPlainText` method is called from three paths: Shift+Enter (keyboard), Shift+double-click (mouse), and Cmd+Shift+1-9 (quick paste). All three paths currently have this bug.
- The context menu "Paste" entry does NOT have a plain-text variant yet. Adding "Paste as Plain Text" to the context menu must use the corrected implementation.

**How to avoid:**
- **For true plain text paste: write ONLY `.string` type.** Clear the pasteboard, then set exactly one type: `pasteboard.setString(text, forType: .string)`. No `.rtf`, no `.html`. This forces every receiving app to fall back to unformatted plain text.
- **Do NOT write `.html` in the plain text path.** The HTML representation exists for paste-back fidelity when the user wants formatting preserved. Plain text paste explicitly abandons formatting fidelity.
- **Test with receiving apps that prioritize HTML:** Safari's URL bar, Notes, Pages, TextEdit (rich text mode), Google Docs in Chrome. If any of these show bold/italic/colored text after a "plain text paste," the bug is present.

**Warning signs:**
- Paste-as-plain-text into Google Docs shows formatted text instead of plain text.
- Paste-as-plain-text into Notes preserves link styling or font changes.
- Users report "paste as plain text doesn't work" -- the feature works technically but the output looks rich.

**Affects:** PAST-20 (Paste as plain text)
**Phase to address:** Must be fixed in the paste-as-plain-text implementation phase, before any UI work.

**Confidence:** HIGH -- verified by reading PasteService.swift lines 218-240. The HTML write is plainly visible in the existing code. NSPasteboard type priority behavior (apps prefer richer types) is well-documented.

---

### Pitfall 2: Drag-and-Drop from Panel Writes to NSPasteboard.general, Triggering Self-Capture Loop

**What goes wrong:**
When implementing drag-and-drop from the panel to an external app, developers commonly write the dragged content to `NSPasteboard.general` as part of the drag operation. This triggers `ClipboardMonitor`'s 0.5s polling timer, which detects the `changeCount` change and re-captures the item as a "new" clipboard entry. The user drags an item to paste it, and Pastel creates a duplicate entry in the history. If the user drags the same item multiple times, the history fills with duplicates.

**Why it happens:**
macOS drag-and-drop uses a **separate drag pasteboard** (`NSDragPboard`), NOT `NSPasteboard.general`. When using SwiftUI's `.draggable()` modifier with `Transferable`, the framework handles the drag pasteboard correctly. However, if the implementation accidentally also writes to the general pasteboard (for example, by calling `writeToPasteboard()` before initiating the drag), or if the drop target app copies the dropped content to its own clipboard (which then appears on `.general`), the monitor picks it up.

The specific risk: after the drop completes, some receiving apps (TextEdit, Notes, Terminal) copy the dropped content to the system clipboard as part of their "insert" operation. This changes `NSPasteboard.general.changeCount`, and the monitor captures it as a new item -- even though it is the same content the user just dragged from Pastel.

**Specific risk in Pastel's architecture:**
- `ClipboardMonitor.checkForChanges()` compares `changeCount` every 0.5s. It has no awareness of whether a change came from a drag-and-drop initiated by Pastel itself.
- The existing `skipNextChange` flag is a boolean -- it skips exactly ONE change. If the drag operation causes two pasteboard changes (one from the drag write, one from the receiving app's insert), only the first is skipped.
- Consecutive dedup (`isDuplicateOfMostRecent`) will catch exact duplicates, but the `@Attribute(.unique)` constraint on `contentHash` will cause a save failure and rollback for non-consecutive identical content. Neither provides clean UX -- the user sees no feedback but the save silently fails.

**How to avoid:**
- **Use SwiftUI's `.draggable()` modifier with `Transferable` protocol.** This writes to the drag pasteboard (`NSDragPboard`), NOT to `NSPasteboard.general`. The monitor will NOT detect drag pasteboard changes because it only polls `.general`.
- **Do NOT call `writeToPasteboard()` or `PasteService.paste()` as part of the drag flow.** The drag operation provides its own data transfer mechanism entirely separate from the clipboard.
- **Set a "dragging in progress" flag on ClipboardMonitor** during drag operations. If a receiving app copies the dropped content to the general pasteboard, the monitor should skip that change. Use a time-window flag (e.g., skip changes for 2 seconds after a drag ends) since the receiving app's clipboard write is asynchronous and unpredictable.
- **Consider whether `skipNextChange` should be extended to `skipChangesUntil: Date?`** to handle multi-change scenarios (drag completion + app insertion).

**Warning signs:**
- Dragging an item from the panel creates a duplicate entry at the top of history.
- History count increases by 1 every time the user drags an item.
- Console shows "Captured text item from [receiving app]" immediately after a drag-drop.

**Affects:** HIST-02 (Drag-and-drop from panel)
**Phase to address:** Drag-and-drop implementation phase. The `skipNextChange` extension should be designed before implementing the draggable modifier.

**Confidence:** HIGH -- verified that `ClipboardMonitor` polls only `NSPasteboard.general`. Confirmed via research that drag-and-drop uses a separate pasteboard (`NSDragPboard`). The receiving-app-copies-dropped-content behavior is a known macOS pattern.

---

### Pitfall 3: App Filtering Checks frontmostApplication at Capture Time, Not at Copy Time

**What goes wrong:**
App filtering (allow/ignore lists) uses `NSWorkspace.shared.frontmostApplication` to determine which app produced the clipboard content. But `frontmostApplication` returns the app that has focus **at the moment of the check**, not the app that performed the copy. Because `ClipboardMonitor` polls every 0.5s, there is a race condition: the user copies in App A (which is on the ignore list), then switches to App B within 500ms. By the time the monitor fires, `frontmostApplication` returns App B. The ignored item is captured because the monitor thinks it came from App B.

This is worse than no filtering -- the user added App A to the ignore list specifically to prevent capturing from it, but the items still appear in history. The user loses trust in the privacy feature.

**Why it happens:**
`NSPasteboard.general` has no metadata about which process wrote to it. There is no API to query "which app last wrote to the pasteboard." The only available signal is `frontmostApplication`, which is the app with key focus -- not necessarily the app that most recently wrote to the pasteboard. Background processes, scripts, and AppleScript can write to the pasteboard without being frontmost.

The existing code in `ClipboardMonitor.processPasteboardContent()` already captures `NSWorkspace.shared.frontmostApplication` (lines 223-225). This is used for display purposes (`sourceAppName`, `sourceAppBundleID`). Using the same value for filtering inherits the same race condition.

**Specific risk in Pastel's architecture:**
- The 0.5s polling interval means up to 500ms can elapse between the actual clipboard change and the monitor detecting it. Users frequently switch apps within that window (copy, then Cmd+Tab to paste).
- Background clipboard writes (from CLI tools, AppleScript, Shortcuts, password managers, screen-capture tools) have NO frontmost app or report the wrong one. The monitor would attribute the content to whatever app happens to be frontmost at poll time.
- The Maccy open-source clipboard manager has the same limitation (uses `NSWorkspace.shared.frontmostApplication`). This is a known limitation of the macOS clipboard monitoring approach, not a solvable problem.

**How to avoid:**
- **Accept the race condition as a known limitation.** Document it in the UI: "App filtering is based on the active app when the copy is detected. Fast app-switching may cause some items to be attributed to the wrong app."
- **Use the `sourceAppBundleID` at capture time (current behavior).** Even though it is imperfect, it is the best available signal. Do not try to infer the source app from pasteboard types or content -- this is unreliable.
- **Implement BOTH allow-list and ignore-list modes** (as Maccy does). Allow-list mode ("only capture from these apps") is safer for privacy-sensitive users because it fails closed -- unrecognized apps are excluded by default.
- **Filter at display/storage time, not just capture time.** Store ALL items with their `sourceAppBundleID`, then filter the display. If the user later removes an app from the ignore list, previously-filtered items can reappear. If filtering at capture time, those items are permanently lost.
- **Handle nil bundleIdentifier gracefully.** Some processes (command-line tools, launchd services) have no bundle identifier. Decide whether nil-bundle-ID items are captured or ignored. The safe default: capture them (they are likely user-initiated).

**Warning signs:**
- User copies from Terminal (on ignore list), switches to Safari immediately, and the Terminal item appears in history attributed to Safari.
- Background password manager fills a field, and the item appears attributed to the browser.
- Items from ignored apps appear intermittently but not consistently (timing-dependent).

**Affects:** PRIV-01 (Allow/ignore app lists)
**Phase to address:** App filtering implementation phase. The architecture decision (filter at capture vs. filter at display) must be made before implementation.

**Confidence:** HIGH -- verified that `ClipboardMonitor` uses `NSWorkspace.shared.frontmostApplication` at poll time (line 223). Verified via Maccy source code that this is the standard approach. The race condition is inherent to the polling architecture.

---

### Pitfall 4: Import Overwrites Existing Items Due to contentHash Unique Constraint Collision

**What goes wrong:**
When importing clipboard history from a `.pastel` export file, imported items that share a `contentHash` with existing items in the database fail to insert. SwiftData's `@Attribute(.unique)` constraint on `contentHash` causes the `modelContext.save()` to throw, and `modelContext.rollback()` discards the imported item. The user imports a 500-item export, but only 200 items appear -- the other 300 were duplicates of existing history. There is no feedback about which items were skipped or why.

This is especially problematic for the "backup and restore" use case: export history, reinstall app, import history. If any items were captured between the export and the reimport, the overlapping items are silently dropped.

**Why it happens:**
The `@Attribute(.unique)` constraint on `contentHash` is designed for live deduplication during clipboard monitoring. It prevents the exact same content from being stored twice. But during import, the user explicitly WANTS all items from the export file to be present -- even if some overlap with existing items.

The dilemma: if you remove the unique constraint for import, duplicate items accumulate. If you keep it, imported items are silently dropped. Neither behavior matches user expectations.

**Specific risk in Pastel's architecture:**
- `contentHash` is `@Attribute(.unique)` on `ClipboardItem` (line 49 of ClipboardItem.swift). This is a database-level constraint that cannot be bypassed per-operation.
- `modelContext.rollback()` rolls back the ENTIRE pending transaction, not just the failed insert. If you insert 10 items, and the 5th has a duplicate hash, the rollback loses items 1-4 as well unless you save between each insert.
- Images are stored as separate files on disk. An imported item's `imagePath` points to a filename that may not exist in the local images directory. The import must also copy/recreate the image files.

**How to avoid:**
- **Insert items one at a time with individual save calls.** After each `modelContext.insert()`, call `modelContext.save()`. If it fails due to a unique constraint violation, call `modelContext.rollback()` and continue with the next item. This ensures one failed import does not roll back others.
- **Pre-check for existing hashes before inserting.** Fetch all `contentHash` values from the database into a Set. For each imported item, check if its hash already exists. If it does, either skip silently (with a counter) or update the existing item's timestamp.
- **Show import results to the user.** "Imported 200 items. 300 items were already in your history and were skipped." This sets expectations and prevents confusion.
- **For image items: include image data in the export format.** Base64-encode images into the export file (or use a zip archive with images as separate files). During import, save the image data to disk first, then create the `ClipboardItem` with the new local path.
- **Generate new `contentHash` values during import if the "merge" strategy is selected.** Append a UUID to the content before hashing to guarantee uniqueness. This creates duplicates but preserves all imported items. Let the user choose: "Skip duplicates" or "Import all."

**Warning signs:**
- User imports a file and sees fewer items than expected.
- User reports "import didn't work" when all items were duplicates.
- Image items show broken thumbnails after import (file paths don't exist locally).
- Crash or hang during import of large export files (saving 1000+ items in a single transaction).

**Affects:** DATA-01 (Import/export)
**Phase to address:** Import/export implementation phase. The duplicate handling strategy must be decided before implementing import logic.

**Confidence:** HIGH -- verified `@Attribute(.unique)` on `contentHash` in ClipboardItem.swift. Verified `modelContext.rollback()` behavior in existing code (ClipboardMonitor line 298).

---

### Pitfall 5: Drag-and-Drop from Non-Activating NSPanel Fails Because Panel Cannot Initiate Drag Session

**What goes wrong:**
SwiftUI's `.draggable()` modifier works by initiating a drag session through the view hierarchy's window. For a standard `NSWindow`, the window becomes the drag source and manages the drag lifecycle. But Pastel's panel is an `NSPanel` with `.nonactivatingPanel` style mask, which means it never becomes the main window and has restricted interaction with the window server. The drag session may fail to initiate, or the drag image may not appear, or the drag terminates immediately when the cursor leaves the panel's frame.

The specific failure mode: the user long-presses or drags on a card in the panel. The drag preview appears briefly, then vanishes as the cursor crosses the panel boundary. The receiving app never sees a drop. Or worse: the drag appears to work, but no data is transferred because the drag pasteboard was not properly configured by the non-activating panel.

**Why it happens:**
`NSPanel` with `.nonactivatingPanel` manages its window server tags differently from standard windows. The `kCGSPreventsActivationTagBit` affects how the window server routes events, including drag events. The panel can become key (receive keyboard events) but cannot become main. Drag sessions initiated from non-main windows have historically been unreliable in AppKit.

SwiftUI's `.draggable()` modifier uses `NSItemProvider` under the hood, which creates an `NSDraggingSession` through the hosting view's window. If the window's activation behavior is restricted, the dragging session may not receive proper event routing.

**Specific risk in Pastel's architecture:**
- `SlidingPanel` has `canBecomeMain: false` (line 43 of SlidingPanel.swift). This is correct for paste-back (panel must not steal focus) but may prevent drag sessions from initiating properly.
- The panel uses `level: .floating` which places it above all other windows. Dragging TO other apps requires the drag to cross from a floating window to a normal-level window. The window server must handle this level transition.
- The `globalClickMonitor` (PanelController line 200-203) dismisses the panel on any click outside it. A drag that starts inside the panel but moves outside will trigger this monitor, hiding the panel mid-drag.

**How to avoid:**
- **Test `.draggable()` on `SlidingPanel` early.** Before building any UI, create a minimal test: a card in the non-activating panel with `.draggable("test")`. Verify the drag initiates, crosses the panel boundary, and drops into TextEdit. If it fails, fall back to AppKit's `NSDraggingSource` protocol directly.
- **Disable the globalClickMonitor during active drag sessions.** When a drag begins (detectable via SwiftUI's drag callbacks or NSEvent monitoring), temporarily remove the click-outside monitor. Restore it when the drag ends. Otherwise, the panel hides mid-drag.
- **If `.draggable()` fails on NSPanel:** Use `NSDraggingSource` on the `NSHostingView` or a custom `NSView` subclass. Create the dragging session manually with `beginDraggingSession(with:event:source:)`. This gives direct control over the drag pasteboard and lifecycle, bypassing SwiftUI's abstraction.
- **For image drag: provide multiple representations.** Write both `.png` and `.tiff` data to the drag pasteboard (via `NSPasteboardItem`). Some apps only accept `.tiff` (Finder), others prefer `.png` (web apps). Also write `.fileURL` for apps that want a file reference (the image is already stored on disk).
- **For text drag: write `.string` only.** Do not include `.rtf` or `.html` in the drag representation -- the user is dragging plain text content, and drag-and-drop does not have the "preserve formatting" expectation that paste-back does.

**Warning signs:**
- Drag gesture starts but no drag preview appears.
- Drag preview appears but vanishes when cursor leaves the panel.
- Panel disappears mid-drag (click-outside monitor fires).
- Drop completes but no data appears in the receiving app.
- Drag works on some macOS versions but not others (window server behavior changes between releases).

**Affects:** HIST-02 (Drag-and-drop from panel)
**Phase to address:** Drag-and-drop implementation phase. The feasibility test (can `.draggable()` work on non-activating NSPanel?) must be the FIRST task in this phase.

**Confidence:** MEDIUM -- the NSPanel non-activating style mask is known to have interaction limitations (verified via developer blog post). However, SwiftUI's `.draggable()` on NSPanel specifically has not been widely documented. The globalClickMonitor conflict is HIGH confidence (verified in PanelController.swift).

---

## Moderate Pitfalls

Mistakes that cause degraded UX, inconsistent behavior, or technical debt.

### Pitfall 6: Shift+Enter / Shift+Double-Click Conflict with Existing Keyboard Handling

**What goes wrong:**
The current `FilteredCardListView` handles `.return` for paste (line 231-234) and monitors Shift key state via `isShiftHeld` (set by NSEvent flags monitor in `PanelContentView`). Adding Shift+Enter for "paste as plain text" requires distinguishing between Enter (normal paste) and Shift+Enter (plain text paste) in the `.onKeyPress(.return)` handler. But `.onKeyPress` receives a `KeyPress` value whose `modifiers` may not reliably include `.shift` on all macOS versions, because the flags monitor and `.onKeyPress` use different event sources.

Similarly, Shift+double-click requires distinguishing from a regular double-click on the `.onTapGesture(count: 2)` handler. SwiftUI's `onTapGesture` does not provide modifier key state. The current `isShiftHeld` state variable may be stale (set by `NSEvent.addLocalMonitorForEvents(.flagsChanged)`) if the Shift key was pressed after the last flags-changed event but before the tap.

**Prevention:**
- For Shift+Enter: Use the `keyPress.modifiers` property within `.onKeyPress(.return)` to check for Shift. This is more reliable than the external `isShiftHeld` state because it reads modifiers from the same event. Test on macOS 14 and macOS 15 to verify consistency.
- For Shift+double-click: Continue using `isShiftHeld` (set by the flags monitor) since `onTapGesture` does not provide modifier access. The flags monitor fires synchronously on the main thread, so it should be current by the time `onTapGesture` fires. Test with rapid Shift-press-and-double-click to verify timing.
- If `isShiftHeld` is unreliable for double-click: Use `NSEvent.modifierFlags.contains(.shift)` directly in the `onTapGesture` closure (class property, not instance-specific). This reads the current global modifier state at tap time.

**Affects:** PAST-20 (Paste as plain text)

**Confidence:** MEDIUM -- `isShiftHeld` already works for the keycap badge display (v1.1), suggesting the flags monitor is reliable. But double-click + Shift timing has not been tested.

---

### Pitfall 7: App Filtering UI Exposes Raw Bundle Identifiers Instead of Human-Readable App Names

**What goes wrong:**
The allow/ignore list settings UI stores and displays app bundle identifiers (e.g., `com.apple.Terminal`, `com.google.Chrome`). Users do not know their apps' bundle identifiers. If the UI shows only bundle IDs, users cannot identify which app is which. If the UI lets users type bundle IDs manually, they will make typos (`com.apple.terminal` vs `com.apple.Terminal`) and filtering silently fails.

**Prevention:**
- Use an app picker that resolves installed apps by name. `NSWorkspace.shared.urlsForApplications(withBundleIdentifier:)` resolves bundle ID to app URL, and `Bundle(url:)?.infoDictionary?["CFBundleName"]` gives the display name. Or use the `NSRunningApplication.localizedName` property.
- Show the app icon alongside the name using `NSWorkspace.shared.icon(forFile:)` or the app's bundle icon.
- Store bundle identifiers internally (stable across renames and updates) but display localized names and icons to the user.
- Provide an "Add from running apps" button that lists currently running apps (via `NSWorkspace.shared.runningApplications`) for easy selection.
- Consider also providing an "Add from recently captured" option showing apps that have appeared as `sourceAppBundleID` in the clipboard history.

**Affects:** PRIV-01 (Allow/ignore app lists)

**Confidence:** HIGH -- this is a UX standard. Maccy's implementation also uses app names + icons.

---

### Pitfall 8: Export Format Lacks Versioning, Breaking Future Import Compatibility

**What goes wrong:**
The initial export format is a JSON file with the current `ClipboardItem` fields. In v1.4 or v2, new fields are added to `ClipboardItem` (e.g., `isPinned`, `isSensitive`). Old export files do not contain these fields. The import code crashes or silently discards items when it encounters missing fields during JSON decoding. Users who exported their history before the update cannot import it after updating.

Conversely, if a user exports from a newer version and tries to import into an older version, the import fails because the older version does not recognize new fields.

**Prevention:**
- **Include a format version number in the export file.** The top-level JSON should have `{ "version": 1, "exportDate": "...", "appVersion": "...", "items": [...] }`. On import, check the version and apply appropriate parsing logic.
- **Use Codable with explicit CodingKeys and default values.** Every new field added to the export format must have a default value in `init(from decoder:)`. This ensures old exports (missing new fields) decode successfully. New fields are filled with defaults.
- **Never remove or rename fields in the export format.** Only add new optional fields. This maintains backward compatibility. If a field must be renamed, keep the old key as an alias in the decoder.
- **Test import of v1 exports after every model change.** Keep a reference export file from each version in the test suite. Run import tests against all previous versions.
- **For image data: store as separate files in a .pastel directory (or .zip).** Do not base64-encode images inline in JSON -- this bloats the file 33% and makes it unreadable. Use a structured directory: `export.pastel/manifest.json` + `export.pastel/images/UUID.png`.

**Affects:** DATA-01 (Import/export)

**Confidence:** HIGH -- versioning in export formats is a well-established pattern. The risk of breaking imports with schema changes is virtually certain if versioning is omitted.

---

### Pitfall 9: Drag-and-Drop of Image Items Fails Because Image Data Is on Disk, Not in Memory

**What goes wrong:**
For text items, drag-and-drop is straightforward: the `textContent` string is available in memory and can be passed directly to `.draggable()`. For image items, the actual image data is stored on disk at `~/Library/Application Support/Pastel/images/{UUID}.png`. The `ClipboardItem` only stores the filename (`imagePath`), not the image data.

If the `.draggable()` modifier attempts to provide the image via `Transferable` and the image must be loaded from disk synchronously, the drag initiation blocks the main thread. For large images (4K screenshots, 2-5MB PNGs), this causes a visible pause before the drag preview appears. If the file has been deleted (orphan record), the drag fails silently.

**Prevention:**
- **Load image data asynchronously before the drag begins.** When the user starts a long-press or drag gesture on an image card, begin loading the image from disk on a background queue. Provide the loaded data to the drag session via `NSItemProvider`'s async loading callback.
- **Use `NSItemProvider(contentsOf: URL)` with the file URL directly.** This is the most efficient approach -- the system reads the file lazily when the drop target requests the data. No need to load the entire image into memory during drag initiation.
- **Handle missing files gracefully.** Before initiating the drag, check if `FileManager.default.fileExists(atPath:)`. If the file is missing, show a brief error tooltip ("Image no longer available") and do not initiate the drag.
- **Provide a drag preview from the thumbnail** (which is small and loads fast). The full image data is only needed when the drop target requests it.

**Affects:** HIST-02 (Drag-and-drop from panel)

**Confidence:** HIGH -- verified that `ClipboardItem.imagePath` stores only the filename (not data) and images are loaded from disk via `ImageStorageService.resolveImageURL()`.

---

### Pitfall 10: Export File Contains Full Disk Paths That Break on Other Machines

**What goes wrong:**
`ClipboardItem` stores `imagePath` as a filename (e.g., `"UUID.png"`) and resolves it at runtime via `ImageStorageService.resolveImageURL()`. This is correct for the local database. But if the export naively serializes `ClipboardItem` fields, the `imagePath` value is meaningless on a different machine -- the image file does not exist there. The import creates items with broken image references.

Worse, `ClipboardItem.textContent` for `.file` type items stores an **absolute file path** (e.g., `/Users/alice/Documents/report.pdf`). Exporting this path and importing on another machine creates a file reference that points to a non-existent location. The card shows a file path that does not resolve.

**Prevention:**
- **For image items: embed the image data in the export.** Either base64-encode inline (simple but bloated) or use a zip/directory format with images as separate files (efficient, standard).
- **For file items: export only the filename, not the full path.** File references are inherently non-portable. On import, show the file item with its name but mark it as "file not available" if the path does not exist on the importing machine. Do not silently discard file items.
- **For URL metadata images (favicon, preview): include them in the export.** These are small (<100KB each) and can be base64-encoded without significant bloat.
- **Store relative paths within the export archive.** The manifest JSON references `images/UUID.png`, and the archive contains `images/UUID.png`. On import, copy images to the local images directory and update paths.

**Affects:** DATA-01 (Import/export)

**Confidence:** HIGH -- verified that `imagePath` is a filename, `textContent` for file items is an absolute path. Both patterns are visible in ClipboardItem.swift.

---

## Integration Gotchas

Mistakes specific to adding v1.3 features alongside the existing v1.0/v1.1/v1.2 system.

| Integration Point | Common Mistake | Correct Approach |
|-------------------|----------------|------------------|
| `writeToPasteboardPlainText` + HTML | Keeping existing HTML write when adding new UI triggers for plain text paste | Remove `.html` write from `writeToPasteboardPlainText()`. Write ONLY `.string` type. Verify with Pages, Notes, Google Docs |
| `globalClickMonitor` + drag-and-drop | Panel dismisses when drag cursor leaves panel boundary | Disable click-outside monitor during active drag. Restore on drag end |
| `skipNextChange` + drag-and-drop | Single-skip flag insufficient for drag operations that cause multiple pasteboard changes | Extend to time-window skip: `skipChangesUntil: Date?` set to 2 seconds after drag end |
| App filter + `sourceAppBundleID` | Filtering at capture time permanently discards items from ignored apps | Store all items with `sourceAppBundleID`, filter at display/query time. User can change filters without losing data |
| Export + `@Attribute(.unique)` on `contentHash` | Batch import fails on first duplicate, rolling back all pending inserts | Insert one item at a time with individual `save()` calls. Count skipped duplicates and report to user |
| Export + `imagePath` filenames | Export contains filenames but not image data. Import creates broken references | Include image data in export (zip with images directory, or base64 inline) |
| Export + `labels` relationship | Importing items with label references creates orphan labels or duplicates | Export labels separately. On import, match labels by name+color. Reuse existing labels, create new ones only if no match |
| Context menu + paste plain text | Adding "Paste as Plain Text" to context menu duplicates code from keyboard handler | Extract paste-as-plain-text action to a single method on `PanelActions`. Call from context menu, Shift+Enter, Shift+double-click, and Cmd+Shift+1-9 |
| Drag-and-drop + `.onTapGesture(count: 1)` | SwiftUI's gesture recognizers conflict: long-press for drag vs. single-click to select | Use `.simultaneousGesture()` or prioritize the drag gesture with a minimum drag distance. Single click selects; drag gesture requires 5px+ movement |
| App filter + `isConcealed` | Password manager items already have `org.nspasteboard.ConcealedType` detection. Adding app filtering on top may double-filter or conflict | App filter and concealed detection are independent. App filter controls capture. Concealed detection controls expiry. Both can apply to the same item without conflict. Document this clearly |

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Store app filter list in `UserDefaults` as `[String]` | Simple, no SwiftData model needed | Cannot store metadata (app name, icon, date added). Must serialize/deserialize on every check. Performance degrades with 100+ entries | Acceptable for v1.3 (lists will be small). Migrate to SwiftData model in v2 if needed |
| Export as flat JSON (no versioning) | Simpler implementation, faster to ship | Any model change in v1.4+ breaks import of v1.3 exports. No migration path | Never -- always include version number in format |
| Base64 images inline in JSON | Single-file export, simple to implement | 33% file size bloat (base64 overhead). Export of 100 images = 300MB+ JSON file. Unreadable, unparseable by tools | Acceptable for small exports (<20 images). Use zip for larger exports |
| Hardcode drag data types | No configuration needed, works for common cases | Some apps only accept specific UTTypes. Hard to add support for new types later | Acceptable if providing at least `.string` + `.fileURL` + `.png`/`.tiff` |
| Single-boolean `skipNextChange` for drag | Minimal change to existing code | Drag operations may cause 2+ pasteboard changes (drag write + app insert). Only first is skipped | Never -- extend to time-window skip for drag operations |

---

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Exporting all items with images as base64 in a single JSON | Export hangs, memory spike, 500MB+ JSON file | Use streaming JSON encoder or zip format with separate image files. Export in batches | 100+ image items (common after weeks of use) |
| Importing 1000+ items in a single SwiftData transaction | UI freezes, `modelContext.save()` takes 10+ seconds, potential crash | Insert in batches of 50. Show progress indicator. Use background context | 500+ items in import file |
| Querying `contentHash` for duplicate check on every import item | O(n*m) where n=import items, m=existing items | Pre-load all existing hashes into a Set. O(1) lookup per import item | 5000+ existing items and 500+ import items |
| Loading full image data for drag preview | 2-5 second freeze on drag initiation for 4K screenshots | Use thumbnail for drag preview. Load full image data lazily via NSItemProvider callback | Any image over 1MB |
| App filter list checked via `UserDefaults.array(forKey:)` on every poll | UserDefaults access on every 0.5s timer fire adds latency | Cache the filter list in memory. Update cache when UserDefaults changes (via KVO or Notification) | UserDefaults access is fast for small arrays, but the pattern is wasteful |

---

## UX Pitfalls

Common user experience mistakes when adding these features.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| "Paste as Plain Text" pastes with HTML formatting | User explicitly requested plain text, gets formatted text. Fundamental broken promise | Write ONLY `.string` type to pasteboard. No `.html`, no `.rtf`. Test with multiple receiving apps |
| App filter has no "test" or "preview" | User adds apps to ignore list but has no way to verify it works without copying from each app | Show a "last captured from" indicator in the panel or settings. When an item is skipped due to filter, briefly show "Skipped (app filtered)" in the status area |
| Import shows no progress for large files | User imports a 2000-item file. App appears frozen for 30 seconds. User force-quits | Show a progress bar: "Importing... 450 of 2000 items" with a cancel button |
| Export includes sensitive/concealed items without warning | User exports history to share with a colleague. Export includes password manager entries (even if they expired from the UI, they may still be in the database) | Show a pre-export summary: "This export contains 5 concealed items. Exclude them?" with a checkbox |
| Drag-and-drop has no visual feedback | User drags a card. Nothing happens (drag failed). No indication of why | Show a drag preview (card thumbnail). If drag fails, show a brief tooltip: "Drag not supported for this item type" |
| "Paste as Plain Text" context menu next to "Paste" is confusing | Two "Paste" entries that do different things. User clicks the wrong one | Use clear labels: "Paste" and "Paste without Formatting". Add a keyboard shortcut hint in the menu: "Paste without Formatting  Shift+Enter" |
| App filter does not explain what "ignore" means | User thinks "ignore" means "delete existing items from that app." Actually means "stop capturing new items" | Explain in the UI: "New copies from ignored apps will not be saved. Existing items are not affected." |

---

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Paste as plain text:** Looks done when text pastes without bold in TextEdit. But test with: (1) Google Docs in Chrome (reads HTML from pasteboard), (2) Notes app (renders HTML links), (3) Slack desktop app (preserves rich formatting), (4) a rich text item with inline images (should paste text only, no images). If any show formatting, the HTML type is still being written.
- [ ] **App filtering:** Looks done when copies from Terminal are ignored. But test with: (1) copy from Terminal then immediately Cmd+Tab to Safari -- does the item appear attributed to Safari? (2) copy from an app with no bundle ID (CLI tool) -- is it captured or filtered? (3) switch from ignore-list to allow-list mode -- do previously captured items from non-listed apps disappear? They should not.
- [ ] **Export:** Looks done when JSON file is created. But verify: (1) import the exported file on a clean install -- do all items appear? (2) export includes image data, not just filenames. (3) export file has a version number. (4) concealed items are handled (excluded or warned about). (5) labels are exported and re-imported correctly (matched by name, not by PersistentIdentifier).
- [ ] **Import:** Looks done when items appear in history. But verify: (1) duplicate items are handled (skip with counter, not crash). (2) imported images are saved to the local images directory. (3) import of 1000+ items does not freeze the UI (background processing with progress). (4) import of an older-version export file works (version migration). (5) item timestamps are preserved from the export, not set to import time.
- [ ] **Drag-and-drop:** Looks done when text drags to TextEdit. But verify: (1) image drag to Finder creates a .png file. (2) URL drag to Safari opens the URL. (3) drag does not trigger clipboard monitor (no duplicate capture). (4) panel does not dismiss mid-drag. (5) drag from horizontal panel layout (top/bottom edge) works the same as vertical (left/right edge).

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| HTML in plain text paste (1) | Paste-as-plain-text phase | Paste into Google Docs, Notes, Pages. Verify NO formatting appears. Inspect pasteboard types with Pasteboard Viewer app |
| Drag triggers self-capture (2) | Drag-and-drop phase | Drag 5 items to TextEdit. Check history count -- should not increase by 5. Check console for "Captured" log lines |
| App filter race condition (3) | App filtering phase | Copy from Terminal (ignored), Cmd+Tab to Safari within 200ms. Check if item appears. Repeat 10 times -- race is probabilistic |
| Import hash collision (4) | Import/export phase | Export 100 items. Import on same install. Verify "100 items skipped (already in history)" message. No crash |
| Drag fails from NSPanel (5) | Drag-and-drop phase -- FIRST TASK | Create minimal test: single card with `.draggable("test")` in non-activating NSPanel. Verify drag crosses panel boundary and drops into TextEdit. If fails, switch to AppKit NSDraggingSource |
| Shift+Enter conflict (6) | Paste-as-plain-text phase | Hold Shift, press Enter on selected card. Verify plain text paste. Release Shift, press Enter on same card. Verify normal paste. Test rapid alternation |
| Bundle ID display (7) | App filtering phase | Open app filter settings. Verify apps show name + icon, not `com.apple.xxx`. Test with apps that have no icon (CLI wrappers) |
| Export versioning (8) | Import/export phase | Export from v1.3. Add a new field to ClipboardItem. Import v1.3 export. Verify all items import successfully with default value for new field |
| Image drag disk loading (9) | Drag-and-drop phase | Drag a 5MB screenshot from panel. Verify no freeze (drag preview should appear within 200ms using thumbnail) |
| File paths in export (10) | Import/export phase | Export with images. Import on clean install (different images directory). Verify all image thumbnails display correctly |

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| HTML still written in plain text paste (1) | LOW | Fix `writeToPasteboardPlainText()` to exclude `.html`. Ship as patch update. No data loss, only UX issue |
| Drag creates duplicate history entries (2) | LOW | Extend `skipNextChange` to time-window. Add dedup pass to remove duplicates created during testing. No data loss |
| App filter attributes item to wrong app (3) | MEDIUM | Cannot retroactively fix misattributed items (the real source app is unknown). Clear affected items manually. Add UI disclaimer about race condition |
| Import silently drops items (4) | MEDIUM | Re-export from source (if available). Fix import to handle duplicates gracefully. Re-import. If source export is lost, items are unrecoverable |
| Drag fails from NSPanel (5) | HIGH | If `.draggable()` does not work on NSPanel, must rewrite using AppKit `NSDraggingSource`. This is a fundamentally different approach. Test BEFORE building the feature |
| Export lacks version number (8) | MEDIUM | Retroactively add version detection by field inspection (v1.3 exports have certain fields that v1.4 exports have). Fragile but workable. Always include version going forward |
| Import breaks image references (10) | MEDIUM | Re-export with image data included. Re-import. If original export had no images, those items show broken thumbnails permanently |

---

## Sources

- [Maccy Clipboard.swift -- app filtering implementation](https://github.com/p0deje/Maccy/blob/master/Maccy/Clipboard.swift) -- ignore/allow list pattern, frontmostApplication usage (HIGH confidence -- open-source reference implementation)
- [NSPanel nonactivating style mask blog analysis](https://philz.blog/nspanel-nonactivating-style-mask-flag/) -- window server tag behavior, activation limitations (HIGH confidence)
- [NSPasteboard type priority -- Kodeco Forums](https://forums.kodeco.com/t/dealing-with-formatted-text-in-nspasteboard/59650) -- apps prefer richer pasteboard types when multiple are present (MEDIUM confidence)
- [NSTextView plain text pasteboard handling -- Christian Tietze](https://christiantietze.de/posts/2022/09/nstextview-plain-text-pasteboard-string-not-included/) -- NSStringPboardType vs .string type compatibility (HIGH confidence)
- [macOS paste plain text shortcuts -- Apple Community](https://discussions.apple.com/thread/253654093) -- Cmd+Shift+V vs Cmd+Shift+Option+V inconsistency across apps (HIGH confidence)
- [Drag-and-drop uses separate drag pasteboard -- Eclectic Light](https://eclecticlight.co/2026/01/10/explainer-copy-and-paste-drag-and-drop/) -- drag-and-drop does not use NSPasteboard.general (HIGH confidence)
- [NSPasteboard changeCount -- Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nspasteboard/1533544-changecount) -- independent change counts per named pasteboard (HIGH confidence)
- [SwiftUI draggable and Transferable -- Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/Adopting-drag-and-drop-using-SwiftUI) -- .draggable() modifier behavior (HIGH confidence)
- [SwiftData Codable conformance -- Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-make-swiftdata-models-conform-to-codable) -- manual Codable implementation for SwiftData models (HIGH confidence)
- [Floating panel in SwiftUI -- Cindori](https://cindori.com/developer/floating-panel) -- NSPanel configuration for non-activating floating windows (HIGH confidence)
- [Maccy issue #79 -- ignore sensitive apps](https://github.com/p0deje/Maccy/issues/79) -- community discussion on app-specific clipboard filtering (MEDIUM confidence)
- Direct analysis of Pastel codebase: `PasteService.swift`, `ClipboardMonitor.swift`, `PanelController.swift`, `FilteredCardListView.swift`, `ClipboardItem.swift`, `SlidingPanel.swift`, `AppState.swift`, `ImageStorageService.swift`, `ClipboardCardView.swift` (HIGH confidence -- source code inspection)

---
*Pitfalls research for: Pastel v1.3 Power User Features*
*Researched: 2026-02-09*
