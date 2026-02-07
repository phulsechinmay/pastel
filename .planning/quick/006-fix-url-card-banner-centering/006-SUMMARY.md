---
phase: quick
plan: 006
subsystem: ui
tags: [swiftui, image-cropping, url-preview, nspanel]

requires:
  - phase: 08-url-preview-cards
    provides: URLCardView with og:image banner display
provides:
  - Center-cropped og:image banner in URLCardView enriched state
affects: []

tech-stack:
  added: []
  patterns:
    - "SwiftUI center-crop: Image.resizable().scaledToFill().aspectRatio(contentMode: .fill).clipped() -- no GeometryReader needed"

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/URLCardView.swift

key-decisions:
  - "Direct Image with scaledToFill + aspectRatio(.fill) + clipped instead of GeometryReader + ZStack + position -- SwiftUI's default centering handles crop alignment"
  - "Avoided Color.clear.overlay pattern which was previously tried and broke URL copy hit-testing"

patterns-established:
  - "Center-crop pattern: Image.resizable().scaledToFill().frame(minWidth:0, maxWidth:.infinity).aspectRatio(W/H, contentMode:.fill).clipped()"

duration: <1min
completed: 2026-02-07
---

# Quick 006: Fix URL Card Banner Centering Summary

**Replaced GeometryReader-based banner with direct SwiftUI center-crop pattern for reliable og:image centering**

## Performance

- **Duration:** <1 min
- **Started:** 2026-02-07T07:10:10Z
- **Completed:** 2026-02-07T07:10:45Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Banner images now reliably center-crop within 2:1 aspect ratio frame
- Removed GeometryReader, ZStack, and .position() modifiers that caused unpredictable image anchoring
- Preserved URL copy functionality by keeping Image directly in view hierarchy (no overlay)

## Task Commits

Each task was committed atomically:

1. **Task 1: Replace GeometryReader banner with simple center-cropping pattern** - `95dfa7c` (fix)

## Files Created/Modified
- `Pastel/Views/Panel/URLCardView.swift` - Simplified banner image block in enrichedState from GeometryReader+ZStack+position to direct Image with scaledToFill+aspectRatio(.fill)+clipped

## Decisions Made
- Used `contentMode: .fill` on aspectRatio (not `.fit`) to ensure the image fills the entire 2:1 frame rather than letterboxing
- Kept `frame(minWidth: 0, maxWidth: .infinity)` to let the image expand to full card width before aspect ratio constrains height

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- URLCardView banner centering fixed, ready for continued Phase 8 work
- No blockers

---
*Quick task: 006-fix-url-card-banner-centering*
*Completed: 2026-02-07*
