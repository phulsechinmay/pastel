# Phase 9: Quick Paste Hotkeys - Research

**Researched:** 2026-02-07
**Domain:** SwiftUI keyboard event handling (.onKeyPress), NSPanel key event routing, NSPasteboard plain text stripping, keycap badge UI
**Confidence:** HIGH

## Summary

Phase 9 adds panel-scoped quick paste hotkeys (Cmd+1-9 for normal paste, Cmd+Shift+1-9 for plain text paste) and keycap-style position badges on the first 9 cards. All decisions are locked by CONTEXT.md: hotkeys are panel-scoped using `.onKeyPress`, not global `KeyboardShortcuts.Name` registrations.

The existing codebase already has `.onKeyPress` handlers for arrow keys and Enter in `FilteredCardListView`, and the `SlidingPanel` (NSPanel subclass) has `canBecomeKey = true`, which means it correctly receives keyboard events. The approach adds `.onKeyPress(characters: .decimalDigits)` to catch number key presses, then checks `keyPress.modifiers` to distinguish Cmd+N from Cmd+Shift+N. The plain text paste requires a new method on `PasteService` that writes to NSPasteboard without RTF data while preserving HTML and plain string types. The keycap badges are a SwiftUI overlay on `ClipboardCardView` with a rounded-rect "key" visual.

**Primary recommendation:** Add `.onKeyPress(characters: .decimalDigits)` at the `FilteredCardListView` level (co-located with existing key handlers), check `keyPress.modifiers` for `.command` vs `[.command, .shift]`, and delegate to the existing paste flow via `onPaste` callback (normal) or a new `onPastePlainText` callback (RTF-stripped).

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI `.onKeyPress` | macOS 14+ | Panel-scoped keyboard shortcut detection | Already used in codebase for arrow keys + Enter. Native SwiftUI, no dependencies. |
| `EventModifiers` (SwiftUI) | macOS 14+ | Modifier key detection (Cmd, Shift) | OptionSet with `.command`, `.shift` members. Accessed via `keyPress.modifiers.contains()`. |
| `NSPasteboard` (AppKit) | macOS 14+ | Pasteboard writing (normal + plain text) | Already used in PasteService.writeToPasteboard(). |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `@AppStorage` (SwiftUI) | macOS 14+ | Persist quick paste enabled/disabled setting | Toggle at `quickPasteEnabled` key, default `true` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `.onKeyPress` in SwiftUI | NSEvent local monitor in PanelController | Would work but bypasses SwiftUI responder chain. `.onKeyPress` is consistent with existing arrow key handling. Local monitor would be AppKit-level, harder to integrate with SwiftUI state. |
| `.onKeyPress` in SwiftUI | `KeyboardShortcuts.Name` registration | Designed for global hotkeys. Overkill for panel-scoped shortcuts. Would register system-wide, causing conflicts with browser Cmd+1-9 tab switching. |
| Checking modifiers in action closure | Hypothetical `.onKeyPress(modifiers:)` overload | No such overload exists in SwiftUI as of macOS 15. Must check `keyPress.modifiers` inside the action. |

**Installation:** No new dependencies needed. All APIs are built into SwiftUI and AppKit.

## Architecture Patterns

### Recommended File Changes
```
Pastel/
├── Views/Panel/
│   ├── FilteredCardListView.swift  # Add .onKeyPress for Cmd+1-9 and Cmd+Shift+1-9
│   └── ClipboardCardView.swift     # Add keycap badge overlay (position number)
├── Services/
│   └── PasteService.swift          # Add pastePlainText() method (RTF stripping)
├── Views/Settings/
│   └── GeneralSettingsView.swift   # Add quick paste toggle under Hotkey section
└── App/
    └── AppState.swift              # Add pastePlainText(item:) coordination method
```

