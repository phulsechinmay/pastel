# Phase 3: Paste-Back and Hotkeys - Research

**Researched:** 2026-02-06
**Domain:** macOS CGEvent paste simulation, Accessibility permissions, keyboard navigation in NSPanel
**Confidence:** HIGH

## Summary

Phase 3 implements the core value proposition of Pastel: selecting a clipboard item and pasting it into the active app. The research covers six technical domains: CGEvent paste-back simulation, Accessibility permission handling, keyboard navigation in non-activating panels, tracking the previously active app, sandbox removal, and double-click detection in SwiftUI within NSPanel.

The standard approach is well-established and verified through analysis of Maccy (the most popular open-source macOS clipboard manager): write the selected item's content to NSPasteboard, simulate Cmd+V via CGEvent, and use a marker-based approach to prevent the self-paste loop. The existing codebase already has the `skipNextChange` flag in ClipboardMonitor, the non-activating NSPanel with `canBecomeKey = true`, and the global hotkey registration via KeyboardShortcuts -- all of which provide a solid foundation.

Two critical prerequisites must be addressed: (1) removing App Sandbox from entitlements (currently enabled, incompatible with CGEvent posting), and (2) implementing the Accessibility permission request flow.

**Primary recommendation:** Build a `PasteService` that writes content to NSPasteboard (preserving all representations), hides the panel, waits ~50ms, then posts CGEvent Cmd+V. Use the existing `skipNextChange` flag on ClipboardMonitor. Use SwiftUI `.onKeyPress` (available on macOS 14+) for arrow key navigation and Enter-to-paste.

## Standard Stack

### Core

| Library/API | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| CGEvent (CoreGraphics) | Stable since macOS 10.4 | Simulate Cmd+V keystroke | Only reliable way to paste into another app; used by Maccy, Clipy, Alfred |
| AXIsProcessTrusted (ApplicationServices) | Stable | Check/request Accessibility permission | The only API for Accessibility permission; required for CGEvent posting |
| NSPasteboard (AppKit) | Stable | Write clipboard content for paste-back | Already used for reading; writing mirrors the existing read approach |
| NSWorkspace.frontmostApplication (AppKit) | Stable | Track which app was active before panel | Standard property, no alternatives needed |
| SwiftUI .onKeyPress | macOS 14+ (Sonoma) | Arrow key/Enter navigation | Native SwiftUI keyboard handling; deployment target is macOS 14 |
| IsSecureEventInputEnabled (Carbon) | Stable | Detect secure input fields | Prevents silent paste failures in password fields |

### Supporting

| Library/API | Purpose | When to Use |
|-------------|---------|-------------|
| KeyboardShortcuts (already integrated) | Global hotkey for panel toggle | Already wired in Phase 2; Cmd+Shift+V already works |
| NSEvent.addLocalMonitorForEvents | Fallback keyboard handling within panel | Already used for Escape dismiss; extend for keyboard nav if .onKeyPress has issues |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CGEvent Cmd+V | AXUIElement API to directly insert text | Less reliable across apps, more complex, does not work for images/files |
| SwiftUI .onKeyPress | NSEvent local monitor for all key handling | More code, manual key code mapping, but guaranteed to work in NSPanel context |
| AXIsProcessTrustedWithOptions prompt | Manual "Open Settings" link | Less friction but user may not understand what to do |

## Architecture Patterns

### Recommended Project Structure Additions

```
Pastel/
  Services/
    PasteService.swift           # CGEvent paste simulation + pasteboard writing
    AccessibilityService.swift   # Permission check/request/polling
  Views/
    Panel/
      PanelContentView.swift     # MODIFY: add selection state + keyboard nav
      ClipboardCardView.swift    # MODIFY: add selection highlight + double-click
    Onboarding/
      AccessibilityPromptView.swift  # Permission request UI
```

### Pattern 1: PasteService - Write + Simulate

**What:** A @MainActor service that writes a ClipboardItem's content to NSPasteboard, signals the monitor to skip the next change, hides the panel, waits a brief delay, then posts CGEvent Cmd+V.

**When to use:** For all paste-back operations (double-click, Enter key, future Cmd+1-9).

**Source:** Maccy Clipboard.swift pattern, verified via GitHub source.

