# Drag-to-Paste Panel Dismiss — Investigation Notes

## Problem
Panel should auto-dismiss after a successful drag-to-paste, but it only works intermittently.

## Current Implementation (PanelController.swift)

### Flow
1. User starts dragging a card → SwiftUI `.onDrag` fires → `onDragStarted?()` callback chain → `PanelController.dragSessionStarted()`
2. `dragSessionStarted()` sets `isDragging = true` and installs a **one-shot `didResignActiveNotification` observer** (`dragEndMonitor`)
3. When user drops into another app, that app becomes frontmost → Pastel deactivates → observer fires
4. Observer cleans itself up, waits 300ms, then sets `isDragging = false` and calls `hide()` if setting enabled

### Why It's Unreliable

**Race condition with `deactivationObserver`:** There are TWO observers on `didResignActiveNotification`:

1. `dragEndMonitor` (from `dragSessionStarted`) — checks `isDragging == true`, handles drag end
2. `deactivationObserver` (from `installEventMonitors`) — checks `isDragging != true`, handles normal deactivation

Both fire on the SAME notification. The execution order of two `NotificationCenter` observers on the same notification is **undefined by Apple**. Possible scenarios:

- **If `dragEndMonitor` fires first:** It sees `isDragging == true`, removes itself, schedules 300ms dismiss. Then `deactivationObserver` fires, sees `isDragging == true` (still set), returns early. **This works.**

- **If `deactivationObserver` fires first:** It sees `isDragging == true`, returns early. Then `dragEndMonitor` fires, handles drag end. **This also works.** But timing of the 0.15s deactivation delay vs 0.3s drag delay could cause issues.

**The real problem — deactivation may NOT fire at all:**

- If the user drags but drops **back onto the panel itself** (cancel/failed drag), no deactivation happens. `isDragging` stays `true` forever. Future clicks won't dismiss the panel (globalClickMonitor checks `isDragging`).
- If the user drags to a **window on the same app** (e.g., Settings window), no deactivation happens.
- If the user drags to the **desktop** or **Finder** in the background without Finder coming to front, deactivation may not happen.
- If Pastel was already deactivated DURING the drag (e.g., another app stole focus), the notification already fired before `dragEndMonitor` was installed.

**`hide()` may silently fail:**

- `hide()` guards on `panel.isVisible`. After deactivation + 300ms delay, the existing `deactivationObserver`'s 150ms delay may have already hidden the panel. So when `dragEndMonitor`'s 300ms fires, `panel.isVisible` is false and `hide()` returns immediately. But this is actually OK — the panel was already hidden.
- More concerning: if `hide()` is called while the app is NOT active, `panel.animator().setFrame(offScreen, display: true)` may not animate properly since NSAnimationContext may not run when the app is inactive.

## Proposed Fix Approaches

### Approach 1: Use NSDraggingSource protocol (Best)
Subclass or wrap the drag to get `draggingSession(_:endedAt:operation:)` callback. This fires reliably when any drag session ends, regardless of where the drop lands (including cancel). SwiftUI's `.onDrag` returns an `NSItemProvider` — could use a custom `NSItemProvider` subclass or add a `NSDraggingSource` delegate at the AppKit level.

**Challenge:** SwiftUI's `.onDrag` doesn't expose the `NSDraggingSession`. Would need to intercept at the `NSView` level (e.g., swizzling or using `NSView.beginDraggingSession`).

### Approach 2: Timer-based fallback (Simpler)
After `dragSessionStarted()`, start a repeating timer that checks:
- `NSEvent.pressedMouseButtons == 0` (no mouse buttons held = drag ended)
- Once detected, wait 300ms then dismiss

This is more reliable than notification-based detection since it works regardless of which app receives the drop.

### Approach 3: Combine both monitors (Belt-and-suspenders)
Keep the deactivation observer AND add a `leftMouseUp` local monitor (not global). The local monitor fires for events within the app. Also add a timer fallback that checks `pressedMouseButtons` every 100ms.

### Approach 4: Monitor NSPasteboard changes
After drag starts, poll `NSPasteboard.general.changeCount` — when it increments, the drop completed. But this may not work for all drag types.

## Recommendation
**Approach 2 (timer-based)** is the most reliable and simplest:

```swift
func dragSessionStarted() {
    isDragging = true
    onDragStarted?()

    // Poll for drag end: when no mouse buttons are pressed, the drag is over
    dragEndTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
        guard NSEvent.pressedMouseButtons == 0 else { return }
        timer.invalidate()
        self?.dragEndTimer = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self?.isDragging = false

            // Only dismiss if the drop went to an EXTERNAL app.
            // If Pastel is still active, the user dropped back on the panel
            // (cancelled drag or drag-to-reorder) — don't dismiss.
            guard !NSApp.isActive else { return }

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

This eliminates the reliance on `didResignActiveNotification` entirely. The timer checks every 100ms if the mouse button is released (drag ended). After detecting mouse-up, it checks `NSApp.isActive` — if Pastel is still active, the drop landed back on the panel (cancelled or reorder), so we skip dismissal. If another app is active, the drop went external and we dismiss.

Works for all cases:
- Drop in another app → Pastel deactivated → dismiss ✓
- Drop on desktop/Finder → Finder activated → dismiss ✓
- Cancelled drag (drop back on panel) → Pastel still active → NO dismiss ✓
- Drop back on panel for reorder → Pastel still active → NO dismiss ✓

**Note:** Change `dragEndMonitor: Any?` to `dragEndTimer: Timer?` and update `removeEventMonitors()` to invalidate the timer instead of removing a notification observer.

## Files to Modify
- `Pastel/Views/Panel/PanelController.swift` — `dragSessionStarted()`, `removeEventMonitors()`, property declaration

## Settings
- UserDefaults key: `dismissAfterDragPaste` (Bool, defaults to true via nil-check)
- Toggle in: `Pastel/Views/Settings/GeneralSettingsView.swift` under "Paste Behavior"
