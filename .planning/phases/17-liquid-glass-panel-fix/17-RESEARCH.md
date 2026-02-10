# Phase 17: Liquid Glass Panel Fix - Research

**Researched:** 2026-02-10
**Domain:** macOS 26 Liquid Glass rendering verification, NSPanel activation lifecycle, automated screenshot comparison, paste-back timing
**Confidence:** HIGH

## Summary

Phase 17 is a **verification and polish** phase, not a build-from-scratch phase. The core implementation (NSGlassEffectView, NSApp.activate() on show, previousApp.activate() on hide, DistributedNotification routing for hotkey) is already complete from quick tasks 017/018. The remaining work is:

1. **Visual verification** that the glass actually renders correctly when triggered via the global hotkey
2. **Functional verification** that paste-back, dismiss behaviors, and edge cases all work
3. **Automated screenshot comparison** to prove hotkey-triggered and notification-triggered panels produce identical glass
4. **Debug logging cleanup** once verified
5. **Edge case hardening** for rapid toggle, deactivation races, etc.

**Primary recommendation:** Build a lightweight test harness using `screencapture -l <windowID>` and pixel comparison to automate visual verification, then systematically test each dismiss/paste-back path. Remove debug logging after all tests pass.

## Standard Stack

The established libraries/tools for this domain:

### Core (Already Implemented)
| Library/API | Version | Purpose | Status |
|-------------|---------|---------|--------|
| NSGlassEffectView | macOS 26+ | Native Liquid Glass at AppKit layer | Implemented in PanelController.createPanel() |
| NSApp.activate() | AppKit | Force app activation for full glass rendering | Implemented in PanelController.show() |
| NSRunningApplication.activate() | AppKit | Re-activate previous app on panel hide | Implemented in PanelController.hide() |
| DistributedNotificationCenter | Foundation | Route hotkey out of Carbon handler context | Implemented in AppState.setupPanel() |
| NSVisualEffectView | AppKit | Pre-macOS 26 fallback blur | Implemented in PanelController.createPanel() |

### Testing/Verification Tools
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `screencapture -l <windowID> -x <file>` | Capture specific window screenshot silently | Automated visual comparison |
| NSWindow.windowNumber | Get CGWindowID for screencapture -l | Identifying the panel window |
| CGWindowListCopyWindowInfo | List all windows with IDs, names, owners | Finding window IDs from CLI |
| vImage / CoreImage pixel comparison | Compare two screenshots programmatically | Asserting glass quality match |
| `defaults write` | Toggle "Reduce Transparency" for testing | Accessibility fallback testing |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| screencapture -l | ScreenCaptureKit (SCScreenshotManager) | SCK requires Screen Recording permission and more code; screencapture -l is simpler for one-off captures |
| CGWindowListCreateImage | screencapture CLI | CGWindowListCreateImage is deprecated in macOS 15; screencapture -l is the supported path |
| Manual visual inspection | Automated pixel comparison | Manual is faster for initial check but not repeatable; automated proves consistency |

## Architecture Patterns

### Current Implementation Architecture (Already Built)

```
User presses Option+V (global hotkey)
    |
    v
Carbon RegisterEventHotKey fires
    |
    v
KeyboardShortcuts.onKeyUp posts DistributedNotification
  (escapes Carbon handler context that blocks NSApp.activate())
    |
    v
DistributedNotification observer on main queue
    |
    v
AppState.togglePanel() -> PanelController.show()
    |
    v
PanelController.show():
  1. Captures previousApp = NSWorkspace.shared.frontmostApplication
  2. Sets panel frame off-screen, orderFrontRegardless, makeKey
  3. Calls NSApp.activate() (LSUIElement=true, invisible activation)
  4. Animates panel on-screen (0.1s easeOut)
  5. Installs event monitors (click-outside, Escape, deactivation)
    |
    v
Panel visible with full Liquid Glass (NSGlassEffectView + active app)
    |
    v  (user selects item to paste)
PanelController.hide():
  1. Animates panel off-screen (0.1s easeIn)
  2. In completion handler: orderOut, removeEventMonitors
  3. previousApp?.activate() (returns focus to original app)
  4. previousApp = nil
    |
    v  (after 250ms delay in PasteService)
CGEvent Cmd+V simulation fires into now-frontmost previous app
```

### Pattern 1: Screenshot Comparison Test Harness

**What:** A shell script or Swift test that captures the panel under two trigger methods and compares pixel output.

**When to use:** Verification that glass rendering is identical regardless of trigger path.

