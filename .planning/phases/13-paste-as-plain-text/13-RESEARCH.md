# Phase 13: Paste as Plain Text - Research

**Researched:** 2026-02-09
**Domain:** SwiftUI interaction handlers, NSPasteboard writing, plain text paste
**Confidence:** HIGH

## Summary

Phase 13 adds three UI entry points for "paste as plain text" (context menu, Shift+Enter, Shift+double-click) and fixes a critical HTML bug in PasteService. The existing codebase is 90% ready -- `PasteService.pastePlainText()` exists and is fully wired through `PanelActions.pastePlainTextItem`, `PanelController.onPastePlainTextItem`, and `AppState.pastePlainText()`. The `isShiftHeld` state is already tracked in `PanelContentView` and passed through `FilteredCardListView`.

The work breaks down into: (1) one 2-line bug fix in `PasteService.writeToPasteboardPlainText()`, (2) one context menu item addition in `ClipboardCardView`, (3) one Shift+Enter handler addition in `FilteredCardListView`, (4) Shift+double-click detection in `FilteredCardListView`'s `onTapGesture(count: 2)` handlers, and (5) mirroring the context menu item to `HistoryGridView`. Total estimated change: ~25-30 lines across 4 files.

**Primary recommendation:** Fix the HTML bug first (it is a 2-line change that removes the HTML write from `writeToPasteboardPlainText`), then add the three UI entry points using the existing patterns already proven in the codebase.

## Standard Stack

No new libraries required. This phase uses only existing framework APIs already in the project.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 14+ | `.onKeyPress`, `.contextMenu`, `.onTapGesture` | Already in use, native framework |
| AppKit | macOS 14+ | `NSEvent.modifierFlags`, `NSPasteboard` | Already in use for modifier detection and pasteboard |

### Supporting
No additional libraries needed.

### Alternatives Considered
None -- all needed APIs are already in use in the codebase.

## Architecture Patterns

### Existing Paste Callback Chain (Already Wired)

```
User Action
  -> FilteredCardListView.onPastePlainText(item)
    -> PanelContentView.pastePlainTextItem(item)
      -> PanelActions.pastePlainTextItem?(item)
        -> PanelController.onPastePlainTextItem?(item)
          -> AppState.pastePlainText(item)
            -> PasteService.pastePlainText(item, ...)
              -> writeToPasteboardPlainText(item)
```

This full chain is already implemented. No new wiring needed.

### Pattern 1: Context Menu Actions via PanelActions Environment

**What:** Context menu buttons call `panelActions.someAction?(item)` to invoke AppKit callbacks.
**Where proven:** `ClipboardCardView.swift` lines 163-172 (Copy, Paste, Copy+Paste buttons).
**How to add Paste as Plain Text:**

```swift
// In ClipboardCardView contextMenu, after existing "Copy + Paste" button:
Button("Paste as Plain Text") {
    panelActions.pastePlainTextItem?(item)
}
```

**Confidence:** HIGH -- this is an exact replica of the existing Paste button pattern. The `panelActions.pastePlainTextItem` callback is already wired (PanelController.swift line 119, AppState.swift line 65).

### Pattern 2: Shift+Enter via .onKeyPress Modifier Check

**What:** `.onKeyPress(.return)` handler checks `isShiftHeld` state to branch between normal paste and plain text paste.
**Where proven:** `.onKeyPress(characters: .decimalDigits)` in FilteredCardListView lines 236-258 already branches on `keyPress.modifiers.contains(.shift)` for Cmd+Shift+N plain text paste.
**How to add Shift+Enter:**

```swift
// Replace the existing .onKeyPress(.return) handler:
.onKeyPress(.return) {
    if let index = selectedIndex, index < filteredItems.count {
        if isShiftHeld {
            onPastePlainText(filteredItems[index])
        } else {
            onPaste(filteredItems[index])
        }
    }
    return .handled
}
```

**IMPORTANT - Why use `isShiftHeld` instead of `keyPress.modifiers.contains(.shift)`:** The `.onKeyPress(.return)` handler receives a `KeyPress` object that has a `.modifiers` property. However, the existing codebase consistently uses the `isShiftHeld` state variable (tracked via `NSEvent.addLocalMonitorForEvents` in PanelContentView line 126-128) and passes it through as a parameter. Either approach works, but using `keyPress.modifiers.contains(.shift)` in the `.onKeyPress` handler is more direct and avoids any timing edge cases with the external monitor. The Cmd+Shift+N handler at line 250 uses `keyPress.modifiers.contains(.shift)` successfully.

**Recommendation:** Use `keyPress.modifiers.contains(.shift)` since it is available directly in the handler and is already proven in the Cmd+Shift+N handler.

