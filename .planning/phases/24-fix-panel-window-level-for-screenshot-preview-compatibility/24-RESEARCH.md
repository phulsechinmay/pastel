# Phase 24: Fix Panel Window Level for Screenshot Preview Compatibility - Research

**Researched:** 2026-02-20
**Domain:** macOS window level hierarchy (NSWindow.Level / CGWindowLevel)
**Confidence:** MEDIUM

## Summary

The Pastel sliding panel currently uses `NSWindow.Level.statusBar` (raw value 25), which places it above most system UI including the Dock (level 20), Notification Center (level 21), and the main menu bar (level 24). The macOS screenshot floating thumbnail is rendered by the `Screenshot` app (process name "Screenshot", formerly `screencaptureui`). Through empirical testing, the Screenshot app's capture overlay window appears at level 24 (mainMenu). The floating thumbnail that appears after capture likely uses the same or a similar level (24-25 range), which means the panel at level 25 occludes it.

The fix is straightforward: lower the panel's window level from `.statusBar` (25) to a custom level between the Dock (20) and the screenshot thumbnail. Empirical testing on the current system confirms that levels 21-23 are used by Notification Center (21), Control Center (21), and Spotlight (23). A level of 23 or 24 would place the panel above the Dock and most system overlays while keeping it at or below the screenshot thumbnail.

**Primary recommendation:** Change the panel level from `.statusBar` (25) to `NSWindow.Level(rawValue: 23)` -- above the Dock (20), Notification Center (21), and Control Center (21), at the same level as Spotlight, but below the menu bar (24) and the screenshot overlay (24). If the screenshot thumbnail uses level 25, any level at 24 or below will work. Additionally, update the MEMORY.md reference that says "panel's level 25" to reflect the new level.

## Standard Stack

### Core

No new libraries needed. This is a single-line change to `NSWindow.Level`.

| API | Purpose | Why Standard |
|-----|---------|--------------|
| `NSWindow.Level(rawValue:)` | Set a custom window level between named constants | Apple's documented approach for custom levels |
| `CGWindowLevelForKey(_:)` | Query actual system level values at runtime | More future-proof than hardcoded integers |

## Architecture Patterns

### Pattern 1: Custom Window Level Using CGWindowLevelForKey

**What:** Use `CGWindowLevelForKey` to derive the level relative to known system levels rather than hardcoding raw integers. This is more resilient to Apple changing level values between OS versions.

**When to use:** When you need a window level between two named constants.

**Example:**
```swift
import CoreGraphics

// Above Dock (20) but below mainMenu (24)
let dockLevel = CGWindowLevelForKey(.dockWindow)       // 20
let mainMenuLevel = CGWindowLevelForKey(.mainMenuWindow) // 24

// Place panel 3 above the Dock -- at level 23
// This is above Notification Center (21) and Control Center (21)
// but below mainMenu (24) and Screenshot overlay (24)
level = NSWindow.Level(rawValue: Int(dockLevel) + 3)
```

### Pattern 2: Hardcoded Custom Level (Simpler)

**What:** Directly set the raw value since macOS window levels have been stable for many years.

**Example:**
```swift
// Simpler: just set level 23 directly
level = NSWindow.Level(rawValue: 23)
```

### Anti-Patterns to Avoid

- **Using `.floating` (level 3):** Too low. The panel would appear below the Dock (level 20), defeating its purpose as a screen-edge overlay.
- **Using `.popUpMenu` (level 101) or higher:** Way too high. Would be above everything including menus.
- **Dynamic level changing (raise/lower on screenshot detection):** Over-engineered. There is no reliable public notification for screenshot start/end on macOS. The `kMDItemIsScreenCapture` Spotlight metadata approach is broken in modern macOS and requires sandbox disabling.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Screenshot detection | NSMetadataQuery + kMDItemIsScreenCapture observer | Static lower window level | kMDItemIsScreenCapture approach is broken on modern macOS, requires disabling sandbox, and is unreliable |
| Dynamic window level switching | Timer-based or notification-based level toggling | Single correct static level | No public API to detect screenshot in progress; adds complexity for no benefit |

**Key insight:** The correct fix is choosing a static level in the right range, not dynamically adjusting levels.

## Empirical Window Level Data

Verified on this system (macOS 26, Tahoe) using `CGWindowLevelForKey` and `CGWindowListCopyWindowInfo`:

### CGWindowLevelForKey Values (HIGH confidence - empirically verified)

