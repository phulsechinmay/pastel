# Phase 16: Drag-and-Drop from Panel - Research

**Researched:** 2026-02-09
**Domain:** macOS drag-and-drop (SwiftUI + AppKit hybrid, NSPanel)
**Confidence:** MEDIUM-HIGH

## Summary

This research investigates how to implement drag-and-drop from the Pastel sliding panel (NSPanel) into external macOS applications. The critical feasibility question -- whether SwiftUI's `.draggable()` works inside an NSPanel with `.nonactivatingPanel` style mask -- is answered with HIGH confidence: **it already works**. The existing codebase uses `.draggable()` on label chips (ChipBarView line 57) inside this same NSPanel, proving the SwiftUI drag infrastructure functions correctly in this window type.

The standard approach uses SwiftUI's `.draggable()` modifier with either `Transferable` conformance or the `.onDrag()` variant that returns an `NSItemProvider`. For text-based content (plain text, URLs, code), `String` already conforms to `Transferable`, making implementation straightforward. Images require providing file URLs via `NSItemProvider`, and the existing disk-based storage at `~/Library/Application Support/Pastel/images/` means files are already available. The AppKit fallback (NSDraggingSource/beginDraggingSession) is unlikely to be needed but remains a viable escape hatch.

Key challenges are: (1) detecting drag session lifecycle (start/end) for panel dismissal suppression and clipboard monitor pausing, (2) providing correct UTTypes for each content type so receiving apps accept the drop, and (3) avoiding conflicts with the existing label `.dropDestination()` on the same card views.

**Primary recommendation:** Use `.onDrag()` (not `.draggable()`) for the clipboard card drag -- it provides an NSItemProvider closure that fires on drag start (enabling side effects like pausing the clipboard monitor), and it avoids type conflicts with the existing String-based `.dropDestination()` for label assignment.

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| SwiftUI `.onDrag()` | macOS 11+ | Initiates drag from SwiftUI view | Returns NSItemProvider, fires closure on drag start |
| NSItemProvider | Foundation | Carries typed data across process boundaries | macOS standard for inter-app data transfer |
| UTType | UniformTypeIdentifiers | Declares content types for drop targets | Required for receiving apps to accept drops |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| `.onDrag(_:preview:)` | macOS 12+ | Custom drag preview | Better UX than default snapshot |
| NSFilePromiseProvider | macOS 10.12+ | Deferred file creation for large files | Only needed if file URL approach fails for images |
| NSDraggingSource protocol | AppKit | Full drag lifecycle control | Only if SwiftUI approach fails (unlikely) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `.onDrag()` | `.draggable(Transferable)` | `.draggable()` is simpler but provides no drag-start callback and may conflict with existing `.dropDestination(for: String.self)` on the same view hierarchy |
| NSItemProvider file URL | NSFilePromiseProvider | File promises support deferred creation but SwiftUI does NOT support file promises natively -- requires AppKit fallback |
| SwiftUI drag | AppKit `beginDraggingSession` | Full lifecycle control but requires NSView subclass, bypasses SwiftUI view hierarchy |

## Architecture Patterns

### Pattern 1: `.onDrag()` with NSItemProvider and Side Effects

**What:** Use `.onDrag()` closure to both construct the NSItemProvider AND perform side effects (pause monitor, set drag state).
**When to use:** For all clipboard card drag operations.
**Why:** The closure fires exactly when drag begins, providing a natural "drag started" hook without needing AppKit delegation.

```swift
// Source: community pattern verified via multiple sources
ClipboardCardView(item: item, ...)
    .onDrag {
        // Side effect: signal drag started
        isDragging = true
        clipboardMonitor.skipNextChange = true

        // Construct appropriate NSItemProvider
        return createItemProvider(for: item)
    } preview: {
        // Custom drag preview
        DragPreviewView(item: item)
    }
```

### Pattern 2: NSItemProvider Construction by Content Type

**What:** Build NSItemProvider with correct UTTypes based on ClipboardItem.type.
**When to use:** Inside the `.onDrag()` closure.