**Confidence:** HIGH -- both the `.onKeyPress(.return)` handler and `.shift` modifier check are already working patterns in this exact file.

### Pattern 3: Shift+Double-Click via NSEvent.modifierFlags

**What:** Inside `.onTapGesture(count: 2)` closure, check `NSEvent.modifierFlags.contains(.shift)` to branch.
**Where proven:** `HistoryGridView.swift` line 160 uses `NSEvent.modifierFlags` to detect Cmd-click and Shift-click in `handleTap()`.
**How to add Shift+double-click:**

```swift
// Replace existing .onTapGesture(count: 2) handlers in FilteredCardListView:
.onTapGesture(count: 2) {
    if NSEvent.modifierFlags.contains(.shift) {
        onPastePlainText(item)
    } else {
        onPaste(item)
    }
}
```

**Critical detail:** This pattern must be applied in BOTH the horizontal layout (line 120) and vertical layout (line 172) branches of FilteredCardListView, since both have separate `.onTapGesture(count: 2)` handlers.

**Confidence:** HIGH -- `NSEvent.modifierFlags` static property is already used in HistoryGridView for the same purpose (modifier detection in gesture handlers).

### Pattern 4: HistoryGridView Context Menu Addition

**What:** The History browser's context menu (HistoryGridView lines 98-131) also needs a "Paste as Plain Text" option for single-item context menus.
**Current state:** HistoryGridView provides its own context menu with Copy, Paste, Edit, Delete. It does NOT use PanelActions; instead it uses `onBulkCopy`/`onBulkPaste` closures from the parent `HistoryBrowserView`.
**Approach:** Add a new closure `onSinglePastePlainText` or wire through the existing AppState environment.

**Confidence:** MEDIUM -- the exact wiring approach needs a design decision (new closure vs. AppState direct call). The simplest approach is to add PanelActions environment with pastePlainTextItem wired, but HistoryBrowserView currently passes a bare `PanelActions()` on line 53 without wiring callbacks. An alternative is to access `AppState` from environment directly since HistoryBrowserView already has `@Environment(AppState.self)`.

**Recommended approach:** Use `@Environment(AppState.self)` which is already available in HistoryBrowserView (line 24), and call `appState.pastePlainText(item)` directly. This requires passing an `onPastePlainText` closure from HistoryBrowserView to HistoryGridView, following the same pattern as `onBulkPaste`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Shift key detection in gestures | Custom NSEvent monitor | `NSEvent.modifierFlags` static property | Thread-safe class property, already proven in HistoryGridView |
| Shift key detection in key handlers | External state tracking | `keyPress.modifiers.contains(.shift)` | Available directly in `.onKeyPress` closure, more reliable |
| Plain text pasteboard writing | New paste method | Fix existing `writeToPasteboardPlainText()` | Method already exists, just needs HTML line removed |
| Paste callback chain | New callback wiring | Existing `PanelActions.pastePlainTextItem` | Fully wired end-to-end, just call it |

## Common Pitfalls

### Pitfall 1: HTML Data Surviving Plain Text Paste (THE BUG)

**What goes wrong:** `writeToPasteboardPlainText()` still writes `.html` content to the pasteboard (line 235-237 of PasteService.swift). When pasting into apps like Google Docs or Apple Notes that prefer HTML over plain string, the HTML formatting is preserved -- completely defeating the "plain text" intent.

**Root cause:** The method comment says "Write string and HTML only -- NO .rtf data" but this is wrong. For true plain text, NEITHER `.rtf` NOR `.html` should be written. The method should ONLY write `.string`.

**How to fix:** Remove lines 235-237 from `writeToPasteboardPlainText()`:
```swift
// REMOVE these lines:
if let html = item.htmlContent {
    pasteboard.setString(html, forType: .html)
}
```

**Why this is the complete fix:** When only `.string` type is on the pasteboard, ALL receiving apps (Google Docs, Notes, TextEdit, VS Code, etc.) must fall back to their default text formatting. There is no rich format data to interpret.

**Confidence:** HIGH -- this is verified by reading the code directly. The `.html` pasteboard type is the cause; NSPasteboard type hierarchy means apps prefer `.html` over `.string` when both are present.

### Pitfall 2: Two Duplicate onTapGesture Handlers in FilteredCardListView

**What goes wrong:** FilteredCardListView has TWO separate layout branches (horizontal at line 106 and vertical at line 160), each with their own `.onTapGesture(count: 2)` handlers. Forgetting to update BOTH creates inconsistent behavior depending on panel edge configuration.

**How to avoid:** Update both handlers identically. Search for ALL occurrences of `.onTapGesture(count: 2)` in the file.

