---
phase: 07-code-and-color-detection
plan: 01
subsystem: services
tags: [regex, color-detection, code-detection, heuristics, clipboard, swift-regex, hsl]

# Dependency graph
requires:
  - phase: 06-schema-migration
    provides: detectedColorHex, detectedLanguage fields and .code/.color ContentType cases
provides:
  - ColorDetectionService with hex/rgb/rgba/hsl/hsla parsing and hex normalization
  - CodeDetectionService with multi-signal heuristic pre-filter and async detectLanguage stub
  - ClipboardMonitor integration: detection wired into processPasteboardContent()
affects:
  - 07-02 (code card view needs HighlightSwift language detection implementation)
  - 07-03 (card routing needs .code/.color items to exist in the database)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Color-first detection: always run color detection before code detection to prevent rgb() false positives"
    - "Pure static service pattern: detection services are stateless structs with static methods for testability"
    - "HSL-to-RGB manual conversion: proper algorithm (not NSColor HSB) for correct color normalization"

key-files:
  created:
    - Pastel/Services/ColorDetectionService.swift
    - Pastel/Services/CodeDetectionService.swift
  modified:
    - Pastel/Services/ClipboardMonitor.swift
    - Pastel.xcodeproj/project.pbxproj

key-decisions:
  - "Swift Regex wholeMatch for all color patterns -- prevents false positives from embedded values"
  - "Score >= 3 threshold for code heuristic (out of max 7) -- balances sensitivity vs false positives"
  - "detectLanguage is a nil-returning stub -- HighlightSwift dependency deferred to Plan 07-02"
  - "Non-empty lines used for ratio calculations in code heuristic -- empty lines don't skew results"

patterns-established:
  - "Detection order: color first, code second (prevents rgb() from triggering code heuristic)"
  - "Concealed items never reclassified (password manager content stays .text)"
  - "Detection runs synchronously on main thread (fast: regex + heuristic, no async penalty)"

# Metrics
duration: 10min
completed: 2026-02-07
---

# Phase 7 Plan 1: Detection Services Summary

**Regex-based color detection (hex/rgb/hsl) and multi-signal code heuristic wired into ClipboardMonitor at capture time**

## Performance

- **Duration:** 10 min
- **Started:** 2026-02-07T03:19:30Z
- **Completed:** 2026-02-07T03:29:17Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- ColorDetectionService detects standalone hex (#RGB, #RRGGBB), rgb(), rgba(), hsl(), hsla() values and normalizes to 6-digit uppercase hex
- CodeDetectionService scores text across 5 signals (punctuation density, keywords, indentation, line endings, identifier patterns) with score >= 3 threshold
- ClipboardMonitor runs detection on every text capture: color first, code second, concealed items skipped
- Proper HSL-to-RGB conversion (not NSColor HSB) for correct color normalization

## Task Commits

Each task was committed atomically:

1. **Task 1: ColorDetectionService and CodeDetectionService** - `ae2ea24` (feat)
2. **Task 2: Wire detection into ClipboardMonitor** - `3b931bb` (feat)

## Files Created/Modified
- `Pastel/Services/ColorDetectionService.swift` - Regex-based color detection with hex/rgb/rgba/hsl/hsla and HSL-to-RGB conversion
- `Pastel/Services/CodeDetectionService.swift` - Multi-signal heuristic pre-filter and async detectLanguage stub
- `Pastel/Services/ClipboardMonitor.swift` - Detection integration in processPasteboardContent()
- `Pastel.xcodeproj/project.pbxproj` - Added new files to Xcode project

## Decisions Made
- Used Swift Regex `wholeMatch` for all color patterns to ensure only standalone values match (no embedded hex in prose)
- Set code heuristic threshold at score >= 3 (out of max 7 points) for a good balance of sensitivity vs false positive rejection
- Left detectLanguage as a nil-returning stub since HighlightSwift SPM dependency is added in Plan 07-02
- Used non-empty lines for ratio calculations in code heuristic to prevent empty lines from skewing results

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Detection backbone is complete; Plan 07-02 can add HighlightSwift dependency and implement async language detection
- Plan 07-03 can route .code and .color items to dedicated card views since items are now being classified
- The detectLanguage stub returns nil -- code items will have detectedLanguage = nil until 07-02

---
*Phase: 07-code-and-color-detection*
*Completed: 2026-02-07*