### Pattern 1: .onKeyPress with Modifier Checking for Quick Paste
**What:** Use `.onKeyPress(characters: .decimalDigits)` to catch all digit key presses on the `FilteredCardListView`, then inspect `keyPress.modifiers` to determine the action.
**When to use:** When the panel is open and the user presses Cmd+1-9 or Cmd+Shift+1-9.
**Why this approach:**
1. `.onKeyPress(characters: .decimalDigits)` receives the digit character regardless of modifier keys held (confirmed: "characters received do not have modifier keys attached")
2. `keyPress.modifiers` is an `EventModifiers` OptionSet that supports `.contains(.command)` and `.contains(.shift)`
3. Co-located with existing `.onKeyPress(.upArrow)` etc. handlers in the same view

```swift
// Source: OnKeyPressDemo (GitHub mvolkmann), Apple EventModifiers docs
// In FilteredCardListView, alongside existing .onKeyPress handlers:

.onKeyPress(characters: .decimalDigits) { keyPress in
    // Only handle when Command is held
    guard keyPress.modifiers.contains(.command) else { return .ignored }

    // Extract the digit (1-9, ignore 0)
    guard let digit = keyPress.characters.first,
          let number = digit.wholeNumberValue,
          number >= 1, number <= 9 else { return .ignored }

    let index = number - 1  // Convert 1-based to 0-based
    guard index < items.count else { return .ignored }

    let item = items[index]

    if keyPress.modifiers.contains(.shift) {
        // Cmd+Shift+N: Plain text paste
        onPastePlainText(item)
    } else {
        // Cmd+N: Normal paste (preserving formatting)
        onPaste(item)
    }

    return .handled
}
```

### Pattern 2: Plain Text Paste (RTF Stripping)
**What:** A variant of the existing `paste()` method that writes to NSPasteboard without RTF data, keeping HTML and plain string types.
**When to use:** When user presses Cmd+Shift+1-9 for plain text paste.
**Decision from CONTEXT.md:** "Removes RTF data from pasteboard. Retains HTML and plain string types."

```swift
// In PasteService, alongside existing writeToPasteboard():
private func writeToPasteboardPlainText(item: ClipboardItem) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    switch item.type {
    case .text, .richText, .code, .color:
        // Write plain text and HTML only — skip RTF
        if let text = item.textContent {
            pasteboard.setString(text, forType: .string)
        }
        if let html = item.htmlContent {
            pasteboard.setString(html, forType: .html)
        }
        // NOTE: item.rtfData is intentionally NOT written

    case .url:
        // URLs have no RTF to strip — same as normal paste
        if let urlString = item.textContent {
            pasteboard.setString(urlString, forType: .string)
            if let url = URL(string: urlString) {
                pasteboard.writeObjects([url as NSURL])
            }
        }

    case .image:
        // Images have no RTF — same as normal paste
        // (delegate to existing writeToPasteboard)

    case .file:
        // Files have no RTF — same as normal paste
        // (delegate to existing writeToPasteboard)
    }
}
```

### Pattern 3: Keycap Badge Overlay on ClipboardCardView
**What:** A small rounded-rect badge mimicking a physical keyboard key, showing "cmd N" in the bottom-right corner of each card.
**When to use:** On the first 9 visible cards when quick paste is enabled.
**Decision from CONTEXT.md:** Bottom-right corner, keyboard key style, muted (white/0.15 bg, white/0.7 text), "cmd 1" format.

```swift
// Badge view
struct KeycapBadge: View {
    let number: Int  // 1-9

    var body: some View {
        HStack(spacing: 2) {
            Text("\u{2318}")  // ⌘ symbol
                .font(.system(size: 9, weight: .medium))
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// Usage in ClipboardCardView (as overlay):
.overlay(alignment: .bottomTrailing) {
    if let position = badgePosition, quickPasteEnabled {
        KeycapBadge(number: position)
            .padding(6)
    }
}
```

### Pattern 4: Callback Plumbing for Plain Text Paste
**What:** Thread the plain text paste action through the same callback chain as normal paste: FilteredCardListView -> PanelContentView -> PanelActions -> AppState -> PasteService.
**When to use:** To invoke plain text paste from the quick paste hotkey handler.

