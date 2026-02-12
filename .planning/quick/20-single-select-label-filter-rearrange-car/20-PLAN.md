---
phase: quick-020
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/LabelChipView.swift
  - Pastel/Views/Panel/ChipBarView.swift
  - Pastel/Views/Panel/ClipboardCardView.swift
  - Pastel/Views/Panel/PanelContentView.swift
  - Pastel/Views/Settings/HistoryBrowserView.swift
autonomous: true
must_haves:
  truths:
    - "Clicking a label filter chip selects ONLY that label (deselects all others)"
    - "Clicking the already-active label chip deselects it (shows all items)"
    - "Cmd+Left/Right cycles through label filters in order"
    - "Item labels appear in the top row next to the app icon, not in the footer"
    - "Item title appears at the bottom of the card in bold text"
    - "All label chips (filter bar and card) show a colored dot instead of colored background"
  artifacts:
    - path: "Pastel/Views/Panel/LabelChipView.swift"
      provides: "Color dot + neutral background label chip"
    - path: "Pastel/Views/Panel/ChipBarView.swift"
      provides: "Single-select toggle logic + Cmd+arrow label cycling"
    - path: "Pastel/Views/Panel/ClipboardCardView.swift"
      provides: "Rearranged card layout with labels on top, title on bottom"
  key_links:
    - from: "ChipBarView"
      to: "PanelContentView/HistoryBrowserView"
      via: "@Binding selectedLabelIDs"
      pattern: "selectedLabelIDs"
---

<objective>
Single-select label filter, rearrange card layout, and add color dots to label chips.

Purpose: Simplify label filtering UX (single-select instead of multi), improve card visual hierarchy (labels at top, title at bottom), and make label chips visually cleaner with color dots instead of colored backgrounds.
Output: Updated ChipBarView, LabelChipView, ClipboardCardView, PanelContentView, HistoryBrowserView
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Panel/LabelChipView.swift
@Pastel/Views/Panel/ChipBarView.swift
@Pastel/Views/Panel/ClipboardCardView.swift
@Pastel/Views/Panel/PanelContentView.swift
@Pastel/Views/Settings/HistoryBrowserView.swift
@Pastel/Views/Panel/FilteredCardListView.swift
@Pastel/Models/Label.swift
@Pastel/Models/LabelColor.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Label chip visual redesign -- color dots with neutral background</name>
  <files>Pastel/Views/Panel/LabelChipView.swift</files>
  <action>
Redesign `LabelChipView` to use a color dot instead of colored background:

1. **Color dot**: Add a small filled `Circle()` (6pt for regular, 5pt for compact) as the FIRST element in the HStack, BEFORE the emoji (if any) and name text. The circle color comes from `LabelColor(rawValue: label.colorName)?.color ?? .gray`. For emoji labels, still show the dot (color from label.colorName) followed by the emoji then the name.

2. **Neutral background**: Change the `background` computed property to ALWAYS use neutral styling:
   - Active state: `Color.accentColor.opacity(0.3)` (same for all labels regardless of emoji)
   - Inactive state: `Color.white.opacity(0.1)` (same for all labels regardless of emoji)
   - If `tintOverride` is set (color cards): use `tint.opacity(0.15)` as before

3. **Active border**: Keep the existing `Capsule().strokeBorder` for active state (accent stroke).

4. **Color dot in color card context**: When `tintOverride` is set (for color cards), the dot circle should use `tintOverride` color instead of the label color, to maintain contrast.

The result: every label chip looks the same neutral capsule with a small colored dot on the left, making labels scannable at a glance.
  </action>
  <verify>Build succeeds (`xcodebuild build -scheme Pastel -destination 'platform=macOS'`). LabelChipView renders with neutral background and colored dot for both regular and compact sizes.</verify>
  <done>All label chips (filter bar, card footer, edit modal) show colored dot + neutral background instead of fully colored background.</done>
</task>

<task type="auto">
  <name>Task 2: Single-select label filtering with Cmd+Left/Right cycling</name>
  <files>Pastel/Views/Panel/ChipBarView.swift, Pastel/Views/Panel/PanelContentView.swift, Pastel/Views/Settings/HistoryBrowserView.swift</files>
  <action>
**ChipBarView -- single-select toggle:**

Change the `onTapGesture` in `labelChip(for:)` from multi-select toggle to single-select:
- If tapped label is already active (`isActive == true`): clear `selectedLabelIDs` entirely (deselect)
- If tapped label is NOT active: replace `selectedLabelIDs` with ONLY this label's ID (`selectedLabelIDs = [label.persistentModelID]`)
- Remove the old `insert`/`remove` logic

This keeps `selectedLabelIDs` as `Set<PersistentIdentifier>` (0 or 1 elements), so FilteredCardListView and HistoryGridView need zero changes -- they already handle empty set = all items, non-empty set = filter.

**ChipBarView -- add Cmd+Left/Right label cycling:**

Add a new public method or accept a callback for label cycling. Actually, since ChipBarView doesn't have focus, the keyboard shortcuts should be added to the PARENT views that have focus.

**PanelContentView -- add Cmd+Left/Right handlers:**

Add two `.onKeyPress` modifiers on the outer `VStack` (or on the FilteredCardListView section):

```swift
.onKeyPress(.leftArrow) { keyPress in
    guard keyPress.modifiers.contains(.command) else { return .ignored }
    cycleLabelFilter(direction: -1)
    return .handled
}
.onKeyPress(.rightArrow) { keyPress in
    guard keyPress.modifiers.contains(.command) else { return .ignored }
    cycleLabelFilter(direction: 1)
    return .handled
}
```

