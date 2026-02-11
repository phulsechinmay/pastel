# Dark Panel Fix — Liquid Glass Degradation on macOS 26

## Problem Statement

On macOS 26 (Tahoe), Pastel's sliding clipboard panel renders **degraded Liquid Glass** — dark, opaque, with a black outline — instead of the expected translucent, light-tinted glass material. The degradation occurs specifically when the panel is the **only visible window** for the app.

### Conditions

- **App type**: LSUIElement (`Info.plist: Application is agent = YES`). No Dock icon, no Cmd+Tab entry.
- **Window type**: `NSPanel` subclass (`SlidingPanel`), `.statusBar` level (25), `.titled` + `.fullSizeContentView` styleMask, transparent background.
- **Glass provider**: `NSGlassEffectView` (AppKit-level, `.style = .regular`) layered underneath an `NSHostingView` containing `PanelContentView`.
- **Trigger**: Global hotkey (Cmd+Shift+V) via Carbon `RegisterEventHotKey` → `PanelController.toggle()`.

### Observed Behavior

| Scenario | Glass Rendering |
|----------|----------------|
| Panel shown via hotkey (only window) | **Degraded** — dark, opaque, black outline |
| Panel shown + Settings window open | **Correct** — translucent, light tint, proper glass |
| Panel shown + MenuBarExtra dropdown open | **Correct** — same as above |
| Settings closed while panel visible | **Degrades** back to dark |

### Root Cause (Best Understanding)

The macOS 26 compositor applies a **reduced glass rendering pipeline** for LSUIElement apps that only have NSPanel windows visible. The compositor appears to require at least one **standard titled NSWindow** (not NSPanel) to be on-screen before it enables full-quality Liquid Glass for the entire app. This is likely an optimization in the window server — agent apps without standard windows are treated as background/utility apps that don't need full glass compositing.

The Settings window (`NSWindow` with `[.titled, .closable, .resizable]`, level `.normal` (0)) satisfies this requirement. When it's visible, the compositor upgrades glass rendering for ALL of the app's windows, including the panel.

---

## What We Tried (and What Failed)

### Round 1: Panel Window Properties

These changes were made directly to `SlidingPanel` or `PanelController`. None fixed the glass.

| # | Approach | Result |
|---|----------|--------|
| 1 | `NSApp.activate(ignoringOtherApps: true)` instead of `NSApp.activate()` | No change |
| 2 | `canBecomeMain: true` on SlidingPanel | No change |
| 3 | `.titled` styleMask on NSPanel at `.statusBar` level | No change |
| 4 | Using NSWindow instead of NSPanel for the sliding panel | No change |
| 5 | `.titled, .closable, .resizable, .fullSizeContentView` on NSWindow | No change |
| 6 | `level = .floating` (3) instead of `.statusBar` (25) | No change |
| 7 | `level = .normal` (0) instead of `.statusBar` (25) | No change |
| 8 | Delayed re-activation 0.3s after panel show | No change |
| 9 | Direct hosting view as contentView (no container intermediary) | No change |

### Round 2: Isolating Content vs Window

| # | Test | Result | Conclusion |
|---|------|--------|------------|
| 1 | Replace PanelContentView with `Color.blue.opacity(0.2).glassEffect(.regular)` | **Perfect glass** | Panel window CAN render glass; the complex SwiftUI hierarchy is the issue |
| 2 | Split-layer: `PanelGlassBackground` NSHostingView underneath + PanelContentView on top | **Still degraded** | The glass layer underneath renders correctly but the content on top degrades the visual |
| 3 | NSGlassEffectView (AppKit) underneath + NSHostingView on top | **Still degraded** | Same result as SwiftUI split-layer |
| 4 | Removing `.preferredColorScheme(.dark)` | No fix | Dark mode forcing is not the cause |
| 5 | Removing `.environment(\.colorScheme, .dark)` | No fix | Same |

**Key finding**: Simple glass content ALONE in the panel window = correct. But with PanelContentView's complex hierarchy on top = degraded. However, this degradation is FIXED when a standard NSWindow is also visible.

### Round 3: Helper Window Approaches

All of these created custom NSWindow instances in `PanelController` to try to satisfy the compositor's standard-window requirement.