```swift
// Option A: Add a second callback (onPastePlainText) alongside existing onPaste
// Pros: Clean separation, explicit intent
// Cons: Duplicates callback plumbing

// Option B: Add a `plainText: Bool` flag to the existing paste path
// Pros: Single callback path, less plumbing
// Cons: Overloads existing method semantics

// Recommendation: Option A — a second callback is cleaner and avoids changing
// the signature of existing paste methods used for Enter/double-click.
```

### Anti-Patterns to Avoid
- **Registering KeyboardShortcuts.Name for panel-scoped hotkeys:** These register globally via Carbon `RegisterEventHotKey`. Would conflict with browser Cmd+1-9 tab switching when the panel is NOT open.
- **Placing .onKeyPress on PanelContentView instead of FilteredCardListView:** PanelContentView does not have `.focusable()`. The FilteredCardListView already has focus management and existing key handlers. Adding quick paste handlers there keeps all keyboard logic co-located.
- **Using `.onKeyPress(.init("1"))` for each digit separately:** Would require 9 separate `.onKeyPress` calls. Use `.onKeyPress(characters: .decimalDigits)` once and parse the digit in the action.
- **Forgetting to check `quickPasteEnabled` in the key handler:** The `.onKeyPress` handler must check the `@AppStorage("quickPasteEnabled")` flag and return `.ignored` when disabled, so the key event propagates normally.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Panel-scoped keyboard shortcuts | NSEvent monitors or Carbon hotkeys | SwiftUI `.onKeyPress` | Already used in the codebase for arrow/Enter. Integrates with SwiftUI focus system. |
| Modifier key detection | NSEvent.modifierFlags bit masking | `keyPress.modifiers.contains(.command)` | SwiftUI EventModifiers is type-safe OptionSet, consistent with SwiftUI patterns. |
| Plain text from rich text | NSAttributedString -> string conversion | Simply skip writing RTF type to NSPasteboard | The pasteboard already has type separation. Don't convert; just omit the `.rtf` type when writing. |

**Key insight:** Plain text paste is NOT about converting RTF to plain text. It's about writing to NSPasteboard WITHOUT the `.rtf` data type. When the receiving app finds no RTF on the pasteboard, it falls back to `.string` (plain text). This is exactly how "Paste and Match Style" works system-wide.

## Common Pitfalls

### Pitfall 1: Cmd+1-9 Intercepted by Frontmost App's Menu
**What goes wrong:** User presses Cmd+1 in the panel, but Safari's "Switch to Tab 1" fires instead.
**Why it happens:** With `.nonactivatingPanel`, the other app remains "active" and has its menu bar. One might think its menu shortcuts get first priority.
**Why this is actually NOT a problem:** macOS routes key equivalents to the key window's view hierarchy FIRST via `performKeyEquivalent:`. Only if no view handles the event does it fall through to the menu bar. Since our NSPanel is the key window (canBecomeKey = true), and `.onKeyPress` returns `.handled`, the event never reaches the other app's menus. This is confirmed by Apple's event routing docs: "NSApplication sends a performKeyEquivalent: message to the key NSWindow object... If no object in the view hierarchy handles the key equivalent, NSApp then sends performKeyEquivalent: to the menus."
**How to verify:** Test with Safari in the background, open panel, press Cmd+1. Verify item pastes (not tab switch).
**Warning signs:** If tabs switch instead of paste, the event routing is bypassing our panel.

### Pitfall 2: Quick Paste Fires While Typing in Search Field
**What goes wrong:** User types "1" in the search field while Cmd is held (e.g., for Cmd+A select-all then typing), triggering an unintended quick paste.
**Why it happens:** `.onKeyPress` handlers on FilteredCardListView might intercept events even when the search TextField has focus.
**How to avoid:** This is actually self-preventing: when the search TextField has focus, the `FilteredCardListView`'s `.onKeyPress` handlers are NOT active because focus is on the TextField, not the `.focusable()` view. The existing arrow key handlers already demonstrate this -- they don't fire while typing in search. However, with `performKeyEquivalent:`, Cmd+digit might propagate differently than plain digits. Verify during testing.
**Warning signs:** Typing Cmd+1 in search field triggers a paste instead of being handled by the text field.

