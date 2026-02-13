---
phase: quick-023
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/PanelController.swift
autonomous: true
must_haves:
  truths:
    - "Drag-to-paste into external app reliably dismisses the panel"
    - "Cancelled drag (drop back onto panel) does NOT dismiss the panel"
    - "isDragging resets to false after every drag, whether completed or cancelled"
    - "No competing notification observers on didResignActiveNotification during drag"
  artifacts:
    - path: "Pastel/Views/Panel/PanelController.swift"
      provides: "Timer-based drag end detection"
      contains: "dragEndTimer"
  key_links:
    - from: "dragSessionStarted()"
      to: "Timer.scheduledTimer"
      via: "100ms repeating timer polling NSEvent.pressedMouseButtons"
      pattern: "NSEvent\\.pressedMouseButtons\\s*==\\s*0"
    - from: "dragEndTimer callback"
      to: "NSApp.isActive check"
      via: "guard !NSApp.isActive to skip dismiss on cancelled drag"
      pattern: "guard.*!NSApp\\.isActive"
---

<objective>
Fix unreliable drag-to-paste panel dismiss by replacing the notification-based `dragEndMonitor` with a timer that polls `NSEvent.pressedMouseButtons`.

Purpose: The current implementation uses a one-shot `didResignActiveNotification` observer to detect drag end, but this fails in multiple scenarios: cancelled drags (drop back on panel), drops to desktop/Finder without activation change, and races with the existing `deactivationObserver`. A timer polling mouse button state is universally reliable.

Output: Updated PanelController.swift with timer-based drag end detection.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/drag-to-paste-dismiss.md
@Pastel/Views/Panel/PanelController.swift
</context>

<important>
DO NOT commit changes. The user explicitly requested: "Don't commit this till I verify."
After completing the task, report what was changed and let the user verify.
</important>

<tasks>

<task type="auto">
  <name>Task 1: Replace notification-based dragEndMonitor with timer-based dragEndTimer</name>
  <files>Pastel/Views/Panel/PanelController.swift</files>
  <action>
Make three targeted edits to PanelController.swift:

**Edit 1 -- Property declaration (line 37):**
Change:
```swift
private var dragEndMonitor: Any?
```
To:
```swift
private var dragEndTimer: Timer?
```

**Edit 2 -- dragSessionStarted() method (lines 116-147):**
Replace the entire method body with timer-based polling. The new implementation:
```swift
func dragSessionStarted() {
    isDragging = true
    onDragStarted?()

    // Poll for drag end: when no mouse buttons are pressed, the drag is over.
    // NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) does NOT fire
    // during AppKit drag sessions. Timer polling pressedMouseButtons is reliable.
    dragEndTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
        guard NSEvent.pressedMouseButtons == 0 else { return }
        timer.invalidate()
        self?.dragEndTimer = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self?.isDragging = false

            // Only dismiss if the drop went to an EXTERNAL app.
            // If Pastel is still active, the user dropped back on the panel
            // (cancelled drag or drag-to-reorder) -- don't dismiss.
            guard !(NSApp.isActive) else { return }

            let defaults = UserDefaults.standard
            let dismissAfterDrag = defaults.object(forKey: "dismissAfterDragPaste") == nil
                || defaults.bool(forKey: "dismissAfterDragPaste")
            if dismissAfterDrag {
                self?.hide()
            }
        }
    }
}
```

Key differences from old implementation:
- No notification observer -- uses 100ms repeating Timer instead
- Checks `NSEvent.pressedMouseButtons == 0` to detect mouse-up (drag end)
- After 300ms delay, checks `!NSApp.isActive` -- if Pastel is still active, the drop was back on the panel (cancelled), so skip dismiss
- No race condition with `deactivationObserver` since we no longer observe the same notification

**Edit 3 -- removeEventMonitors() method (lines 374-377):**
Replace the dragEndMonitor cleanup block:
```swift
if let observer = dragEndMonitor {
    NotificationCenter.default.removeObserver(observer)
    dragEndMonitor = nil
}
```
With timer cleanup:
```swift
dragEndTimer?.invalidate()
dragEndTimer = nil
```

**Also update the doc comment on dragSessionStarted() (lines 110-115):**
Replace the existing comment block with:
```swift
/// Called when a card drag session begins.
/// Starts a timer that polls `NSEvent.pressedMouseButtons` every 100ms to
/// detect when the drag ends (mouse released). Once detected, checks whether
/// Pastel is still active -- if not, the drop went to an external app and
/// the panel should auto-dismiss (if setting enabled).
```
  </action>
  <verify>
Build the project:
```
cd /Users/phulsechinmay/Desktop/Projects/pastel && xcodebuild -scheme Pastel -configuration Debug build 2>&1 | tail -5
```
Verify:
- No compilation errors
- `dragEndMonitor` does not appear anywhere in the file (fully replaced)
- `dragEndTimer` appears as property, in dragSessionStarted(), and in removeEventMonitors()
  </verify>
  <done>
PanelController.swift compiles cleanly with timer-based drag end detection. The property is `dragEndTimer: Timer?`, dragSessionStarted() uses a 100ms repeating timer polling `NSEvent.pressedMouseButtons`, and removeEventMonitors() invalidates the timer. No references to the old `dragEndMonitor` notification observer remain.
  </done>
</task>

</tasks>

<verification>
1. Build succeeds with zero errors
2. Grep for `dragEndMonitor` returns zero matches in PanelController.swift (old code fully removed)
3. Grep for `dragEndTimer` returns matches in: property declaration, dragSessionStarted(), removeEventMonitors()
4. No duplicate `didResignActiveNotification` observers -- only `deactivationObserver` in installEventMonitors() remains
</verification>

<success_criteria>
- PanelController.swift compiles with the timer-based approach
- Old notification-based `dragEndMonitor` fully removed
- Timer polls `NSEvent.pressedMouseButtons == 0` at 100ms intervals
- Cancelled drags (Pastel still active) do NOT dismiss the panel
- External drops (Pastel not active) DO dismiss the panel (if setting enabled)
- Changes are NOT committed (user will verify first)
</success_criteria>

<output>
DO NOT commit. Report changes to user for manual verification.
After user verifies, they will commit manually or instruct a commit.
</output>
