# Phase 16: Drag-and-Drop from Panel - Context

## Phase Goal

Users can drag clipboard items directly from the sliding panel into other macOS applications as a natural alternative to paste-back.

## Requirements

- DRAG-01: User can drag clipboard items from panel to other applications
- DRAG-02: Drag-and-drop supports text, images, URLs, and files
- DRAG-03: Drag provides correct NSItemProvider UTTypes for receiving apps
- DRAG-04: Panel remains visible during drag session (does not dismiss on drag)
- DRAG-05: Drag session does not trigger clipboard monitor self-capture

## Success Criteria

1. User drags a text card from the panel and drops it into TextEdit, and the text appears
2. User drags an image card from the panel and drops it into Finder or Preview, and the image file is received
3. User drags a URL card from the panel and drops it into Safari's address bar, and the URL is accepted
4. Panel remains visible throughout the entire drag session (does not dismiss when cursor leaves panel bounds)
5. Dragging an item from the panel does not create a duplicate entry in clipboard history (no self-capture)

## Implementation Decisions

### 1. Feasibility Approach (CRITICAL)

**Decision**: Test .draggable() first, then plan

**Rationale**: SwiftUI's `.draggable()` is designed for regular windows, but Pastel uses `NSPanel` with custom style masks (`.nonactivatingPanel`, `.utilityWindow`). Feasibility is unknown.

**Plan Structure**:
- **Plan 01**: Minimal feasibility test
  - Add `.draggable()` to one card type (text)
  - Test drag from NSPanel to TextEdit
  - Document whether it works or fails
  - Create SUMMARY with go/no-go decision
- **If .draggable() works**: Continue with SwiftUI approach in subsequent plans
- **If .draggable() fails**: Pivot to AppKit NSView drag APIs (`beginDraggingSession(with:event:source:)`)

**Risk mitigation**: Early test in Plan 01 prevents wasted planning/implementation effort if SwiftUI approach doesn't work on NSPanel.

### 2. Content Representation Strategy

**Decision**: Match current paste behavior

**Rationale**: Drag should use the same content representation logic that paste-back uses. This ensures consistency:
- If PasteService pastes RTF for rich text, drag provides RTF
- If PasteService pastes plain text for code, drag provides plain text
- Leverages existing `ContentRepresentationService` logic
- Users get predictable behavior: "drag = paste without keyboard"

**Implementation**: Use `PasteService.getPasteboardContent(for:)` or equivalent to determine which representation to provide in `NSItemProvider`.

### 3. Image File Strategy

**Decision**: Full-resolution file (from disk)

**Rationale**:
- Images are stored on disk at `~/Library/Application Support/Pastel/images/{uuid}.{ext}`
- Thumbnails are 200x200 preview versions, not suitable for drag-and-drop
- Receiving apps expect full-quality images
- May require `NSFilePromiseProvider` for large files (instead of direct file URL)

**Implementation**:
- For image clipboard items, resolve `imagePath` to full file URL
- If file exists, provide via `NSItemProvider` with `.fileURL` UTType
- Consider `NSFilePromiseProvider` for files >10MB to avoid blocking main thread

**Edge case**: If image file was deleted (manual cleanup), fall back to in-memory thumbnail data with `.png` UTType.

### 4. Panel Visibility During Drag

**Decision**: Track drag state, disable dismissal

**Rationale**: NSPanel currently dismisses when cursor leaves bounds. During a drag session, this would interrupt the drag and confuse users.

**Implementation**:
- Add `@State private var isDragging: Bool = false` to panel state
- SwiftUI `.draggable()` provides `onDragStart` and `onDragEnd` callbacks (if available), OR track via custom gesture recognizers
- While `isDragging == true`, ignore panel dismissal triggers:
  - Mouse exit from panel bounds
  - Panel deactivation
  - Focus loss
- Restore normal dismissal behavior when `isDragging == false`

**Alternative approach** (if SwiftUI callbacks unavailable): Set `NSPanel.hidesOnDeactivate = false` on drag start, restore on drag end.

### 5. Self-Capture Prevention

**Decision**: Pause clipboard monitor during drag session (same as paste-back)

**Rationale**:
- When user drops content into another app, that app may write to the pasteboard
- If monitor is active, this creates a duplicate entry
- PasteService already has `pauseMonitoring()` / `resumeMonitoring()` for paste-back
- Reuse the same mechanism for drag-and-drop

**Implementation**:
- On drag start: Call `ClipboardMonitor.pauseMonitoring()`
- On drag end/cancel: Call `ClipboardMonitor.resumeMonitoring()` after 500ms delay (same as paste-back)
- 500ms delay prevents self-capture if receiving app writes to pasteboard on drop

**Note**: This decision was not explicitly discussed but follows the established pattern from Phase 3 (Paste-Back).