### Pitfall 3: Badge Position Mismatch After Filtering
**What goes wrong:** User filters by label, sees 3 items. Badges show 1-3. Cmd+1 pastes... item 1 from the unfiltered list?
**Why this is NOT a problem:** Decision from CONTEXT.md: "Cmd+N pastes the Nth visible card in the current filtered view." Since both the badge position AND the `.onKeyPress` handler index into the same `items` array from `@Query`, they are always in sync. The `items` array IS the filtered view.
**How to verify:** Filter to a label with few items, verify Cmd+1 pastes the first visible item (not the first in the full list).

### Pitfall 4: Self-Paste Loop on Quick Paste
**What goes wrong:** Quick paste writes to pasteboard and simulates Cmd+V. ClipboardMonitor detects the pasteboard change and re-captures the item, creating a duplicate.
**Why it happens:** Same issue as normal paste, well-understood in the codebase.
**How to avoid:** The existing `clipboardMonitor.skipNextChange = true` flag in `PasteService.paste()` already handles this. Quick paste goes through the same PasteService flow, so it inherits this protection. No additional work needed.
**Warning signs:** Duplicate items appearing in the history after quick paste.

### Pitfall 5: Panel Not Closing After Quick Paste
**What goes wrong:** User presses Cmd+3, item is pasted, but the panel stays open.
**Why it happens:** If the quick paste callback doesn't trigger panel hide.
**How to avoid:** Route through the existing `paste(item:)` / `pastePlainText(item:)` on AppState, which calls `PasteService.paste()` which calls `panelController.hide()`. The same hide flow as Enter/double-click paste.
**Warning signs:** Panel remains visible after quick paste.

### Pitfall 6: Badge Shows on More Than 9 Items
**What goes wrong:** 15 items visible, all 15 show badges.
**Why it happens:** Forgot to limit badge display to first 9.
**How to avoid:** Pass the index from `ForEach(Array(items.enumerated()))` to `ClipboardCardView`. Only show badge when `index < 9`.
**Warning signs:** Badges with numbers > 9 appearing on cards.

## Code Examples

Verified patterns from the existing codebase and official sources:

### Existing .onKeyPress Pattern (FilteredCardListView)
```swift
// Source: Pastel/Views/Panel/FilteredCardListView.swift (existing code)
.focusable()
.focusEffectDisabled()
.onKeyPress(.upArrow) {
    if !isHorizontal { moveSelection(by: -1) }
    return isHorizontal ? .ignored : .handled
}
.onKeyPress(.return) {
    if let index = selectedIndex, index < items.count {
        onPaste(items[index])
    }
    return .handled
}
```

### EventModifiers Contains Check
```swift
// Source: GitHub mvolkmann/OnKeyPressDemo
let commandDown = press.modifiers.contains(.command)
let shiftDown = press.modifiers.contains(.shift)
let controlDown = press.modifiers.contains(.control)
let optionDown = press.modifiers.contains(.option)
```

### NSPasteboard Type-Selective Writing (Plain Text)
```swift
// Source: Existing PasteService.writeToPasteboard() pattern
// Normal write (preserves RTF):
pasteboard.setData(rtfData, forType: .rtf)    // RTF formatting
pasteboard.setString(html, forType: .html)     // HTML formatting
pasteboard.setString(text, forType: .string)   // Plain text fallback

// Plain text write (strips RTF):
// pasteboard.setData(rtfData, forType: .rtf)  // OMIT RTF
pasteboard.setString(html, forType: .html)     // Keep HTML
pasteboard.setString(text, forType: .string)   // Keep plain text
```

### AppStorage Toggle Pattern (Existing in GeneralSettingsView)
```swift
// Source: Pastel/Views/Settings/GeneralSettingsView.swift
@AppStorage("fetchURLMetadata") private var fetchURLMetadata: Bool = true

Toggle("Fetch page title, favicon, and preview image for copied URLs", isOn: $fetchURLMetadata)
    .toggleStyle(.switch)
```