```swift
import AppKit
import CoreGraphics
import OSLog

@MainActor
final class PasteService {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "PasteService"
    )

    /// Paste a clipboard item into the frontmost app.
    ///
    /// Flow:
    /// 1. Check Accessibility permission
    /// 2. Write item content to NSPasteboard.general
    /// 3. Set skipNextChange on ClipboardMonitor
    /// 4. Hide the panel
    /// 5. After 50ms delay, post CGEvent Cmd+V
    func paste(
        item: ClipboardItem,
        clipboardMonitor: ClipboardMonitor,
        panelController: PanelController
    ) {
        // 1. Check accessibility
        guard AccessibilityService.isGranted else {
            AccessibilityService.requestPermission()
            return
        }

        // 2. Check secure input
        if IsSecureEventInputEnabled() {
            logger.warning("Secure input is active -- paste-back unavailable")
            // Still write to pasteboard so user can Cmd+V manually
            writeToPasteboard(item: item)
            clipboardMonitor.skipNextChange = true
            return
        }

        // 3. Write to pasteboard
        writeToPasteboard(item: item)

        // 4. Signal monitor to skip next change
        clipboardMonitor.skipNextChange = true

        // 5. Hide panel
        panelController.hide()

        // 6. Simulate Cmd+V after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Self.simulatePaste()
        }
    }

    /// Write item content to NSPasteboard, preserving all representations.
    private func writeToPasteboard(item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.type {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
            // Also write RTF if available
            if let rtfData = item.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            if let html = item.htmlContent {
                pasteboard.setString(html, forType: .html)
            }

        case .richText:
            // Write all representations for maximum fidelity
            if let rtfData = item.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            if let html = item.htmlContent {
                pasteboard.setString(html, forType: .html)
            }
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .url:
            if let urlString = item.textContent {
                pasteboard.setString(urlString, forType: .string)
                // Also set as URL type
                if let url = URL(string: urlString) {
                    pasteboard.writeObjects([url as NSURL])
                }
            }

        case .image:
            if let imagePath = item.imagePath {
                let imageURL = ImageStorageService.shared.resolveImageURL(imagePath)
                if let imageData = try? Data(contentsOf: imageURL) {
                    pasteboard.setData(imageData, forType: .png)
                }
            }

        case .file:
            if let filePath = item.textContent, let url = URL(string: filePath) {
                pasteboard.writeObjects([url as NSURL])
            }
        }
    }

    /// Simulate Cmd+V keystroke via CGEvent.
    private static func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Suppress local keyboard events during paste
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
```

**Confidence:** HIGH -- CGEvent paste simulation with virtual key 0x09, `.combinedSessionState`, and `.cgSessionEventTap` is the exact pattern used by Maccy. The flow (write to pasteboard, skip monitor, hide panel, delay, simulate) is proven.

### Pattern 2: Accessibility Permission Flow

**What:** Check and request Accessibility permission with user-friendly guidance.

**When to use:** Before first paste attempt, and optionally at app launch.

```swift
import ApplicationServices
import AppKit

enum AccessibilityService {

    /// Check if Accessibility permission is currently granted.
    /// This is a cheap check -- call before every paste.
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Request Accessibility permission with system prompt.
    /// Shows macOS system dialog directing user to System Settings.
    @discardableResult
    static func requestPermission() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings directly to the Accessibility pane.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

**Confidence:** HIGH -- AXIsProcessTrusted and AXIsProcessTrustedWithOptions are stable APIs verified via Apple Developer Documentation and multiple independent sources.

### Pattern 3: Keyboard Navigation with Selection State

**What:** Track a selected card index in PanelContentView, move it with arrow keys, paste with Enter.

**When to use:** Always in the panel for keyboard-driven workflows.

**Approach: SwiftUI .onKeyPress (macOS 14+)**

Since Pastel targets macOS 14 (Sonoma), `.onKeyPress` is available natively.

```swift
struct PanelContentView: View {
    @Query(sort: \ClipboardItem.timestamp, order: .reverse)
    private var items: [ClipboardItem]

