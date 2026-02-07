---
phase: 08-url-preview-cards
plan: 01
subsystem: services
tags: [LinkPresentation, LPMetadataProvider, URLMetadata, favicon, og:image, async]

# Dependency graph
requires:
  - phase: 06-data-model-and-label-enhancements
    provides: ClipboardItem urlTitle, urlFaviconPath, urlPreviewImagePath, urlMetadataFetched fields
provides:
  - URLMetadataService with LPMetadataProvider-based fetch, 5s timeout, private URL filtering, duplicate reuse
  - ImageStorageService saveFavicon and savePreviewImage methods for URL metadata images
  - ClipboardMonitor fire-and-forget URL metadata fetch wiring
affects:
  - 08-02 (URL card view and settings toggle depend on metadata being populated)

# Tech tracking
tech-stack:
  added: [LinkPresentation framework (system)]
  patterns: [fire-and-forget async enrichment for URL items, NSItemProvider continuation wrapper]

key-files:
  created:
    - Pastel/Services/URLMetadataService.swift
  modified:
    - Pastel/Services/ImageStorageService.swift
    - Pastel/Services/ClipboardMonitor.swift
    - Pastel.xcodeproj/project.pbxproj

key-decisions:
  - "LPMetadataProvider created locally per fetch (not stored) -- it is not Sendable"
  - "loadImageData marked @MainActor to satisfy Swift 6 strict concurrency for NSItemProvider"
  - "UserDefaults.standard.object(forKey:) with nil coalescing to true for fetchURLMetadata default"

patterns-established:
  - "URL metadata enrichment: save item first, async fetch metadata, SwiftData update triggers UI re-render"
  - "NSItemProvider to Data via withCheckedContinuation wrapping loadDataRepresentation"

# Metrics
duration: 3min
completed: 2026-02-07
---

# Phase 8 Plan 1: URLMetadataService Summary

**LPMetadataProvider-based URL metadata fetching with 5s timeout, private URL filtering, duplicate reuse, and favicon/og:image disk caching via ImageStorageService**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-07T06:08:05Z
- **Completed:** 2026-02-07T06:11:34Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- URLMetadataService created with shouldFetchMetadata (private URL/scheme/settings filtering) and fetchMetadata (LPMetadataProvider with 5s timeout, duplicate reuse, favicon/og:image extraction)
- ImageStorageService extended with saveFavicon and savePreviewImage async methods for URL metadata disk caching
- ClipboardMonitor wired with fire-and-forget URL metadata fetch for .url items, mirroring existing code detection pattern

## Task Commits

Each task was committed atomically:

1. **Task 1: Create URLMetadataService with LPMetadataProvider** - `6e53bc0` (feat)
2. **Task 2: Wire URLMetadataService into ClipboardMonitor** - `5d25ecd` (feat)

## Files Created/Modified
- `Pastel/Services/URLMetadataService.swift` - New service: URL metadata fetching with LPMetadataProvider, private URL filtering, duplicate reuse, NSItemProvider continuation wrapper
- `Pastel/Services/ImageStorageService.swift` - Added saveFavicon and savePreviewImage async methods for URL metadata image caching
- `Pastel/Services/ClipboardMonitor.swift` - Added fire-and-forget URL metadata fetch Task after URL item save
- `Pastel.xcodeproj/project.pbxproj` - Added URLMetadataService.swift to Xcode project

## Decisions Made
- LPMetadataProvider created locally per fetch call (not stored as property) because it is not Sendable -- matches Apple's recommendation
- loadImageData helper marked @MainActor to satisfy Swift 6 strict concurrency when receiving NSItemProvider from @MainActor-isolated fetchMetadata
- UserDefaults key "fetchURLMetadata" defaults to true via nil coalescing (`?? true`) -- matches the @AppStorage default that will be added in plan 08-02

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed PersistentModelID type name**
- **Found during:** Task 1 (URLMetadataService creation)
- **Issue:** Plan used `PersistentModelID` which does not exist in SwiftData -- the correct type is `PersistentIdentifier`
- **Fix:** Changed parameter type to `PersistentIdentifier`
- **Files modified:** Pastel/Services/URLMetadataService.swift
- **Verification:** Build compiles cleanly
- **Committed in:** 6e53bc0 (Task 1 commit)

**2. [Rule 1 - Bug] Fixed Swift 6 strict concurrency for NSItemProvider**
- **Found during:** Task 1 (URLMetadataService creation)
- **Issue:** Passing main actor-isolated NSItemProvider to nonisolated loadImageData caused "sending risks data races" error in Swift 6
- **Fix:** Added @MainActor annotation to loadImageData helper
- **Files modified:** Pastel/Services/URLMetadataService.swift
- **Verification:** Build compiles without concurrency errors
- **Committed in:** 6e53bc0 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes necessary for compilation. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- URL metadata backend complete -- all SwiftData fields (urlTitle, urlFaviconPath, urlPreviewImagePath, urlMetadataFetched) are populated by the service
- Ready for plan 08-02: URLCardView enrichment with og:image banner, favicon + title display, loading states, and settings toggle
- No blockers

---
*Phase: 08-url-preview-cards*
*Completed: 2026-02-07*