| # | Approach | Properties | Result |
|---|----------|------------|--------|
| 1 | Tiny helper (10x10, alpha 0.01) | `.titled`, `.clear` bg, corner position | **Failed** |
| 2 | Larger helper (200x200, alpha 0.05) | `.titled`, `makeKeyAndOrderFront` | **Failed** |
| 3 | Full helper (300x300, alpha 1.0, glass content) | `.titled, .closable, .resizable`, `Color.blue.opacity(0.2).glassEffect(.regular)`, dark appearance | Helper itself had correct glass, **panel still degraded** |
| 4 | Helper with GlassEffectContainer content | Same as #3 but with GlassEffectContainer + Color.clear | **Failed** |
| 5 | Helper shown 150ms AFTER panel visible | Same as #3, delayed timing | **Failed** |
| 6 | Helper with opaque background (no `.clear`, no `isOpaque = false`) | Matching Settings properties, alpha 0.01 | **Failed** |
| 7 | Helper at panel frame, alpha 1.0, behind panel (level 0) | Full alpha, completely covered by panel | **Failed** |
| 8 | Helper with full SettingsView content + modelContainer + environment | Exact SettingsView hierarchy, all modifiers | **Failed** |
| 9 | Helper with .glassProminent buttons (matching Settings' GlassEffectContainer) | Full glass button styles | **Failed** |
| 10 | Exact byte-for-byte clone of SettingsWindowController creation code | New NSWindow each time, same styleMask/properties/content/activation, center() then move to panelFrame | **Failed** |

### Round 4: Real SettingsWindowController

| # | Approach | Result |
|---|----------|--------|
| 1 | `SettingsWindowController.shared.showSettings()` called AFTER panel visible (from completion handler) | **WORKS** — glass upgrades in real-time |
| 2 | Settings window then repositioned behind panel at panelFrame | **WORKS** — glass stays correct after repositioning |
| 3 | Settings `orderOut` when panel hides | Works — glass degrades (expected, panel is also hiding) |

### The Mystery

Only `SettingsWindowController.shared.showSettings()` — the actual singleton — fixes the glass. An exact replica of the window creation code, called from the exact same location (completion handler), with the exact same content (SettingsView + modelContainer + environment), the exact same window properties, and the exact same activation sequence — does NOT work.

Possible explanations:
1. **Singleton lifecycle**: The singleton's strong `self.window` reference in a separate `@MainActor final class` creates a different retain graph that the window server tracks differently
2. **Window server registration**: Windows created by different object graphs may be registered differently in the compositor's tracking
3. **Subtle code differences**: Despite "byte-for-byte" attempts, there may have been a minor difference (e.g., `defer: true` vs `defer: false`, missing `.resizable`, timing)
4. **SettingsView's glass buttons**: SettingsView uses `GlassEffectContainer` with `.glassProminent` and `.glass` button styles — these may register with the compositor differently than passive glass content

---

## Current Fix (Implemented)

### Architecture

`SettingsWindowController` serves dual purpose:
1. **Normal mode**: Real Settings window, centered on screen, user-facing
2. **Glass helper mode**: Same window, positioned at the panel's frame, hidden behind the panel (level 0 vs panel's level 25)

### Flow

```
Panel show():
  1. NSApp.activate(ignoringOtherApps: true)
  2. Panel ordered front at off-screen position
  3. Panel animates to on-screen position (0.1s)
  4. Animation completion handler fires:
     a. SettingsWindowController.shared.showAsGlassHelper(at: panelFrame)
        - Creates/reuses NSWindow at panelFrame
        - Calls makeKeyAndOrderFront + NSApp.activate
        - Window is at level 0, completely behind panel at level 25
     b. panel.makeKey() — restores panel as key window
  5. Compositor detects standard NSWindow → upgrades glass for all app windows

Panel hide():
  1. Panel animates off-screen
  2. Completion handler:
     a. Panel ordered out
     b. SettingsWindowController.shared.hideGlassHelper()
        - Only hides if isGlassHelper == true
        - No-op if user intentionally opened Settings
     c. previousApp.activate() — returns focus

Gear button clicked (while panel open):
  1. SettingsWindowController.shared.showSettings() called
  2. Detects isGlassHelper == true → promotes to real Settings:
     a. Resizes to 700x550, restores minSize
     b. Centers on screen
     c. Brings to front
  3. isGlassHelper = false — window won't be hidden when panel closes
```

### Files Changed

- **`SettingsWindowController.swift`** — Added `showAsGlassHelper(at:)`, `hideGlassHelper()`, `isGlassHelper` flag, refactored `createAndShowWindow()`
- **`PanelController.swift`** — Removed `glassHelperWindow` property and `showGlassHelperWindow()` method. Completion handler calls `SettingsWindowController.shared.showAsGlassHelper()`. `hide()` and `handleEdgeChange()` call `hideGlassHelper()`.
- **`AppState.swift`** — Removed debug `app.pastel.openSettings` DistributedNotification handler
- **`PanelContentView.swift`** — Removed unused `PanelGlassBackground` view

---

## How to Test

### Prerequisites

- macOS 26 (Tahoe) — the Liquid Glass APIs and the compositor bug are macOS 26-only
- Pastel built and running (Cmd+R from Xcode or `open Pastel.app`)
- At least one item in clipboard history (copy something to the pasteboard)

### Test 1: Basic Glass Rendering

