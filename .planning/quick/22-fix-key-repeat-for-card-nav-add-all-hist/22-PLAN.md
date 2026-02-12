---
phase: quick-022
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/FilteredCardListView.swift
  - Pastel/Views/Panel/PanelContentView.swift
  - Pastel/Views/Panel/ChipBarView.swift
  - Pastel/Views/Panel/PanelController.swift
  - Pastel/Views/Settings/GeneralSettingsView.swift
autonomous: true

must_haves:
  truths:
    - "Holding left/right arrow key smoothly scrolls through panel cards with each one highlighted in sequence"
    - "An 'All History' chip with circle-arrow icon appears as the first item in the label chip bar, selected by default"
    - "Clicking 'All History' chip clears any active label filter and shows all items"
    - "Cmd+Left/Right cycling includes 'All History' as the first position (clearing label filter)"
    - "Panel auto-closes after drag-to-paste completes (when setting enabled)"
    - "Settings includes a 'Dismiss panel after drag-to-paste' toggle (default: on)"
  artifacts:
    - path: "Pastel/Views/Panel/FilteredCardListView.swift"
      provides: "Reliable key repeat card navigation via NSEvent local monitor"
    - path: "Pastel/Views/Panel/ChipBarView.swift"
      provides: "All History chip as first item in label chip bar"
    - path: "Pastel/Views/Panel/PanelContentView.swift"
      provides: "Updated cycleLabelFilter that includes All History position"
    - path: "Pastel/Views/Panel/PanelController.swift"
      provides: "Auto-dismiss after drag-to-paste with setting gate"
    - path: "Pastel/Views/Settings/GeneralSettingsView.swift"
      provides: "Toggle for dismiss-after-drag setting"
  key_links:
    - from: "FilteredCardListView"
      to: "NSEvent local key monitor"
      via: "onAppear/onDisappear installs arrow key monitor bypassing SwiftUI onKeyPress"
      pattern: "addLocalMonitorForEvents.*keyDown"
    - from: "ChipBarView 'All History' chip"
      to: "PanelContentView.selectedLabelIDs"
      via: "Tapping All History calls selectedLabelIDs.removeAll()"
      pattern: "selectedLabelIDs\\.removeAll"
    - from: "PanelController.dragSessionStarted"
      to: "PanelController.hide"
      via: "leftMouseUp monitor calls hide() after delay when setting enabled"
      pattern: "dismissAfterDragPaste.*hide"
---

<objective>
Fix key repeat for panel card navigation, add "All History" label chip, and auto-close panel after drag-to-paste.

Purpose: Three usability fixes -- (1) holding arrow keys should continuously scroll through cards (currently requires one press per card despite phases: [.down, .repeat] on onKeyPress), (2) provide an explicit "All History" chip so users can return to unfiltered view via click or Cmd+arrow cycling, (3) automatically dismiss the panel after a drag-to-paste operation completes.

Output: Updated FilteredCardListView with NSEvent-based arrow key handling, ChipBarView with synthetic "All History" chip, PanelController with post-drag auto-dismiss, and GeneralSettingsView with new toggle.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Panel/FilteredCardListView.swift
@Pastel/Views/Panel/PanelContentView.swift
@Pastel/Views/Panel/ChipBarView.swift
@Pastel/Views/Panel/PanelController.swift
@Pastel/Views/Panel/SlidingPanel.swift
@Pastel/Views/Panel/LabelChipView.swift
@Pastel/Views/Settings/GeneralSettingsView.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix key repeat card navigation + Add "All History" chip + Cmd+arrow cycling</name>
  <files>
    Pastel/Views/Panel/FilteredCardListView.swift
    Pastel/Views/Panel/ChipBarView.swift
    Pastel/Views/Panel/PanelContentView.swift
  </files>
  <action>