Add a `cycleLabelFilter(direction:)` private method:
- Build ordered label IDs from `labels` array (already sorted by sortOrder via @Query)
- If `selectedLabelIDs` is empty: select first label (direction +1) or last label (direction -1)
- If one label is selected: find its index in the ordered list, move by direction. If out of bounds, wrap around OR deselect (wrapping is better UX)
- Set `selectedLabelIDs = [newLabelID]`

IMPORTANT: These Cmd+Left/Right handlers must NOT conflict with FilteredCardListView's existing `.leftArrow`/`.rightArrow` handlers for horizontal panel mode. Those handlers do NOT check for Cmd modifier, so they will fire on plain left/right. The Cmd+Left/Right handlers should be placed on the parent VStack in PanelContentView, ABOVE the FilteredCardListView (SwiftUI processes key events from focused view outward -- FilteredCardListView will get plain arrows, and if it returns `.ignored` for Cmd+arrows, the parent gets them). Actually, FilteredCardListView's horizontal left/right handlers don't check modifiers and return `.handled` unconditionally when `isHorizontal`. To avoid conflict:

- Add the Cmd+Left/Right handlers to the FilteredCardListView itself (inside the existing `.onKeyPress(.leftArrow)` and `.onKeyPress(.rightArrow)` blocks), checking for `.command` modifier FIRST, and calling a new `onCycleLabelFilter` callback. If Cmd is held, handle label cycling and return `.handled`. Otherwise fall through to existing horizontal navigation logic.

- Add `onCycleLabelFilter: ((Int) -> Void)?` parameter to FilteredCardListView's init.

- In PanelContentView, pass `onCycleLabelFilter: { direction in cycleLabelFilter(direction: direction) }` and implement `cycleLabelFilter(direction:)` there.

**HistoryBrowserView -- no keyboard cycling needed** (History browser uses mouse-centric interaction, but the single-select change in ChipBarView applies automatically since it shares the same component).
  </action>
  <verify>Build succeeds. Tapping a label in chip bar selects only that label. Tapping same label deselects. Cmd+Left/Right cycles through labels in panel.</verify>
  <done>Label filtering is single-select. Cmd+Left/Right iterates through label filters in panel. History browser chip bar also single-selects.</done>
</task>

<task type="auto">
  <name>Task 3: Rearrange card layout -- labels to top row, title to bottom</name>
  <files>Pastel/Views/Panel/ClipboardCardView.swift</files>
  <action>
Rearrange ClipboardCardView's VStack layout:

**Current layout:**
1. Header: app icon + title + timestamp
2. Content preview
3. Footer: metadata (chars/dimensions) + label chips + keycap badge

**New layout:**
1. Header: app icon + label chips (max 3) + overflow badge + Spacer + timestamp
2. Content preview
3. Footer: title (bold, left-aligned) + Spacer + keycap badge

Specific changes:

**Header row** (line ~64 HStack):
- Keep `sourceAppIcon` as first element
- MOVE label chips from footer to header, right after app icon. Use the same `let visibleLabels = Array(item.labels.prefix(3))` pattern with `ForEach` and `LabelChipView(label:size:.compact)`. Include the `+N` overflow badge.
- Keep `Spacer()` and timestamp on the right

**Content preview**: No changes.

**Footer row** -- replace the current footer with:
- Show this row ONLY if `item.title` is non-nil/non-empty OR `badgePosition` is non-nil
- Left side: `Text(title)` with `.font(.caption.bold())`, `.lineLimit(1)`, foreground color respecting `isColorCard`
- `Spacer()`
- Right side: `KeycapBadge` (if `badgePosition` is non-nil)
- Remove the old `footerMetadataText` from the footer entirely (chars count, dimensions, host -- these are removed per the task description "replacing the chars/image size footer")

**Remove from header**: The title that currently appears in the header row (lines 68-73) must be removed from the header since it's moving to the footer.

**Clean up**: The `footerMetadataText` computed property and `imageDimensions` state can be removed entirely since they're no longer displayed. Also remove the `.task` block that loads `imageDimensions` (keep the `dominantColor` loading part).

For color cards: use `colorCardTextColor` for label chip `tintOverride` on the header label chips (same as current footer behavior).
  </action>
  <verify>Build succeeds. Cards show app icon + labels on top row, content in middle, title (bold) on bottom row. No chars/dimensions metadata shown.</verify>
  <done>Card layout rearranged: labels moved to top next to app icon, title moved to bottom in bold, metadata footer removed.</done>
</task>

</tasks>

<verification>
1. `xcodebuild build -scheme Pastel -destination 'platform=macOS'` succeeds with no errors
2. Label chips everywhere show colored dot + neutral background
3. Chip bar single-selects (clicking one deselects others)
4. Cmd+Left/Right cycles through label filters in the panel
5. Cards show labels in top row, title in bottom row
</verification>

<success_criteria>
- All label chips use color dot + neutral capsule background (no fully colored chips)
- Label filter is single-select in both panel and history browser
- Cmd+Left/Right keyboard shortcuts cycle through labels in panel
- Card layout: header = icon + labels + timestamp, footer = title (bold) + keycap badge
- Build succeeds with no warnings related to these changes
</success_criteria>

<output>
After completion, create `.planning/quick/20-single-select-label-filter-rearrange-car/20-SUMMARY.md`
</output>