```swift
func createItemProvider(for item: ClipboardItem) -> NSItemProvider {
    switch item.type {
    case .text, .code, .color:
        let provider = NSItemProvider(object: (item.textContent ?? "") as NSString)
        return provider

    case .richText:
        let provider = NSItemProvider()
        if let text = item.textContent {
            provider.registerObject(text as NSString, visibility: .all)
        }
        if let rtfData = item.rtfData {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier,
                                                 visibility: .all) { completion in
                completion(rtfData, nil)
                return nil  // no progress
            }
        }
        return provider

    case .url:
        if let urlString = item.textContent, let url = URL(string: urlString) {
            return NSItemProvider(object: url as NSURL)
        }
        return NSItemProvider(object: (item.textContent ?? "") as NSString)

    case .image:
        if let imagePath = item.imagePath {
            let fileURL = ImageStorageService.shared.resolveImageURL(imagePath)
            let provider = NSItemProvider(contentsOf: fileURL)
            return provider ?? NSItemProvider()
        }
        return NSItemProvider()

    case .file:
        if let filePath = item.textContent {
            let fileURL = URL(fileURLWithPath: filePath)
            let provider = NSItemProvider(contentsOf: fileURL)
            return provider ?? NSItemProvider()
        }
        return NSItemProvider()
    }
}
```

### Pattern 3: Drag State Tracking for Panel Dismissal

**What:** Track `isDragging` state to suppress panel hide during drag session.
**When to use:** Panel dismissal logic in PanelController.

```swift
// In PanelController -- add drag state
var isDragging: Bool = false

// In installEventMonitors -- check drag state before hiding
globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
    matching: [.leftMouseDown, .rightMouseDown]
) { [weak self] _ in
    guard self?.isDragging != true else { return }
    self?.hide()
}
```

### Pattern 4: Drag End Detection via NSApplication Event Monitoring

**What:** Since `.onDrag()` has no built-in "drag ended" callback, use NSEvent monitoring to detect when the drag session ends.
**When to use:** To restore panel dismissal behavior and resume clipboard monitoring after drag.

```swift
// Monitor for left mouse up (drag end) globally
// Install when drag starts, remove when drag ends
var dragEndMonitor: Any?

func onDragStarted() {
    isDragging = true
    dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self?.isDragging = false
            if let monitor = self?.dragEndMonitor {
                NSEvent.removeMonitor(monitor)
                self?.dragEndMonitor = nil
            }
        }
    }
}
```

### Anti-Patterns to Avoid

- **Using `.draggable(String)` on cards:** Conflicts with existing `.dropDestination(for: String.self)` for label assignment. The view hierarchy would try to accept its own drag as a label drop. Use `.onDrag()` with NSItemProvider instead.
- **Using DragGesture for inter-app drag:** DragGesture is for in-view movement (offset tracking). Inter-app drag requires NSItemProvider-based APIs (`.onDrag()` or `.draggable()`).
- **Writing to NSPasteboard.general during drag:** Drag-and-drop uses a separate dragging pasteboard, NOT NSPasteboard.general. NSItemProvider handles this automatically.
- **Using NSFilePromiseProvider through SwiftUI:** SwiftUI does not support file promises. If needed, requires full AppKit fallback with custom NSView subclass.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Inter-app data transfer | Custom IPC or pasteboard writing | NSItemProvider | Handles serialization, type negotiation, process boundaries |
| UTType registration | Manual string identifiers | `UTType` framework constants | `.plainText`, `.url`, `.fileURL`, `.rtf`, `.png` are all pre-defined |
| Drag preview rendering | Manual NSImage snapshot | `.onDrag(preview:)` closure | SwiftUI renders the preview view automatically |
| File URL for images | Re-read image data into memory | `NSItemProvider(contentsOf: fileURL)` | Initializer reads file lazily; avoids loading full image into memory |

**Key insight:** NSItemProvider does the heavy lifting of type negotiation with receiving apps. Manually writing to NSPasteboard is unnecessary and would bypass the drag-and-drop system entirely.

## Common Pitfalls

### Pitfall 1: `.draggable()` / `.dropDestination()` Type Collision

**What goes wrong:** Adding `.draggable("text content")` to ClipboardCardView would make the card's String content draggable, but the card already has `.dropDestination(for: String.self)` (for label assignment). SwiftUI may match the card's own drag to its own drop zone.
**Why it happens:** Both modifiers use the same `String` transfer type. SwiftUI's drag system doesn't distinguish between "label ID string" and "clipboard text string."
**How to avoid:** Use `.onDrag()` which returns NSItemProvider with specific UTTypes (e.g., `.plainText`, `.fileURL`), NOT `.draggable()` with a String payload. The existing `.dropDestination(for: String.self)` specifically handles label ID strings and won't match NSItemProvider content.
**Warning signs:** Dragging a card onto another card triggers label assignment instead of inter-app drag.

