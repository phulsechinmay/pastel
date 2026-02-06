# Phase 4: Organization — Context & Decisions

**Created:** 2026-02-06
**Requirements:** ORGN-01, ORGN-02, ORGN-03, ORGN-04, ORGN-05, ORGN-06

## Goal

Users can search, label, filter, and manage their clipboard history so it remains useful as it grows.

## Decisions

### 1. Search Behavior

| Decision | Choice |
|----------|--------|
| Search field placement | Below header, above chip bar. Persistent, always visible. |
| Search scope | `textContent`, `sourceAppName`, and file paths (from `textContent` for file type items) |
| Filter mode | Real-time with ~200ms debounce |
| Empty results | Show empty state message ("No matching items") |

**Layout order:** Header → Search → Chip Bar → Cards

### 2. Label System

| Decision | Choice |
|----------|--------|
| Label creation | Inline '+' chip in chip bar (quick create) + separate management view in Settings |
| Label colors | Preset palette of 6-8 colors (red, orange, yellow, green, blue, purple, pink, gray) |
| Label assignment | Right-click context menu on card → label submenu with radio-style selection |
| Multiple labels per item | No — one label per item max |
| Label deletion | Via label management view in Settings |

**Data model implications:**
- New `Label` SwiftData model: `name: String`, `colorName: String`, `sortOrder: Int`
- `ClipboardItem` gets optional relationship: `var label: Label?`
- One-to-many: one Label → many ClipboardItems

### 3. Chip Bar & Filtering

| Decision | Choice |
|----------|--------|
| Chip bar position | Below search field, above card list |
| Filter + search interaction | Combined (AND): chip filter and search text stack |
| 'All' chip | No — deselect the active chip to show all items |
| Chip selection | Single-select (matches one-label-per-item model) |

**Behavior:**
- Tapping a chip selects it (highlights), filtering cards to that label only
- Tapping the active chip deselects it, showing all items
- Search text filters within the chip-filtered results (AND logic)
- Chip bar only shows labels that have been created (no chips if no labels exist)

### 4. Deletion UX

| Decision | Choice |
|----------|--------|
| Individual delete | Right-click context menu → "Delete" |
| Delete confirmation | No confirmation for individual items |
| Clear all history | In Settings menu, red-colored button to indicate danger, with confirmation dialog |
| Image cleanup on delete | Immediate — delete image + thumbnail files from disk when item is deleted |

**Context menu structure** (right-click on card):
1. Label → [submenu of labels]
2. ---
3. Delete

### 5. Panel Layout (Updated)

```
┌──────────────────────┐
│  Pastel          [≡] │  ← Header
├──────────────────────┤
│  🔍 Search...        │  ← Search field (persistent)
├──────────────────────┤
│  [Work] [Personal].. │  ← Chip bar (only if labels exist)
├──────────────────────┤
│  ┌──────────────────┐│
│  │ Card 1           ││  ← Scrollable card list
│  └──────────────────┘│
│  ┌──────────────────┐│
│  │ Card 2           ││
│  └──────────────────┘│
│         ...          │
└──────────────────────┘
```

## Architecture Notes

- **SwiftData predicates** for search: `#Predicate<ClipboardItem>` combining text search + label filter
- **NSMenu** for right-click context menus (standard macOS, works well with NSPanel)
- **Debounced search**: `@State` text field with `.task(id:)` or Combine `debounce`
- **Image deletion**: `ImageStorageService` already handles file paths — add `deleteImage(for:)` method
- **Label management**: Settings window (Phase 5 adds full settings, but label management view can be standalone or embedded early)

## Open Questions (Resolved)

All gray areas have been resolved through discussion. No open questions remain.
