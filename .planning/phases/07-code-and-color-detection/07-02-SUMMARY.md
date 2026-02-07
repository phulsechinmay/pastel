---
phase: 07-code-and-color-detection
plan: 02
subsystem: views, services
tags: [highlightswift, syntax-highlighting, language-detection, code-card, spm]

# Dependency graph
requires:
  - phase: 07-01
    provides: CodeDetectionService stub, .code ContentType classification
provides:
  - HighlightSwift SPM dependency resolved
  - CodeDetectionService.detectLanguage async implementation with keyword hints
  - HighlightCache actor for in-memory AttributedString caching
  - CodeCardView with syntax highlighting, language badge, monospaced font
  - Fire-and-forget language detection wired into ClipboardMonitor
affects:
  - 07-03 (CodeCardView now exists for routing)

# Tech tracking
tech-stack:
  added:
    - "HighlightSwift 1.1.0 (SPM)"
  patterns:
    - "Actor-based highlight cache with 200-entry eviction"
    - "Keyword-based language hints to correct highlight.js misdetections"
    - ".task(id: contentHash) for on-demand async highlighting"

key-files:
  created:
    - Pastel/Views/Panel/CodeCardView.swift
  modified:
    - Pastel/Services/CodeDetectionService.swift
    - Pastel/Services/ClipboardMonitor.swift
    - Pastel.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

key-decisions:
  - "HighlightSwift 1.1.0 via SPM -- builds cleanly with Swift 6"
  - "Relevance >= 5 threshold for language detection to avoid false positives"
  - "Keyword-based hints (Swift, Python, JS, Rust, Go) correct highlight.js misdetections"
  - ".dark(.atomOne) theme for syntax highlighting matches always-dark panel"
  - "Language badge below code as capsule with monospaced font"

patterns-established:
  - "Fire-and-forget Task.detached for async language detection after item save"
  - "HighlightCache actor for thread-safe in-memory caching of highlighted AttributedStrings"

# Metrics
duration: ~15min
completed: 2026-02-07
---

# Phase 7 Plan 2: CodeCardView with Syntax Highlighting

**HighlightSwift SPM integration, async language detection, and CodeCardView with syntax-highlighted previews and language badges**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-02-07
- **Tasks:** 2 (+ checkpoint verified by user)
- **Files modified:** 4

## Accomplishments
- HighlightSwift 1.1.0 added as SPM dependency, builds cleanly
- CodeDetectionService.detectLanguage implemented with highlight.js via HighlightSwift, plus keyword-based hints for Swift/Python/JS/Rust/Go
- HighlightCache actor provides in-memory caching (200-entry limit) to avoid re-highlighting on scroll
- CodeCardView renders syntax-highlighted code with .dark(.atomOne) theme, monospaced font, and language badge
- ClipboardMonitor fires async language detection after saving .code items via Task.detached
- Post-checkpoint refinements: language hints, color card redesign, paste delay fix

## Task Commits

1. **Task 1: Add HighlightSwift SPM and implement detectLanguage + HighlightCache** - `c505456` (feat)
2. **Task 2: Create CodeCardView with syntax highlighting and language badge** - `0b3c1b0` (feat)
3. **Post-checkpoint fixes** - `3f9cbab`, `30fe131`, `0ea4c62`, `d91fada` (fix/style)

## Files Created/Modified
- `Pastel/Views/Panel/CodeCardView.swift` - Syntax-highlighted code preview with language badge and caching
- `Pastel/Services/CodeDetectionService.swift` - Async detectLanguage with HighlightSwift and keyword hints
- `Pastel/Services/ClipboardMonitor.swift` - Fire-and-forget language detection after .code item save
- `Package.resolved` - HighlightSwift 1.1.0 dependency

## Decisions Made
- Used HighlightSwift 1.1.0 (Swift 6 compatible, no @preconcurrency needed)
- Relevance threshold of >= 5 to avoid false positive language detection
- Added keyword-based language hints to correct common highlight.js misdetections
- .dark(.atomOne) theme for syntax highlighting to match always-dark panel

## Deviations from Plan

Post-checkpoint feedback led to refinements in color card design, language detection hints, and paste delay increase.

## Issues Encountered

None blocking.

---
*Phase: 07-code-and-color-detection*
*Completed: 2026-02-07*
