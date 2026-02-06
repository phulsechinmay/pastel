# Phase 2: Sliding Panel - Context

**Gathered:** 2026-02-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Screen-edge sliding panel that displays clipboard history as visually rich cards. Users can browse their history, see previews of each content type (text, images, URLs, files), and scroll through items. No paste-back, no search, no labels, no settings — just visual browsing of captured clipboard content.

</domain>

<decisions>
## Implementation Decisions

### Panel Appearance
- Width: ~300px (narrow, compact)
- Default position: right screen edge
- Behavior: overlay (float on top of desktop content, don't push windows)
- Background: NSVisualEffectView dark material with vibrancy/blur
- Height: full screen height, edge-to-edge vertically
- Animation: fast & snappy (~0.2s slide in/out)
- Edge treatment: drop shadow on the left edge of the panel for depth
- Multi-display: panel appears on the screen where the mouse cursor is (active screen)

### Card Design
- Size: medium cards (~70-90px tall), good balance of preview and density
- Text cards: multi-line preview (2-3 lines of content visible)
- Image cards: thumbnail only (the 200px thumbnail fills most of the card, minimal text)
- URL cards: link/globe icon + URL text in accent color (visually distinct from plain text)
- File cards: standard approach — show file name/path
- Source app: icon only (small app icon, no text name — saves space)
- Timestamps: relative time (e.g., "2m ago") on each card
- Content type indicator: implicit from card design (no explicit badge needed)

### Panel Trigger & Dismiss
- Open: click menu bar icon toggles panel open/closed + temporary Cmd+Shift+V keyboard shortcut for early testing
- Close: click outside the panel OR press Escape key
- Menu bar icon is a toggle: click once to open, click again to close
- Status popover (from Phase 1) remains independent — opening the panel does NOT auto-close the popover

### Scrolling & Layout
- Layout: vertical list — cards stacked top to bottom
- Scroll direction: vertical (up/down)
- Order: newest item at the top, oldest at bottom
- Panel header: minimal — small "Pastel" title or drag handle, maximize card space
- Empty state: friendly message — "Copy something to get started" with a subtle icon/illustration
- Virtualization: Claude's discretion for handling large histories efficiently

### Claude's Discretion
- Exact card dimensions and spacing within the ~70-90px height range
- File card layout specifics
- Card selection/hover states (visual feedback)
- Exact accent color for URL text
- Empty state illustration/icon choice
- Scroll physics and momentum
- Virtualization approach for large history lists
- Whether cards have rounded corners, subtle separators, or other micro-styling
- Exact header design (title text vs icon)

</decisions>

<specifics>
## Specific Ideas

- PastePal-style panel as reference — narrow, dark, cards with previews
- The always-dark theme with vibrancy blur should feel native macOS
- Panel should feel instant to open (0.2s animation) — responsiveness matters
- Source app icon on cards helps identify "where did I copy this from" at a glance

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-sliding-panel*
*Context gathered: 2026-02-06*