## Technical Constraints

### NSPanel + SwiftUI Limitations

- NSPanel may not fully support SwiftUI drag modifiers due to custom window level and style masks
- If SwiftUI approach fails, fallback to AppKit:
  - Custom NSView subclass with `draggingSession(willBeginAt:)` and `draggingSession(endedAt:operation:)`
  - Manual NSItemProvider construction
  - Manual drag image rendering

### NSItemProvider UTType Mapping

Content type to UTType mapping (based on existing ContentType enum):

| ContentType | Primary UTType | Secondary UTTypes | Notes |
|-------------|---------------|-------------------|-------|
| `.text` | `.plainText` | `.utf8PlainText` | Always plain text |
| `.richText` | Match paste behavior | May include `.rtf`, `.html`, `.plainText` | Determined by PasteService logic |
| `.code` | `.plainText` | `.utf8PlainText` | Code is text |
| `.url` | `.url` | `.plainText` | URL string for Safari address bar + plain text fallback |
| `.image` | `.fileURL` | `.png` (fallback) | File URL to full-res image, or in-memory PNG if file missing |
| `.file` | `.fileURL` | None | Direct file reference |

### Drag Affordances

- SwiftUI `.draggable()` automatically shows drag preview (default: snapshot of view)
- Custom drag preview may be needed for better UX (e.g., show content type icon + truncated text)
- If using AppKit: must manually create drag image with `NSImage(size:flipped:drawingHandler:)`

## Open Questions

None. All key decisions made during discussion phase.

## References

- **Existing code**:
  - `Pastel/Services/PasteService.swift` - pause/resume monitoring, content representation logic
  - `Pastel/Services/ContentRepresentationService.swift` - determines which representation to use
  - `Pastel/Views/Panel/ClipboardCardView.swift` - card view where `.draggable()` will be added
  - `Pastel/Controllers/PanelController.swift` - NSPanel configuration, dismissal logic

- **Related phases**:
  - Phase 3: Paste-Back (established monitor pause pattern)
  - Phase 13: Paste as Plain Text (content representation logic)

- **Apple documentation**:
  - [Transferable protocol](https://developer.apple.com/documentation/coretransferable/transferable) - SwiftUI drag-and-drop
  - [NSItemProvider](https://developer.apple.com/documentation/foundation/nsitemprovider) - UTType registration
  - [NSFilePromiseProvider](https://developer.apple.com/documentation/appkit/nsfilepromiseprovider) - large file drag
  - [NSDraggingSession](https://developer.apple.com/documentation/appkit/nsdraggingsession) - AppKit fallback

## Planning Guidance

### Suggested Plan Structure

**Plan 01: Feasibility Test + Text Drag**
- Add `.draggable()` to ClipboardCardView for text items only
- Test drag from NSPanel to TextEdit
- If successful: Document approach, proceed to Plan 02
- If failed: Document failure, create Plan 02 with AppKit fallback

**Plan 02 (if SwiftUI works): Image, URL, File Drag**
- Extend `.draggable()` to image, URL, file content types
- Implement NSFilePromiseProvider for images
- Test drag to Finder, Preview, Safari

**Plan 03 (if SwiftUI works): Panel State + Self-Capture**
- Add `isDragging` state tracking
- Wire drag start/end to panel dismissal logic
- Wire drag start/end to ClipboardMonitor pause/resume
- End-to-end testing

**Alternative Plan Structure (if SwiftUI fails)**:
- Plan 02: AppKit NSView drag infrastructure for all content types
- Plan 03: Same as above (panel state + self-capture)

### Key Files to Modify

- `Pastel/Views/Panel/ClipboardCardView.swift` - add `.draggable()` or custom drag handling
- `Pastel/Controllers/PanelController.swift` - track `isDragging`, modify dismissal logic
- `Pastel/Services/ClipboardMonitor.swift` - may need to expose `isPaused` state for debugging
- `Pastel/Services/PasteService.swift` - potentially extract content-to-NSItemProvider logic for reuse

### Testing Checkpoints

Each plan should have checkpoint to verify:
1. Drag gesture starts (cursor changes, drag preview appears)
2. Receiving app accepts drop (content appears)
3. Panel stays visible during drag (does not dismiss)
4. No duplicate entry created in history

### Edge Cases to Handle

- Image file deleted from disk (fall back to thumbnail or show error)
- Concealed items (should they be draggable? Probably yes, since they're in history)
- Items with no content (empty string, null image path)
- Drag cancelled mid-session (cursor returns, panel behavior restores)
- Multiple items selected (out of scope for Phase 16, but consider architecture)

---

**Context captured**: 2026-02-09
**Discussion participants**: User + Claude
**Next step**: /gsd:plan-phase 16
