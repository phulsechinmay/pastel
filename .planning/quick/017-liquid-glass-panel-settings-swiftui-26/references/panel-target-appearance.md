# Phase 17 — Target Panel Appearance Reference

Screenshot provided 2026-02-10 showing the correct/desired panel UI.

## Panel Layout (Left to Right, Top to Bottom)

### Header
- **Pastel logo** (small icon) at top-left with "Pastel" text
- **Search bar** with magnifying glass icon and "Search..." placeholder, rounded pill shape
- **Label tabs** in a horizontal scrollable row:
  - ❤️ Favs
  - 🔧 Commands
  - Banff Trip (orange/warm background)
  - 🎨 Design Ideas
  - 🛒 Shopping List (green background)
  - 🚀 Development
  - 📝 Prompts
  - **+** button at end
- **Gear icon** (⚙️) at far right of header for settings

### Content Area — Card Grid
- Cards arranged in a horizontal row (grid layout)
- Each card has:
  - **App icon** (small, top-left of card) — shows source app (e.g., VS Code icon)
  - **Timestamp** (top-right) — e.g., "1 min ago", "8 mins ago", "12 mins ago", "27 mins ago"
  - **Content preview** — text snippet or image thumbnail
  - **Footer** — shows metadata:
    - Text items: character count (e.g., "578 chars", "477 chars", "67 chars", "129 chars", "82 chars")
    - Image items: dimensions (e.g., "2940 x 676")
    - Right side: keyboard shortcut badge (e.g., ⌘⇧1, ⌘⇧2, ⌘⇧3, ⌘⇧4, ⌘⇧5)

### Visual Style
- **Dark theme** throughout — dark card backgrounds against slightly lighter panel background
- Cards have subtle rounded corners and slight elevation/border
- Text is light/white on dark backgrounds
- Image cards show a thumbnail preview of the image content
- The panel appears to be a wide horizontal strip (screen-edge sliding panel)
- Overall aesthetic: clean, minimal, macOS-native dark mode feel
- **No visible Liquid Glass effect** in this screenshot — cards and background are opaque dark

### Specific Card Contents (for verification)
1. Card 1: VS Code icon, text about "/gsd:add-phase" discussion, 578 chars, ⌘⇧1
2. Card 2: VS Code icon, same/similar text, 477 chars, ⌘⇧2
3. Card 3: Image card showing a screenshot (2940x676), ⌘⇧3
4. Card 4: VS Code icon, "It did work but i did something to dismiss it. Try the hotkey again", 67 chars, ⌘⇧4
5. Card 5: VS Code icon, text about updating app to open panel on startup, 129 chars, ⌘⇧5
6. Card 6 (partially visible): VS Code icon, text about "nonactivating" working, 82 chars, ⌘⇧5(?)