### Pitfall 2: No Built-in Drag-End Callback

**What goes wrong:** SwiftUI's `.onDrag()` fires a closure when drag starts but provides NO callback when drag ends or is cancelled.
**Why it happens:** SwiftUI abstracts away the NSDraggingSession lifecycle. The closure returns NSItemProvider and that's it.
**How to avoid:** Use one of these approaches:
1. Global NSEvent monitor for `.leftMouseUp` (installed on drag start, removed on first fire)
2. Custom NSHostingView subclass overriding `draggingSession(_:endedAt:operation:)` (more robust but more invasive)
3. Timer-based polling checking if mouse button is still down (fragile, not recommended)
**Warning signs:** Panel stays in "drag mode" forever, or clipboard monitor never resumes.

### Pitfall 3: Panel Dismissal During Drag

**What goes wrong:** User starts dragging from panel, cursor exits panel bounds, globalClickMonitor fires and hides the panel mid-drag.
**Why it happens:** The existing globalClickMonitor in PanelController monitors `leftMouseDown` globally. A drag operation involves mouse-down followed by mouse movement. The initial mouse-down (which starts the drag within the panel) won't trigger it (it's local), but if the user has any secondary click during drag, the panel could dismiss.
**How to avoid:** Set `isDragging = true` before the drag begins (in `.onDrag()` closure). Guard the global click monitor handler with `guard !isDragging`.
**Warning signs:** Panel disappears when user drags cursor outside panel area.

### Pitfall 4: Self-Capture on Drop

**What goes wrong:** User drops clipboard item into TextEdit. TextEdit writes the content to its document AND may also update NSPasteboard.general. The clipboard monitor detects this change and creates a duplicate history entry.
**Why it happens:** Some receiving apps write to the general pasteboard as part of their drop handling.
**How to avoid:** Set `clipboardMonitor.skipNextChange = true` when drag starts (same pattern as paste-back in Phase 3). For extra safety, add a 500ms delay before resetting `skipNextChange` after drag ends.
**Warning signs:** Dragging an item to another app creates a duplicate entry in clipboard history.

### Pitfall 5: Image File Deleted from Disk

**What goes wrong:** User drags an image card, but the image file no longer exists on disk (manual cleanup, retention service deleted it).
**Why it happens:** ClipboardItem model retains the imagePath reference even after the file is purged.
**How to avoid:** Check `FileManager.default.fileExists(atPath:)` before creating NSItemProvider. If missing, fall back to thumbnail data or skip the drag entirely.
**Warning signs:** Drag appears to start but receiving app shows nothing, or app crashes on nil URL.

### Pitfall 6: `.onDrag()` Conflicts with `.onTapGesture()`

**What goes wrong:** Adding `.onDrag()` to a view that also has `.onTapGesture()` can cause click-to-select to stop working, because the drag gesture recognizer intercepts the mouse-down.
**Why it happens:** macOS requires a long-press (not just mouse-down) to differentiate drag from click. If the gesture recognizer is greedy, clicks may be consumed.
**How to avoid:** Place `.onDrag()` before `.onTapGesture()` in the modifier chain so SwiftUI correctly arbitrates. Test that single-click still selects and double-click still pastes. If conflict persists, add a minimum drag distance threshold.
**Warning signs:** Cards can be dragged but can no longer be clicked to select.

## Code Examples

### Example 1: Basic `.onDrag()` with NSItemProvider for Plain Text

```swift
// Source: Apple docs + community pattern
import UniformTypeIdentifiers

Text(item.textContent ?? "")
    .onDrag {
        NSItemProvider(object: (item.textContent ?? "") as NSString)
    }
```

### Example 2: NSItemProvider for URL with Fallback to String

```swift
// Source: Apple NSItemProvider docs
func urlItemProvider(urlString: String) -> NSItemProvider {
    if let url = URL(string: urlString) {
        // NSURL conforms to NSItemProviderWriting -- provides both .url and .plainText
        return NSItemProvider(object: url as NSURL)
    }
    return NSItemProvider(object: urlString as NSString)
}
```