**Approach:**
```bash
# 1. Get the panel's CGWindowID from within the app
#    NSWindow.windowNumber gives the CGWindowID directly

# 2. Trigger panel via hotkey, wait for render, capture
screencapture -l$WINDOW_ID -x /tmp/panel-hotkey.png

# 3. Dismiss, trigger via DistributedNotification, wait, capture
screencapture -l$WINDOW_ID -x /tmp/panel-notification.png

# 4. Compare the two images (pixel diff)
```

The app can expose the windowNumber via a debug helper or log it. The `screencapture -l` flag captures a specific window by its CGWindowID. The `-x` flag suppresses the shutter sound. The `-o` flag excludes window shadow if needed for cleaner comparison.

### Pattern 2: Activation State Verification

**What:** Log-based verification that NSApp.isActive is true when the panel is visible.

**When to use:** Confirming the activation dance works correctly.

**Current implementation already has this:**
```swift
// In PanelController.show():
logger.info("Before activate: isActive=\(NSApp.isActive), isKey=\(panel.isKeyWindow)")
NSApp.activate()
logger.info("After activate: isActive=\(NSApp.isActive), isKey=\(panel.isKeyWindow)")

// 200ms check
logger.info("200ms later: isActive=\(NSApp.isActive), panel.isKey=\(panel.isKeyWindow)")
// 500ms check
logger.info("500ms later: isActive=\(NSApp.isActive), panel.isKey=\(panel.isKeyWindow)")
```

**Expected values for correct glass:** `isActive=true` at all checkpoints while panel is visible.

### Pattern 3: Paste-Back Timing Chain

**What:** The sequence of events from paste trigger to CGEvent delivery.

**Current timing:**
1. User action triggers paste (Enter key, double-click, context menu)
2. PasteService.paste() writes to NSPasteboard
3. Sets clipboardMonitor.skipNextChange = true
4. Calls panelController.hide()
5. hide() animates off-screen (0.1s)
6. In animation completion: previousApp?.activate()
7. After 250ms from step 4: CGEvent Cmd+V fires

**Critical timing analysis:**
- Panel animation: 100ms
- Animation completion fires: ~100ms after hide() called
- previousApp.activate(): fires at ~100ms
- CGEvent delay: 250ms from hide() call
- Gap between app reactivation and CGEvent: ~150ms

This 150ms gap should be sufficient for the previous app to become frontmost and ready to receive keyboard events. The existing 250ms delay was chosen to exceed the panel hide animation + re-activation time.

### Anti-Patterns to Avoid

- **Calling NSApp.activate() inside the Carbon event handler:** The Carbon RegisterEventHotKey handler runs in a context that blocks NSApp.activate(). The DistributedNotification routing already solves this.
- **Using .nonactivatingPanel style mask:** This prevents the compositor from rendering full Liquid Glass. Already removed in SlidingPanel.swift.
- **Glass-on-glass stacking:** The GlassEffectModifier correctly passes through on macOS 26+ since NSGlassEffectView handles glass at the AppKit layer.
- **Polling NSApp.isActive in a tight loop:** Activation state changes propagate on the next run loop turn. The existing delayed checks (200ms, 500ms) are the right approach.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Window screenshot capture | CGWindowListCreateImage (deprecated) | `screencapture -l <windowID> -x` CLI | CGWindowListCreateImage deprecated in macOS 15; screencapture is the supported tool |
| Image pixel comparison | Manual pixel-by-pixel loop | vImage differencing or simple histogram comparison | Edge cases with subpixel rendering, color profiles |
| Window ID discovery | Parsing CGWindowListCopyWindowInfo from CLI | NSWindow.windowNumber property (available in-app) | Direct access from the panel reference |
| App activation timing | Custom run loop polling | DispatchQueue.main.asyncAfter with fixed delays | Run loop turn timing is not guaranteed; fixed delays are more reliable for this use case |
| Glass quality detection | ML-based image analysis | Human visual inspection + screenshot diff | Glass quality is a visual property; pixel-identical screenshots prove consistency |

**Key insight:** The verification tooling is lightweight CLI + simple scripting. Do not over-engineer the test harness -- this is a one-time verification phase, not a permanent CI pipeline.

## Common Pitfalls

### Pitfall 1: Deactivation Observer Dismisses Panel Prematurely
**What goes wrong:** The `NSApplication.didResignActiveNotification` observer in PanelController dismisses the panel when the app loses active status. If another app momentarily takes focus (e.g., notification banner, Spotlight), the panel disappears unexpectedly.
**Why it happens:** The observer fires for ALL deactivation events, not just intentional ones like Cmd+Tab.
**How to avoid:** This is actually the correct behavior -- if the user switches away, the panel should dismiss. The existing `isDragging` guard prevents dismissal during drag sessions. No additional guards needed unless testing reveals false-positive dismissals.
**Warning signs:** Panel disappearing when a notification banner appears or when clicking a menu bar extra.

