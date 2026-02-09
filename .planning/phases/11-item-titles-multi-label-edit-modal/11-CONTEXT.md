# Phase 11 Context: Item Titles, Multi-Label Support, and Edit Modal

## Decisions

### Title Display

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Title location | Header row, right of source app icon | Title is the primary identifier — header placement gives prominence |
| Character limit | 50 characters | Always fits on one line; full title visible in edit modal |
| Visual style | Bold caption (`.caption2.bold()`) | Distinguishable from metadata without increasing card size |
| Time abbreviation | Use "mins/sec/secs" | Shorter format: "2 mins ago", "30 secs ago" instead of "2 minutes ago" |
| Header layout | `[App Icon] [Title] [Spacer] [Timestamp]` | Title replaces where label chip was; labels move to footer |
| No-title fallback | Show nothing (no title text) | Source app name and timestamp remain in header; metadata in footer unchanged |

### Multi-Label UX

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Label display location | Footer row, right of metadata text | Moves from header to footer since title now occupies header space |
| Label overflow | Show first 3 chips + "+N" badge | Keeps card height consistent; all labels visible in edit modal |
| Drag-drop behavior | Append (add label) | Intuitive — dragging a label adds it. Remove via context menu or edit modal |
| Chip bar filtering | Multi-select with OR logic | Tap multiple labels to show items matching ANY selected label |
| Label removal | Via context menu or edit modal | Right-click label submenu or edit modal label picker |

### Edit Modal

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Trigger | Right-click context menu "Edit" | Consistent with existing context menu pattern |
| Contents | Title text field + label multi-select | Core editing features for Phase 11 |
| Presentation | `.sheet()` modal | Proven to work (used for label creation); stays on screen |
| Save semantics | Live editing (no explicit save/cancel) | SwiftData @Bindable allows direct model binding; consistent with label settings editing |

### Data Model

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Title field | `var title: String?` (optional, nil default) | Per decision [06-01]: optional fields need no VersionedSchema |
| Label relationship | `var labels: [Label]` (many-to-many) | Replaces `var label: Label?`; SwiftData handles join table automatically |
| Migration | Existing `label` values migrate to `labels` array | One-time migration on first launch |
| Search | Include `title` in search predicate | Title is the primary discovery mechanism |

## Current Architecture (Key Files)

### Models
- `ClipboardItem.swift:52` — `var label: Label?` (to become `var labels: [Label]`)
- `Label.swift:16-17` — inverse relationship (needs update)

### Card Views
- `ClipboardCardView.swift:32-57` — header row with app icon, label chip, timestamp
- `ClipboardCardView.swift:92-106` — footer row with metadata + keycap badge
- `ClipboardCardView.swift:327-354` — `footerMetadataText` computed property

### Filtering & Search
- `FilteredCardListView.swift:37-69` — @Query predicate with single label filter
- `PanelContentView.swift:117` — `.id()` view recreation trigger
- `PanelContentView.swift:19-23` — `selectedLabel: Label?` state (needs multi-select)

### Label Assignment
- `ClipboardCardView.swift:166-184` — context menu label submenu (single assign)
- `FilteredCardListView.swift:117-129` — drag-drop label assignment (single assign)
- `ChipBarView.swift:12` — `@Binding var selectedLabel: Label?` (needs multi-select)

## Constraints

- SwiftData `#Predicate` does not support `.contains()` on relationship arrays for filtering — may need alternative approach (fetch all, filter in-memory, or use intermediate predicate)
- `@Query` predicate is set once in `init` — must continue using `.id()` pattern for view recreation
- Card width varies by panel edge position — label chips in footer must handle narrow panels gracefully
- Keycap badges (Cmd+1-9) share footer space with labels — layout must accommodate both
