# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-07)

**Core value:** Clipboard history is always one hotkey away, with instant paste-back into any app.
**Current focus:** Milestone v1.2 -- Storage & Security

## Current Position

Phase: 11 — Item Titles, Multi-Label Support, and Edit Modal
Plan: 02 of 3
Status: In progress
Last activity: 2026-02-08 — Completed 11-02-PLAN.md (card layout restructure)

Progress: [==============......] ~67% of Phase 11 (2/3 plans)

## Previous Milestones

### v1.0 MVP
- 29/29 requirements delivered across 5 phases (13 plans)
- Total execution time: ~37 min
- 8 quick tasks completed post-v1.0

### v1.1 Rich Content & Enhanced Paste
- 15/15 requirements delivered across 5 phases (10 plans)
- 10 quick tasks completed during v1.1
- Features: code detection, color swatches, URL metadata, quick paste hotkeys, label emoji, drag-drop labels

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Key decisions from v1.1 carrying forward:

- [06-01]: All new SwiftData fields Optional with nil defaults -- no VersionedSchema needed
- [07-01]: Swift Regex wholeMatch for all color patterns
- [07-01]: Code heuristic score >= 3 threshold
- [08-01]: LPMetadataProvider created locally per fetch (not Sendable)
- [09-01]: Cmd+1-9 for normal paste, Cmd+Shift+1-9 for plain text
- [10-01]: PersistentIdentifier serialized as JSON string for drag payload via Codable
- [quick-014]: First-launch onboarding gate via UserDefaults hasCompletedOnboarding key; handleFirstLaunch() routes between onboarding and accessibility-only prompt
- [11-01]: Two-property migration strategy -- keep deprecated label: Label? alongside new labels: [Label], migrate on first launch via UserDefaults gate
- [11-01]: Label.items has no @Relationship attribute -- SwiftData infers inverse from ClipboardItem.labels to avoid dual-inverse conflict
- [11-01]: EditItemView uses live editing via @Bindable (no save/cancel) matching existing LabelSettingsView pattern
- [11-02]: Custom relativeTimeString over built-in Date.RelativeFormatStyle for exact abbreviated wording (mins/secs/hours/days)
- [11-02]: Footer shows max 3 label chips with +N overflow badge to prevent narrow panel layout breakage
- [11-02]: Label submenu uses toggle pattern (add/remove) with checkmark indicators

### Pending Todos

- Final manual testing of full application before distribution

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 014 | Create onboarding flow with accessibility permissions, hotkey setup, and quick settings | 2026-02-08 | bbcddb3 | [014-onboarding-flow-accessibility-hotkey-settings](./quick/014-onboarding-flow-accessibility-hotkey-settings/) |

### Roadmap Evolution

- Phase 11 added: Item Titles, Multi-Label Support, and Edit Modal (first phase of v1.2)

### Blockers/Concerns

None currently.

## Session Continuity

Last session: 2026-02-08
Stopped at: Completed 11-02-PLAN.md (card layout restructure)
Resume file: None