### Existing Paste Flow (AppState -> PasteService)
```swift
// Source: Pastel/App/AppState.swift
func paste(item: ClipboardItem) {
    guard let clipboardMonitor else { return }
    pasteService.paste(item: item, clipboardMonitor: clipboardMonitor, panelController: panelController)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Global Carbon hotkeys for clipboard shortcuts | Panel-scoped `.onKeyPress` | Decision for this phase | Avoids all global shortcut conflicts, simpler implementation |
| Single paste mode (all formatting) | Dual paste mode (normal + plain text) | Decision for this phase | Cmd+1-9 for normal, Cmd+Shift+1-9 for RTF-stripped |
| No visual position indicators | Keycap-style badges (cmd 1-9) | New for this phase | Users can see which number corresponds to which card |

**Deprecated/outdated:**
- Global hotkey approach (original roadmap): CONTEXT.md explicitly overrides this. Panel-scoped is the locked decision.
- `KeyboardShortcuts.Name` registration: Only needed for global shortcuts. Panel-scoped shortcuts use `.onKeyPress`.

## Open Questions

None. All gray areas were resolved in the CONTEXT.md discuss phase:
- Scope: Panel-scoped (locked)
- Hotkey sets: Two (Cmd+N and Cmd+Shift+N) (locked)
- Implementation: `.onKeyPress` (locked)
- Item resolution: Filtered view / WYSIWYG (locked)
- Badge design: Keycap style, bottom-right, muted colors (locked)
- Settings: Toggle under Hotkey section, default enabled (locked)

## Sources

### Primary (HIGH confidence)
- Existing codebase: `FilteredCardListView.swift`, `ClipboardCardView.swift`, `PasteService.swift`, `AppState.swift`, `PanelContentView.swift`, `PanelController.swift`, `SlidingPanel.swift`, `GeneralSettingsView.swift` -- verified all existing patterns, key event flow, paste flow, settings UI layout
- [Apple Event Architecture docs](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/EventArchitecture/EventArchitecture.html) -- key equivalent routing order: key window view hierarchy first, then menu bar
- [Apple Handling Key Events docs](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingKeyEvents/HandlingKeyEvents.html) -- performKeyEquivalent: routing, NSPanel key window behavior
- [OnKeyPressDemo (GitHub mvolkmann)](https://github.com/mvolkmann/OnKeyPressDemo/blob/main/OnKeyPressDemo/ContentView.swift) -- verified `press.modifiers.contains(.command)` pattern

### Secondary (MEDIUM confidence)
- [SwiftLee: Key press events detection](https://www.avanderlee.com/swiftui/key-press-events-detection/) -- onKeyPress overloads, characters parameter, .decimalDigits usage, phases
- [Hacking with Swift: key press events](https://www.hackingwithswift.com/quick-start/swiftui/how-to-detect-and-respond-to-key-press-events) -- confirmed "characters received do not have modifier keys attached"
- [NSPanel nonactivating blog post](https://philz.blog/nspanel-nonactivating-style-mask-flag/) -- nonactivating panels receive key events when key window; style mask bug only applies when changing mask after init (not our case)

### Tertiary (LOW confidence)
- Web search results for macOS key event routing with NSPanel -- general confirmation of event routing order, no single definitive source beyond Apple's archived docs

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All APIs are built-in SwiftUI/AppKit, already used in the codebase. No new dependencies.
- Architecture: HIGH - Extends existing patterns (`.onKeyPress`, paste flow, settings toggle). All patterns verified against existing codebase code.
- Pitfalls: HIGH - Key event routing verified against Apple docs. Self-paste loop already solved. Search field focus isolation follows from existing arrow key behavior.
- Badge design: HIGH - Pure SwiftUI overlay, no complex interactions. Uses existing card view overlay pattern.

**Research date:** 2026-02-07
**Valid until:** 2026-03-07 (30 days -- stable domain, SwiftUI keyboard APIs unlikely to change)