    @State private var selectedIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            // ... header ...

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipboardCardView(
                                item: item,
                                isSelected: selectedIndex == index,
                                onPaste: { pasteItem(item) }
                            )
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: selectedIndex) { _, newValue in
                    if let newValue {
                        withAnimation {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            if let index = selectedIndex, index < items.count {
                pasteItem(items[index])
            }
            return .handled
        }
    }

    private func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        if let current = selectedIndex {
            selectedIndex = max(0, min(items.count - 1, current + offset))
        } else {
            selectedIndex = 0
        }
    }
}
```

**Confidence:** HIGH for the approach, MEDIUM for .onKeyPress within NSPanel context. The `.onKeyPress` modifier is confirmed available on macOS 14+. However, there is a small risk that key events may not propagate correctly to SwiftUI views hosted inside a non-activating NSPanel. The panel has `canBecomeKey = true` which should allow key events, but if issues arise, the fallback is to extend the existing `localKeyMonitor` in PanelController to handle arrow keys and dispatch selection changes.

**Fallback pattern (NSEvent local monitor):**

If `.onKeyPress` does not work reliably inside the NSPanel, extend the existing local key monitor in PanelController:

```swift
// In PanelController.installEventMonitors()
localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
    switch event.keyCode {
    case 53: // Escape
        self?.hide()
        return nil
    case 126: // Up arrow
        self?.onArrowUp?()
        return nil
    case 125: // Down arrow
        self?.onArrowDown?()
        return nil
    case 36: // Return/Enter
        self?.onReturn?()
        return nil
    default:
        return event
    }
}
```

### Pattern 4: Tracking the Previously Active App

**What:** Before showing the panel, record which app is frontmost so paste-back targets the correct app.

**When to use:** In PanelController.show().

```swift
// In PanelController
private var previousApp: NSRunningApplication?