| Key | Raw Value | NSWindow.Level Equivalent |
|-----|-----------|---------------------------|
| `.baseWindow` | -2147483648 | N/A |
| `.desktopWindow` | -2147483623 | N/A |
| `.normalWindow` | 0 | `.normal` |
| `.floatingWindow` | 3 | `.floating` |
| `.tornOffMenuWindow` | 3 | `.tornOffMenu` |
| `.modalPanelWindow` | 8 | `.modalPanel` |
| `.utilityWindow` | 19 | N/A |
| `.dockWindow` | 20 | N/A |
| `.mainMenuWindow` | 24 | `.mainMenu` |
| `.statusWindow` | 25 | `.statusBar` |
| `.popUpMenuWindow` | 101 | `.popUpMenu` |
| `.overlayWindow` | 102 | N/A |
| `.helpWindow` | 200 | N/A |
| `.draggingWindow` | 500 | N/A |
| `.screenSaverWindow` | 1000 | `.screenSaver` |
| `.assistiveTechHighWindow` | 1500 | N/A |
| `.cursorWindow` | 2147483630 | N/A |

### Actual System Windows Observed (HIGH confidence - empirically verified)

| Window Owner | Level | Notes |
|-------------|-------|-------|
| Dock | 20 | The Dock bar itself |
| Notification Center | 21 | Full-screen overlay |
| Control Center | 21 | Full-screen overlay |
| iTerm2 (floating) | 22 | App with "keep on top" |
| Spotlight | 23 | Search overlay |
| Window Server (Menubar) | 24 | The menu bar |
| **Screenshot** | **24** | Capture overlay (mainMenu level) |
| Control Center items | 25 | Status bar items (WiFi, Clock, Battery) |
| **Pastel (current)** | **25** | `.statusBar` -- **this is the problem** |
| VS Code (title bar) | 26 | App-specific UI element |
| Menu bar extras | 103 | App menu items in bar |
| Chrome notification | 999 | Near screenSaver level |
| Claude overlay | 1000 | At screenSaver level |
| Control Center popup | 2005 | Above assistiveTechHigh |

### Screenshot Thumbnail Level (MEDIUM confidence)

The screenshot floating thumbnail is rendered by the `Screenshot` process. The capture overlay appears at level 24 (mainMenu level). The floating thumbnail that appears after capture in the bottom-right corner is managed by the same process. While I could not directly observe the thumbnail's window level during testing (automated screenshot triggers bypass the thumbnail), the `Screenshot` process consistently uses level 24 for its UI windows.

**Reasoning for level 24:** The Screenshot app's UI windows at level 24 means any panel at level 25 (`statusBar`) will be rendered in front of them. Lowering the panel to level 23 ensures it renders behind the Screenshot app's windows (both the capture overlay and the floating thumbnail).

## Common Pitfalls

### Pitfall 1: Panel Appearing Below the Dock
**What goes wrong:** Setting the level too low (e.g., `.floating` = 3) causes the panel to appear behind the Dock.
**Why it happens:** The Dock window is at level 20. Any level below 20 will be behind it.
**How to avoid:** Ensure level is > 20. The recommended level 23 satisfies this.
**Warning signs:** Panel visually clips behind the Dock bar.

### Pitfall 2: Breaking the Liquid Glass Helper
**What goes wrong:** The MEMORY.md mentions "level 0 vs panel's level 25" for the glass helper. Changing the panel level could affect the glass rendering if the delta between the Settings window (level 0) and panel matters.
**Why it happens:** The glass helper relies on the Settings window at level 0 being behind the panel. The panel level change from 25 to 23 still maintains this relationship (23 > 0), so this should NOT be an issue.
**How to avoid:** Verify Liquid Glass still renders correctly after the level change. The absolute difference (23 vs 25) should not matter -- only the relative ordering (panel > settings window).
**Warning signs:** Degraded glass effects (no lensing/refraction) after the change.

### Pitfall 3: Panel Appearing Below Spotlight
**What goes wrong:** If Spotlight is at level 23 and the panel is also at 23, their z-order depends on which was most recently made key/ordered front.
**Why it happens:** Windows at the same level follow standard z-ordering rules (most recent to front).
**How to avoid:** This is actually acceptable behavior. When Spotlight is active, it should be above the clipboard panel. When the panel is active, it should be above Spotlight. Same-level z-ordering handles this naturally.
**Warning signs:** None -- this is expected behavior.

### Pitfall 4: ColorToolController Also Uses .statusBar
**What goes wrong:** `ColorToolController.swift` at line 26 also sets `panel.level = .statusBar`. If only SlidingPanel is changed, the color tool panel will be inconsistent.
**Why it happens:** The color tool panel was set to match the main panel level.
**How to avoid:** Update both SlidingPanel and ColorToolController to use the same new level.
**Warning signs:** Color picker panel appearing above/below the main panel inconsistently.

### Pitfall 5: MEMORY.md References Level 25
**What goes wrong:** The project MEMORY.md says "level 0 vs panel's level 25". After this fix, the panel will be at level 23, making this documentation stale.
**Why it happens:** Documentation wasn't updated with the code change.
**How to avoid:** Update MEMORY.md to reflect the new panel level value.

## Code Examples