### Pitfall 2: Rapid Toggle Race Condition
**What goes wrong:** User presses hotkey twice quickly. First press starts show(), second press hits toggle() while the first animation is in-flight. The panel could end up in an inconsistent state.
**Why it happens:** The 100ms animation is fast but not instant. `isVisible` becomes true as soon as `orderFrontRegardless` is called (before animation completes), so the second toggle should trigger hide(). But the hide animation could overlap with the show animation.
**How to avoid:** NSAnimationContext.runAnimationGroup animations are additive -- starting a new animation on the same property cancels the in-flight one. The second call to `setFrame` (now moving off-screen) should correctly override the first. Test this explicitly to confirm.
**Warning signs:** Panel stuck on-screen, panel visible but not responding to input, panel at wrong position.

### Pitfall 3: previousApp is nil After Rapid Toggle
**What goes wrong:** If the user toggles rapidly, the hide() completion handler sets `previousApp = nil`. If show() is called again before the completion handler fires, `previousApp` is already captured (from the first show). But if hide()'s completion fires between the second show()'s capture and the second hide(), it clears previousApp.
**Why it happens:** The completion handler from the first hide() fires asynchronously.
**How to avoid:** In show(), only capture previousApp if the panel is not already visible. The current code captures it unconditionally, which is actually fine because show() only runs when `isVisible` is false (toggle() gates this). Still worth testing.
**Warning signs:** After paste, focus returns to Pastel instead of the original app.

### Pitfall 4: CGEvent Cmd+V Fires Before Previous App is Frontmost
**What goes wrong:** The 250ms delay in PasteService may not be enough on slower systems or when the previous app is heavy (e.g., Xcode, Photoshop).
**Why it happens:** `previousApp?.activate()` is called in the animation completion handler. The activation is asynchronous -- the app may not be fully frontmost when the CGEvent fires 150ms later.
**How to avoid:** The 250ms delay has been working in production since Phase 3. If issues arise, increase to 350-500ms. Could also observe `NSWorkspace.shared.frontmostApplication` and only fire CGEvent when it matches previousApp, but this adds complexity for a rare edge case.
**Warning signs:** Paste fires into Pastel (panel already hidden but Pastel still frontmost) or paste silently drops.

### Pitfall 5: Liquid Glass Renders as Dark Blur Despite Activation
**What goes wrong:** Even with NSApp.activate(), the glass could render as a degraded blur if the activation doesn't fully propagate before the glass view renders.
**Why it happens:** NSApp.activate() is asynchronous. The panel is ordered front and animated BEFORE the activation may have fully propagated.
**How to avoid:** The current implementation calls NSApp.activate() AFTER orderFrontRegardless and makeKey. The debug logs at 200ms and 500ms will confirm activation state. If glass is still degraded, try calling NSApp.activate() BEFORE ordering the panel front, or add a short delay between activation and panel display.
**Warning signs:** Debug logs show isActive=false at any checkpoint while panel is visible.

### Pitfall 6: screencapture Requires Screen Recording Permission
**What goes wrong:** `screencapture -l` may fail or produce blank images if Terminal (or the test runner) doesn't have Screen Recording permission.
**Why it happens:** macOS privacy controls gate screen capture.
**How to avoid:** Ensure Terminal.app (or whatever runs the test script) is authorized in System Settings > Privacy & Security > Screen Recording.
**Warning signs:** Captured images are all-black or all-transparent.