func show() {
    // Capture frontmost app BEFORE showing panel
    previousApp = NSWorkspace.shared.frontmostApplication

    // ... existing show() code ...
}
```

**Confidence:** HIGH -- `NSWorkspace.shared.frontmostApplication` is a stable, synchronous property. Because the panel uses `.nonactivatingPanel` style mask, Pastel never becomes the frontmost application, so the target app retains focus naturally. However, storing the reference is still useful for edge cases (e.g., reactivating the app if focus shifts during panel interaction).

### Anti-Patterns to Avoid

- **Do NOT post CGEvent immediately after writing to pasteboard.** A 50ms delay is needed for the pasteboard write to be committed and the panel hide animation to complete. Maccy uses this approach.
- **Do NOT use `.cghidEventTap` for event posting.** Use `.cgSessionEventTap` instead. Maccy uses `.cgSessionEventTap` and it is more reliable across app contexts.
- **Do NOT cache AXIsProcessTrusted() result.** Users can revoke permission at any time. Check before every paste.
- **Do NOT use `canBecomeMain = true` on the NSPanel.** This would interfere with the previously active app retaining main window status. Current code correctly has `canBecomeMain = false`.
- **Do NOT create a custom marker pasteboard type for self-paste detection.** The existing `skipNextChange` flag in ClipboardMonitor is simpler and sufficient for Pastel's single-paste-at-a-time model. Maccy uses a marker type because it supports more complex clipboard operations. Pastel's flag-based approach is cleaner.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Global hotkey registration | Custom Carbon RegisterEventHotKey wrapper | KeyboardShortcuts library (already integrated) | Already working in Phase 2; handles Carbon API complexity, Dvorak layouts, conflicts |
| CGEvent keystroke simulation | Complex event source management | Simple static function (6 lines, see Pattern 1) | The CGEvent API is straightforward for Cmd+V; Maccy's code is essentially 6 lines |
| Accessibility permission UI | Custom window with complex state machine | Simple conditional check + system prompt | AXIsProcessTrustedWithOptions handles the system dialog; just need a pre-explanation view |
| Keyboard layout detection for paste key | Custom keyboard layout parsing | Use hardcoded 0x09 (kVK_ANSI_V) | Virtual key codes are layout-independent. 0x09 is V on all layouts. Maccy's Dvorak-QWERTY handling is for edge cases Pastel can skip initially |
| Double-click detection | Custom NSClickGestureRecognizer wrapper | SwiftUI `.onTapGesture(count: 2)` | Works in SwiftUI views, even inside NSPanel with `canBecomeKey = true` |

## Common Pitfalls

### Pitfall 1: Self-Paste Loop

**What goes wrong:** When PasteService writes to NSPasteboard for paste-back, the ClipboardMonitor detects this as a new clipboard change and creates a duplicate history entry.

**Why it happens:** The monitor polls every 0.5s and sees a new changeCount.

**How to avoid:** Set `clipboardMonitor.skipNextChange = true` immediately before writing to the pasteboard. The existing flag in ClipboardMonitor.checkForChanges() already handles this -- it resets the flag and skips processing. This is already implemented in the codebase.

**Warning signs:** Duplicate entries appearing after every paste-back.

**Confidence:** HIGH -- this is already coded into ClipboardMonitor.swift and just needs to be triggered.

### Pitfall 2: CGEvent Timing -- Paste Goes to Wrong App or Is Lost

**What goes wrong:** The CGEvent is posted before the panel has fully hidden or before the target app has regained input focus, causing the paste to go to the wrong app or be silently dropped.

**Why it happens:** `panel.orderOut()` and the animation completion are asynchronous. Posting CGEvent synchronously after calling hide() races with the panel dismissal.

**How to avoid:** Use `DispatchQueue.main.asyncAfter(deadline: .now() + 0.05)` (50ms delay) between hiding the panel and posting the CGEvent. This gives macOS time to route focus back. Maccy uses this exact timing.

**Warning signs:** Paste works inconsistently, especially with fast double-clicks.

**Confidence:** HIGH -- verified through Maccy source code.

### Pitfall 3: Secure Input Blocks Paste Silently

**What goes wrong:** When the user has a secure input field active (password fields, banking apps, 1Password), CGEvent posting is silently blocked. The paste appears to do nothing.

**Why it happens:** Secure Event Input (enabled via EnableSecureEventInput()) prevents CGEvent injection as a security measure.

**How to avoid:** Check `IsSecureEventInputEnabled()` before attempting CGEvent paste. If true, still write to pasteboard but show a brief notification: "Content copied. Paste manually with Cmd+V (secure input detected)." The user can then paste manually.

**Warning signs:** "Paste doesn't work" reports from users in banking/password contexts.

**Confidence:** HIGH -- IsSecureEventInputEnabled is a documented Carbon API. Apple TN2150 covers this.

### Pitfall 4: Sandbox Blocks CGEvent Posting

**What goes wrong:** The current entitlements file has `com.apple.security.app-sandbox = true`. CGEvent posting requires Accessibility permission which is incompatible with App Sandbox.

**Why it happens:** Sandboxed apps cannot post synthetic keyboard events to other applications.

**How to avoid:** Remove `com.apple.security.app-sandbox` from Pastel.entitlements. Set it to `false` or remove the key entirely. This is a Phase 3 prerequisite that must happen before any paste-back code can work.

**Warning signs:** CGEvent post calls succeed (no error) but the target app never receives the paste. This is a silent failure.

**Confidence:** HIGH -- this is a well-documented Apple restriction. The project MEMORY.md already notes "Direct distribution (no App Sandbox)."

### Pitfall 5: Panel Focus Interferes with Paste Target

**What goes wrong:** If the panel becomes the active/main window, CGEvent Cmd+V pastes into the panel itself rather than the target app.

**Why it happens:** The panel incorrectly activates the Pastel process.

**How to avoid:** The current NSPanel configuration is correct: `styleMask: [.nonactivatingPanel]`, `canBecomeKey = true`, `canBecomeMain = false`. Do NOT change `canBecomeMain` to `true`. The non-activating style mask prevents Pastel from becoming the frontmost app. This is verified working from Phase 2.

**Warning signs:** macOS menu bar shows "Pastel" menus instead of the target app's menus when the panel is open.

**Confidence:** HIGH -- NSPanel nonactivatingPanel behavior is verified by Phase 2 implementation.

### Pitfall 6: .onKeyPress Not Working in NSPanel Context

**What goes wrong:** SwiftUI `.onKeyPress` modifiers attached to views hosted inside an NSPanel via NSHostingView may not receive key events if the focus chain is not correctly set up.

**Why it happens:** The NSPanel must be the key window, and the SwiftUI view must have `.focusable()` with the focus state bound. If the NSHostingView does not correctly forward first responder status to the SwiftUI focus system, key events are lost.

**How to avoid:** Ensure PanelContentView has `.focusable()` and `.focused($isFocused)` with `isFocused` set to `true` when the panel appears. If this does not work, fall back to the NSEvent local monitor approach (Pattern 3 fallback) which is guaranteed to work since it operates at the AppKit level.

**Warning signs:** Arrow keys and Enter do nothing when the panel is open.

**Confidence:** MEDIUM -- .onKeyPress in NSPanel is not extensively documented. The fallback (local monitor) is HIGH confidence.

## Code Examples

### Writing Rich Text to Pasteboard (All Representations)

```swift
// Source: NSPasteboard documentation + Maccy pattern
let pasteboard = NSPasteboard.general
pasteboard.clearContents()

