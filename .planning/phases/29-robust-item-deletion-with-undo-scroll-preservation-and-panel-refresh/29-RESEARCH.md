# Phase 29: Robust Item Deletion with Undo, Scroll Preservation, and Panel Refresh - Research

**Researched:** 2026-02-21
**Domain:** SwiftUI list management, undo infrastructure, macOS system sounds, SwiftData deletion
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Undo behavior:**
- Undo triggered via **Cmd+Z** only -- no toast/snackbar UI
- **Soft-delete**: item is hidden immediately but kept in DB; permanently deleted when panel closes or a new action occurs
- **Single-level undo** -- only the most recent deletion can be undone
- Restored item appears at **top of list**, not original position

**Deletion feedback:**
- **No confirmation** for single item deletion -- undo via Cmd+Z is the safety net
- **Keep confirmation dialog** for bulk deletion (2+ items) with count
- Delete animation: **slide left + collapse gap** (item slides off to the left, then gap closes)
- Animation duration: **quick (~0.2s)** -- fast and snappy
- Play **macOS system trash sound** on deletion
- Delete via **context menu + keyboard only** -- no swipe-to-delete gesture
- After deleting selected item, selection moves to **next item (below)**

**Panel refresh:**
- No item count displayed -- no count update needed
- When last item in a filtered view is deleted: **show empty state** (stay on current filter)
- Settings history tab: **refresh on focus** -- not real-time sync with panel deletions
- Image cleanup: **deferred** -- mark for background cleanup, keep deletion fast
- **Cancel image cleanup on undo** -- if user undoes before sweep runs, images are preserved

**Scroll preservation:**
- After deletion: **anchor to scroll offset** -- maintain exact pixel position, items shift up to fill gap
- Deleting last visible item at bottom: **scroll up to fill** -- no empty whitespace at bottom
- Panel open/close: **remember scroll position** across dismiss/reopen cycles

### Claude's Discretion

- Rapid deletion settling behavior (stable per-delete vs batch settle)
- Soft-delete implementation details (DB flag vs in-memory tracking)
- Exact slide-left animation curve and gap collapse timing
- Background image cleanup sweep interval

### Deferred Ideas (OUT OF SCOPE)

None -- discussion stayed within phase scope
</user_constraints>

## Summary

This phase transforms the existing hard-delete-and-recreate-view pattern into a robust deletion pipeline with undo support, animations, sound feedback, scroll preservation, and reliable panel refresh. The current codebase performs immediate SwiftData deletion with `deleteClipboardItemWithCleanup()` from `ClipboardCardView.deleteItem()`, then uses a `deletionCount` counter to trigger `FilteredCardListView` recomputation. There are two key problems to solve: (1) the deletion is permanent with no undo path, and (2) the view `.id()` approach for refresh causes full view recreation that resets scroll position.

