# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-07)

**Core value:** Clipboard history is always one hotkey away, with instant paste-back into any app.
**Current focus:** Milestone v1.1 -- Phase 7: Code and Color Detection

## Current Position

Phase: 7 of 9 (Code and Color Detection)
Plan: 1 of 3 in current phase
Status: In progress
Last activity: 2026-02-07 -- Completed 07-01-PLAN.md (Detection Services)

Progress: [#############░░░░░░░] 73% (16/22 plans across all milestones)

## Previous Milestone: v1.0

- 29/29 requirements delivered across 5 phases (13 plans)
- Total execution time: ~37 min
- 5 quick tasks completed post-v1.0

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap v1.1]: 4-phase structure (6-9) derived from 15 requirements across 5 categories
- [Roadmap v1.1]: Schema migration in Phase 6 first -- all subsequent phases depend on new model fields
- [Roadmap v1.1]: Highlightr for syntax highlighting (verify Swift 6 compat before adding SPM dependency)
- [Roadmap v1.1]: Cmd+Shift+1-9 (not Cmd+1-9) for quick paste to avoid browser/editor hotkey conflicts
- [Roadmap v1.1]: All new SwiftData fields optional with nil defaults for lightweight migration
- [06-01]: All new ClipboardItem fields Optional with nil defaults -- no VersionedSchema needed
- [06-01]: ContentType .code/.color routed to TextCardView as placeholder until Phase 7
- [06-01]: LabelColor new cases appended after existing 8 for raw value stability
- [06-02]: Emoji field between color dot menu and name in LabelRow for compact layout
- [06-02]: orderFrontCharacterPalette with 0.1s FocusState delay for correct field targeting
- [06-02]: Emoji-or-dot pattern: `if let emoji = label.emoji, !emoji.isEmpty` across all renderers
- [quick-004]: Unified palette popover replaces separate color Menu + emoji TextField + smiley Button in LabelRow
- [quick-005]: Color dot Circle dropped from context menu labels -- macOS NSMenu unreliable with shapes; concatenated text used instead
- [07-01]: Swift Regex wholeMatch for all color patterns -- prevents false positives from embedded values
- [07-01]: Code heuristic score >= 3 threshold (out of max 7) balances sensitivity vs false positives
- [07-01]: detectLanguage stub returns nil until HighlightSwift added in Plan 07-02
- [07-01]: Detection order: color first, code second (prevents rgb() from triggering code heuristic)

### Pending Todos

- Final manual testing of full application before distribution

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 004 | Unified color/emoji label menu in settings | 2026-02-07 | a4687e2 | [004-unified-color-emoji-label-menu](./quick/004-unified-color-emoji-label-menu/) |
| 005 | Card label chips and emoji menu fix | 2026-02-07 | 41861c0 | [005-card-label-chips-and-emoji-menu-fix](./quick/005-card-label-chips-and-emoji-menu-fix/) |

### Blockers/Concerns

- Highlightr Swift 6 compatibility and current maintenance status need verification in Phase 7

## Session Continuity

Last session: 2026-02-07
Stopped at: Completed 07-01-PLAN.md (Detection Services)
Resume file: None