### Pitfall 7: SDK Version Determines Glass Availability
**What goes wrong:** Glass effects don't render at all, even on macOS 26.
**Why it happens:** Apple checks the SDK version the executable was compiled against. If compiled with an older SDK, glass effects are disabled entirely (confirmed in rubicon-objc issue #648).
**How to avoid:** Ensure the project is compiled with Xcode 26 / macOS 26 SDK. This is already the case since the project targets macOS 26 features.
**Warning signs:** NSGlassEffectView exists but renders as opaque/flat.

## Code Examples

### Example 1: Getting Panel Window ID for screencapture

```swift
// In PanelController, expose the window number for testing
var panelWindowNumber: Int {
    panel?.windowNumber ?? 0
}
```

Usage from command line after getting the window number:
```bash
# Capture panel window (silent, no shadow for clean comparison)
screencapture -l$WINDOW_ID -x -o /tmp/panel-capture.png
```

### Example 2: Triggering Panel via DistributedNotification (for testing)

```bash
# From Terminal, trigger the panel toggle without a hotkey
# (The observer is already registered in AppState.setupPanel())
# The comment says "TEMPORARY" but it's exactly what we need for testing
osascript -e 'tell application "System Events" to do shell script "
/usr/bin/python3 -c \"
import Foundation
dnc = Foundation.NSDistributedNotificationCenter.defaultCenter()
dnc.postNotificationName_object_(\\\"app.pastel.togglePanel\\\", None)
\"
"'
```

Or more simply via Swift command-line tool or direct Foundation call.

### Example 3: Pixel Comparison Script Concept

```bash
#!/bin/bash
# Compare two panel screenshots for visual equivalence
# Uses ImageMagick 'compare' or simple file hash comparison

FILE1="/tmp/panel-hotkey.png"
FILE2="/tmp/panel-notification.png"

# Option A: Exact pixel match (strict)
if cmp -s "$FILE1" "$FILE2"; then
    echo "PASS: Screenshots are identical"
else
    echo "DIFF: Screenshots differ"
    # Generate visual diff
    compare "$FILE1" "$FILE2" /tmp/panel-diff.png 2>/dev/null
fi

# Option B: Perceptual hash comparison (tolerant of timing differences)
# sips can convert to raw pixels for comparison
HASH1=$(md5 -q "$FILE1")
HASH2=$(md5 -q "$FILE2")
echo "Hotkey:       $HASH1"
echo "Notification: $HASH2"
```

### Example 4: Verifying Activation State (Already in Codebase)

The debug logging in PanelController.show() already covers this:
```swift
// Lines 180-199 of PanelController.swift
logger.info("Before activate: isActive=\(NSApp.isActive), isKey=\(panel.isKeyWindow)")
NSApp.activate()
logger.info("After activate: isActive=\(NSApp.isActive), isKey=\(panel.isKeyWindow)")

DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
    self?.logger.info("200ms later: isActive=\(NSApp.isActive), panel.isKey=\(panel.isKeyWindow)")
}
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
    self?.logger.info("500ms later: isActive=\(NSApp.isActive), panel.isKey=\(panel.isKeyWindow)")
}
```

### Example 5: Cleanup -- Removing Debug Logging

After verification, remove these lines from PanelController.show():
```swift
// REMOVE these 6 lines:
logger.info("Before activate: isActive=\(NSApp.isActive), isKey=\(panel.isKeyWindow)")
// ...
logger.info("After activate: isActive=\(NSApp.isActive), isKey=\(panel.isKeyWindow)")
// ...
DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ... }
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ... }
```

And remove the "TEMPORARY" DistributedNotification observer comment (keep the observer itself -- it IS the production hotkey routing mechanism):
```swift
// REMOVE this comment:
// TEMPORARY: Allow toggling panel via DistributedNotification (for automated testing loop)
// Remove after liquid glass fix is verified

// KEEP the observer -- it's the production hotkey handler
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| .nonactivatingPanel on NSPanel | Remove .nonactivatingPanel, call NSApp.activate() manually | Quick task 017 (2026-02-09) | Panel activates Pastel for full glass, re-activates previous app on hide |
| SwiftUI .glassEffect on panel | NSGlassEffectView at AppKit layer | Quick task 018 (2026-02-09) | Glass rendered by compositor, not SwiftUI; avoids glass-on-glass with SwiftUI content |
| Direct hotkey -> togglePanel() | Hotkey -> DistributedNotification -> togglePanel() | Quick task 018 (2026-02-09) | Escapes Carbon handler context that blocks NSApp.activate() |
| CGWindowListCreateImage for screenshots | screencapture -l CLI | macOS 15 | CGWindowListCreateImage deprecated; screencapture -l is the supported approach |

**Still current:**
- NSVisualEffectView with .active state for pre-macOS 26 fallback (unchanged since macOS 10.10)
- CGEvent paste simulation (unchanged, works with Accessibility permission)
- Carbon RegisterEventHotKey for global hotkeys (legacy but stable)

## Open Questions

1. **Exact glass visual fidelity under activation**
   - What we know: NSGlassEffectView + active app should produce full lensing/refraction/specular. Debug logs confirm activation state.
   - What's unclear: Whether the glass renders fully on the FIRST frame or takes a few frames to "warm up" after activation. If screenshots are taken too early, they might capture a transitional state.
   - Recommendation: Add a 500ms delay after panel show before capturing screenshot. If glass still looks degraded, try 1000ms.

2. **Screenshot comparison tolerance**
   - What we know: Two captures of the same panel content should be pixel-identical if the glass pipeline is deterministic.
   - What's unclear: Whether the glass effect includes any time-dependent animation (specular shimmer, light tracking) that would make consecutive captures differ slightly.
   - Recommendation: Start with exact pixel match. If it fails due to animation, switch to histogram-based comparison with a small tolerance threshold.

3. **Edge case: panel toggle during paste-back delay**
   - What we know: PasteService fires CGEvent 250ms after hide(). If the user re-opens the panel within that 250ms, the CGEvent fires into Pastel's panel instead of the previous app.
   - What's unclear: How likely this is in practice (250ms is very fast for a human to re-press the hotkey).
   - Recommendation: Accept this as a known limitation. If testing reveals it's a real problem, gate the CGEvent on `!panelController.isVisible`.

## Verification Test Matrix

| Test | Trigger | Expected | How to Verify |
|------|---------|----------|---------------|
| Glass renders on hotkey | Option+V | Full liquid glass (lensing, refraction, specular) | Visual inspection + screenshot |
| Glass matches notification trigger | DistributedNotification | Identical to hotkey capture | Screenshot diff |
| Paste-back works | Select item + Enter | Panel hides, item pastes into previous app | Paste into TextEdit, verify content |
| Paste-back plain text | Shift+Enter | RTF stripped, plain text pasted | Paste into Notes, verify no formatting |
| Dismiss: click outside | Click outside panel | Panel slides away, previous app focused | Visual + check frontmostApplication |
| Dismiss: Escape | Press Escape | Panel slides away, previous app focused | Visual + check frontmostApplication |
| Dismiss: Cmd+Tab | Cmd+Tab to another app | Panel slides away, switched app focused | Visual |
| Rapid toggle | Option+V twice quickly | Panel shows then hides cleanly | Visual, no stuck panel |
| Drag keeps panel open | Start drag from card | Panel stays visible during drag | Visual |
| Drag self-capture prevention | Drop card into another app | No duplicate clipboard entry | Check clipboard history |
| Reduce Transparency | Enable in System Settings | Glass degrades gracefully to opaque | Visual |
| Debug logs present | Open Console.app, filter "PanelController" | Activation state logs visible | Console output |
| Debug logs removed | After cleanup | No activation debug logs | Console output |

## Sources

### Primary (HIGH confidence)
- Existing codebase: PanelController.swift, SlidingPanel.swift, AppState.swift, PasteService.swift, PanelContentView.swift -- direct code review
- [Apple: NSGlassEffectView Documentation](https://developer.apple.com/documentation/appkit/nsglasseffectview) -- API surface
- [Apple: screencapture man page](https://ss64.com/mac/screencapture.html) -- CLI flags including -l for window ID capture
- Quick task 017/018 RESEARCH.md and PLAN.md -- prior implementation decisions and rationale

### Secondary (MEDIUM confidence)
- [rubicon-objc Issue #648: macOS 26 Liquid Glass Effects Not Applied](https://github.com/beeware/rubicon-objc/issues/648) -- SDK version determines glass availability
- [Multi.app Blog: Nailing Activation Behavior](https://multi.app/blog/nailing-the-activation-behavior-of-a-spotlight-raycast-like-command-palette) -- NSPanel activation patterns for Spotlight-like UI
- [Apple: CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo) -- Window enumeration for screenshot capture
- [Apple: NSRunningApplication.activate](https://developer.apple.com/documentation/appkit/nsrunningapplication) -- Activation API

### Tertiary (LOW confidence)
- [HWS Forums: glassEffect in Floating Window/Panel](https://www.hackingwithswift.com/forums/swiftui/glasseffect-in-floating-window-panel/30067) -- Community reports of glass degradation in non-activating panels
- [Apple Developer Forums: CGEvent Not Working](https://developer.apple.com/forums/thread/773989) -- CGEvent timing considerations

## Metadata

**Confidence breakdown:**
- Implementation architecture: HIGH -- direct code review of already-implemented solution
- Activation/glass rendering: HIGH -- documented macOS behavior, confirmed by prior quick task research
- Screenshot comparison approach: HIGH -- screencapture -l is well-documented CLI tool
- Timing/race conditions: MEDIUM -- based on analysis of async code paths, not yet tested
- Edge cases: MEDIUM -- identified from code review and general macOS knowledge, needs validation

**Research date:** 2026-02-10
**Valid until:** 2026-03-10 (stable -- no fast-moving dependencies)
