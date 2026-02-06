# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-05)

**Core value:** Clipboard history is always one hotkey away, with instant paste-back into any app.
**Current focus:** Phase 4 in progress -- Organization (search, labels, filtering, deletion).

## Current Position

Phase: 4 of 5 (Organization)
Plan: 3 of 4 in current phase
Status: In progress
Last activity: 2026-02-06 -- Completed 04-03-PLAN.md

Progress: [████████░░] 77% (10/13 plans estimated)

## Performance Metrics

**Velocity:**
- Total plans completed: 10
- Average duration: 3min
- Total execution time: 30min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-clipboard-capture-and-storage | 3/3 | 13min | 4.3min |
| 02-sliding-panel | 2/2 | 5min | 2.5min |
| 03-paste-back-and-hotkeys | 2/2 | 5min | 2.5min |
| 04-organization | 3/4 | 7min | 2.3min |

**Recent Trend:**
- Last 5 plans: 03-02 (2min), 04-01 (3min), 04-02 (2min), 04-03 (2min)
- Trend: stable, fast

*Updated after each plan completion*

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

### Pending Todos

- Phase 1 checkpoint verification: user should build and run the app to verify all 5 content types captured correctly (see 01-03-SUMMARY.md checkpoint notes)

### Blockers/Concerns

- None. All builds verified with xcodebuild.

## Session Continuity

Last session: 2026-02-06T20:05:46Z
Stopped at: Completed 04-03-PLAN.md
Resume file: None
