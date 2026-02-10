---
phase: 16-dragdrop
plan: 01
subsystem: ui
tags: [drag-and-drop, NSItemProvider, UTType, onDrag, SwiftUI]

# Dependency graph
requires:
  - phase: 01-core
    provides: ClipboardItem model with all content type properties
  - phase: 02-capture
    provides: ImageStorageService for resolving image file paths
provides:
  - DragItemProviderService with NSItemProvider construction for all 7 content types
  - .onDrag() modifier on clipboard cards in both horizontal and vertical panel layouts
affects: [16-02-dragdrop panel-state, future drag preview customization]

# Tech tracking
tech-stack:
  added: []
  patterns: [".onDrag() for inter-app drag to avoid .draggable type collision with .dropDestination"]

key-files:
  created:
    - Pastel/Services/DragItemProviderService.swift
  modified:
    - Pastel/Views/Panel/FilteredCardListView.swift
    - Pastel.xcodeproj/project.pbxproj

key-decisions:
  - "Use .onDrag() instead of .draggable() to avoid type collision with existing .dropDestination(for: String.self) for label assignment"
  - "DragItemProviderService as pure Foundation/UTI enum (no SwiftUI/SwiftData imports) for clean separation"
  - "RTF registered before plain text fallback for richText items so receiving apps prefer richer format"

patterns-established:
  - "DragItemProviderService pattern: static enum with createItemProvider(for:) returning NSItemProvider per content type"
  - ".onDrag() placed before .onTapGesture in modifier chain for correct gesture arbitration"

# Metrics
duration: 3min
completed: 2026-02-09
---

# Phase 16 Plan 01: Drag-and-Drop Core Summary

**DragItemProviderService with NSItemProvider for all 7 content types, .onDrag() wired to cards in both panel layouts**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-10T00:47:50Z
- **Completed:** 2026-02-10T00:50:56Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created DragItemProviderService handling all 7 content types (text, richText, code, color, url, image, file) with correct UTType representations
- Wired .onDrag() to clipboard cards in both horizontal (LazyHStack) and vertical (LazyVStack) layouts
- No conflict with existing label drop (.dropDestination for String) or click/double-click gestures

## Task Commits

Each task was committed atomically:

1. **Task 1: Create DragItemProviderService** - `106ea73` (feat)
2. **Task 2: Wire .onDrag() to clipboard cards in FilteredCardListView** - `a30d7b7` (feat)

## Files Created/Modified
- `Pastel/Services/DragItemProviderService.swift` - Static service creating NSItemProvider per ClipboardItem content type
- `Pastel/Views/Panel/FilteredCardListView.swift` - Added .onDrag() modifier on cards in both horizontal and vertical layouts
- `Pastel.xcodeproj/project.pbxproj` - Added DragItemProviderService.swift to Xcode project

## Decisions Made
- **Use .onDrag() not .draggable():** Cards already have `.dropDestination(for: String.self)` for label assignment. `.draggable(String)` would create type collision. `.onDrag()` returns NSItemProvider with UTType-specific representations that do not match the String-based drop destination.
- **Enum not class for service:** DragItemProviderService is a caseless enum with a static method -- no state, no instances needed, pure utility.
- **RTF first, then plain text:** For richText items, RTF data is registered before the plain text fallback so rich text editors receive formatted content.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added DragItemProviderService.swift to Xcode project.pbxproj**
- **Found during:** Task 2 (wiring .onDrag)
- **Issue:** New file was on disk but not in Xcode project references -- build failed with "cannot find DragItemProviderService in scope"
- **Fix:** Added PBXBuildFile, PBXFileReference, Services group entry, and Sources build phase entry to project.pbxproj
- **Files modified:** Pastel.xcodeproj/project.pbxproj
- **Verification:** Build succeeds
- **Committed in:** a30d7b7 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Standard Xcode project file update required for new source file. No scope creep.

## Issues Encountered
None -- plan executed smoothly after the Xcode project reference fix.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Drag initiation is functional for all content types
- Plan 02 will add panel state tracking (isDragging), panel dismissal suppression during drag, and clipboard monitor pause/resume for self-capture prevention
- Drag end detection (via NSEvent global monitor) needed in Plan 02

---
*Phase: 16-dragdrop*
*Completed: 2026-02-09*
