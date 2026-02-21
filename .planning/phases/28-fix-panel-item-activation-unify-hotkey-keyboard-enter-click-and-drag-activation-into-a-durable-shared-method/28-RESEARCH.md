# Phase 28: Fix Panel Item Activation - Research

**Researched:** 2026-02-21
**Domain:** macOS AppKit keyboard event handling / SwiftUI focus system
**Confidence:** HIGH

## Summary

The panel's keyboard activation (Enter to paste, Cmd+1-9 for quick paste, Cmd+Shift+1-9 for plain text quick paste) is broken because SwiftUI `.onKeyPress` handlers on FilteredCardListView's `.focusable()` Group never fire -- the Group does not reliably receive SwiftUI keyboard focus in the NSPanel context. Arrow key navigation works because it uses an NSEvent local monitor (`installArrowKeyMonitor()`), which operates at the AppKit level and is immune to SwiftUI focus issues.

The fix is straightforward: extend the existing `installArrowKeyMonitor()` to also handle Enter (keyCode 0x24), Cmd+1-9, and Cmd+Shift+1-9 via `event.keyCode` and `event.modifierFlags`. Then remove the three broken `.onKeyPress` handlers (Return, `.decimalDigits`, shifted digits `!@#$%^&*(`). The type-to-search `.onKeyPress` handler is kept per user decision.

**Primary recommendation:** Extend the existing NSEvent local monitor in `installArrowKeyMonitor()` (rename to `installKeyboardMonitor()`) to handle Enter, Cmd+1-9, and Cmd+Shift+1-9 activation. Remove the three broken `.onKeyPress` handlers. This is a focused refactor of ~80 lines in a single file.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Root Cause:**
- SwiftUI `.onKeyPress` handlers in FilteredCardListView are wired correctly but never fire
- The `.focusable()` on the Group wrapper isn't reliably receiving keyboard focus
- Arrow key navigation works because it uses NSEvent local monitor (not `.onKeyPress`)
- Escape works because PanelController uses NSEvent local monitor
- Double-click works because `.onTapGesture` doesn't depend on SwiftUI focus
- Drag works because `.onDrag` doesn't depend on SwiftUI focus

**Keyboard Event Strategy:**
- Use NSEvent local monitor for Enter, Cmd+1-9, and Cmd+Shift+1-9 activation
- Extend the existing `installArrowKeyMonitor()` in FilteredCardListView
- Remove the broken `.onKeyPress` handlers for Return, `.decimalDigits`, and shifted digits (`!@#$%^&*(`)
- Keep the type-to-search `.onKeyPress` handler (`.alphanumerics.union(.punctuationCharacters)`)

**Activation Architecture:**
- Keep the existing callback chain: `onPaste(item)` -> `panelActions.pasteItem?()` -> `PanelController.onPasteItem` -> `AppState.paste()` -> `PasteService.paste()`
- Do NOT extract a new `activateItem()` abstraction -- the callback chain is already the unified path
- `PasteService.paste()` and `PasteService.pastePlainText()` remain the single point of truth
- Drag-and-drop stays on its separate path (NSItemProvider)

**Post-Activation Behavior:**
- All activation methods respect the existing `PasteBehavior` setting uniformly
- No method-specific behavior differences
- Panel dismiss behavior follows existing logic (PasteService handles this)

**Scope Boundaries:**
- Four activation methods: double-click, drag-and-drop, Enter key, Cmd+1-9 hotkeys
- Single-click remains selection-only (no change)
- Right-click remains context menu (no change)
- Arrow key navigation stays as-is (already working via NSEvent)

### Claude's Discretion

- Exact refactoring of `installArrowKeyMonitor()` (rename to `installKeyboardMonitor()` or similar)
- Whether to use keyCode constants or raw values for Enter/digit keys
- Any necessary cleanup of unused focus management code after removing `.onKeyPress`

### Deferred Ideas (OUT OF SCOPE)

None -- discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core

No new libraries needed. This phase uses only existing macOS system APIs.

| API | Purpose | Why Standard |
|-----|---------|--------------|
| `NSEvent.addLocalMonitorForEvents(matching:)` | Intercept keyboard events at the AppKit level | Already used for arrow keys, Escape, flags monitoring. Proven reliable in the codebase |
| `NSEvent.keyCode` | Identify physical key presses independent of keyboard layout | Virtual key codes from `<HIToolbox/Events.h>`, stable since ADB era |
| `NSEvent.modifierFlags` | Check Cmd, Shift, and other modifier state | Standard AppKit API, already used in arrow key handler |

### Supporting

No new supporting libraries.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NSEvent local monitor | SwiftUI `.onKeyPress` | `.onKeyPress` is the broken approach being replaced. Does not work when `.focusable()` Group lacks keyboard focus |
| NSEvent local monitor | `NSResponder.keyDown(with:)` subclass | Would require NSPanel/NSView subclass. More invasive, same result |