The research found that an **in-memory soft-delete manager** (not a DB flag) is the cleanest approach for single-level undo. The item is hidden from the filtered items array immediately but its SwiftData model is not deleted until the panel closes or a subsequent action commits it. The macOS "move to trash" system sound is accessible at a known file path and playable via `NSSound`. The Cmd+Z handler fits naturally into the existing `NSEvent.addLocalMonitorForEvents` pattern already used for keyboard navigation. Scroll preservation requires switching from the current `ScrollViewReader` approach to the newer `ScrollPosition` API (macOS 14+, which is the project's deployment target).

**Primary recommendation:** Build a `DeletionManager` (an `@Observable @MainActor` class) that owns the soft-delete buffer, undo logic, sound playback, and deferred image cleanup. FilteredCardListView excludes soft-deleted item IDs from its `computeFilteredItems`. Cmd+Z is intercepted by the existing NSEvent local key monitor. The `ScrollPosition` API with identity-based tracking preserves scroll position automatically when items are removed.

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| SwiftUI ScrollPosition | macOS 14+ | Identity-based scroll position tracking and preservation | Apple's recommended scroll position API; maintains position stability when data changes |
| NSSound | AppKit | Play macOS system "move to trash" sound | Lightweight, no extra frameworks; reads AIFF from system path |
| NSEvent local monitor | AppKit | Intercept Cmd+Z for undo in NSPanel context | Already used in codebase for Enter, Cmd+digits, Escape; proven reliable in NSPanel |
| SwiftUI withAnimation + transition | SwiftUI | Slide-left removal animation with gap collapse | Built-in; `.transition(.move(edge: .leading))` + `.animation()` handles both slide-out and gap-close |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| DispatchWorkItem | Foundation | Cancellable delayed image cleanup after soft-delete | Deferred disk I/O that can be cancelled on undo |
| @Observable class | Swift 5.9+ | DeletionManager holding soft-delete state, undo buffer, cleanup timers | Central coordination point for all deletion concerns |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| In-memory soft-delete | SwiftData `isDeleted` DB flag | DB flag adds schema complexity, CloudKit migration risk, query predicate changes everywhere; in-memory is simpler for single-level undo |
| In-memory soft-delete | SwiftData UndoManager (`modelContext.undoManager`) | Built-in undo for SwiftData exists but redo with deletions is reported "flaky" (HackingWithSwift); requires `isUndoEnabled: true` on ModelContainer which changes behavior globally; soft-delete gives full control |
| NSSound for trash sound | AVAudioPlayer / AudioToolbox | Heavier frameworks; NSSound is sufficient for a single AIFF file |
| ScrollPosition API | ScrollViewReader + proxy.scrollTo | ScrollViewReader cannot preserve offset -- only scroll-to-ID; ScrollPosition tracks position automatically |

## Architecture Patterns

### Recommended Project Structure
```
Pastel/
├── Services/
│   └── DeletionManager.swift    # NEW: soft-delete buffer, undo, sound, deferred cleanup
├── Views/Panel/
│   ├── FilteredCardListView.swift  # MODIFIED: exclude soft-deleted IDs, ScrollPosition, animations
│   ├── PanelContentView.swift      # MODIFIED: pass DeletionManager, remove deletionCount from .id()
│   ├── PanelController.swift       # MODIFIED: Cmd+Z in key monitor, commit soft-deletes on hide()
│   └── ClipboardCardView.swift     # MODIFIED: call DeletionManager.softDelete() instead of hard delete
└── App/
    └── AppState.swift              # MODIFIED: own DeletionManager, wire into panel lifecycle
```

### Pattern 1: DeletionManager (In-Memory Soft-Delete with Undo)
**What:** An `@Observable @MainActor` class that:
- Holds a single `pendingDeletion: (item: ClipboardItem, imagePaths: ImagePaths)?` struct
- On `softDelete(item)`: stores item reference + image paths, hides from list, starts deferred cleanup timer, plays sound
- On `undo()`: restores item to visible, cancels cleanup timer
- On `commitPendingDeletion()`: calls `deleteClipboardItemWithCleanup` + save for real
- Commits are triggered by: panel hide, new soft-delete (replaces previous), or app termination

**When to use:** Any deletion action in the panel (context menu, keyboard Delete key)

**Example:**
```swift
@MainActor @Observable
final class DeletionManager {
    /// The currently soft-deleted item (single-level undo buffer)
    private(set) var pendingDeletion: SoftDeleteEntry?
    /// IDs to exclude from display (hidden but not yet committed)
    var softDeletedIDs: Set<PersistentIdentifier> {
        if let entry = pendingDeletion { return [entry.itemID] }
        return []
    }

    private var cleanupWorkItem: DispatchWorkItem?
    private let trashSound: NSSound?

    struct SoftDeleteEntry {
        let itemID: PersistentIdentifier
        let imagePath: String?
        let thumbnailPath: String?
        let urlFaviconPath: String?
        let urlPreviewImagePath: String?
    }

    init() {
        let soundURL = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/move to trash.aif")
        trashSound = NSSound(contentsOf: soundURL, byReference: true)
    }

    func softDelete(_ item: ClipboardItem) {
        // Commit any previous pending deletion first
        commitPendingDeletion(in: /* modelContext */)

        pendingDeletion = SoftDeleteEntry(
            itemID: item.persistentModelID,
            imagePath: item.imagePath,
            thumbnailPath: item.thumbnailPath,
            urlFaviconPath: item.urlFaviconPath,
            urlPreviewImagePath: item.urlPreviewImagePath
        )
        trashSound?.play()
        scheduleImageCleanup()
    }

    func undo() {
        cleanupWorkItem?.cancel()
        pendingDeletion = nil
    }

    func commitPendingDeletion(in modelContext: ModelContext) {
        guard let entry = pendingDeletion else { return }
        // Fetch and hard-delete the item
        if let item = try? modelContext.model(for: entry.itemID) as? ClipboardItem {
            deleteClipboardItemWithCleanup(item, from: modelContext)
            saveWithLogging(modelContext, operation: "commit soft-delete")
        }
        pendingDeletion = nil
    }
}
```

### Pattern 2: Scroll Position Preservation via ScrollPosition API
**What:** Replace `ScrollViewReader { proxy in ScrollView { ... } }` with `ScrollView { ... }.scrollPosition($position)` using identity-based tracking. SwiftUI automatically keeps the tracked view visible when items are removed.

**When to use:** Both vertical (LazyVStack) and horizontal (LazyHStack) panel layouts.

**Example:**
```swift
// In FilteredCardListView
@State private var scrollPosition = ScrollPosition(idType: Int.self)

// Vertical layout
ScrollView {
    LazyVStack(spacing: PanelLayout.cardSpacing) {
        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
            if !deletionManager.softDeletedIDs.contains(item.persistentModelID) {
                cardView(for: item, at: index)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
    }
    .scrollTargetLayout()
}
.scrollPosition($scrollPosition)
.animation(.easeInOut(duration: 0.2), value: deletionManager.softDeletedIDs)
```

### Pattern 3: Cmd+Z via NSEvent Local Monitor
**What:** Add Cmd+Z handling to the existing `installKeyboardMonitor()` in FilteredCardListView (or PanelController's local key monitor). The project already intercepts keyDown events this way for Enter, Cmd+digits, and arrow keys.

**Example:**
```swift
// In the existing keyDown monitor (FilteredCardListView.installKeyboardMonitor or PanelController)
case 0x06: // kVK_ANSI_Z
    if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) {
        deletionManager.undo()
        return nil // consumed
    }
    return event
```

### Pattern 4: Panel Scroll Position Memory (Across Dismiss/Reopen)
**What:** Save and restore the scroll position when the panel is hidden/shown. The `ScrollPosition` API supports reading the current position. Store it on `PanelActions` or `DeletionManager` before hide, restore on show.

**When to use:** Panel toggle (Cmd+Shift+V).

**Example:**
```swift
// In PanelActions or a dedicated PanelState
var savedScrollPosition: ScrollPosition?

// Before hide:
savedScrollPosition = currentScrollPosition

// On show (in FilteredCardListView.onAppear):
if let saved = panelActions.savedScrollPosition {
    scrollPosition = saved
}
```

### Anti-Patterns to Avoid
- **Including deletionCount in `.id()` modifier:** This causes full view recreation, destroying scroll position and animation state. The current uncommitted fix correctly removes it from `.id()` and uses `onChange(of: deletionCount)` instead. Phase 29 should build on this pattern.
- **Using SwiftData ModelContext.undoManager for deletion undo:** Reported "flaky" with redo of deletions. Requires `isUndoEnabled: true` on ModelContainer which has global side effects. Custom single-level undo is simpler and more predictable.
- **Deleting image files synchronously during soft-delete:** Blocks the main thread and prevents undo. Image cleanup must be deferred and cancellable.
- **Animating with `.id()` changes:** When the view ID changes, SwiftUI creates a new view instance -- transitions and animations on the old view are lost. Use conditional rendering or data filtering instead.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Scroll position tracking | Manual offset tracking via GeometryReader | `ScrollPosition` API (macOS 14+) | Handles edge cases (content size changes, item removal) automatically; Apple-recommended |
| System sound playback | AudioToolbox/AVAudioPlayer setup | `NSSound(contentsOf:byReference:)` | Single-line load, `.play()` to fire; perfect for one-shot sound effects |
| Slide-left removal animation | Manual offset animation + timer-based removal | SwiftUI `.transition(.move(edge: .leading))` with `withAnimation` | Handles insertion/removal animations, gap collapse is automatic via layout engine |
| Cancellable delayed work | Custom Timer + boolean flag | `DispatchWorkItem` with `.cancel()` | Clean cancellation semantics; no retained state issues |

**Key insight:** SwiftUI's animation system handles the "slide left then collapse gap" pattern natively when items are removed from a `ForEach` with proper `.transition()` modifiers. The gap collapse happens automatically as `LazyVStack`/`LazyHStack` reflows. No manual frame calculations needed.

## Common Pitfalls

### Pitfall 1: View Recreation vs. Data Mutation for Refresh
**What goes wrong:** Including mutable counters (like `deletionCount`) in the `.id()` modifier of FilteredCardListView causes SwiftUI to destroy and recreate the entire view on every deletion. This resets scroll position, keyboard focus, animation state, and the NSEvent monitor.
**Why it happens:** SwiftUI treats `.id()` changes as "this is a different view" and performs full teardown + setup.
**How to avoid:** Never include deletion-related state in `.id()`. Pass `deletionCount` as a regular parameter and use `.onChange(of:)` to trigger in-place recomputation of filtered items. The uncommitted changes in the working tree already implement this pattern -- build upon it.
**Warning signs:** Scroll jumping to top after delete; keyboard focus lost after delete; NSEvent monitor reinstalled (visible in logs).

### Pitfall 2: NSSound Playback Blocking
**What goes wrong:** `NSSound.play()` is asynchronous and returns immediately, but creating the NSSound object from a file URL can be slow on first load.
**Why it happens:** Disk I/O to read the AIFF file.
**How to avoid:** Create the NSSound instance once in `DeletionManager.init()` using `byReference: true` (loads lazily). Cache the instance. Subsequent `.play()` calls are essentially free.
**Warning signs:** Slight delay on first deletion; no sound issues after that.

### Pitfall 3: Soft-Delete Item Leaking into Display
**What goes wrong:** After soft-deleting an item, it still appears in the list because `computeFilteredItems` does not exclude it.
**Why it happens:** The item is still in SwiftData (not deleted yet), so `@Query` returns it. The in-memory filter must explicitly check `softDeletedIDs`.
**How to avoid:** `computeFilteredItems` must filter out `deletionManager.softDeletedIDs` at the top of the pipeline, before sync/label filtering.
**Warning signs:** Deleted item briefly reappears; item flashes then disappears.

### Pitfall 4: Undo After Panel Close
**What goes wrong:** User deletes item, panel closes (committing the deletion permanently), then tries Cmd+Z -- nothing happens or wrong item is affected.
**Why it happens:** Panel hide triggers `commitPendingDeletion()`, clearing the undo buffer.
**How to avoid:** This is the correct behavior per user decision ("permanently deleted when panel closes"). Document clearly that undo only works while the panel is open. The Cmd+Z monitor is only active when the panel is open (installed in `installKeyboardMonitor`, removed in `onDisappear`).
**Warning signs:** None -- this is intentional behavior.

### Pitfall 5: Scroll Position Loss on FilteredCardListView Recreation
**What goes wrong:** When the `.id()` on `FilteredCardListView` changes (e.g., search text changes, label filter changes), SwiftUI recreates the view and scroll position resets to top.
**Why it happens:** View identity change = new view = new scroll state.
**How to avoid:** For deletions, never change the `.id()`. For filter changes, this is acceptable (user expects to see new results from the top). For panel dismiss/reopen, save the `ScrollPosition` before hide and restore on show.
**Warning signs:** Scroll jumps to top when switching label filters -- acceptable. Scroll jumps to top after deletion -- not acceptable (bug).

### Pitfall 6: Animation Interference with LazyVStack Recycling
**What goes wrong:** Transition animations on items in a LazyVStack may not play if the item is off-screen (recycled).
**Why it happens:** LazyVStack only renders visible items. If a deleted item is off-screen, its removal transition never plays.
**How to avoid:** Only animate deletion of on-screen items. For off-screen items, skip the animation -- the user cannot see them anyway. The `withAnimation` block naturally handles this.
**Warning signs:** No visible issue -- off-screen deletions are invisible to the user.

### Pitfall 7: Race Between Undo and Image Cleanup
**What goes wrong:** Background image cleanup runs before user presses Cmd+Z, deleting files that the restored item needs.
**Why it happens:** Deferred cleanup timer fires before undo.
**How to avoid:** Use `DispatchWorkItem` for image cleanup with a generous delay (e.g., 5-10 seconds). Cancel the work item in `undo()`. Per user decision: "Cancel image cleanup on undo -- if user undoes before sweep runs, images are preserved."
**Warning signs:** Restored image item shows broken thumbnail after undo.

## Code Examples

### Playing the macOS "Move to Trash" Sound
```swift
// Source: Verified on local macOS system -- file exists at this path
// Path: /System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/move to trash.aif

import AppKit

// Load once, reuse. byReference: true avoids copying file into memory.
let trashSoundURL = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/move to trash.aif")
let trashSound = NSSound(contentsOf: trashSoundURL, byReference: true)

// Play (async, non-blocking, returns immediately)
trashSound?.play()
```

### SwiftUI Slide-Left Removal Transition
```swift
// Source: Apple SwiftUI documentation - Transition
// The .move(edge: .leading) transition slides the view off to the left on removal.
// Combined with .opacity for a polished fade-out during slide.
// Gap collapse happens automatically via LazyVStack reflow.

ForEach(visibleItems, id: \.id) { item in
    cardView(for: item)
        .transition(.asymmetric(
            insertion: .opacity,  // Simple fade-in for undo restore
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
}
// Trigger with:
withAnimation(.easeOut(duration: 0.2)) {
    deletionManager.softDelete(item)
}
```

### Cancellable Deferred Image Cleanup
```swift
// Source: Foundation DispatchWorkItem documentation

private var cleanupWorkItem: DispatchWorkItem?

func scheduleImageCleanup() {
    cleanupWorkItem?.cancel()  // Cancel previous if any

    let workItem = DispatchWorkItem { [weak self] in
        guard let entry = self?.pendingDeletion else { return }
        ImageStorageService.shared.deleteImage(
            imagePath: entry.imagePath,
            thumbnailPath: entry.thumbnailPath
        )
        ImageStorageService.shared.deleteImage(
            imagePath: entry.urlFaviconPath,
            thumbnailPath: entry.urlPreviewImagePath
        )
    }
    cleanupWorkItem = workItem
    // 10-second delay gives user time to undo
    DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
}

func cancelImageCleanup() {
    cleanupWorkItem?.cancel()
    cleanupWorkItem = nil
}
```

### ScrollPosition for Scroll Preservation (macOS 14+)
```swift
// Source: Apple SwiftUI documentation - ScrollPosition
// ScrollPosition with identity tracking maintains position stability
// when content changes (items removed, reordered, etc.)

@State private var scrollPosition = ScrollPosition(idType: Int.self)

ScrollView {
    LazyVStack(spacing: PanelLayout.cardSpacing) {
        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
            cardView(for: item, at: index)
                .id(index)
        }
    }
    .scrollTargetLayout()
}
.scrollPosition($scrollPosition)

// Programmatic scroll (replaces ScrollViewReader proxy.scrollTo):
scrollPosition.scrollTo(id: targetIndex, anchor: .center)
```

### Cmd+Z Interception via NSEvent Monitor
```swift
// Source: Existing codebase pattern (FilteredCardListView.installKeyboardMonitor)
// keyCode 0x06 = kVK_ANSI_Z

// Inside the existing NSEvent.addLocalMonitorForEvents(matching: .keyDown) handler:
case 0x06: // Z key
    if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) {
        // Cmd+Z: undo last deletion
        withAnimation(.easeOut(duration: 0.2)) {
            deletionManager.undo()
        }
        return nil // consumed
    }
    return event
```

### Selection Advancement After Deletion
```swift
// After soft-deleting the selected item, advance selection to next item (below).
// If deleted item was last in list, select new last item.

func handleDeletion(at index: Int) {
    withAnimation(.easeOut(duration: 0.2)) {
        deletionManager.softDelete(visibleItems[index])
    }

    // Recompute visible items after soft-delete
    let newItems = computeVisibleItems()
    if newItems.isEmpty {
        selectedIndex = nil
    } else if index < newItems.count {
        selectedIndex = index  // Same index = next item (shifted up)
    } else {
        selectedIndex = newItems.count - 1  // Was last, select new last
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ScrollViewReader + proxy.scrollTo | ScrollPosition with identity tracking | macOS 14 / iOS 17 (2023) | Automatic position stability; no manual offset tracking needed |
| UndoManager with SwiftData | Custom undo for deletions | Ongoing | SwiftData UndoManager redo is "flaky" with deletions; custom approach more reliable |
| `.animation()` on individual views | `withAnimation {}` wrapping state changes | SwiftUI best practice | Wrapping the state change (not the view) ensures all affected views animate consistently |

**Deprecated/outdated:**
- `ScrollViewReader` for scroll position preservation: Still works for scroll-to but cannot preserve position during item removal. Use `ScrollPosition` instead.
- SwiftData `isUndoEnabled: true` for deletion undo: Works for simple property changes but deletion redo is unreliable. Avoid for this use case.

## Open Questions

1. **ScrollPosition and .id() index stability**
   - What we know: ScrollPosition tracks by the ID passed to `.id()`. Currently, items use their enumeration index as ID (`.id(index)`).
   - What's unclear: When an item is soft-deleted (hidden from the array), all subsequent indices shift. Does ScrollPosition handle this gracefully, or will it scroll to the wrong position?
   - Recommendation: Use the item's `persistentModelID` or `UUID` as the scroll target ID instead of the enumeration index. This decouples scroll identity from array position. Test both approaches during implementation.

2. **Horizontal layout scroll position**
   - What we know: The panel supports both vertical (left/right edge) and horizontal (top/bottom edge) layouts.
   - What's unclear: Whether `ScrollPosition` works identically with `LazyHStack` as with `LazyVStack`.
   - Recommendation: Implement for vertical first, then verify horizontal. The API documentation does not distinguish between axes.

3. **Bulk deletion interaction with single-level undo**
   - What we know: User wants confirmation dialog for bulk delete (2+ items). Single-level undo only undoes the most recent deletion.
   - What's unclear: Should bulk delete be undoable? If 5 items are bulk-deleted, does Cmd+Z restore all 5 or just 1?
   - Recommendation: Bulk deletion with confirmation dialog does NOT need undo (the confirmation IS the safety net). Commit bulk deletions immediately with `deleteClipboardItemWithCleanup`. Only single-item context menu/keyboard deletions use soft-delete + undo.

4. **Panel scroll position memory across edge changes**
   - What we know: Panel edge changes (right -> left) destroy and recreate the panel. User wants scroll position remembered across dismiss/reopen.
   - What's unclear: Whether saved ScrollPosition is valid after edge change (vertical <-> horizontal swap).
   - Recommendation: Only preserve scroll position for same-edge dismiss/reopen. Clear saved position on edge change.

## Sources

### Primary (HIGH confidence)
- Apple SwiftUI ScrollPosition documentation: https://developer.apple.com/documentation/SwiftUI/ScrollPosition - scroll position preservation API, identity tracking, position stability
- Apple SwiftUI Transition documentation: https://developer.apple.com/documentation/SwiftUI/AnyTransition - `.move(edge:)`, `.asymmetric()`, animation patterns
- Apple SwiftData ModelContext documentation: https://developer.apple.com/documentation/swiftdata/modelcontext - delete, rollback, undoManager properties
- Local filesystem verification: `/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/move to trash.aif` -- confirmed readable AIFF file on macOS
- Existing codebase: `FilteredCardListView.swift`, `PanelController.swift`, `ClipboardCardView.swift`, `SwiftDataHelpers.swift` -- current deletion flow, NSEvent monitor patterns, deletionCount mechanism

### Secondary (MEDIUM confidence)
- HackingWithSwift SwiftData undo tutorial: https://www.hackingwithswift.com/quick-start/swiftdata/how-to-add-support-for-undo-and-redo - `isUndoEnabled: true`, redo "flaky" with deletions
- Nil Coalescing blog on UndoManager in SwiftUI: https://nilcoalescing.com/blog/HandlingUndoAndRedoInSwiftUI/ - UndoProvider pattern, registerUndo with target

### Tertiary (LOW confidence)
- macOS system sound paths from community sources (macReports, Apple Community forums) -- verified independently on local system

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all components are Apple frameworks already used in the codebase or verified via official docs
- Architecture: HIGH -- DeletionManager pattern follows existing project conventions (@Observable @MainActor service classes like ClipboardMonitor, SyncMonitor)
- Pitfalls: HIGH -- identified from direct codebase analysis (the view recreation bug was found in actual uncommitted changes) and official documentation
- Animation: MEDIUM -- SwiftUI transitions with LazyVStack are well-documented but edge cases with recycled off-screen items need implementation-time verification
- Scroll preservation: MEDIUM -- ScrollPosition API is documented but its behavior with dynamically filtered data (soft-delete exclusion) needs testing

**Research date:** 2026-02-21
**Valid until:** 2026-03-21 (stable Apple frameworks, no expected breaking changes)