**Problem diagnosis:** SwiftUI's `.onKeyPress(phases: [.down, .repeat])` handlers on FilteredCardListView DO have the repeat phase, but key repeat is not working for card navigation. The likely cause: when `moveSelection(by:)` updates the `@Binding selectedIndex`, the resulting view re-render (ScrollViewReader animation + card highlight change) interrupts SwiftUI's key repeat event chain. Cmd+Left/Right works because `cycleLabelFilter` updates `selectedLabelIDs` on the PARENT view (PanelContentView), which forces a full view recreation via `.id()` -- but the key repeat continues because the key handler is on PanelContentView's focus scope, not the recreated child.

**Fix approach:** Replace the arrow key `.onKeyPress` handlers with an `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` installed on the FilteredCardListView. NSEvent monitors operate at the AppKit level and are immune to SwiftUI re-render interruptions. The existing Escape key monitor in PanelController already proves this pattern works reliably in this NSPanel.

**FilteredCardListView.swift changes:**

1. Add `@State private var keyMonitor: Any? = nil` property.

2. Remove the four `.onKeyPress(.upArrow, ...)`, `.onKeyPress(.downArrow, ...)`, `.onKeyPress(keys: [.leftArrow], ...)`, and `.onKeyPress(keys: [.rightArrow], ...)` handlers (lines ~234-257). Keep ALL other `.onKeyPress` handlers (Return, decimal digits, shifted digits, alphanumeric type-to-search) unchanged.

3. In `.onAppear`, install a local key monitor:
```swift
keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
    // Only handle arrow keys
    switch event.keyCode {
    case 123: // Left arrow
        if event.modifierFlags.contains(.command) {
            onCycleLabelFilter?(-1)
        } else if isHorizontal {
            moveSelection(by: -1)
        } else {
            return event // pass through in vertical mode
        }
        return nil // consumed
    case 124: // Right arrow
        if event.modifierFlags.contains(.command) {
            onCycleLabelFilter?(1)
        } else if isHorizontal {
            moveSelection(by: 1)
        } else {
            return event
        }
        return nil
    case 125: // Down arrow
        if !isHorizontal {
            moveSelection(by: 1)
            return nil
        }
        return event
    case 126: // Up arrow
        if !isHorizontal {
            moveSelection(by: -1)
            return nil
        }
        return event
    default:
        return event // pass through all other keys
    }
}
```
NOTE: This is a local monitor (not global), so it only fires when the panel's app is active. The `[self]` capture provides access to `isHorizontal`, `moveSelection`, and `onCycleLabelFilter`. Key codes: 123=left, 124=right, 125=down, 126=up.

IMPORTANT: If the Swift compiler complains about `[self]` capture in a struct (since FilteredCardListView is a struct), refactor the monitor installation by extracting the callback logic. One approach: store the needed state/functions in local variables before the closure. Or, since NSEvent monitor closures are `@Sendable`, you may need to pass the values explicitly. Use whatever pattern compiles cleanly -- the key requirement is that arrow key events are handled at the NSEvent level, not SwiftUI's onKeyPress.

4. In `.onAppear`, after the existing `selectedIndex = nil`, add the monitor installation. The existing `.onAppear` just sets `selectedIndex = nil`, so wrap both in the same `.onAppear`.

5. Add `.onDisappear` to clean up the monitor:
```swift
.onDisappear {
    if let monitor = keyMonitor {
        NSEvent.removeMonitor(monitor)
        keyMonitor = nil
    }
}
```

6. Add `import AppKit` at the top of the file (needed for NSEvent).

**ChipBarView.swift changes:**

Add a synthetic "All History" chip as the first item before the ForEach of real labels.

