---
phase: 25-fix-panel-dismissal
plan: 01
quick_task: 25
type: execute
wave: 1
depends_on: []
files_modified: [Pastel/Views/Panel/PanelController.swift]
autonomous: true

must_haves:
  truths:
    - "Clicking on Edit Item modal does not dismiss the sliding panel"
    - "Clicking on Settings window does not dismiss the sliding panel"
    - "Clicking on NSColorPanel (color picker) does not dismiss the sliding panel"
    - "Clicking outside all Pastel windows still dismisses the panel"
  artifacts:
    - path: "Pastel/Views/Panel/PanelController.swift"
      provides: "Fixed globalClickMonitor logic to check all app windows"
      min_lines: 300
  key_links:
    - from: "globalClickMonitor in installEventMonitors()"
      to: "NSApp.windows.contains"
      via: "click location check"
      pattern: "NSApp\\.windows\\.contains.*isVisible.*frame\\.contains"
---

<objective>
Fix panel dismissal bug where clicking on any Pastel window (Edit Item modal, Settings window, NSColorPanel) incorrectly triggers the globalClickMonitor and dismisses the sliding panel.

Purpose: Panel should only dismiss when clicking outside ALL Pastel-owned windows, not just outside the main sliding panel.

Output: Updated PanelController.swift with fixed click detection logic.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md

## Bug Analysis

The `globalClickMonitor` in `installEventMonitors()` (lines 288-301) only checks if the click is within the sliding panel's frame:

```swift
let clickLocation = NSEvent.mouseLocation
if !panelFrame.contains(clickLocation) {
    self?.hide()
}
```

This causes dismissal when clicking on:
- EditItemWindow (separate NSPanel at .floating level)
- SettingsWindowController (standard NSWindow)
- NSColorPanel (system color picker opened by ColorPicker)

The fix: Check if the click is inside ANY visible Pastel window before dismissing.
</context>

<tasks>

<task type="auto">
  <name>Fix globalClickMonitor to check all app windows</name>
  <files>Pastel/Views/Panel/PanelController.swift</files>
  <action>
Replace the single-panel frame check in `globalClickMonitor` (lines 288-301) with a check against all visible app windows.

Current logic (lines 288-301):
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

Replace with:
```swift
globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
    matching: [.leftMouseDown, .rightMouseDown]
) { [weak self] event in
    guard self?.isDragging != true else { return }
    let clickLocation = NSEvent.mouseLocation
    // Don't dismiss if clicking on ANY Pastel window (panel, edit modal, settings, color picker)
    let clickedInsideApp = NSApp.windows.contains { window in
        window.isVisible && window.frame.contains(clickLocation)
    }
    if !clickedInsideApp {
        self?.hide()
    }
}
```

This covers:
- Sliding panel (SlidingPanel)
- Edit modal (EditItemWindow)
- Settings window (SettingsWindowController)
- NSColorPanel (system color picker)
- Any future Pastel windows
  </action>
  <verify>
Build the app in Xcode (Cmd+B) — should succeed without errors.

Manual testing:
1. Launch Pastel, open sliding panel (Cmd+Shift+V)
2. Click a card's edit button → edit modal appears
3. Click inside edit modal, type in title field → panel should stay open
4. Click color picker in edit modal → NSColorPanel appears
5. Click in NSColorPanel to pick a color → panel should stay open
6. Click outside all Pastel windows (on desktop or another app) → panel should dismiss
7. Open panel again, click Settings gear in panel toolbar
8. Click inside Settings window → panel should stay open
9. Click outside all Pastel windows → panel should dismiss
  </verify>
  <done>
globalClickMonitor checks all NSApp.windows, not just the sliding panel frame. Clicking on Edit Item modal, Settings window, or NSColorPanel no longer dismisses the panel. Clicking outside all Pastel windows still dismisses correctly.
  </done>
</task>

</tasks>

<verification>
Build succeeds without errors. Panel remains open when clicking on Edit Item modal, Settings window, or NSColorPanel. Panel dismisses when clicking outside all Pastel windows.
</verification>

<success_criteria>
- [x] PanelController.swift globalClickMonitor updated to check NSApp.windows
- [x] Build succeeds
- [x] Panel stays open when clicking Edit Item modal
- [x] Panel stays open when clicking Settings window
- [x] Panel stays open when clicking NSColorPanel
- [x] Panel dismisses when clicking outside all Pastel windows
</success_criteria>

<output>
After completion, create `.planning/quick/25-fix-panel-dismissal-when-clicking-edit-m/25-SUMMARY.md`
</output>