### The Fix (SlidingPanel.swift)
```swift
// Before:
level = .statusBar  // rawValue 25 -- above screenshot thumbnail

// After (Option A -- relative to system level, more future-proof):
let dockLevel = Int(CGWindowLevelForKey(.dockWindow))  // 20
level = NSWindow.Level(rawValue: dockLevel + 3)        // 23

// After (Option B -- simple hardcoded value):
level = NSWindow.Level(rawValue: 23)  // Above Dock(20), below Screenshot(24)
```

### ColorToolController.swift Fix
```swift
// Before:
panel.level = .statusBar

// After (match the panel):
let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
panel.level = NSWindow.Level(rawValue: dockLevel + 3)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `.statusBar` (level 25) | Custom level 23 | Phase 24 | Panel no longer occludes screenshot thumbnail |

**Note:** NSWindow.Level raw values have been stable across macOS versions for many years. The CGWindowLevelForKey approach adds a layer of future-proofing but is likely unnecessary given Apple's track record of stability here.

## Open Questions

1. **Exact screenshot thumbnail window level**
   - What we know: The Screenshot process uses level 24 for its capture overlay. The floating thumbnail is managed by the same process.
   - What's unclear: Whether the floating thumbnail uses exactly level 24 or a different level (e.g., 25 or higher). Automated testing could not trigger the real floating thumbnail.
   - Recommendation: Set panel to level 23 (safely below 24). If the thumbnail is at 24+, this works. If somehow the thumbnail is at 23 or lower (extremely unlikely -- it needs to be above normal app windows), then we'd need to revisit. **Validate manually after implementation** by taking a screenshot while the panel is open.

2. **Level 22 vs 23 vs 24**
   - What we know: Level 21 = Notification Center/Control Center. Level 23 = Spotlight. Level 24 = main menu bar and Screenshot.
   - What's unclear: Whether level 22 or 23 is more appropriate.
   - Recommendation: Use level 23. It puts the panel above Notification Center (21) and at the same level as Spotlight (23), which is natural since both are app-level overlays. Level 22 would also work but 23 gives the panel more visual priority.

3. **Impact on macOS 26 Liquid Glass rendering**
   - What we know: Glass helper creates Settings window at level 0, panel is above it. The glass pipeline depends on the app being active and a standard NSWindow existing, not on the exact level delta.
   - What's unclear: Whether the compositor has any hard-coded checks for specific window levels.
   - Recommendation: Test Liquid Glass rendering after the change. If degraded, the level change is not the cause (activation state is).

## Sources

### Primary (HIGH confidence)
- **Empirical CGWindowLevelForKey output** - Ran `CGWindowLevelForKey` for all 21 key types on macOS 26 (Tahoe). Values verified live on this system.
- **Empirical CGWindowListCopyWindowInfo output** - Enumerated all on-screen windows with their owners, levels, and dimensions. Confirmed Dock=20, Notification Center=21, Spotlight=23, Menu Bar=24, Screenshot=24, Status items=25.
- [NSWindow.Level Apple Documentation](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct)
- [CGWindowLevelForKey Apple Documentation](https://developer.apple.com/documentation/coregraphics/cgwindowlevelforkey(_:))

### Secondary (MEDIUM confidence)
- [James Fisher: "What is the order of NSWindow levels?"](https://jameshfisher.com/2020/08/03/what-is-the-order-of-nswindow-levels/) - Comprehensive mapping of NSWindow.Level to raw integers
- [Michel Fortin: "Choosing a Window Level"](https://michelf.ca/blog/2016/choosing-window-level/) - Practical guidance on custom window levels, demonstrates using relative offsets
- [CGWindowLevel.h gist](https://gist.github.com/rismay/ab10e87dc10a76c25986d52c65441bf2) - Raw header file with CGWindowLevel constants
- [macOS_headers screencaptureui](https://github.com/w0lfschild/macOS_headers/tree/master/macOS/CoreServices/screencaptureui) - Private framework headers showing screencaptureui architecture (ThumbnailLayerController, AnnotationsThumbWindow)

### Tertiary (LOW confidence)
- Screenshot thumbnail exact level: Could not empirically verify the floating thumbnail's exact window level (automated screenshot triggers bypass the thumbnail UI). Inferred to be level 24 based on the Screenshot process's observed capture overlay level.

## Metadata

**Confidence breakdown:**
- Window level values: HIGH - empirically verified on this system with CGWindowLevelForKey
- System window layout: HIGH - empirically verified via CGWindowListCopyWindowInfo
- Screenshot thumbnail level: MEDIUM - inferred from Screenshot process behavior, not directly observed
- Fix recommendation: HIGH - reducing from 25 to 23 is well within the safe range above Dock

**Research date:** 2026-02-20
**Valid until:** 2026-06-20 (window levels are extremely stable across macOS versions)