1. Add a callback property: `var onSelectAllHistory: (() -> Void)?`
2. Add a property to know if no label is currently active: `var isAllHistoryActive: Bool`
3. Update the `init` if needed, or rely on memberwise init.
4. Before the `ForEach(labels)` in the body, add an "All History" chip:
```swift
// "All History" chip -- always first, active when no label is filtered
Button {
    onSelectAllHistory?()
} label: {
    HStack(spacing: 4) {
        Image(systemName: "arrow.counterclockwise.circle.fill")
            .font(.system(size: 11))
        Text("All History")
            .font(.system(size: 11))
            .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(
        isAllHistoryActive ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.1),
        in: Capsule()
    )
    .overlay(
        Capsule().strokeBorder(
            isAllHistoryActive ? Color.accentColor.opacity(0.6) : Color.clear,
            lineWidth: 1
        )
    )
}
.buttonStyle(.plain)
```

**PanelContentView.swift changes:**

1. Update ChipBarView call sites (both horizontal and vertical layouts) to pass the new properties:
```swift
ChipBarView(
    labels: labels,
    selectedLabelIDs: $selectedLabelIDs,
    isAllHistoryActive: selectedLabelIDs.isEmpty,
    onSelectAllHistory: { selectedLabelIDs.removeAll() }
)
```

2. Update `cycleLabelFilter(direction:)` to include "All History" as position 0 in the cycle. When cycling forward from the last label, go to "All History" (clear selection). When cycling backward from "All History", go to the last label. When cycling forward from "All History", go to the first label:
```swift
private func cycleLabelFilter(direction: Int) {
    guard !labels.isEmpty else { return }
    let labelIDs = labels.map(\.persistentModelID)

    if selectedLabelIDs.isEmpty {
        // Currently on "All History"
        if direction > 0 {
            // Forward: go to first label
            selectedLabelIDs = [labelIDs.first!]
        } else {
            // Backward: go to last label
            selectedLabelIDs = [labelIDs.last!]
        }
    } else if let currentID = selectedLabelIDs.first,
              let currentIndex = labelIDs.firstIndex(of: currentID) {
        let newIndex = currentIndex + direction
        if newIndex < 0 || newIndex >= labelIDs.count {
            // Wrap to "All History"
            selectedLabelIDs.removeAll()
        } else {
            selectedLabelIDs = [labelIDs[newIndex]]
        }
    }
}
```
This replaces the existing `cycleLabelFilter` method. The key difference from the old version: instead of wrapping around (last -> first), it now goes last -> All History -> first (and vice versa).
  </action>
  <verify>
Build the project: `cd /Users/phulsechinmay/Desktop/Projects/pastel && xcodebuild -scheme Pastel -destination 'platform=macOS' build 2>&1 | tail -5`
Confirm: no build errors. Verify the NSEvent monitor is installed (grep for `addLocalMonitorForEvents.*keyDown` in FilteredCardListView.swift). Verify "All History" chip exists (grep for "All History" in ChipBarView.swift). Verify cycleLabelFilter includes All History position (grep for "removeAll" in cycleLabelFilter method).
  </verify>
  <done>
Holding left/right arrow keys smoothly and continuously scrolls through panel cards via NSEvent key monitor. "All History" chip appears first in chip bar with circle-arrow icon, highlighted by default when no label is filtered. Clicking "All History" clears the label filter. Cmd+Left/Right cycling includes "All History" as a position between the first and last labels (no wrap-around; goes first -> ... -> last -> All History -> first).
  </done>
</task>

<task type="auto">
  <name>Task 2: Auto-dismiss panel after drag-to-paste with settings toggle</name>
  <files>
    Pastel/Views/Panel/PanelController.swift
    Pastel/Views/Settings/GeneralSettingsView.swift
  </files>
  <action>
**PanelController.swift changes:**

1. In the `dragSessionStarted()` method, modify the existing `leftMouseUp` global monitor handler. Currently, after mouse-up it resets `isDragging = false` after 500ms. Add panel dismiss logic AFTER the isDragging reset, gated by the UserDefaults setting:

```swift
func dragSessionStarted() {
    isDragging = true
    onDragStarted?()

    dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
        // Clean up this one-shot monitor immediately
        if let monitor = self?.dragEndMonitor {
            NSEvent.removeMonitor(monitor)
            self?.dragEndMonitor = nil
        }
        // Delay to allow receiving app to process the drop
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self?.isDragging = false
            // Auto-dismiss panel after drag-to-paste if setting is enabled
            let dismissAfterDrag = UserDefaults.standard.bool(forKey: "dismissAfterDragPaste")
            if dismissAfterDrag {
                self?.hide()
            }
        }
    }
}
```

2. Register the default value for `dismissAfterDragPaste` to `true`. Add this to the UserDefaults registration. Check how other defaults are registered in the app -- if there's an `AppDelegate` or similar that calls `register(defaults:)`, add it there. If no central registration exists, the @AppStorage default value in GeneralSettingsView will serve as the effective default. BUT since PanelController reads it via `UserDefaults.standard.bool(forKey:)`, and `bool(forKey:)` returns `false` for unset keys, we need to handle this. Two options:
   - Option A: Register the default in AppDelegate/App init: `UserDefaults.standard.register(defaults: ["dismissAfterDragPaste": true])`
   - Option B: Use `UserDefaults.standard.object(forKey: "dismissAfterDragPaste") == nil || UserDefaults.standard.bool(forKey: "dismissAfterDragPaste")` in PanelController.

Find where other UserDefaults are registered (search for `register(defaults:)`). If found, add there. If not found, use Option B inline in PanelController for safety, since `bool(forKey:)` returns false for missing keys and we want default=true.

**GeneralSettingsView.swift changes:**

1. Add `@AppStorage("dismissAfterDragPaste") private var dismissAfterDragPaste: Bool = true`

2. Add a new section after the "Paste Behavior" section (section 5, before the Divider before "URL Previews"). Or place it within the Paste Behavior section since it's paste-related. Add:
```swift
Toggle("Dismiss panel after drag-to-paste", isOn: $dismissAfterDragPaste)
    .toggleStyle(.switch)
Text("Automatically closes the panel after dropping an item into another app.")
    .font(.caption)
    .foregroundStyle(.secondary)
```
Place this inside the existing "Paste Behavior" VStack (after the picker and its caption text), since drag-to-paste is a paste behavior.
  </action>
  <verify>
Build the project: `cd /Users/phulsechinmay/Desktop/Projects/pastel && xcodebuild -scheme Pastel -destination 'platform=macOS' build 2>&1 | tail -5`
Confirm: no build errors. Verify setting is read in PanelController (grep for "dismissAfterDragPaste" in PanelController.swift). Verify toggle exists in settings (grep for "dismissAfterDragPaste" in GeneralSettingsView.swift).
  </verify>
  <done>
Panel auto-closes after drag-to-paste completes (500ms delay for drop processing, then dismiss). Setting "Dismiss panel after drag-to-paste" appears in General Settings under Paste Behavior section, defaults to on. When the toggle is off, panel stays open after drag (existing behavior preserved).
  </done>
</task>

</tasks>

<verification>
1. Build succeeds with no errors
2. NSEvent arrow key monitor installed in FilteredCardListView (grep confirms addLocalMonitorForEvents)
3. "All History" chip rendered as first item in ChipBarView
4. cycleLabelFilter includes All History position (selectedLabelIDs.removeAll path)
5. PanelController reads dismissAfterDragPaste setting and calls hide() after drag end
6. GeneralSettingsView has toggle for dismissAfterDragPaste with default true
</verification>

<success_criteria>
- Holding arrow keys continuously scrolls through panel cards without needing individual presses
- "All History" chip with circle-arrow icon is the first chip, highlighted when no label is filtered
- Clicking "All History" clears label filter; Cmd+Left/Right includes it in the cycle
- Panel auto-dismisses after drag-to-paste when setting is enabled (default)
- New "Dismiss panel after drag-to-paste" toggle in Settings > General > Paste Behavior
</success_criteria>

<output>
After completion, create `.planning/quick/22-fix-key-repeat-for-card-nav-add-all-hist/22-SUMMARY.md`
</output>