**Confidence:** HIGH -- verified by reading the code.

### Pitfall 3: onKeyPress .return with Shift May Conflict with Search Field

**What goes wrong:** If the search field has focus, Enter/Shift+Enter should not trigger paste.

**Why it's NOT a problem here:** The `.onKeyPress(.return)` handler is on the `FilteredCardListView` which only receives key events when `panelFocus == .cardList`. When the search field is focused, key events go to the search field, not to the card list. This is already working correctly for the normal Enter-to-paste behavior.

**Confidence:** HIGH -- the existing `.onKeyPress(.return)` handler has been working without search field conflicts since Phase 3.

### Pitfall 4: Context Menu Button Text Ambiguity

**What goes wrong:** Having both "Paste" and "Paste as Plain Text" in the context menu could confuse users, especially when "Copy + Paste" already exists.

**How to avoid:** Place "Paste as Plain Text" right after "Paste" (or after "Copy + Paste") with a separator before the label management section. This groups all paste-related actions together.

**Recommended menu order:**
```
Copy
Paste
Copy + Paste
Paste as Plain Text    <-- NEW
---
Edit...
---
Label >
---
Delete
```

**Confidence:** HIGH -- follows standard macOS context menu patterns.

### Pitfall 5: HistoryGridView Does Not Track Shift State

**What goes wrong:** HistoryGridView does not have `isShiftHeld` state or an `onPastePlainText` callback, so Shift+double-click and Shift+Enter cannot be added there without additional wiring.

**How to handle:** For Phase 13, only add the context menu "Paste as Plain Text" option to HistoryGridView. Shift+double-click and Shift+Enter are panel-specific interactions. The History browser is a settings window (standard macOS window, not the sliding panel), so the keyboard/mouse modifier patterns differ. Double-click is not currently a gesture in HistoryGridView (it uses single-click for selection only).

**Confidence:** HIGH -- verified by reading HistoryGridView code. There are no `onTapGesture(count: 2)` handlers in HistoryGridView, and no Enter key handler for paste.

## Code Examples

### Example 1: Fix HTML Bug in writeToPasteboardPlainText

```swift
// PasteService.swift - writeToPasteboardPlainText()
// BEFORE (buggy):
private func writeToPasteboardPlainText(item: ClipboardItem) {
    switch item.type {
    case .url, .image, .file:
        writeToPasteboard(item: item)
        return
    case .text, .richText, .code, .color:
        break
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    if let text = item.textContent {
        pasteboard.setString(text, forType: .string)
    }
    if let html = item.htmlContent {           // <-- BUG: this preserves formatting
        pasteboard.setString(html, forType: .html)
    }

    logger.info("Wrote \(item.type.rawValue) content to pasteboard (plain text, RTF stripped)")
}

// AFTER (fixed):
private func writeToPasteboardPlainText(item: ClipboardItem) {
    switch item.type {
    case .url, .image, .file:
        writeToPasteboard(item: item)
        return
    case .text, .richText, .code, .color:
        break
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    // Write ONLY plain string -- no .rtf, no .html
    if let text = item.textContent {
        pasteboard.setString(text, forType: .string)
    }

    logger.info("Wrote \(item.type.rawValue) content to pasteboard (plain text, RTF and HTML stripped)")
}
```

### Example 2: Context Menu Addition in ClipboardCardView

```swift
// ClipboardCardView.swift - inside .contextMenu { ... }
// After the existing "Copy + Paste" button:

Button("Copy") {
    panelActions.copyOnlyItem?(item)
}
Button("Paste") {
    panelActions.pasteItem?(item)
}
Button("Copy + Paste") {
    panelActions.pasteItem?(item)
}
Button("Paste as Plain Text") {       // <-- NEW
    panelActions.pastePlainTextItem?(item)
}

Divider()
// ... rest of menu
```

### Example 3: Shift+Enter in FilteredCardListView

```swift
// FilteredCardListView.swift - replace existing .onKeyPress(.return)
.onKeyPress(.return) { keyPress in
    if let index = selectedIndex, index < filteredItems.count {
        if keyPress.modifiers.contains(.shift) {
            onPastePlainText(filteredItems[index])
        } else {
            onPaste(filteredItems[index])
        }
    }
    return .handled
}
```

Note: The existing `.onKeyPress(.return)` closure signature takes no arguments. The new version needs to accept `keyPress` to check modifiers. SwiftUI's `.onKeyPress` supports both `{ ... }` (no args, returns KeyPress.Result) and `{ keyPress in ... }` (with KeyPress argument). The Cmd+Shift+N handler at line 236 already uses the `keyPress in` form.

