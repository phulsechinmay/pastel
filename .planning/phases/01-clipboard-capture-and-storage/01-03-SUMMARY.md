---
phase: 01-clipboard-capture-and-storage
plan: 03
subsystem: infra, clipboard
tags: [ImageIO, CGImageSource, SwiftData, NSPasteboard, CryptoKit, image-storage, thumbnail, expiration]

# Dependency graph
requires:
  - phase: 01-clipboard-capture-and-storage (plans 01, 02)
    provides: project structure, ClipboardMonitor, SwiftData model, pasteboard classification
provides:
  - Disk-based image storage with background queue processing
  - CGImageSource-based fast thumbnail generation (200px)
  - Auto-expiration of concealed clipboard items (password managers, 60s TTL)
  - Complete end-to-end clipboard capture for all 5 content types
affects: [02-sliding-panel-and-history-ui, 03-paste-back-and-hotkeys]

# Tech tracking
tech-stack:
  added: [ImageIO, CryptoKit (image hashing)]
  patterns: [background-queue disk I/O with main-thread completion, @MainActor @Sendable closures for Swift 6]

key-files:
  created:
    - Pastel/Services/ImageStorageService.swift
    - Pastel/Extensions/NSImage+Thumbnail.swift
    - Pastel/Services/ExpirationService.swift
  modified:
    - Pastel/Services/ClipboardMonitor.swift
    - Pastel/Services/ImageStorageService.swift

key-decisions:
  - "Image hash uses first 4KB of data via SHA256 for speed (not full image data)"
  - "@MainActor @Sendable completion handler pattern for Swift 6 strict concurrency with GCD"
  - "ExpirationService integrated into ClipboardMonitor init (not standalone wiring in PastelApp)"
  - "Overdue concealed items cleaned up at ClipboardMonitor init time"

patterns-established:
  - "Background I/O pattern: read pasteboard data on main thread, dispatch to utility queue, callback on main thread for SwiftData insert"
  - "@MainActor @Sendable completion: mark GCD completion handlers as @MainActor @Sendable for Swift 6 compliance when callers are @MainActor"
  - "Filename-only storage: database stores filenames, runtime path resolution via ImageStorageService.resolveImageURL"

# Metrics
duration: 4min
completed: 2026-02-06
---

# Phase 1 Plan 3: Image Storage, Expiration, and Pipeline Completion Summary

**Disk-based PNG image storage with CGImageSource thumbnails, concealed item auto-expiration, and full 5-type clipboard capture pipeline**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-06T09:20:42Z
- **Completed:** 2026-02-06T09:25:06Z
- **Tasks:** 2 auto + 1 checkpoint (verification notes below)
- **Files modified:** 4 (2 created, 2 modified)

## Accomplishments

- Image capture end-to-end: pasteboard image data read on main thread, saved as PNG to disk on background utility queue, 200px thumbnails generated via CGImageSource, ClipboardItem created with filename references (never image data in DB)
- ExpirationService auto-deletes concealed items (password manager content) after 60 seconds, with launch-time cleanup of overdue items
- All 5 content types now captured: text, richText, URL, file, image -- Phase 1 clipboard capture is complete
- Full Swift 6 strict concurrency compliance maintained with @MainActor @Sendable completion pattern

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ImageStorageService and NSImage+Thumbnail extension** - `fe83e28` (feat)
2. **Task 2: Create ExpirationService, wire image capture, complete pipeline** - `4f1fa2e` (feat)

**Plan metadata:** (pending docs commit)

## Files Created/Modified

- `Pastel/Extensions/NSImage+Thumbnail.swift` - CGImageSource-based thumbnail generation at configurable max pixel size
- `Pastel/Services/ImageStorageService.swift` - Singleton image storage: background save, 4K downscale, PNG conversion, thumbnail generation, cleanup, path resolution
- `Pastel/Services/ExpirationService.swift` - @MainActor service scheduling concealed item deletion after 60s with launch-time overdue cleanup
- `Pastel/Services/ClipboardMonitor.swift` - Added processImageContent(), isDuplicateOfMostRecent(), ExpirationService wiring, concealed item expiration for all content types

## Decisions Made

