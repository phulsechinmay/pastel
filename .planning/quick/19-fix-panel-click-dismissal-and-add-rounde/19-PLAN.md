---
phase: quick-19
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/PanelController.swift
  - Pastel/Views/Panel/SlidingPanel.swift
autonomous: true

must_haves:
  truths:
    - "Clicking search bar, label chips, card items, and gear button inside the panel does NOT dismiss it"
    - "Clicking OUTSIDE the panel (on desktop, other windows) DOES dismiss it"
    - "Pressing the global hotkey while panel is open DOES dismiss it (toggle behavior unchanged)"
    - "Cmd+1-9 quick paste hotkeys still work"
    - "Escape key still dismisses the panel"
    - "Panel has rounded inward-facing corners at the window level"
  artifacts:
    - path: "Pastel/Views/Panel/PanelController.swift"
      provides: "Fixed event monitors that only dismiss on true outside clicks"
    - path: "Pastel/Views/Panel/SlidingPanel.swift"
      provides: "Window-level corner radius masking"
  key_links:
    - from: "PanelController.installEventMonitors()"
      to: "PanelController.hide()"
      via: "Global click monitor and deactivation observer"
      pattern: "addGlobalMonitorForEvents|didResignActiveNotification"
---

<objective>
Fix the panel so clicking inside it (search bar, labels, cards, buttons) no longer dismisses it, and add rounded corners at the window level.

Purpose: The panel is currently unusable for mouse interaction -- any click inside dismisses it. Only keyboard shortcuts (Cmd+1-9) work. This makes search, label filtering, and double-click-to-paste completely broken. Additionally, the panel needs polished rounded corners on the inward-facing edge.

Output: A panel that properly handles inside vs outside clicks and has elegant rounded corners.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Panel/PanelController.swift
@Pastel/Views/Panel/SlidingPanel.swift
@Pastel/Views/Panel/PanelContentView.swift
@Pastel/Models/PanelEdge.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix panel click-through dismissal</name>
  <files>Pastel/Views/Panel/PanelController.swift, Pastel/Views/Panel/SlidingPanel.swift</files>
  <action>
The panel dismisses on internal clicks because of two interacting issues:

**Issue 1 - Deactivation observer is too aggressive:** `PanelController.installEventMonitors()` installs a `NSApplication.didResignActiveNotification` observer that calls `hide()`. For an LSUIElement borderless NSPanel, clicking inside SwiftUI content hosted via NSHostingView can cause momentary deactivation events (especially when SwiftUI focus changes or when clicking interactive controls like text fields). This fires the deactivation observer and dismisses the panel.

**Issue 2 - Global monitor may fire for panel clicks:** `NSEvent.addGlobalMonitorForEvents` should only fire for events in OTHER apps. However, with borderless NSPanel + LSUIElement, macOS can route some mouse events as "global" if the panel doesn't properly claim them.

**Fixes to apply in PanelController.swift:**

1. In `installEventMonitors()`, replace the simple `globalClickMonitor` with one that checks whether the click point is inside the panel frame. Use `NSEvent.mouseLocation` (screen coordinates) and compare against `panel?.frame`. If the click is inside the panel frame, do NOT dismiss. This is a defensive check -- the global monitor shouldn't fire for panel clicks, but this guards against edge cases:

```swift
globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
    matching: [.leftMouseDown, .rightMouseDown]
) { [weak self] event in
    guard self?.isDragging != true else { return }
    // Only dismiss if click is genuinely outside the panel
    guard let panelFrame = self?.panel?.frame else {
        self?.hide()
        return
    }
    let clickLocation = NSEvent.mouseLocation
    if !panelFrame.contains(clickLocation) {
        self?.hide()
    }
}
```

2. For the `deactivationObserver`, add a short delay (0.1s) and re-check `NSApp.isActive` before dismissing. This prevents false-positive dismissals from momentary deactivation during internal focus changes:

```swift
deactivationObserver = NotificationCenter.default.addObserver(
    forName: NSApplication.didResignActiveNotification,
    object: nil, queue: .main
) { [weak self] _ in
    guard self?.isDragging != true else { return }
    // Delay check: internal focus changes (e.g., clicking search field)
    // can cause momentary deactivation that resolves immediately.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        guard let self, self.isVisible else { return }
        // If the app re-activated (focus returned to panel), don't dismiss
        if !NSApp.isActive {
            self.hide()
        }
    }
}
```

3. Also add a local mouse event monitor to ensure clicks inside the panel are properly handled as local events. This is belt-and-suspenders to ensure the panel stays active on internal clicks:

```swift
// In installEventMonitors(), add a local click monitor that keeps the panel active
localClickMonitor = NSEvent.addLocalMonitorForEvents(
    matching: [.leftMouseDown, .rightMouseDown]
) { [weak self] event in
    // Ensure the app stays active when clicking inside the panel
    if let panel = self?.panel, event.window == panel {
        if !NSApp.isActive {
            NSApp.activate()
        }
    }
    return event // pass through -- don't consume
}
```

Add `private var localClickMonitor: Any?` alongside the existing monitor properties. Clean it up in `removeEventMonitors()`.