// Write RTF first (richest), then HTML, then plain text
// Apps will pick the richest format they support
if let rtfData = item.rtfData {
    pasteboard.setData(rtfData, forType: .rtf)
}
if let html = item.htmlContent {
    pasteboard.setString(html, forType: .html)
}
if let text = item.textContent {
    pasteboard.setString(text, forType: .string)
}
```

**Confidence:** HIGH -- NSPasteboard supports multiple types per write. The receiving app picks the richest format it supports.

### Writing Image to Pasteboard

```swift
// Source: NSPasteboard documentation
let pasteboard = NSPasteboard.general
pasteboard.clearContents()

if let imagePath = item.imagePath {
    let imageURL = ImageStorageService.shared.resolveImageURL(imagePath)
    if let imageData = try? Data(contentsOf: imageURL) {
        // Write as PNG (most universal)
        pasteboard.setData(imageData, forType: .png)
        // Also write as TIFF for apps that prefer it
        if let nsImage = NSImage(data: imageData),
           let tiffData = nsImage.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
        }
    }
}
```

**Confidence:** HIGH -- standard NSPasteboard image writing pattern.

### Writing File URL to Pasteboard

```swift
// Source: NSPasteboard documentation
let pasteboard = NSPasteboard.general
pasteboard.clearContents()

if let filePath = item.textContent {
    // item.textContent stores the file path for file-type items
    let fileURL = URL(fileURLWithPath: filePath)
    // writeObjects handles the proper UTI conversions
    pasteboard.writeObjects([fileURL as NSURL])
}
```

**Confidence:** HIGH -- `writeObjects` with NSURL is the standard file URL pasteboard pattern.

### CGEvent Paste Simulation (Verified from Maccy)

```swift
// Source: Maccy Clipboard.swift (verified via GitHub)
// Virtual key code 0x09 = kVK_ANSI_V (layout-independent)
private static func simulatePaste() {
    let source = CGEventSource(stateID: .combinedSessionState)
    source?.setLocalEventsFilterDuringSuppressionState(
        [.permitLocalMouseEvents, .permitSystemDefinedEvents],
        state: .eventSuppressionStateSuppressionInterval
    )

    let vKeyCode: CGKeyCode = 0x09

    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)

    keyDown?.flags = .maskCommand
    keyUp?.flags = .maskCommand

    keyDown?.post(tap: .cgSessionEventTap)
    keyUp?.post(tap: .cgSessionEventTap)
}
```

**Key details:**
- `CGEventSource(stateID: .combinedSessionState)` -- combines all event sources
- `setLocalEventsFilterDuringSuppressionState` -- suppresses local keyboard events during paste to avoid interference
- `0x09` -- virtual key code for V (layout-independent, works on Dvorak/Colemak/etc.)
- `.maskCommand` -- Command modifier flag
- `.cgSessionEventTap` -- posts to the session-level event tap (reaches the frontmost app)

**Confidence:** HIGH -- directly verified from Maccy source code on GitHub.

### Accessibility Permission Check

```swift
// Source: Apple Developer Documentation
import ApplicationServices

// Quick check (call before every paste)
let trusted = AXIsProcessTrusted()

// Check with prompt (call once during onboarding)
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
let trustedWithPrompt = AXIsProcessTrustedWithOptions(options)

// Open Settings directly to Accessibility pane
if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
    NSWorkspace.shared.open(url)
}

// Check for secure input (call before paste)
import Carbon
let secureInputActive = IsSecureEventInputEnabled()
```

**Confidence:** HIGH -- stable Apple APIs verified through official documentation.

### Double-Click on Card

```swift
// Source: SwiftUI documentation
ClipboardCardView(item: item, isSelected: selectedIndex == index)
    .onTapGesture(count: 2) {
        pasteItem(item)
    }
    .onTapGesture(count: 1) {
        selectedIndex = index
    }
