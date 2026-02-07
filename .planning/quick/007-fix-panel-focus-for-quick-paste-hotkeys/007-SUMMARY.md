---
phase: quick
plan: 007
subsystem: panel
tags: [NSPanel, makeKey, focus, keyboard-events, onKeyPress]

key-files:
  modified:
    - Pastel/Views/Panel/PanelController.swift

key-decisions:
  - "panel.makeKey() after orderFrontRegardless() — nonactivating panel becomes key window without stealing app activation"

duration: 1min
completed: 2026-02-07
---

# Quick Task 007: Fix Panel Focus for Quick Paste Hotkeys

**Panel now receives keyboard events immediately on open — no click required**

## Root Cause

`PanelController.show()` called `panel.orderFrontRegardless()` which brings the panel to front visually but does NOT make it the key window. SwiftUI `.onKeyPress` handlers route through the key window's view hierarchy, so without key window status, Cmd+1-9 events went to the frontmost app (e.g., Safari's tab switching) instead of the panel's quick paste handlers.

## Fix

Added `panel.makeKey()` after `panel.orderFrontRegardless()` in `PanelController.show()`. The `.nonactivatingPanel` style mask ensures the panel becomes key window without stealing app activation — exactly the behavior needed for a clipboard manager overlay.

## Impact

- Cmd+1-9 quick paste hotkeys now work immediately when panel opens
- Arrow key navigation and Enter paste also work without clicking first
- No behavior change for panel dismiss (Escape, click-outside still work)

## Commit

- `ecf5481` — fix(quick-007): make panel key window on show for immediate hotkey response

---
*Quick task 007 — Completed: 2026-02-07*
