# Phase 28: Fix Panel Item Activation - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix broken item activation for Enter key and Cmd+1-9/Cmd+Shift+1-9 hotkeys. Unify keyboard activation into the proven NSEvent local monitor pattern (already used for arrow keys). Double-click and drag-and-drop work correctly and are not touched.

</domain>

<decisions>
## Implementation Decisions

### Root Cause
- SwiftUI `.onKeyPress` handlers in FilteredCardListView are wired correctly but never fire
- The `.focusable()` on the Group wrapper isn't reliably receiving keyboard focus
- Arrow key navigation works because it uses NSEvent local monitor (not `.onKeyPress`)
- Escape works because PanelController uses NSEvent local monitor
- Double-click works because `.onTapGesture` doesn't depend on SwiftUI focus
- Drag works because `.onDrag` doesn't depend on SwiftUI focus

### Keyboard Event Strategy
- **Use NSEvent local monitor** for Enter, Cmd+1-9, and Cmd+Shift+1-9 activation
- Extend the existing `installArrowKeyMonitor()` in FilteredCardListView — it already has access to `visibleItems`, `selectedIndex`, `quickPasteEnabled`, and the `onPaste`/`onPastePlainText` callbacks
- **Remove the broken `.onKeyPress` handlers** for Return, `.decimalDigits`, and shifted digits (`!@#$%^&*(`)
- Keep the type-to-search `.onKeyPress` handler (`.alphanumerics.union(.punctuationCharacters)`) — it's not broken and is a different category (text forwarding, not activation)

### Activation Architecture
- Keep the existing callback chain: `onPaste(item)` → `panelActions.pasteItem?()` → `PanelController.onPasteItem` → `AppState.paste()` → `PasteService.paste()`
- Do NOT extract a new `activateItem()` abstraction — the callback chain is already the unified path
- `PasteService.paste()` and `PasteService.pastePlainText()` remain the single point of truth for activation behavior
- Drag-and-drop stays on its separate path (NSItemProvider) — fundamentally different mechanism

### Post-Activation Behavior
- All activation methods (Enter, Cmd+1-9, double-click) respect the existing `PasteBehavior` setting:
  - `.paste` — write to pasteboard + simulate Cmd+V
  - `.copy` — write to pasteboard only
  - `.copyAndPaste` — write to pasteboard + simulate Cmd+V
- No method-specific behavior differences — user's setting applies uniformly
- Panel dismiss behavior follows existing logic (PasteService handles this)

### Scope Boundaries
- Four activation methods: double-click, drag-and-drop, Enter key, Cmd+1-9 hotkeys
- Single-click remains selection-only (no change)
- Right-click remains context menu (no change)
- Arrow key navigation stays as-is (already working via NSEvent)

### Claude's Discretion
- Exact refactoring of `installArrowKeyMonitor()` (rename to `installKeyboardMonitor()` or similar)
- Whether to use keyCode constants or raw values for Enter/digit keys
- Any necessary cleanup of unused focus management code after removing `.onKeyPress`

</decisions>

<specifics>
## Specific Ideas

- Arrow keys already prove the NSEvent pattern works in this codebase — extend that proven approach
- The shifted digit map (`!@#$%^&*(` → 1-9) for Cmd+Shift+N must be preserved in the NSEvent handler
- Existing `quickPasteEnabled` (`@AppStorage`) gating must be respected in the NSEvent path

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 28-fix-panel-item-activation-unify-hotkey-keyboard-enter-click-and-drag-activation-into-a-durable-shared-method*
*Context gathered: 2026-02-21*
