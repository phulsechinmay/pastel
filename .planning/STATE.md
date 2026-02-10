# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-09)

**Core value:** Clipboard history is always one hotkey away, with instant paste-back into any app.
**Current focus:** Milestone v1.3 -- Phase 16: Drag-and-Drop from Panel (COMPLETE)

## Current Position

Phase: 16 of 16 (Drag-and-Drop from Panel)
Plan: 02 of 02 complete
Status: Phase complete -- v1.3 milestone complete
Last activity: 2026-02-09 -- Completed quick task 016 (sandbox + URLSession metadata)

Progress: [████████████████████] 100% (v1.3 -- 4/4 phases complete)

## Previous Milestones

### v1.0 MVP
- 29/29 requirements delivered across 5 phases (13 plans)
- Total execution time: ~37 min
- 8 quick tasks completed post-v1.0

### v1.1 Rich Content & Enhanced Paste
- 15/15 requirements delivered across 5 phases (10 plans)
- 10 quick tasks completed during v1.1
- Features: code detection, color swatches, URL metadata, quick paste hotkeys, label emoji, drag-drop labels

### v1.2 Item Management
- Phases 11-12 complete (6 plans)
- Features: item titles, multi-label support, edit modal, history browser with grid view, multi-select, bulk operations

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Key decisions from v1.2 carrying forward:

- [11-01]: Two-property migration strategy -- keep deprecated label: Label? alongside new labels: [Label]
- [11-03]: In-memory label filtering (not #Predicate) because SwiftData .contains() crashes on to-many relationships
- [12-02]: PanelActions() injected as dummy environment for ClipboardCardView reuse outside panel
- [12-03]: resolvedItems @Binding passes filteredItems from HistoryGridView to parent for bulk operations

Key decisions from v1.3:

- [13-01]: Use onKeyPress(keys:) instead of onKeyPress(KeyEquivalent) when modifier detection is needed (latter has no KeyPress parameter)
- [13-01]: No bulk paste-as-plain-text in History browser multi-selection (out of scope for Phase 13)
- [14-01]: Ignore check in checkForChanges() not processPasteboardContent() -- filters ALL content types uniformly including images
- [14-01]: Fresh UserDefaults read each poll cycle for ignore list -- no caching, matches RetentionService pattern
- [14-01]: ignoredAppBundleIDs UserDefaults key stores [String] array of bundle IDs
- [14-02]: Three separate UserDefaults keys (IDs, dates, names) for ignore list persistence -- simpler than Codable, and ignoredAppBundleIDs already consumed by ClipboardMonitor
- [15-01]: Separate Codable transfer structs (ExportedItem, ExportedLabel) decoupled from SwiftData @Model -- avoids fragile persistence state serialization
- [15-01]: Pre-check fetchCount deduplication instead of relying on SwiftData @Attribute(.unique) upsert
- [15-01]: Exclude concealed and image items from export (security-first, images not portable)
- [15-02]: lastExportCount property on ImportExportService for post-export alert count display
- [15-02]: User-selected file read/write entitlement needed for NSSavePanel/NSOpenPanel file access
- [16-01]: Use .onDrag() instead of .draggable() to avoid type collision with existing .dropDestination(for: String.self) for label assignment
- [16-01]: DragItemProviderService as pure Foundation/UTI enum -- no SwiftUI/SwiftData imports
- [16-01]: RTF registered before plain text fallback for richText items
- [16-02]: Callback chain pattern (not NotificationCenter) for drag state propagation through PanelActions bridge
- [16-02]: One-shot global leftMouseUp monitor for drag end detection, self-removes after firing
- [16-02]: 500ms delay before isDragging reset matches existing paste-back timing
- [16-02]: skipNextChange (not full monitor pause) for self-capture prevention during drag

### Research Flags (v1.3)

- ~~Phase 13: PAST-23 (fix HTML bug) must be first task before adding UI~~ DONE
- ~~Phase 16: MANDATORY feasibility test of .draggable() on NSPanel before building feature~~ DONE -- Research confirmed feasibility: existing .draggable() on label chips proves SwiftUI drag works from NSPanel. Using .onDrag() instead to avoid type collision.
- ~~Phase 15: One-at-a-time insert for import (SwiftData @Attribute(.unique) constraint)~~ DONE (pre-check fetchCount before each insert)

### Pending Todos

- Final manual testing of full application before distribution

### Blockers/Concerns

None currently.

## Session Continuity

Last session: 2026-02-09
Stopped at: Completed quick task 016 (sandbox + URLSession metadata)
Resume file: None