## Architecture Patterns

### Current File Structure (no changes to structure)

```
Pastel/Views/Panel/
├── FilteredCardListView.swift    # THE file being modified
├── PanelContentView.swift        # Parent view (passes callbacks, no changes)
├── PanelController.swift         # Panel lifecycle (Escape monitor, no changes)
└── ClipboardCardView.swift       # Card rendering (no changes)
```

### Pattern 1: NSEvent Local Monitor for Keyboard Handling

**What:** Use `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` to intercept keyboard events at the AppKit layer, bypassing SwiftUI's focus system entirely.

**When to use:** When SwiftUI `.onKeyPress` is unreliable due to focus issues in NSPanel/NSHostingView contexts.

**Current implementation (arrows only):**
```swift
// FilteredCardListView.swift, line 321-358
private func installArrowKeyMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        switch event.keyCode {
        case 123: // Left arrow
            // handle...
            return nil // consumed
        case 124: // Right arrow
            // handle...
            return nil
        // ... other arrow keys
        default:
            return event // pass through all other keys
        }
    }
}
```

**Extended implementation (arrows + Enter + Cmd+digits):**
```swift
private func installKeyboardMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        // Arrow keys (existing)
        case 123: // Left arrow
            // ... existing logic unchanged ...
        case 124: // Right arrow
            // ... existing logic unchanged ...
        case 125: // Down arrow
            // ... existing logic unchanged ...
        case 126: // Up arrow
            // ... existing logic unchanged ...

        // Enter/Return key
        case 0x24, 0x4C: // Return, Keypad Enter
            if let index = selectedIndex, index < visibleItems.count {
                if flags.contains(.shift) {
                    onPastePlainText(visibleItems[index])
                } else {
                    onPaste(visibleItems[index])
                }
                return nil
            }
            return event

        // Cmd+1-9 and Cmd+Shift+1-9 (digit keys)
        default:
            if flags.contains(.command), let digitIndex = Self.digitKeyCodeMap[event.keyCode] {
                guard quickPasteEnabled else { return event }
                let index = digitIndex - 1
                guard index < visibleItems.count else { return event }
                if flags.contains(.shift) {
                    onPastePlainText(visibleItems[index])
                } else {
                    onPaste(visibleItems[index])
                }
                return nil
            }
            return event
        }
    }
}
```

### Pattern 2: Virtual Key Code Mapping for Digits

**What:** Map physical digit key codes to logical digit values using a static dictionary. Virtual key codes for digits are non-sequential (0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19) because they map to physical key positions on ANSI keyboards.

**Why needed:** The existing `.onKeyPress(characters: .decimalDigits)` approach relies on character matching which doesn't work without SwiftUI focus. NSEvent `.keyCode` gives physical key codes that need translation.

**Implementation:**
```swift
// Static dictionary mapping NSEvent.keyCode to digit value
private static let digitKeyCodeMap: [UInt16: Int] = [
    0x12: 1,  // kVK_ANSI_1
    0x13: 2,  // kVK_ANSI_2
    0x14: 3,  // kVK_ANSI_3
    0x15: 4,  // kVK_ANSI_4
    0x17: 5,  // kVK_ANSI_5
    0x16: 6,  // kVK_ANSI_6
    0x1A: 7,  // kVK_ANSI_7
    0x1C: 8,  // kVK_ANSI_8
    0x19: 9,  // kVK_ANSI_9
]
```

**Critical note:** Cmd+Shift+1-9 and Cmd+1-9 use the **same key codes**. The physical key is the same; the difference is whether Shift is held. So the same `digitKeyCodeMap` works for both -- check `flags.contains(.shift)` to differentiate paste vs. plain-text paste. This is simpler than the old approach which needed a separate `shiftedDigitMap` (`!@#$%^&*(`) because character mapping changes with Shift.

### Anti-Patterns to Avoid

- **Checking `event.characters` for digit detection with Cmd held:** `event.characters` may return unexpected values when Cmd is held (macOS can modify characters with Cmd modifier). Use `event.keyCode` which is always the physical key.
- **Forgetting to return `nil` for consumed events:** Returning `event` passes it to other monitors (including PanelController's Escape handler and SwiftUI's event pipeline). Consumed events must return `nil`.
- **Installing multiple monitors for the same keys:** FilteredCardListView already has one monitor. Do NOT add a second monitor -- extend the existing one.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Key code constants | A Carbon framework import or custom enum | Inline hex literals with kVK comments | The digit key codes are stable since ADB era (30+ years). A 9-entry dictionary with comments is clearer than importing Carbon framework |
| Event routing between monitors | Custom event dispatch system | NSEvent local monitor ordering | macOS delivers events to all local monitors. Return `nil` to consume. Return `event` to pass through. This is the designed mechanism |

