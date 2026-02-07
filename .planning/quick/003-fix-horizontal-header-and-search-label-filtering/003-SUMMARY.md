---
phase: quick
plan: 003
subsystem: panel-ui
tags: [swiftui, layout, swiftdata, predicate, filtering]
dependency-graph:
  requires: [05-02]
  provides: [horizontal-inline-header, correct-search-label-predicates]
  affects: []
tech-stack:
  added: []
  patterns:
    - "Nil guard + force-unwrap pattern for SwiftData #Predicate (avoids optional chaining bugs)"
    - "Conditional layout branching (isHorizontal) at top level of VStack content"
file-tracking:
  key-files:
    created: []
    modified:
      - Pastel/Views/Panel/PanelContentView.swift
      - Pastel/Views/Panel/FilteredCardListView.swift
decisions:
  - id: "quick-003-predicate-pattern"
    description: "Use != nil && force-unwrap instead of optional chaining ?? false in #Predicate"
    rationale: "SwiftData generates incorrect SQL for optional chaining with nil-coalescing inside #Predicate macro"
metrics:
  duration: "1min"
  completed: "2026-02-07"
---

# Quick Task 003: Fix Horizontal Header and Search/Label Filtering

**One-liner:** Inline header row for horizontal panel mode + nil-guard predicate pattern fixing SwiftData search and label filtering

## Objective

Fix two bugs: (1) horizontal panel mode stacking header, search, and chips vertically instead of inline, and (2) broken SwiftData predicates producing incorrect results for search text and label chip filtering.

## Changes Made

### Task 1: Inline header layout for horizontal panel mode
**Commit:** ff86892

Restructured `PanelContentView.body` to use conditional layout branching:

- **Horizontal mode (top/bottom):** Single `HStack` containing Pastel title, search field (max 200pt), chip bar, spacer, and gear button. No divider needed.
- **Vertical mode (left/right):** Preserved exact existing layout -- header HStack with title and gear, Divider, SearchFieldView, ChipBarView stacked vertically.

The `if isHorizontal` branch is at the top level of the VStack content, with `FilteredCardListView` always appearing after both branches.

### Task 2: Fix SwiftData predicates for search and label filtering
**Commit:** 9e6f47a

Rewrote all predicate construction in `FilteredCardListView.init` to avoid a SwiftData bug where `#Predicate` generates incorrect SQL for optional chaining with nil-coalescing (`?.method() ?? false`) and optional relationship traversal (`item.label?.persistentModelID`).

**Before (broken):**
```swift
item.textContent?.localizedStandardContains(search) ?? false
item.label?.persistentModelID == labelID
```

**After (correct):**
```swift
item.textContent != nil && item.textContent!.localizedStandardContains(search)
item.label != nil && item.label!.persistentModelID == labelID
```

Four predicate branches:
1. **No filter:** `{ _ in true }` -- returns all items
2. **Search-only:** Nil-guard + force-unwrap on textContent and sourceAppName
3. **Label-only:** Nil-guard + force-unwrap on label relationship
4. **Both:** Label guard AND (search text OR source app name) intersection

Force-unwraps are safe because each is preceded by a `!= nil` check in the same `&&` conjunction.

## Deviations from Plan

None -- plan executed exactly as written.

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Nil-guard + force-unwrap pattern in `#Predicate` | SwiftData's macro generates incorrect SQL for optional chaining with `?? false`; explicit nil check + `!` produces correct predicates |
| Top-level `if isHorizontal` branching | Cleanly separates two completely different layout structures without shared intermediate code |

## Verification

- Build succeeds with zero errors via `xcodebuild -scheme Pastel`
- Manual verification needed: switch to top/bottom panel edge to confirm inline header row
- Manual verification needed: search text filtering, label chip filtering, and combined filtering