1. Make sure no Pastel windows are visible (no Settings, no panel)
2. Press **Cmd+Shift+V** to open the panel
3. **Expected**: Panel slides in from the right edge with correct Liquid Glass — translucent, light-tinted material with edge highlights. Should NOT appear dark/opaque with a black outline.
4. Press **Escape** to dismiss
5. Repeat 3-4 times — glass should be correct every time

### Test 2: Toggle Consistency

1. Press **Cmd+Shift+V** to open the panel
2. Verify glass is correct
3. Press **Cmd+Shift+V** again to close (or Escape)
4. Immediately press **Cmd+Shift+V** to reopen
5. **Expected**: Glass is correct on reopen (window reuse path)
6. Repeat rapidly 5+ times

### Test 3: Gear Button (Glass Helper → Real Settings)

1. Press **Cmd+Shift+V** to open the panel
2. Verify glass is correct
3. Click the **gear icon** (top-right in vertical mode, far-right in horizontal mode)
4. **Expected**: Settings window appears centered on screen at 700x550 with proper glass/dark theme
5. Close Settings (Cmd+W or red button)
6. **Expected**: Panel is still visible (it stays open since the user explicitly opened Settings)
7. Press Escape to dismiss the panel

### Test 4: Settings Opened Independently

1. Open Settings via the **menu bar icon** → click the popover → gear button (or any path that calls `showSettings` without the panel being open)
2. **Expected**: Settings appears centered, normal behavior
3. Now press **Cmd+Shift+V** to open the panel
4. **Expected**: Panel glass is correct (Settings is already open, satisfying compositor)
5. Close Settings
6. **Expected**: Panel glass should still be correct (the glass helper window is still behind it)
7. Dismiss panel

### Test 5: Edge Changes

1. Press **Cmd+Shift+V** to open the panel (default: right edge)
2. Verify glass is correct
3. Open Settings (gear button) → General tab → change Panel Edge to "Bottom"
4. Close Settings (panel dismissed automatically on edge change)
5. Press **Cmd+Shift+V** to open the panel on the bottom edge
6. **Expected**: Glass is correct on the bottom edge too
7. Repeat for Left and Top edges

### Test 6: No Visible Helper Window

1. Open **Mission Control** (F3 or swipe up with three fingers)
2. Press **Cmd+Shift+V** to open the panel (may need to exit Mission Control first)
3. While the panel is open, check Mission Control or use `Cmd+Tab` — there should be **no visible "Pastel Settings" window** overlapping the panel or appearing separately on screen
4. The helper window should be completely hidden behind the panel

### Test 7: Window List Verification (Advanced)

1. Press **Cmd+Shift+V** to open the panel
2. In Terminal, run:
   ```bash
   # List all Pastel windows
   osascript -e 'tell application "System Events" to get name of every window of every process whose name is "Pastel"'
   ```
3. **Expected**: You should see the panel window AND a "Pastel Settings" window listed (the glass helper)
4. Press Escape to dismiss the panel
5. Run the command again
6. **Expected**: No Pastel windows listed (both ordered out)

### Test 8: Screenshot Comparison (Definitive)

Use `screencapture` to capture the panel window directly and compare:

```bash
# 1. Get the panel's window ID
osascript -e '
tell application "System Events"
    tell process "Pastel"
        get id of every window
    end tell
end tell'

# 2. Capture the panel window by ID (replace WINDOW_ID)
screencapture -l WINDOW_ID -o /tmp/panel-glass-test.png

# 3. Open and inspect
open /tmp/panel-glass-test.png
```

**Correct glass**: The panel should have a translucent, slightly tinted background where you can see through to the desktop/apps behind it. The material should have subtle edge highlights and depth.

**Degraded glass**: The panel appears as a dark, nearly opaque rectangle with a visible black outline/border. No translucency, no glass highlights.

### Test 9: Pre-macOS 26 Regression

1. Build and run on **macOS 15** (Sequoia) or earlier
2. Press **Cmd+Shift+V** to open the panel
3. **Expected**: Panel uses `NSVisualEffectView` (`.hudWindow` material, behind-window blur). No glass helper window should be created (the `if #available(macOS 26, *)` guard prevents it).
4. Verify normal functionality — paste, search, labels, etc.

---

## Remaining Unknowns

1. **Why only the singleton works**: We never definitively proved WHY exact replica windows don't fix glass but `SettingsWindowController.shared` does. The best hypothesis is that the compositor tracks windows by their creating object/class, or there's a subtle difference in the creation path we missed. This is a macOS window server implementation detail we can't inspect.

2. **Performance of SettingsView creation**: The first panel toggle creates a full `SettingsView` hierarchy (including SwiftData @Query for labels, tab views, glass buttons). Subsequent toggles reuse the window. If first-toggle performance is a concern, the window could be pre-created during `AppState.setupPanel()`.

3. **Apple may fix this**: This compositor behavior may be a macOS 26 beta bug. If Apple fixes it in a later release, the glass helper becomes unnecessary (but harmless — it's behind the panel and uses no CPU once created).