**Key insight:** The entire fix is extending an existing, working pattern by ~30 lines. There is no need for new abstractions, services, or architectural changes.

## Common Pitfalls

### Pitfall 1: Forgetting Keypad Enter

**What goes wrong:** Users with extended keyboards press the numpad Enter key and nothing happens.
**Why it happens:** Return (keyCode 0x24) and Keypad Enter (keyCode 0x4C) are different physical keys with different key codes.
**How to avoid:** Handle both key codes in the same case: `case 0x24, 0x4C:`.
**Warning signs:** Testing only on laptop keyboards misses this.

### Pitfall 2: Modifier Flag Comparison with Extra Bits

**What goes wrong:** `event.modifierFlags.contains(.command)` works, but exact flag comparison fails because `modifierFlags` includes device-dependent bits (Caps Lock, Num Lock, etc.).
**Why it happens:** `NSEvent.modifierFlags` is a bitmask that includes more flags than just the modifier keys.
**How to avoid:** Use `.intersection(.deviceIndependentFlagsMask)` to strip device-dependent bits before comparison. For simple containment checks (`.contains(.command)`), this isn't needed. But for "Cmd only, no Shift" detection, use: `flags.intersection(.deviceIndependentFlagsMask).subtracting(.numericPad) == .command`.
**Warning signs:** Cmd+digit works but Cmd+Shift+digit doesn't (or vice versa).

### Pitfall 3: Event Consumption Order Between Monitors

**What goes wrong:** PanelController's Escape monitor consumes events that FilteredCardListView's monitor should handle, or vice versa.
**Why it happens:** Multiple `NSEvent.addLocalMonitorForEvents` monitors ALL receive the event. They are called in installation order. If one returns `nil`, subsequent monitors don't see the event.
**How to avoid:** PanelController's monitor (installed on panel show) only consumes Escape (keyCode 53). FilteredCardListView's monitor (installed on view appear) only consumes arrow/Enter/digit keys. No overlap exists. Just verify neither monitor consumes the other's keys.
**Warning signs:** Escape stops working after adding Enter handling, or Enter doesn't work.

### Pitfall 4: Stale Closure Captures in NSEvent Monitor

**What goes wrong:** The NSEvent monitor closure captures `self` properties at install time and doesn't see updates.
**Why it happens:** Swift closures capture value types by copy. SwiftUI `@State` and `@AppStorage` are value types. The monitor closure may capture stale values of `selectedIndex`, `quickPasteEnabled`, or `visibleItems`.
**How to avoid:** In the current codebase, the monitor closure accesses `self.selectedIndex`, `self.visibleItems`, `self.quickPasteEnabled` etc. through `self` which is a struct, BUT the closure captures a reference to the underlying storage through SwiftUI's property wrappers. The existing arrow key monitor already accesses `selectedIndex` and `visibleItems` this way and works correctly -- the same pattern should be used for Enter and digits.
**Warning signs:** Quick paste always pastes the wrong item, or selectedIndex is always nil.

### Pitfall 5: Leaving Dead `.onKeyPress` Handlers

**What goes wrong:** The removed `.onKeyPress` handlers are still partially referenced or the `.focusable()` modifier is left with no purpose.
**Why it happens:** Incomplete cleanup after migrating to NSEvent.
**How to avoid:** Remove all three broken `.onKeyPress` handlers. Keep `.focusable()` and `.focusEffectDisabled()` because the `.focused($panelFocus, .cardList)` on PanelContentView still targets this view for `.defaultFocus`. The type-to-search `.onKeyPress` also still needs `.focusable()`. If type-to-search is removed in the future, `.focusable()` can go too.
**Warning signs:** Compiler warnings about unused closures.

## Code Examples

Verified patterns from the existing codebase:

### Current Arrow Key Monitor (Working Pattern to Extend)
```swift
// Source: FilteredCardListView.swift, lines 321-358
private func installArrowKeyMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        switch event.keyCode {
        case 123: // Left arrow
            if event.modifierFlags.contains(.command) {
                onCycleLabelFilter?(-1)
            } else if isHorizontal {
                moveSelection(by: -1)
            } else {
                return event
            }
            return nil
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
            return event
        }
    }
}
```

### PanelController Escape Monitor (Coexisting Pattern)
```swift
// Source: PanelController.swift, lines 318-326
localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
    if event.keyCode == 53 { // Escape
        self?.hide()
        return nil
    }
    return event
}
```

