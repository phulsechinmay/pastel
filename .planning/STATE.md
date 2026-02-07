# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-07)

**Core value:** Clipboard history is always one hotkey away, with instant paste-back into any app.
**Current focus:** Milestone v1.1 -- Phase 8 remaining (08-02)

## Current Position

Phase: 10 of 10 (Drag-Drop Label Assignment) -- Complete
Remaining: Phase 8 plan 2 of 2 (08-02 URLCardView enhancement)
Status: Phase 10 complete, Phase 8 has 1 plan remaining
Last activity: 2026-02-07 -- Completed 10-01-PLAN.md (Drag-drop label assignment)

Progress: [######################] 100% (22/22 plans across all milestones)

## Previous Milestone: v1.0

- 29/29 requirements delivered across 5 phases (13 plans)
- Total execution time: ~37 min
- 8 quick tasks completed post-v1.0

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap v1.1]: 4-phase structure (6-9) derived from 15 requirements across 5 categories
- [Roadmap v1.1]: Schema migration in Phase 6 first -- all subsequent phases depend on new model fields
- [Roadmap v1.1]: Cmd+Shift+1-9 (not Cmd+1-9) for quick paste to avoid browser/editor hotkey conflicts
- [Roadmap v1.1]: All new SwiftData fields optional with nil defaults for lightweight migration
- [06-01]: All new ClipboardItem fields Optional with nil defaults -- no VersionedSchema needed
- [06-01]: ContentType .code/.color routed to TextCardView as placeholder until Phase 7
- [06-01]: LabelColor new cases appended after existing 8 for raw value stability
- [06-02]: Emoji-or-dot pattern: `if let emoji = label.emoji, !emoji.isEmpty` across all renderers
- [quick-004]: Unified palette popover replaces separate color Menu + emoji TextField + smiley Button in LabelRow
- [quick-005]: Color dot Circle dropped from context menu labels -- macOS NSMenu unreliable with shapes
- [07-01]: Swift Regex wholeMatch for all color patterns -- prevents false positives from embedded values
- [07-01]: Code heuristic score >= 3 threshold (out of max 7) balances sensitivity vs false positives
- [07-01]: Detection order: color first, code second (prevents rgb() from triggering code heuristic)
- [07-02]: HighlightSwift 1.1.0 via SPM -- builds cleanly with Swift 6
- [07-02]: Keyword-based language hints correct highlight.js misdetections for Swift/Python/JS/Rust/Go
- [07-02]: .dark(.atomOne) theme for syntax highlighting matches always-dark panel
- [07-03]: Full-card color background instead of small swatch -- more visually striking
- [07-03]: WCAG luminance check for header text contrast on color cards
- [08-01]: LPMetadataProvider created locally per fetch (not Sendable) -- matches Apple recommendation
- [08-01]: loadImageData @MainActor for Swift 6 strict concurrency with NSItemProvider
- [08-01]: UserDefaults "fetchURLMetadata" defaults to true via nil coalescing
- [quick-006]: Center-crop banner via direct Image + scaledToFill + aspectRatio(.fill) + clipped -- no GeometryReader needed
- [quick-007]: panel.makeKey() after orderFrontRegardless() gives panel key window status for immediate .onKeyPress
- [quick-008]: @FocusState defaultFocus to cardList prevents search TextField from stealing focus; type-to-search redirects unmodified characters
- [09-01]: Cmd+1-9 for normal paste, Cmd+Shift+1-9 for plain text (Cmd+N is more natural primary action)
- [09-01]: writeToPasteboardPlainText omits .rtf only, keeps .string and .html
- [09-01]: Non-text types (url, image, file) delegate to normal writeToPasteboard -- no RTF to strip
- [09-01]: quickPasteEnabled defaults to true (opt-out, not opt-in)
- [09-02]: Badge visibility controlled by parent (FilteredCardListView) via nil badgePosition, not @AppStorage in child
- [09-02]: 1-based badge numbers (1-9) matching Cmd+1-9 hotkeys, converted from 0-based array index
- [10-01]: Button replaced with onTapGesture + .draggable in labelChip to avoid macOS gesture conflict
- [10-01]: PersistentIdentifier serialized as JSON string for drag payload via Codable
- [10-01]: isDropTarget highest priority in cardBorderColor (above isSelected and isColorCard)
- [10-01]: Drop target background uses accentColor at 0.15 opacity for subtle highlight

### Roadmap Evolution

- Phase 10 added: Drag-and-drop label assignment from chip bar to clipboard items

### Pending Todos

- Final manual testing of full application before distribution
- Phase 8 plan 08-02 (URLCardView enhancement) still pending

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 004 | Unified color/emoji label menu in settings | 2026-02-07 | a4687e2 | [004-unified-color-emoji-label-menu](./quick/004-unified-color-emoji-label-menu/) |
| 005 | Card label chips and emoji menu fix | 2026-02-07 | 41861c0 | [005-card-label-chips-and-emoji-menu-fix](./quick/005-card-label-chips-and-emoji-menu-fix/) |
| 006 | Fix URL card banner centering | 2026-02-07 | 95dfa7c | [006-fix-url-card-banner-centering](./quick/006-fix-url-card-banner-centering/) |
| 007 | Fix panel focus for quick paste hotkeys | 2026-02-07 | ecf5481 | [007-fix-panel-focus-for-quick-paste-hotkeys](./quick/007-fix-panel-focus-for-quick-paste-hotkeys/) |
| 008 | Fix search focus stealing from hotkeys | 2026-02-07 | d00825f | [008-fix-search-focus-stealing-from-hotkeys](./quick/008-fix-search-focus-stealing-from-hotkeys/) |

### Blockers/Concerns

None currently.

## Session Continuity

Last session: 2026-02-07
Stopped at: Completed 10-01-PLAN.md (Drag-drop label assignment). Phase 8 plan 08-02 still pending.
Resume file: None