```

**Important:** Place the double-click handler BEFORE the single-click handler. SwiftUI processes multi-tap gestures with higher count first.

**Confidence:** MEDIUM -- `.onTapGesture(count: 2)` is standard SwiftUI. In non-activating NSPanel context, clicks may require the view to accept first mouse. If issues arise, use the `acceptClickThrough()` modifier pattern (NSViewRepresentable with `acceptsFirstMouse` override).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Carbon RegisterEventHotKey for global hotkeys | KeyboardShortcuts library (wraps Carbon) | Already adopted in Phase 2 | No change needed |
| NSEvent.addLocalMonitorForEvents for key handling | SwiftUI .onKeyPress (macOS 14+) | WWDC 2023 | Can use native SwiftUI for arrow/Enter key handling |
| Manual CGEvent flag construction | CGEventFlags enum in Swift | Swift 5+ | Cleaner code but same underlying API |
| Polling AXIsProcessTrusted on a timer | Still polling (no notification API) | Never changed | Must poll or check per-operation |

**Not deprecated:**
- CGEvent APIs -- still the standard for event simulation
- AXIsProcessTrusted -- still the only accessibility check API
- NSPasteboard write APIs -- stable since macOS 10.0
- IsSecureEventInputEnabled -- still functional (Carbon API but not deprecated)

## Open Questions

1. **`.onKeyPress` reliability inside NSPanel/NSHostingView**
   - What we know: `.onKeyPress` requires `.focusable()` and works on macOS 14+. The panel has `canBecomeKey = true`.
   - What's unclear: Whether the SwiftUI focus system correctly receives key events when hosted inside an NSPanel via NSHostingView. No documentation explicitly covers this case.
   - Recommendation: Implement `.onKeyPress` first. If key events are not received, immediately fall back to extending the existing NSEvent local monitor in PanelController. The local monitor approach is guaranteed to work.

2. **Image paste-back for non-PNG apps**
   - What we know: Writing PNG data to pasteboard works for most apps. Some apps prefer TIFF.
   - What's unclear: Whether all target apps correctly handle PNG from pasteboard.
   - Recommendation: Write both PNG and TIFF representations when pasting images. This maximizes compatibility.

3. **Accessibility permission after app re-signing**
   - What we know: Re-signing or updating the app binary can invalidate the Accessibility permission entry in System Settings, requiring the user to remove and re-add the app.
   - What's unclear: Whether this affects development builds signed with `-` (ad-hoc signing).
   - Recommendation: Check permission before every paste (already planned). If permission was previously granted but is now denied, show a message explaining the user may need to re-add the app.

4. **Panel auto-dismiss timing after paste**
   - What we know: The panel should hide before CGEvent is posted (Maccy pattern).
   - What's unclear: Whether to animate the hide or use immediate orderOut for faster paste response.
   - Recommendation: Use a faster hide (skip or shorten animation) when pasting, vs. the normal animated hide when dismissing with Escape/click-outside. The 50ms delay before CGEvent gives enough time for immediate orderOut.

## Integration Points with Existing Code

| Existing Component | How Phase 3 Integrates | Changes Needed |
|-------------------|------------------------|----------------|
| **ClipboardMonitor.skipNextChange** | PasteService sets this to `true` before writing to pasteboard | None -- flag already exists and is handled in checkForChanges() |
| **PanelController.hide()** | PasteService calls this before simulating Cmd+V | May need a fast-hide variant (no animation) for paste-back |
| **PanelController.show()** | Must capture `NSWorkspace.shared.frontmostApplication` before showing | Add `previousApp` property |
| **PanelContentView** | Add selection state, keyboard navigation, paste action callback | Major changes: @State selectedIndex, .onKeyPress modifiers, paste callback |
| **ClipboardCardView** | Add `isSelected` parameter, double-click handler, selection highlight | Add isSelected binding, visual highlight, .onTapGesture(count: 2) |
| **AppState** | Wire PasteService, pass it to panel content view | Add pasteService property, pass to PanelContentView environment |
| **Pastel.entitlements** | Remove app-sandbox, keep files.user-selected.read-write (or remove both) | Change `com.apple.security.app-sandbox` to `false` or remove entirely |
| **project.yml** | May need entitlements update if using XcodeGen | Verify entitlements path still correct after modification |

## Sandbox Removal Details

**Current entitlements:**
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

**Required entitlements for Phase 3:**
```xml
<!-- Remove or set to false:
<key>com.apple.security.app-sandbox</key>
<false/>
-->
<!-- Remove files.user-selected.read-write (only needed inside sandbox):
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
-->
```

The entitlements file can be empty (just the plist boilerplate) or removed entirely for a non-sandboxed app. The `files.user-selected.read-write` entitlement is a sandbox sub-entitlement and has no meaning outside the sandbox.

**Impact on existing functionality:**
- ImageStorageService uses `~/Library/Application Support/Pastel/images/` -- works without sandbox (actually easier, no container redirection)
- SwiftData stores in default location -- works without sandbox
- NSPasteboard reading -- works without sandbox
- KeyboardShortcuts -- works without sandbox (uses Carbon APIs internally)
- No existing functionality depends on sandbox

**Confidence:** HIGH -- removing sandbox is straightforward and the project MEMORY.md already mandates it.

## Sources

### Primary (HIGH confidence)
- [Maccy Clipboard.swift](https://github.com/p0deje/Maccy/blob/master/Maccy/Clipboard.swift) -- CGEvent paste simulation, pasteboard writing, self-paste prevention pattern
- [Apple Developer Documentation: AXIsProcessTrusted](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted) -- Accessibility permission API
- [Apple Developer Documentation: NSWorkspace.frontmostApplication](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication) -- Active app tracking
- [Apple TN2150: Using Secure Event Input Fairly](https://developer.apple.com/library/archive/technotes/tn2150/_index.html) -- Secure input detection
- [Apple Developer Forums: CGEvent paste simulation](https://developer.apple.com/forums/thread/659804) -- CGEvent patterns and limitations
- Existing Pastel codebase: ClipboardMonitor.swift (skipNextChange), PanelController.swift (local monitor), SlidingPanel.swift (canBecomeKey)

### Secondary (MEDIUM confidence)
- [Accessibility Permission Guide](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html) -- Permission request patterns, verified against Apple docs
- [NSPanel Nonactivating Behavior Deep Dive](https://philz.blog/nspanel-nonactivating-style-mask-flag/) -- NSPanel activation internals
- [SwiftUI Key Press Events - SwiftLee](https://www.avanderlee.com/swiftui/key-press-events-detection/) -- .onKeyPress usage patterns
- [Hacking with Swift: Key Press Events](https://www.hackingwithswift.com/quick-start/swiftui/how-to-detect-and-respond-to-key-press-events) -- .onKeyPress availability and examples
- [Click-Through for Inactive Windows](https://christiantietze.de/posts/2024/04/enable-swiftui-button-click-through-inactive-windows/) -- acceptsFirstMouse pattern for NSPanel click handling
- [Spotlight-like Panel in SwiftUI](https://www.markusbodner.com/til/2021/02/08/create-a-spotlight/alfred-like-window-on-macos-with-swiftui/) -- NSPanel + SwiftUI integration patterns

### Tertiary (LOW confidence)
- [Swift Virtual KeyCode Gist](https://gist.github.com/swillits/df648e87016772c7f7e5dbed2b345066) -- Key code reference (verified 0x09 = V via multiple sources)
- [Requesting macOS Permissions](https://gannonlawlor.com/posts/macos_privacy_permissions/) -- General permission patterns
- [Maccy App Store Listing](https://maccy.app/) -- Feature reference for clipboard managers

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- CGEvent, AXIsProcessTrusted, NSPasteboard are mature, stable Apple APIs
- Architecture (PasteService, flow): HIGH -- directly verified from Maccy source code
- Keyboard navigation (.onKeyPress): MEDIUM -- API available on macOS 14+ but untested in NSPanel/NSHostingView context
- Accessibility permission flow: HIGH -- stable API, well-documented pattern
- Sandbox removal: HIGH -- straightforward, already planned in MEMORY.md
- Double-click handling: MEDIUM -- standard SwiftUI but may need acceptsFirstMouse in NSPanel

**Research date:** 2026-02-06
**Valid until:** 2026-03-06 (stable APIs, low churn risk)