### Example 3: NSItemProvider from File URL (Images)

```swift
// Source: Apple NSItemProvider docs
func imageItemProvider(imagePath: String) -> NSItemProvider {
    let fileURL = ImageStorageService.shared.resolveImageURL(imagePath)

    // Check file exists before creating provider
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        // Fallback: try thumbnail
        return NSItemProvider()
    }

    // NSItemProvider(contentsOf:) reads file type from extension
    // For .png files, this registers both UTType.png and UTType.image
    return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
}
```

### Example 4: Rich Text with Multiple Representations

```swift
// Source: Apple NSItemProvider docs
func richTextItemProvider(item: ClipboardItem) -> NSItemProvider {
    let provider = NSItemProvider()

    // Register richest format first
    if let rtfData = item.rtfData {
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.rtf.identifier,
            visibility: .all
        ) { completion in
            completion(rtfData, nil)
            return nil
        }
    }

    // Always provide plain text fallback
    if let text = item.textContent {
        provider.registerObject(text as NSString, visibility: .all)
    }

    return provider
}
```

### Example 5: Custom Drag Preview

```swift
// Source: Apple draggable(_:preview:) docs
.onDrag {
    createItemProvider(for: item)
} preview: {
    HStack(spacing: 8) {
        Image(systemName: item.type.systemImageName)
            .font(.title3)
        Text(item.textContent?.prefix(40) ?? "Item")
            .font(.caption)
            .lineLimit(1)
    }
    .padding(8)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
}
```

### Example 6: Drag State Tracking with Global Monitor

