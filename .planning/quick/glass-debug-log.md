# Glass Debug Log (Updated)

## Core Bug
Panel glass renders degraded (dark, opaque, black outline) when shown via hotkey.
Glass renders correctly when Settings window is also open.
Glass degrades again when Settings is closed.

## A/B Proof
- `/tmp/panel-AB-before.png` — panel WITHOUT Settings: dark, opaque
- `/tmp/panel-AB-after.png` — panel WITH Settings: lighter, translucent, correct glass

## Helper Window Discovery
A simple NSWindow with `.titled, .closable, .resizable` at default level (0)
with `Color.blue.opacity(0.3).glassEffect(.regular)` as content renders
PERFECT glass at `/tmp/glass-helper-window.png`. But the panel alongside it
still has degraded glass. This proves:
- The app CAN render glass correctly
- The issue is specific to the panel window, NOT the app

## What FAILED (no glass improvement on panel)
1. `NSApp.activate(ignoringOtherApps: true)` instead of `NSApp.activate()`
2. `canBecomeMain: true` on SlidingPanel
3. `.titled` styleMask on NSPanel at `.statusBar` level
4. Persistent off-screen titled NSWindow with glass content at (-20000,-20000)
5. Persistent ON-SCREEN titled NSWindow with glass content at (100,100) 300x300
6. NSWindow instead of NSPanel (SlidingPanel extends NSWindow)
7. `.titled, .closable, .resizable, .fullSizeContentView` on NSWindow
8. `level = .floating` (3) instead of `.statusBar` (25)
9. `level = .normal` (0) instead of `.statusBar` (25)
10. Delayed re-activation 0.3s after panel show
11. Direct hosting view as contentView (no container intermediary)

## What WORKS
- Settings window open → panel glass correct
- Helper NSWindow (300x300, titled, normal level, simple glass content) → correct glass ON ITSELF

## Key Differences: Helper (works) vs Panel (broken)
| Property | Helper (correct glass) | Panel (degraded glass) |
|----------|----------------------|----------------------|
| Type | NSWindow | NSPanel |
| StyleMask | .titled, .closable, .resizable | .titled, .fullSizeContentView |
| Level | .normal (0) | .statusBar (25) |
| Content | Color.blue + .glassEffect | PanelContentView + .glassEffect |
| ContentView | NSHostingView directly | containerView > hostingView |
| Size | 300x300 | ~300x1470 (bottom) or 300xScreen (right) |

## UNTESTED hypotheses
1. **Simple glass content in panel window** — Replace PanelContentView with
   `Color.clear.glassEffect(.regular)` to test if complex view hierarchy breaks glass
2. **Remove `.environment(\.colorScheme, .dark)`** — Could forcing dark colorScheme
   interfere with glass?
3. **Remove `.preferredColorScheme(.dark)`** — Same as above
4. **contentRect size** — Panel starts with `.zero` contentRect, helper starts with real size
5. **`.fullSizeContentView` conflicts** — This extends content under titlebar, maybe
   it interferes with glass rendering for `.titled` windows

## Settings Window Properties (the "known good" reference)
- NSWindow (not NSPanel)
- StyleMask: [.titled, .closable, .resizable]
- Level: .normal (0)
- Size: 700x550
- Content: SettingsView with GlassEffectContainer, .glassProminent buttons
- `NSApp.activate(ignoringOtherApps: true)`
- `makeKeyAndOrderFront(nil)`

## Round 2: Isolating Content vs Window

### Test: Simple glass in panel window (NO PanelContentView)
- Replaced PanelContentView with `Color.blue.opacity(0.2).glassEffect(.regular, in: .rect(cornerRadius:12))`
- Result: **PERFECT glass** — blue tint, edge highlights, translucency
- Screenshot: `/tmp/panel-debug-glass-only.png`
- **CONCLUSION: The panel WINDOW renders glass correctly. The bug is in PanelContentView.**

### Test: Split-layer approach (glass underneath, content on top)
- Added separate `PanelGlassBackground` NSHostingView with `Color.clear.glassEffect(.regular, in: edgeShape)`
- Layered real PanelContentView on top with `.glassEffect()` disabled (just clipShape)
- Result: **STILL DEGRADED** — the simple glass layer underneath is correct but doesn't fix the overall appearance
- The A/B test appeared to work but Settings was still open (false positive!)
- **CONCLUSION: The split-layer approach does NOT fix the bug by itself**

### Key finding: Simple glass ALONE in this window = correct. But with PanelContentView on top = degraded.
This means PanelContentView's opaque content is covering/interfering with the glass.
The glass IS correct underneath — it's the CONTENT layer that degrades the visual.

## NEXT STEPS TO TRY
1. **Test PanelContentView with transparent backgrounds** — make all card/container backgrounds transparent or semi-transparent
2. **Test without `.preferredColorScheme(.dark)` and `.environment(\.colorScheme, .dark)`** — dark mode forcing might interfere
3. **Test with NSGlassEffectView (AppKit) instead of SwiftUI .glassEffect()** — the simple glass test used SwiftUI but maybe NSGlassEffectView behaves differently for full panels
4. **Test PanelContentView WITHOUT GlassEffectModifier at all** — just the raw content with no glass/clip, over the split glass layer
5. **Check if the hostingView's layer backgroundColor being clear matters** — ensure no layers are opaque

## Current File State
- SlidingPanel.swift: NSPanel, [.titled, .fullSizeContentView], .statusBar, hidden buttons, defer:false
- PanelController.swift: NSApp.activate(ignoringOtherApps:true), split glass layer + content layer (macOS 26+)
- PanelContentView.swift: GlassEffectModifier only does clipShape on macOS 26+ (glass disabled), PanelGlassBackground view added
- AppState.swift: Has debug openSettings notification handler
