---
phase: 22-code-color-edit-controls-and-panel-toolbar-tools-language-override-color-pickers-position-switcher
plan: 01
subsystem: ui
tags: [swiftui, colorpicker, syntax-highlighting, edit-modal]

requires:
  - phase: 07-code-detection
    provides: CodeDetectionService, HighlightCache, CodeCardView, detectedLanguage/detectedColorHex model properties
provides:
  - Language override picker in edit modal (33 languages + auto-detect)
  - Remove code formatting button to revert items to plain text
  - Color picker in edit modal with hex display
  - HighlightCache.evict() for language-aware cache invalidation
affects: [22-02, edit-modal, code-cards, color-cards]

tech-stack:
  added: []
  patterns: [conditional edit sections by content type, cache-aware language switching]

key-files:
  created: []
  modified:
    - Pastel/Views/Panel/EditItemView.swift
    - Pastel/Views/Panel/CodeCardView.swift
    - Pastel/Services/CodeDetectionService.swift

key-decisions:
  - "Combined Task 1 and Task 2 into single commit -- both modify EditItemView.swift and are tightly coupled"
  - "Used Picker (not Menu) for language selection -- provides native macOS dropdown with search"
  - "Color hex init as private extension on Color -- avoids polluting global namespace"

patterns-established:
  - "Conditional edit sections: check item.type == .code/.color to show type-specific UI"
  - "Cache eviction on user override: evict then re-trigger .task(id:) via changing the task ID"

duration: 5min
completed: 2026-02-19
---

# Phase 22 Plan 01: Code/Color Edit Controls Summary

**Language override picker with 33 languages, code removal button, and system ColorPicker in edit modal with cache-aware re-highlighting**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-20T03:44:42Z
- **Completed:** 2026-02-20T03:50:33Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Code items show a language picker in the edit modal with 33 language options plus auto-detect
- "Remove code formatting" button reverts code items to plain text (or rich text if RTF exists)
- Color items show macOS system ColorPicker initialized from detectedColorHex with live hex display
- HighlightCache gets evict() method; CodeCardView task ID includes detectedLanguage for re-rendering

## Task Commits

Tasks 1 and 2 committed together (both modify EditItemView.swift):

1. **Task 1+2: Language override, color picker, cache eviction** - `aa40668` (feat)

## Files Created/Modified
- `Pastel/Views/Panel/EditItemView.swift` - Added @State properties, CodeEditSection (language picker + remove button), ColorEditSection (ColorPicker + hex display), Color hex init extension, onAppear initializers
- `Pastel/Views/Panel/CodeCardView.swift` - Updated .task(id:) to include detectedLanguage for re-highlighting on language change
- `Pastel/Services/CodeDetectionService.swift` - Added evict() method to HighlightCache actor for cache invalidation

## Decisions Made
- Combined Task 1 and Task 2 into a single commit since both modify EditItemView.swift and the color section was defined inline
- Used SwiftUI Picker for language selection (native dropdown with system styling)
- Color hex extension marked private to avoid namespace pollution
- Button role: .destructive for "Remove code formatting" with explicit red foreground style

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- xcodebuild SPM bundle copy errors (pre-existing infrastructure issue, not related to code changes)
- All Swift files compile without errors; build failures are limited to SPM resource bundle path resolution

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Edit modal now supports content-type-specific controls for code and color items
- Ready for Plan 02 (panel toolbar tools, position switcher)

---
*Phase: 22-code-color-edit-controls-and-panel-toolbar-tools-language-override-color-pickers-position-switcher*
*Completed: 2026-02-19*
