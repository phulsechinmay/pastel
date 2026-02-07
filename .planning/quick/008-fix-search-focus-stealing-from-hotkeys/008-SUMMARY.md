---
phase: quick
plan: 008
subsystem: panel
tags: [FocusState, defaultFocus, type-to-search, keyboard-events, onKeyPress]

key-files:
  modified:
    - Pastel/Views/Panel/PanelController.swift
    - Pastel/Views/Panel/PanelContentView.swift
    - Pastel/Views/Panel/FilteredCardListView.swift

key-decisions:
  - "PanelFocus enum with .cardList and .search cases — defaultFocus to .cardList"
  - "PanelActions.showCount incremented on each show() — triggers focus reset via .onChange"
  - "Type-to-search: unmodified character presses redirect from card list to search field"
  - ".focused() applied from PanelContentView on SearchFieldView and FilteredCardListView wrappers"

duration: 2min
completed: 2026-02-07
---

# Quick Task 008: Fix Search Focus Stealing From Hotkeys

**Card list gets default focus on panel open — search activates on type**

## Root Cause

The search TextField automatically received focus when the panel opened as the key window. With the TextField focused, SwiftUI routed keyboard events to it instead of FilteredCardListView's `.onKeyPress` handlers. Cmd+1-9 quick paste and arrow key navigation required clicking the card area first.

## Fix

1. **Default focus to card list**: Added `@FocusState` with `PanelFocus` enum to PanelContentView. `.defaultFocus($panelFocus, .cardList)` ensures the card list area receives focus on initial load.

2. **Reset focus on panel reopen**: Added `showCount` property to `PanelActions` (incremented in `PanelController.show()`). PanelContentView observes it with `.onChange` and resets `panelFocus = .cardList`.

3. **Type-to-search**: Added `.onKeyPress(characters: .alphanumerics.union(.punctuationCharacters))` handler on FilteredCardListView that catches unmodified character presses and forwards them to the search field via `onTypeToSearch` callback. The callback sets `searchText` and moves focus to `.search`.

## Behavior

- Panel opens → card list focused, no cursor in search
- User presses Cmd+3 → quick paste fires immediately
- User presses arrow keys → card navigation works immediately
- User types "hello" → first character redirects to search field, search activates
- User clicks search field → search gets focus (manual focus still works)

## Commit

- `d00825f` — fix(quick-008): prevent search field from stealing focus on panel open

---
*Quick task 008 — Completed: 2026-02-07*
