# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-07)

**Core value:** Clipboard history is always one hotkey away, with instant paste-back into any app.
**Current focus:** Milestone v1.1 — Rich Content & Enhanced Paste

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-02-07 — Milestone v1.1 started

Progress: [░░░░░░░░░░] 0%

## Previous Milestone: v1.0

- 29/29 requirements delivered across 5 phases (13 plans)
- Total execution time: ~37 min
- 3 quick tasks completed post-v1.0

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: 5-phase structure derived from 29 requirements across 5 categories
- [Roadmap]: NSPanel + AppKit bridge mandatory from Phase 2 (research finding: non-negotiable for paste-back)
- [Roadmap]: Images stored on disk from Phase 1 (research finding: prevents OOM at scale)
- [01-01]: XcodeGen for CLI-driven project generation (project.yml is source of truth)
- [01-01]: Package.swift alongside Xcode project for SPM-based build verification
- [01-01]: AppState marked @MainActor for Swift 6 strict concurrency safety
- [01-01]: contentType stored as String in SwiftData for predicate/unique constraint reliability
- [01-02]: Consecutive-only dedup via SHA256 hash (same content at different times creates separate entries)
- [01-02]: Explicit modelContext.save() after every insert (no autosave reliance)
- [01-02]: Manual ModelContainer in PastelApp.init for eager monitor startup
- [01-02]: modelContext.rollback() on save failure for @Attribute(.unique) conflict handling
- [01-02]: OSLog Logger for structured logging
- [01-03]: Image hash uses first 4KB of data via SHA256 for speed (not full image data)
- [01-03]: @MainActor @Sendable completion handler pattern for Swift 6 strict concurrency with GCD
- [01-03]: ExpirationService integrated into ClipboardMonitor init (not standalone wiring)
- [01-03]: Overdue concealed items cleaned up at ClipboardMonitor init time
- [02-01]: NSVisualEffectView .sidebar material with .darkAqua appearance (deprecated .dark replaced)
- [02-01]: NSHostingView typed as NSView to handle conditional modelContainer branch
- [02-01]: KeyboardShortcuts.onKeyUp with MainActor.assumeIsolated for Swift 6 concurrency safety
- [02-02]: Card dispatcher pattern -- ClipboardCardView switches on item.type to route to subviews
- [02-02]: Async thumbnail loading via .task(id:) with withCheckedContinuation for background I/O
- [02-02]: NSWorkspace.urlForApplication for app icon resolution (nil-safe for uninstalled apps)
- [03-01]: String literal "AXTrustedCheckOptionPrompt" instead of kAXTrustedCheckOptionPrompt for Swift 6 concurrency safety
- [03-01]: PanelActions @Observable class bridges SwiftUI paste callbacks via .environment()
- [03-01]: Empty entitlements dict (no app-sandbox key at all) for non-sandboxed app
- [03-02]: Double-tap gesture (count: 2) before single-tap (count: 1) for correct SwiftUI gesture priority
- [03-02]: Timer.publish polling (1s) for Accessibility permission auto-dismiss (no callback API)
- [03-02]: Standalone NSWindow for onboarding in menu-bar-only app (no main window for sheets)
- [03-02]: Selection uses accentColor at two opacities (background + border) distinct from hover
- [04-01]: Keyboard navigation moved into FilteredCardListView (direct items access for Enter-to-paste and arrow clamping)
- [04-01]: localizedStandardContains for Unicode-aware case-insensitive search in #Predicate
- [04-01]: persistentModelID comparison for label filtering in predicates (not direct entity comparison)
- [04-01]: Dynamic @Query pattern: parent holds @State, child constructs @Query in init with predicate
- [04-02]: Popover for label creation (not sheet) since menu-bar-only app has no main window
- [04-02]: @Query for labels independently in ClipboardCardView (context menu) and PanelContentView (chip bar)
- [04-02]: persistentModelID comparison for chip selection and context menu checkmark
- [04-03]: Simpler delete approach: image cleanup in view, expiration timer no-ops via existing ExpirationService guard
- [04-03]: Fetch all items before batch delete to collect image paths for disk cleanup
- [04-03]: Labels preserved through clear-all (reusable organizational tools per CONTEXT.md)
- [04-03]: confirmationDialog for clear-all (better macOS UX for destructive actions)
- [05-01]: SettingsWindowController accepts both ModelContainer and AppState for full environment wiring
- [05-01]: RetentionService uses stop() instead of deinit for Swift 6 strict concurrency compatibility
- [05-01]: PanelController recreates panel on vertical<->horizontal orientation change
- [05-01]: @AppStorage panelEdge defaults to "right", historyRetention defaults to 90 days
- [05-02]: Menu-based color picker using LabelColor.allCases for inline recoloring
- [05-02]: @Bindable for direct TextField binding to SwiftData model in LabelRow
- [05-02]: Fixed 260pt card width in horizontal mode for consistent sizing
- [05-02]: Direction-aware key handlers return .ignored for non-matching axis
- [quick-001]: Automatic code signing with DEVELOPMENT_TEAM in project.yml for stable TCC identity
- [quick-002]: UserDefaults.standard in PasteService (non-view class), copy-only mode skips accessibility check, default is .paste
- [quick-003]: SwiftData #Predicate optionals: use ?.method() == true pattern (force-unwrap unsupported, ?? generates TERNARY SQL)
- [quick-003]: @Query .id() must include ALL filter inputs (search text, label, itemCount) to force view recreation

### Pending Todos

- Final manual testing of full application before distribution

### Blockers/Concerns

- None.

### Quick Tasks Completed (v1.0)

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 001 | Fix code signing for TCC persistence | 2026-02-06 | 2106f94 | [001-fix-code-signing-for-tcc-persistence](./quick/001-fix-code-signing-for-tcc-persistence/) |
| 002 | Add paste behavior setting (Paste/Copy/Copy+Paste) | 2026-02-06 | ac64b61 | [002-add-paste-behavior-setting](./quick/002-add-paste-behavior-setting/) |
| 003 | Fix horizontal header and search/label filtering | 2026-02-07 | 9e6f47a | [003-fix-horizontal-header-and-search-label-filtering](./quick/003-fix-horizontal-header-and-search-label-filtering/) |

## Session Continuity

Last session: 2026-02-07
Stopped at: Starting milestone v1.1
Resume file: None