1. **Image hash uses first 4KB via SHA256** -- Full image hashing is too slow for multi-megabyte images. First 4KB is sufficient to distinguish different images for consecutive dedup purposes.
2. **@MainActor @Sendable completion handler pattern** -- Swift 6 strict concurrency requires the GCD completion handler to be marked `@MainActor @Sendable` so the caller (a @MainActor class) can access its isolated properties. This is the correct pattern when using DispatchQueue.main.async callbacks into @MainActor code.
3. **ExpirationService integrated into ClipboardMonitor.init** -- Rather than separate wiring in PastelApp, the ClipboardMonitor owns and initializes the ExpirationService since it's the only consumer. This keeps the dependency graph simple.
4. **Overdue items cleaned at monitor init** -- Calling `expireOverdueItems()` in ClipboardMonitor.init ensures concealed items that expired while the app was closed get cleaned up before monitoring starts, preventing stale sensitive data.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed PersistentModelID type name**
- **Found during:** Task 2 (ExpirationService compilation)
- **Issue:** Plan referenced `PersistentModelID` but the correct SwiftData type is `PersistentIdentifier`
- **Fix:** Replaced all occurrences of `PersistentModelID` with `PersistentIdentifier`
- **Files modified:** Pastel/Services/ExpirationService.swift
- **Verification:** Build succeeded
- **Committed in:** `4f1fa2e` (Task 2 commit)

**2. [Rule 1 - Bug] Fixed Swift 6 strict concurrency in @Sendable completion**
- **Found during:** Task 2 (ClipboardMonitor compilation)
- **Issue:** `@Sendable` completion closure in `saveImage` couldn't access `@MainActor`-isolated properties of ClipboardMonitor (modelContext, itemCount, expirationService) even though it was dispatched on main queue
- **Fix:** Changed `ImageStorageService.saveImage` completion parameter from `@escaping @Sendable` to `@escaping @MainActor @Sendable` so Swift 6 knows the closure runs on the main actor
- **Files modified:** Pastel/Services/ImageStorageService.swift, Pastel/Services/ClipboardMonitor.swift
- **Verification:** Build succeeded with zero errors/warnings
- **Committed in:** `4f1fa2e` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes necessary for compilation. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviations above.

## Checkpoint Verification Notes (Task 3)

The plan included a `checkpoint:human-verify` task for end-to-end Phase 1 verification. Per execution instructions, verification notes are included here for the orchestrator to present to the user.

### What Was Built

Complete Phase 1 clipboard capture and storage system:
1. Menu bar app with clipboard icon (no dock icon)
2. Captures text, rich text, URLs, file references, and images
3. Content type classification with priority: image > URL > file > richText > text
4. Consecutive duplicate detection via SHA256 hash
5. Images saved as PNG to `~/Library/Application Support/Pastel/images/` with 200px thumbnails
6. All history persisted to SwiftData across restarts
7. Concealed items (password managers) auto-expire after 60 seconds
8. Status popover shows item count and monitoring toggle

### How to Verify

Build and run the app, then test each scenario:

1. **Menu bar presence (INFR-01):** Clipboard icon in menu bar, no dock icon, popover with item count/toggle/quit
2. **Text capture (CLIP-01):** Copy text from any app, item count increments
3. **URL capture (CLIP-03):** Copy a URL, item count increments
4. **File capture (CLIP-04):** Cmd+C a file in Finder, item count increments
5. **Image capture (CLIP-02, INFR-04):** Copy an image, item count increments, check `ls ~/Library/Application\ Support/Pastel/images/` for UUID.png and UUID_thumb.png
6. **Consecutive dedup (CLIP-06):** Copy same text twice, only one increment
7. **Persistence (CLIP-05):** Note count, quit, relaunch, count preserved
8. **Monitoring toggle:** Toggle off, copy text (no increment), toggle on, copy text (increments)

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 1 is complete: all 5 content types captured, images on disk with thumbnails, concealed items auto-expire, data persists
- Phase 2 (Sliding Panel and History UI) can begin -- it will need:
  - `ImageStorageService.resolveImageURL(_:)` to load thumbnails in the history list
  - `ClipboardItem` model for display (all fields populated)
  - `AppState` for monitoring state
- NSPanel implementation required for Phase 2 (per MEMORY.md: non-activating panel that won't steal focus)

---
*Phase: 01-clipboard-capture-and-storage*
*Completed: 2026-02-06*
