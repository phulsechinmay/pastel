# Phase 29: Robust Item Deletion with Undo, Scroll Preservation, and Panel Refresh - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Make item deletion in the panel reliable and user-friendly. Covers undo support (Cmd+Z), delete animations, scroll position handling during and after deletion, and ensuring the panel card list refreshes correctly. Does not add new deletion entry points or new capabilities — focuses on making existing delete actions robust.

</domain>

<decisions>
## Implementation Decisions

### Undo behavior
- Undo triggered via **Cmd+Z** only — no toast/snackbar UI
- **Soft-delete**: item is hidden immediately but kept in DB; permanently deleted when panel closes or a new action occurs
- **Single-level undo** — only the most recent deletion can be undone
- Restored item appears at **top of list**, not original position

### Deletion feedback
- **No confirmation** for single item deletion — undo via Cmd+Z is the safety net
- **Keep confirmation dialog** for bulk deletion (2+ items) with count
- Delete animation: **slide left + collapse gap** (item slides off to the left, then gap closes)
- Animation duration: **quick (~0.2s)** — fast and snappy
- Play **macOS system trash sound** on deletion
- Delete via **context menu + keyboard only** — no swipe-to-delete gesture
- After deleting selected item, selection moves to **next item (below)**

### Panel refresh
- No item count displayed — no count update needed
- When last item in a filtered view is deleted: **show empty state** (stay on current filter)
- Settings history tab: **refresh on focus** — not real-time sync with panel deletions
- Image cleanup: **deferred** — mark for background cleanup, keep deletion fast
- **Cancel image cleanup on undo** — if user undoes before sweep runs, images are preserved

### Scroll preservation
- After deletion: **anchor to scroll offset** — maintain exact pixel position, items shift up to fill gap
- Deleting last visible item at bottom: **scroll up to fill** — no empty whitespace at bottom
- Rapid successive deletions: **Claude's discretion** on settling behavior
- Panel open/close: **remember scroll position** across dismiss/reopen cycles

### Claude's Discretion
- Rapid deletion settling behavior (stable per-delete vs batch settle)
- Soft-delete implementation details (DB flag vs in-memory tracking)
- Exact slide-left animation curve and gap collapse timing
- Background image cleanup sweep interval

</decisions>

<specifics>
## Specific Ideas

- System trash sound — user specifically wants the macOS "move to trash" sound effect
- Slide-left animation mirrors the direction of "swiping away" even though there's no swipe gesture
- Remember scroll position on panel reopen — panel should feel like it picks up where you left off

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 29-robust-item-deletion-with-undo-scroll-preservation-and-panel-refresh*
*Context gathered: 2026-02-21*