### Example 4: Shift+Double-Click in FilteredCardListView

```swift
// FilteredCardListView.swift - both horizontal AND vertical layout branches
.onTapGesture(count: 2) {
    if NSEvent.modifierFlags.contains(.shift) {
        onPastePlainText(item)
    } else {
        onPaste(item)
    }
}
```

### Example 5: HistoryGridView Context Menu Addition

```swift
// HistoryGridView.swift - in single-item context menu section (else branch)
Button("Copy") {
    selectedIDs = [item.persistentModelID]
    onBulkCopy()
}
Button("Paste") {
    selectedIDs = [item.persistentModelID]
    onBulkPaste()
}
Button("Paste as Plain Text") {         // <-- NEW
    onSinglePastePlainText(item)
}
Divider()
// ... rest of menu
```

Where `onSinglePastePlainText` is a new closure passed from HistoryBrowserView that calls `appState.pastePlainText(item)`.

## Exact Files to Modify

| File | Change | Lines Affected |
|------|--------|----------------|
| `Pastel/Services/PasteService.swift` | Remove HTML write from `writeToPasteboardPlainText()` | ~235-237 (delete 3 lines) |
| `Pastel/Views/Panel/ClipboardCardView.swift` | Add "Paste as Plain Text" context menu button | ~170 (add 3 lines) |
| `Pastel/Views/Panel/FilteredCardListView.swift` | Add Shift check to `.onKeyPress(.return)` | ~230-235 (modify 4 lines) |
| `Pastel/Views/Panel/FilteredCardListView.swift` | Add Shift check to both `.onTapGesture(count: 2)` | ~120, ~172 (modify 2+2 lines) |
| `Pastel/Views/Settings/HistoryGridView.swift` | Add "Paste as Plain Text" context menu button + new closure | ~117 (add 3 lines), init (add parameter) |
| `Pastel/Views/Settings/HistoryBrowserView.swift` | Wire `onSinglePastePlainText` closure to HistoryGridView | ~44-52 (add closure) |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Strip RTF only for plain text | Must strip BOTH RTF and HTML | Always (apps check HTML) | HTML on pasteboard defeats plain text intent |

**Key insight:** Many macOS apps (Google Docs, Apple Notes, Pages) check for `.html` pasteboard type BEFORE `.string`. If `.html` is present, they render it with formatting even when the intent was "plain text." The ONLY reliable way to force plain text is to put ONLY `.string` on the pasteboard.

## Open Questions

1. **HistoryGridView paste-as-plain-text beyond context menu**
   - What we know: HistoryGridView has no double-click handler and no Enter-to-paste. It is a settings window grid, not the sliding panel.
   - What's unclear: Whether Shift+double-click should eventually be added to HistoryGridView.
   - Recommendation: Skip for Phase 13. HistoryGridView is for browsing/managing, not quick pasting. Context menu is sufficient. If needed, it can be added later.

2. **Bulk paste as plain text in HistoryBrowserView**
   - What we know: HistoryBrowserView has bulk Copy, Paste, and Delete. There is no "Bulk Paste as Plain Text."
   - What's unclear: Whether users would want to bulk-paste as plain text.
   - Recommendation: Out of scope for Phase 13. The current requirements (PAST-20 through PAST-23) are all single-item operations.

## Sources

### Primary (HIGH confidence)
- Direct code reading: `PasteService.swift` -- confirmed HTML bug at line 235-237
- Direct code reading: `FilteredCardListView.swift` -- confirmed both layout branches and existing patterns
- Direct code reading: `ClipboardCardView.swift` -- confirmed context menu structure and PanelActions usage
- Direct code reading: `PanelContentView.swift` -- confirmed isShiftHeld tracking and onPastePlainText wiring
- Direct code reading: `PanelController.swift` -- confirmed PanelActions.pastePlainTextItem is wired
- Direct code reading: `AppState.swift` -- confirmed pastePlainText() method exists and delegates to PasteService
- Direct code reading: `HistoryGridView.swift` -- confirmed NSEvent.modifierFlags usage and context menu structure

### Secondary (MEDIUM confidence)
- NSPasteboard type priority behavior (apps prefer HTML over string) -- based on established macOS pasteboard documentation and developer experience

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new libraries, all existing APIs
- Architecture: HIGH -- all patterns already proven in codebase
- HTML bug fix: HIGH -- root cause identified by direct code reading
- UI entry points: HIGH -- exact code locations identified, patterns proven
- HistoryGridView integration: MEDIUM -- requires new closure wiring, slightly more design decision

**Research date:** 2026-02-09
**Valid until:** Indefinite (codebase-specific research, no external dependencies)