```swift
// Pattern: detect drag end via global mouse-up monitor
@State private var isDragging = false
@State private var dragEndMonitor: Any?

.onDrag {
    // Drag started
    isDragging = true
    panelController.isDragging = true
    clipboardMonitor.skipNextChange = true

    // Install mouse-up monitor to detect drag end
    installDragEndMonitor()

    return createItemProvider(for: item)
}

func installDragEndMonitor() {
    dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [self] _ in
        // Drag ended -- restore normal behavior after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isDragging = false
            panelController.isDragging = false
            // skipNextChange will auto-reset on next poll cycle
        }
        // Clean up monitor
        if let monitor = dragEndMonitor {
            NSEvent.removeMonitor(monitor)
            dragEndMonitor = nil
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `.onDrag()` + `.onDrop()` with NSItemProvider | `.draggable()` + `.dropDestination()` with Transferable | WWDC 2022 (macOS 13) | Simpler API, but less control over NSItemProvider |
| Manual UTType strings | UTType framework constants | macOS 11 (2020) | Type-safe identifiers, no string typos |
| NSPasteboardItem for drag | NSItemProvider for drag | macOS 10.12+ (2016) | Cross-process, async-capable data transfer |

**Current best practice:** Use `.onDrag()` when you need NSItemProvider control (multiple representations, drag-start side effects). Use `.draggable()` when you have simple Transferable data and no lifecycle needs.

**For Pastel:** `.onDrag()` is the right choice because:
1. Need drag-start side effects (pause monitor, set isDragging)
2. Need NSItemProvider for multiple UTType representations (RTF + plainText)
3. Need to avoid conflict with existing `.dropDestination(for: String.self)` on cards

## Open Questions

### 1. `.onDrag()` vs `.onTapGesture()` Conflict Severity

- **What we know:** Multiple sources report that `.onDrag()` can interfere with click gestures on macOS. The existing codebase uses `.onTapGesture(count: 2)` and `.onTapGesture(count: 1)` on card views.
- **What's unclear:** Whether adding `.onDrag()` to the same view will break single-click selection and double-click paste. This depends on SwiftUI's gesture arbitration which varies by macOS version.
- **Recommendation:** The feasibility test (Plan 01) MUST verify both click gestures still work after adding `.onDrag()`. If they break, mitigation options: (a) place `.onDrag()` on a wrapper view outside the tap gesture chain, (b) use AppKit drag via NSHostingView subclass, (c) use a long-press threshold.

### 2. Drag End Detection Reliability

- **What we know:** `.onDrag()` has no drag-end callback. Global `.leftMouseUp` monitor fires when mouse button is released. NSHostingView can override `draggingSession(_:endedAt:operation:)`.
- **What's unclear:** Whether the global `.leftMouseUp` monitor fires reliably during cross-app drag sessions (the drag is managed by WindowServer, not the app). If the drop occurs in another app's process space, our app may or may not receive the mouse-up event.
- **Recommendation:** Test global `.leftMouseUp` first (simplest). If unreliable, subclass NSHostingView to override `draggingSession(_:endedAt:operation:)` which is guaranteed to fire. A timer-based fallback (e.g., reset isDragging after 10s) provides safety net.

### 3. Image Drag Compatibility with Finder

- **What we know:** `NSItemProvider(contentsOf: fileURL)` creates a provider from a file URL. Finder accepts file URL drops.
- **What's unclear:** Whether Finder accepts the drop as a file copy or just a reference. Images stored in Application Support should be copied (not moved). Also unclear whether Preview accepts PNG file URL drops via drag.
- **Recommendation:** Test in feasibility plan (Plan 01 or 02). If Finder only creates aliases, may need NSFilePromiseProvider (which requires AppKit fallback).

## Sources

### Primary (HIGH confidence)
- **Existing codebase** - ChipBarView.swift already uses `.draggable()` inside NSPanel (line 57), proving feasibility
- **Existing codebase** - FilteredCardListView.swift uses `.dropDestination(for: String.self)` on cards (lines 130, 186)
- **Existing codebase** - PasteService.swift `writeToPasteboard(item:)` documents content-to-pasteboard mapping (lines 147-211)
- **Existing codebase** - SlidingPanel.swift shows `hidesOnDeactivate = false` already set (line 22)
- **Existing codebase** - PanelController.swift globalClickMonitor for dismiss-on-click-outside (lines 199-204)

### Secondary (MEDIUM confidence)
- [SwiftUI Lab - Drag & Drop with SwiftUI](https://swiftui-lab.com/drag-drop-with-swiftui/) - onDrag/onDrop implementation patterns, NSItemProvider usage
- [Hacking with Swift - How to support drag and drop in SwiftUI](https://www.hackingwithswift.com/quick-start/swiftui/how-to-support-drag-and-drop-in-swiftui) - .draggable() API, Transferable protocol basics
- [Wade Tregaskis - SwiftUI drag & drop does not support file promises](https://wadetregaskis.com/swiftui-drag-drop-does-not-support-file-promises/) - Confirmed NSFilePromiseProvider incompatibility with SwiftUI
- [Buckleyisms - How to Actually Implement File Dragging From Your App on Mac](https://buckleyisms.com/blog/how-to-actually-implement-file-dragging-from-your-app-on-mac/) - NSFilePromiseProvider implementation details
- [Apple Developer Forums - draggingSession willBeginAt on NSHostingView](https://developer.apple.com/documentation/appkit/nsdraggingsource/1415960-draggingsession) - NSDraggingSource lifecycle methods
- [Create with Swift - Implementing drag and drop with SwiftUI modifiers](https://www.createwithswift.com/implementing-drag-and-drop-with-the-swiftui-modifiers/) - onDrag NSItemProvider closure pattern
- [Swift with Majid - Drag and drop transferable data in SwiftUI](https://swiftwithmajid.com/2023/04/05/drag-and-drop-transferable-data-in-swiftui/) - Transferable protocol with .draggable()
- [Apple - nonactivatingPanel docs](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel) - NSPanel style mask behavior

### Tertiary (LOW confidence)
- [The Eclectic Light Company - SwiftUI on macOS: Drag and drop](https://eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more/) - General macOS drag-and-drop challenges with SwiftUI
- [Codecademy - SwiftUI .draggable() reference](https://www.codecademy.com/resources/docs/swiftui/viewmodifier/draggable) - API reference for .draggable() modifier

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - `.onDrag()` and NSItemProvider are well-established macOS APIs. Feasibility confirmed by existing `.draggable()` usage in same NSPanel.
- Architecture: MEDIUM-HIGH - Patterns are well-documented. The `.onDrag()` vs `.onTapGesture()` interaction needs validation in feasibility test.
- Pitfalls: HIGH - Self-capture prevention reuses proven Phase 3 pattern. Panel dismissal guard is straightforward.
- Drag-end detection: MEDIUM - Global `.leftMouseUp` is unverified for cross-app drag. May need NSHostingView subclass fallback.

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (30 days -- stable domain, SwiftUI drag APIs unlikely to change)