### Existing Callback Chain (Unchanged)
```swift
// Source: PanelContentView.swift, lines 100-101
onPaste: { item in pasteItem(item) },
onPastePlainText: { item in pastePlainTextItem(item) },

// Source: PanelContentView.swift, lines 217-223
private func pasteItem(_ item: ClipboardItem) {
    panelActions.pasteItem?(item)
}
private func pastePlainTextItem(_ item: ClipboardItem) {
    panelActions.pastePlainTextItem?(item)
}
```

### Virtual Key Code Reference (Carbon HIToolbox/Events.h)
```
// Return/Enter
kVK_Return         = 0x24  (36)
kVK_ANSI_KeypadEnter = 0x4C  (76)

// Digit keys (non-sequential!)
kVK_ANSI_1 = 0x12  (18)
kVK_ANSI_2 = 0x13  (19)
kVK_ANSI_3 = 0x14  (20)
kVK_ANSI_4 = 0x15  (21)
kVK_ANSI_5 = 0x17  (23)  // note: not 0x16
kVK_ANSI_6 = 0x16  (22)  // note: not 0x17
kVK_ANSI_7 = 0x1A  (26)
kVK_ANSI_8 = 0x1C  (28)
kVK_ANSI_9 = 0x19  (25)

// Arrow keys (already handled)
kVK_LeftArrow  = 0x7B  (123)
kVK_RightArrow = 0x7C  (124)
kVK_DownArrow  = 0x7D  (125)
kVK_UpArrow    = 0x7E  (126)

// Escape (handled in PanelController)
kVK_Escape = 0x35  (53)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SwiftUI `.onKeyPress` for activation keys | NSEvent local monitor for activation keys | This phase | Reliable keyboard activation regardless of SwiftUI focus state |
| Separate handlers for Cmd+N and Cmd+Shift+N | Single `keyCode` check with `flags.contains(.shift)` | This phase | Simpler code: same physical key, differentiated by modifier. No need for `shiftedDigitMap` |
| `!@#$%^&*(` character matching for shifted digits | `event.keyCode` for physical digit key | This phase | Layout-independent: works on non-US keyboards where Shift+digits produce different characters |

**Deprecated/outdated:**
- The `.onKeyPress(characters: CharacterSet(charactersIn: "!@#$%^&*("))` pattern is a workaround for macOS Shift+digit character mapping. Moving to `event.keyCode` eliminates this entirely.

## Open Questions

1. **Type-to-search `.onKeyPress` reliability**
   - What we know: The user says to keep it. It uses `.onKeyPress(characters: .alphanumerics.union(.punctuationCharacters))` on the same `.focusable()` Group that doesn't reliably receive focus.
   - What's unclear: Whether type-to-search actually works today. If the Group never gets focus, this handler also never fires.
   - Recommendation: Keep it per user decision. If it's confirmed broken later, it can be migrated to NSEvent in a separate task. The NSEvent monitor can coexist with `.onKeyPress` -- `.onKeyPress` simply won't fire if focus isn't there, and the NSEvent monitor passes unhandled keys through.

2. **`.focusable()` and `.focusEffectDisabled()` cleanup**
   - What we know: After removing three `.onKeyPress` handlers, only the type-to-search handler remains. `.focusable()` is still needed for it and for the `.focused($panelFocus, .cardList)` targeting in PanelContentView.
   - What's unclear: Whether removing the three handlers affects the `.focused()` behavior in any way.
   - Recommendation: Keep `.focusable()` and `.focusEffectDisabled()`. They are low-cost and preserve the focus targeting infrastructure.

## Sources

### Primary (HIGH confidence)

- **Codebase analysis** - Direct reading of FilteredCardListView.swift, PanelController.swift, PanelContentView.swift, PasteService.swift, AppState.swift
- **28-CONTEXT.md** - User decisions from discussion phase
- **Apple Developer Documentation** - [NSEvent.keyCode](https://developer.apple.com/documentation/appkit/nsevent/1534513-keycode)

### Secondary (MEDIUM confidence)

- **Virtual key code reference** - [Swift Keyboard Keycodes Gist](https://gist.github.com/swillits/df648e87016772c7f7e5dbed2b345066) and [Mac virtual keycodes Gist](https://gist.github.com/eegrok/949034) - Cross-verified with Carbon HIToolbox/Events.h constants
- **macOS Forums** - [NSEvent keyCode list](https://forums.macrumors.com/threads/nsevent-keycode-list.780577/), [Apple Developer Forums](https://developer.apple.com/forums/thread/748423)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - No new libraries, using existing codebase pattern
- Architecture: HIGH - Extending a proven, working pattern in a single file
- Pitfalls: HIGH - All pitfalls identified from direct codebase analysis and established macOS keyboard handling knowledge
- Key codes: HIGH - Virtual key codes are stable since ADB era (1980s), verified across multiple sources

**Research date:** 2026-02-21
**Valid until:** 2026-03-21 (stable domain -- macOS keyboard handling APIs don't change)
