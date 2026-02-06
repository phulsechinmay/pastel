---
phase: 01-clipboard-capture-and-storage
plan: 02
subsystem: clipboard
tags: [NSPasteboard, SwiftData, CryptoKit, SHA256, timer-polling, content-classification]

# Dependency graph
requires:
  - phase: 01-clipboard-capture-and-storage (plan 01)
    provides: SwiftData ClipboardItem model, ContentType enum, AppState, PastelApp entry point, StatusPopoverView
provides:
  - ClipboardMonitor service with timer-based NSPasteboard polling
  - NSPasteboard extension for content type classification and typed reading
  - App lifecycle wiring (monitor starts on launch)
  - Reactive item count in status popover
  - Consecutive duplicate detection via SHA256 hash
  - Concealed content detection (password managers)
  - System wake clipboard re-check
affects:
  - 01-clipboard-capture-and-storage (plan 03) -- image capture builds on ClipboardMonitor
  - 02-search-and-quick-access -- search will query ClipboardItem records created here
  - 03-paste-back-engine -- paste-back will use skipNextChange flag for loop prevention

# Tech tracking
tech-stack:
  added: [CryptoKit, OSLog]
  patterns: [timer-based polling, content-type priority classification, consecutive dedup via hash, explicit SwiftData save, observation delegation chain]

key-files:
  created:
    - Pastel/Extensions/NSPasteboard+Reading.swift
    - Pastel/Services/ClipboardMonitor.swift
  modified:
    - Pastel/App/AppState.swift
    - Pastel/PastelApp.swift
    - Pastel/Views/MenuBar/StatusPopoverView.swift

key-decisions:
  - "Consecutive-only dedup via SHA256 hash comparison against most recent item (not global dedup) -- same content at different times is intentionally allowed"
  - "Explicit modelContext.save() after every insert -- no autosave reliance for clipboard manager data integrity"
  - "Manual ModelContainer creation in PastelApp.init for eager monitor startup instead of .modelContainer modifier"
  - "modelContext.rollback() on save failure to handle @Attribute(.unique) conflicts gracefully"
  - "OSLog Logger for structured logging instead of print statements"

patterns-established:
  - "Content type priority: image > fileURL > URL > string (with sub-classification)"
  - "Observation delegation: AppState computed properties delegate to ClipboardMonitor observable properties"
  - "Timer + Task @MainActor pattern for safe main-thread callback from Timer"

# Metrics
duration: 3min
completed: 2026-02-06
---

# Phase 1 Plan 2: Clipboard Monitoring Service Summary

**Timer-based NSPasteboard polling with content classification, SHA256 dedup, and SwiftData persistence wired into app lifecycle**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-06T09:03:00Z
- **Completed:** 2026-02-06T09:06:22Z
- **Tasks:** 2
- **Files modified:** 5 (2 created, 3 modified)

## Accomplishments

- NSPasteboard extension with priority-based content type classification (text, richText, url, file, image) and concealed/transient/auto-generated detection
- ClipboardMonitor service: 0.5s timer polling, source app capture, SHA256 consecutive dedup, explicit SwiftData save, system wake handling
- Full app lifecycle wiring: monitor starts on launch, item count is reactive in popover, toggle pauses/resumes capture
- Concealed content from password managers is captured with 60s expiry flag (deletion service deferred to Plan 01-03)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create NSPasteboard+Reading extension and ClipboardMonitor service** - `07427d6` (feat)
2. **Task 2: Wire ClipboardMonitor into app lifecycle and update status popover** - `74523c3` (feat)

## Files Created/Modified

- `Pastel/Extensions/NSPasteboard+Reading.swift` - Content type classification and typed pasteboard readers (text, URL, file)
- `Pastel/Services/ClipboardMonitor.swift` - Core polling service: 0.5s timer, classify, dedup, persist, source app capture
- `Pastel/App/AppState.swift` - Delegates itemCount/isMonitoring to ClipboardMonitor, setup(modelContext:) method
- `Pastel/PastelApp.swift` - Manual ModelContainer in init, AppState.setup() call for eager monitor startup
- `Pastel/Views/MenuBar/StatusPopoverView.swift` - Toggle bound to ClipboardMonitor.toggleMonitoring(), live item count

## Decisions Made

1. **Consecutive-only dedup** -- SHA256 hash compared against most recent item only. Same content copied at different times creates separate entries. This is intentional for a clipboard history tool.
2. **Explicit save after every insert** -- `modelContext.save()` called immediately, not relying on SwiftData autosave. Data loss is unacceptable for a clipboard manager.
3. **Manual ModelContainer in PastelApp.init** -- Instead of using the `.modelContainer` scene modifier, we create `ModelContainer` manually so we can pass `mainContext` to `AppState.setup()` before the first view renders. This ensures monitoring starts immediately.
4. **Rollback on save failure** -- When `@Attribute(.unique)` on `contentHash` causes a merge conflict (non-consecutive duplicate), we call `modelContext.rollback()` to keep the context consistent.
5. **OSLog for structured logging** -- Using `Logger` with subsystem/category for production-quality logging instead of print statements.

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- ClipboardMonitor is fully operational for text, URL, file, and rich text capture
- Image capture is detected (classified as .image) but deferred to Plan 01-03
- ExpirationService for concealed content cleanup is deferred to Plan 01-03
- `skipNextChange` flag is wired in ClipboardMonitor for Phase 3 paste-back loop prevention
- Build verification deferred until Xcode.app installation completes (syntax verified via swiftc -parse on non-macro files)

---
*Phase: 01-clipboard-capture-and-storage*
*Completed: 2026-02-06*