**Fixes to apply in SlidingPanel.swift:**

4. Override `acceptsFirstMouse(for:)` to return `true` so clicks on the panel are immediately accepted without requiring a separate activation click:

```swift
override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
```

This is critical for borderless NSPanel -- without it, the first click may activate the window but not register as a click on the control, which confuses the event routing.

5. Override `resignKey()` to prevent the panel from giving up key status when interacting with its own content. Only allow resignation if the panel is being hidden:

Do NOT override resignKey -- this could break other behavior. Instead, just ensure `acceptsFirstMouse` is set.
  </action>
  <verify>
Build the project with Cmd+B in Xcode (or `xcodebuild build -scheme Pastel -destination 'platform=macOS'`). Then manually test:
1. Open panel with hotkey
2. Click search bar -- panel should stay open, search field should focus
3. Click a label chip -- panel should stay open, items should filter
4. Click a card item -- panel should stay open
5. Double-click a card item -- should trigger paste
6. Click outside panel (on desktop) -- panel should dismiss
7. Press Escape -- panel should dismiss
8. Press hotkey while panel open -- panel should dismiss (toggle)
9. Cmd+1 through Cmd+9 -- should still paste items
  </verify>
  <done>Panel only dismisses when clicking outside it, pressing Escape, or toggling the hotkey. All internal clicks (search, labels, cards, gear button) work without dismissing the panel.</done>
</task>

<task type="auto">
  <name>Task 2: Add window-level rounded corners</name>
  <files>Pastel/Views/Panel/PanelController.swift</files>
  <action>
Add rounded corners to the panel at the window level so the panel has polished, edge-aware rounding. The SwiftUI layer already has `GlassEffectModifier` with `UnevenRoundedRectangle` clipping, but the window itself (and the glass/blur backing views) needs corner rounding too.

In `PanelController.createPanel()`, after setting up `containerView`:

1. Set up layer-backed container with corner masking:

```swift
containerView.wantsLayer = true
containerView.layer?.cornerRadius = 12
containerView.layer?.masksToBounds = true
containerView.layer?.backgroundColor = NSColor.clear.cgColor
```

2. Apply edge-aware corner masking using `CACornerMask`. Read `currentEdge` and only round the inward-facing corners:

```swift
let edge = currentEdge
switch edge {
case .right:
    // Round top-left and bottom-left (inward-facing)
    containerView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
case .left:
    // Round top-right and bottom-right (inward-facing)
    containerView.layer?.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
case .top:
    // Round bottom-left and bottom-right (inward-facing)
    containerView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
case .bottom:
    // Round top-left and top-right (inward-facing)
    containerView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
}
```

Note: Core Animation Y-axis is flipped vs AppKit/SwiftUI. In CA:
- `layerMinYCorner` = bottom visually
- `layerMaxYCorner` = top visually

So `.layerMinXMinYCorner` = bottom-left, `.layerMinXMaxYCorner` = top-left, `.layerMaxXMinYCorner` = bottom-right, `.layerMaxXMaxYCorner` = top-right.

For `edge == .right`, inward-facing = left side = top-left + bottom-left = `.layerMinXMaxYCorner` + `.layerMinXMinYCorner`. This is correct.

3. The existing `containerView.layer?.backgroundColor = NSColor.clear.cgColor` line (already present) should be kept. Just add cornerRadius, masksToBounds, and maskedCorners.

4. This corner masking applies to both the macOS 26 path (NSGlassEffectView) and the pre-26 path (NSVisualEffectView) since both are subviews of containerView.
  </action>
  <verify>
Build and run the app. Toggle the panel on each edge (change edge in Settings):
1. Right edge: rounded corners on left side (top-left and bottom-left)
2. Left edge: rounded corners on right side (top-right and bottom-right)
3. Top edge: rounded corners on bottom (bottom-left and bottom-right)
4. Bottom edge: rounded corners on top (top-left and top-right)
Corners should look clean with 12pt radius, matching the SwiftUI clip shape.
  </verify>
  <done>Panel has 12pt rounded corners on inward-facing edges that match the current SwiftUI-level clipping. Corners are crisp on all four panel edge configurations.</done>
</task>

</tasks>

<verification>
1. `xcodebuild build -scheme Pastel -destination 'platform=macOS'` succeeds
2. Panel click interactions work: search, labels, cards, gear button all clickable without dismissal
3. Panel dismiss interactions work: click outside, Escape, hotkey toggle
4. Cmd+1-9 hotkeys still paste items
5. Panel has rounded inward-facing corners on all edge configurations
6. Drag-and-drop from cards still works (isDragging guard still functional)
</verification>

<success_criteria>
- Panel no longer dismisses on internal clicks
- Panel dismisses correctly on external clicks, Escape, and hotkey toggle
- Panel has polished rounded corners on inward-facing edges
- All existing keyboard shortcuts (Cmd+1-9, Escape, type-to-search) still work
</success_criteria>

<output>
After completion, create `.planning/quick/19-fix-panel-click-dismissal-and-add-rounde/19-SUMMARY.md`
</output>
