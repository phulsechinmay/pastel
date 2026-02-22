---
status: resolved
trigger: "Deletion is broken after Phase 29 implementation. Multiple related issues with item deletion in the clipboard manager panel."
created: 2026-02-21T00:00:00Z
updated: 2026-02-21T00:00:00Z
---

## Current Focus

hypothesis: Three separate issues: (1) In "All History" the ForEach uses `.id(index)` which means SwiftUI uses index-based identity - when an item is removed from filteredItems, indices shift but the identity stays the same, so SwiftUI doesn't see a removal; (2) In label filter views the same index-based identity causes the wrong visual item to disappear; (3) Cmd+Delete is not handled in the keyboard monitor at all.
test: Check ForEach identity strategy and keyboard monitor for Cmd+Delete
expecting: ForEach using `.id(index)` causes identity confusion when items are removed
next_action: Trace the ForEach identity and transition animation path

## Symptoms

expected:
1. Deleting an item should remove it from the list with slide-left animation in ALL views (All History and label filters)
2. The correct item (the one selected/right-clicked) should be removed
3. Cmd+Delete hotkey should trigger deletion of selected item

actual:
1. In "All History" section: deletion does nothing - no animation, item stays visible, nothing happens
2. In label filter views: deletion "works" but the WRONG item is visually deleted - the LAST item in the list disappears from view, even though the correct item is being deleted in the database
3. When navigating away from a label filter and back, the correct state shows (deleted item gone, last item back)
4. Cmd+Delete hotkey does not work at all for deletion

errors: No error messages reported - silent failures

reproduction:
1. Open panel, stay in "All History" view, right-click an item and choose Delete - nothing happens
2. Switch to a label filter, right-click an item and choose Delete - last item in list disappears instead of selected item
3. Try Cmd+Delete on a selected item - nothing happens

timeline: Started after Phase 29 implementation (Robust Item Deletion with Undo). Phase 29 introduced DeletionManager with in-memory soft-delete pattern.

## Eliminated

## Evidence

- timestamp: 2026-02-21T00:01:00Z
  checked: FilteredCardListView.swift cardView function line 316
  found: ".id(index)" applied to each card view, overriding ForEach's "id: \.element.id"
  implication: SwiftUI uses integer index as view identity. When items shift after deletion, the last index disappears, causing the last card to animate out instead of the deleted one.

- timestamp: 2026-02-21T00:02:00Z
  checked: FilteredCardListView.swift installKeyboardMonitor() lines 322-389
  found: No handler for key code 0x33 (Delete/Backspace). Only handles arrows, Return, Cmd+Z, Cmd+digits.
  implication: Cmd+Delete hotkey for deletion is completely missing from the keyboard monitor.

- timestamp: 2026-02-21T00:03:00Z
  checked: ScrollViewReader usage at lines 186-192 and 204-209
  found: proxy.scrollTo(newValue) targets an Int value, which matches .id(index) on the cards
  implication: Fixing .id(index) to use item identity requires updating scrollTo to use item identity too.

## Resolution

root_cause: |
  Three related bugs:
  1. `.id(index)` on card views (line 316) overrides ForEach's `id: \.element.id`, causing SwiftUI to use integer indices for view identity. When an item is deleted, indices shift and SwiftUI sees the LAST index as removed, so the last card gets the removal animation instead of the deleted card. In "All History" (many items), the last card is off-screen so nothing visible happens. In label views (few items), the last card visibly disappears.
  2. The animation context from `withAnimation` in ClipboardCardView.deleteItem() may not propagate to the @State update in onChange handler.
  3. Cmd+Delete hotkey is not handled in installKeyboardMonitor() - no case for key code 0x33.
fix: |
  All changes in FilteredCardListView.swift:
  1. Changed `.id(index)` to `.id(item.persistentModelID)` on card views (line 321) so SwiftUI uses the item's actual persistent identity for view diffing. Now when an item is removed from filteredItems, SwiftUI correctly identifies WHICH view was removed and applies the slide-left removal transition to that specific card.
  2. Updated both ScrollViewReader.scrollTo() calls (horizontal line 189, vertical line 207) to use `visibleItems[newValue].persistentModelID` instead of the raw index, with bounds checking. This keeps scroll-to-selection working with the new identity scheme.
  3. Added Cmd+Delete handler (key code 0x33) in installKeyboardMonitor() at line 378. When Cmd is held and a valid item is selected, it soft-deletes the item via DeletionManager with animation and decrements itemCount.
  4. Wrapped `filteredItems = computeFilteredItems(from: items)` in the onChange(of: softDeletedIDs) handler with `withAnimation(.easeOut(duration: 0.2))` to ensure the slide-left removal transition plays, since animation context from ClipboardCardView.deleteItem() may not propagate through the onChange handler.
verification: Build succeeded (xcodebuild -scheme "Pastel Sparkle" -configuration Debug-Sparkle build). Manual testing required for visual verification.
files_changed:
  - Pastel/Views/Panel/FilteredCardListView.swift
