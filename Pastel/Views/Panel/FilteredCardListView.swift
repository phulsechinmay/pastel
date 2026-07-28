import SwiftUI
import SwiftData
import AppKit

/// Dynamic query child view that constructs its @Query predicate at init time.
///
/// This pattern is required because SwiftData's @Query cannot be changed dynamically
/// after view creation. When the parent passes new searchText or selectedLabelIDs values,
/// SwiftUI recreates this view with a fresh @Query containing the updated predicate.
///
/// Filtering strategy: text search via @Query predicate, label filtering in-memory.
/// #Predicate cannot use .contains() on to-many relationships, so label filtering
/// is done as a post-filter on the query results (OR logic: items with ANY selected label).
///
/// Handles keyboard navigation and mouse interaction (single-click to select,
/// double-click to paste) since it has direct access to the queried items array.
///
/// Adapts layout based on panel edge: vertical edges (left/right) use LazyVStack
/// with up/down arrow navigation; horizontal edges (top/bottom) use LazyHStack
/// with left/right arrow navigation.
struct FilteredCardListView: View {

    @Query private var items: [ClipboardItem]
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue
    @AppStorage("quickPasteEnabled") private var quickPasteEnabled: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var dropTargetIndex: Int? = nil
    @State private var keyMonitor: Any? = nil
    @State private var filteredItems: [ClipboardItem] = []
    @State private var displayLimit: Int = 50
    private let pageSize: Int = 50

    /// Anchor index for Shift+arrow range selection. `nil` means single selection
    /// (only `selectedIndex`). When set, the selection is the contiguous range
    /// between `selectionAnchor` and `selectedIndex` (the cursor).
    @State private var selectionAnchor: Int? = nil

    let allLabels: [Label]
    @Binding var selectedIndex: Int?
    var isShiftHeld: Bool
    /// Incremented each time the panel is shown; triggers filteredItems recomputation
    /// without view recreation (preserves scroll position across dismiss/reopen).
    var showCount: Int
    var onPaste: (ClipboardItem) -> Void
    var onPastePlainText: (ClipboardItem) -> Void
    /// Copy the current selection (one or many items). Single copies full fidelity;
    /// multiple concatenate as newline-joined text. Invoked by Cmd+C and Cmd+Ctrl+digit.
    var onCopy: ([ClipboardItem]) -> Void
    /// Paste the current multi-selection (concatenated text). Invoked by Enter when
    /// more than one item is selected.
    var onPasteItems: ([ClipboardItem]) -> Void
    var onTypeToSearch: ((Character) -> Void)?
    var onDragStarted: (() -> Void)?
    /// Callback for Cmd+Left/Right label cycling. Direction: -1 = previous, +1 = next.
    var onCycleLabelFilter: ((Int) -> Void)?
    /// Callback for Cmd+F to focus the panel's search field.
    var onFocusSearch: (() -> Void)?

    /// Selected label IDs for in-memory post-filtering (OR logic).
    private let selectedLabelIDs: Set<PersistentIdentifier>

    /// Items visible after pagination (first `displayLimit` of filteredItems).
    private var visibleItems: [ClipboardItem] {
        Array(filteredItems.prefix(displayLimit))
    }

    /// Indices (into `visibleItems`) currently selected. A single cursor when
    /// `selectionAnchor` is nil, otherwise the contiguous anchor…cursor range.
    private var selectedIndices: Set<Int> {
        guard let cursor = selectedIndex, cursor < visibleItems.count else { return [] }
        guard let anchor = selectionAnchor, anchor < visibleItems.count else { return [cursor] }
        return Set(min(anchor, cursor)...max(anchor, cursor))
    }

    /// Selected items in display order (top to bottom), for copy/paste.
    private var selectedItems: [ClipboardItem] {
        selectedIndices.sorted().map { visibleItems[$0] }
    }

    /// Compact signature for label metadata that affects labelKey filtering.
    private var labelFilterSignature: String {
        allLabels
            .map { "\($0.persistentModelID)|\($0.stableID)" }
            .joined(separator: ",")
    }

    /// Compute items filtered by soft-delete exclusion, sync rules, and selected labels (in-memory).
    ///
    /// Soft-delete exclusion (applied first):
    /// - Items in DeletionManager's softDeletedIDs are hidden (pending undo or permanent deletion)
    ///
    /// Sync filtering (applied second):
    /// - Concealed items excluded (passwords never appear in browseable panel)
    /// - Remote image/file items excluded (no displayable content on receiving device)
    /// - Items with empty originDeviceID (pre-v1.5 legacy) treated as local
    ///
    /// Label filtering (applied third, OR logic):
    /// If no labels selected, returns all sync-filtered items. Otherwise checks
    /// each item's denormalized `labelKey` string for the selected labels' stable
    /// IDs — a fast column read that does NOT fault the labels relationship.
    ///
    /// Pinned ordering (applied last):
    /// Pinned items are hoisted to the front. Deliberately after label filtering,
    /// so a filtered view never shows a pinned item that doesn't match the filter.
    private func computeFilteredItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        // Exclude soft-deleted items (hidden but not yet permanently deleted, undoable via Cmd+Z)
        let softDeleted = appState.deletionManager.softDeletedIDs
        let nonDeleted = items.filter { !softDeleted.contains($0.persistentModelID) }

        let localDeviceID = DeviceIdentifier.current
        let syncFiltered = nonDeleted.filter { item in
            // Exclude concealed items (passwords should never appear in browseable history)
            guard !item.isConcealed else { return false }
            // Allow local items and pre-v1.5 legacy items (empty originDeviceID)
            let isLocal = item.originDeviceID == localDeviceID || item.originDeviceID.isEmpty
            if isLocal { return true }
            // Remote items: allow only if NOT image/file (those have no displayable content)
            return item.type != .image && item.type != .file
        }
        guard !selectedLabelIDs.isEmpty else { return pinnedFirst(syncFiltered) }

        let knownStableIDs = Set(allLabels.map(\.stableID).filter { !$0.isEmpty })
        let labelFiltered = syncFiltered.filter { item in
            itemMatchesSelectedLabels(
                item,
                selectedLabelIDs: selectedLabelIDs,
                allLabels: allLabels,
                knownStableIDs: knownStableIDs
            )
        }
        return pinnedFirst(labelFiltered)
    }

    /// Hoist pinned items to the front, most-recently-pinned first, preserving the
    /// query's timestamp order for everything else.
    ///
    /// Partitioning here rather than adding a `SortDescriptor` to `@Query` keeps
    /// pinning off the predicate path, so toggling a pin never re-runs the fetch or
    /// recreates the view. It also guarantees pins survive pagination: they sit at
    /// the head of `filteredItems`, which `visibleItems` takes its prefix from.
    private func pinnedFirst(_ items: [ClipboardItem]) -> [ClipboardItem] {
        var pinned: [ClipboardItem] = []
        var unpinned: [ClipboardItem] = []
        for item in items {
            if item.isPinned { pinned.append(item) } else { unpinned.append(item) }
        }
        guard !pinned.isEmpty else { return unpinned }
        pinned.sort { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
        return pinned + unpinned
    }

    /// Static dictionary mapping NSEvent.keyCode to digit value (1-9).
    /// Key codes are non-sequential because they map to physical ANSI key positions.
    private static let digitKeyCodeMap: [UInt16: Int] = [
        0x12: 1,  // kVK_ANSI_1
        0x13: 2,  // kVK_ANSI_2
        0x14: 3,  // kVK_ANSI_3
        0x15: 4,  // kVK_ANSI_4
        0x17: 5,  // kVK_ANSI_5
        0x16: 6,  // kVK_ANSI_6
        0x1A: 7,  // kVK_ANSI_7
        0x1C: 8,  // kVK_ANSI_8
        0x19: 9,  // kVK_ANSI_9
    ]

    /// Whether the panel is on a horizontal edge (top/bottom), requiring horizontal card layout.
    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    init(
        searchText: String,
        selectedLabelIDs: Set<PersistentIdentifier>,
        allLabels: [Label] = [],
        selectedIndex: Binding<Int?>,
        isShiftHeld: Bool = false,
        showCount: Int = 0,
        onPaste: @escaping (ClipboardItem) -> Void,
        onPastePlainText: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping ([ClipboardItem]) -> Void = { _ in },
        onPasteItems: @escaping ([ClipboardItem]) -> Void = { _ in },
        onTypeToSearch: ((Character) -> Void)? = nil,
        onDragStarted: (() -> Void)? = nil,
        onCycleLabelFilter: ((Int) -> Void)? = nil,
        onFocusSearch: (() -> Void)? = nil
    ) {
        self.allLabels = allLabels
        self.selectedLabelIDs = selectedLabelIDs
        self.showCount = showCount

        // Text-only predicate. Label filtering AND sync filtering are done in-memory
        // via filteredItems because:
        // 1. #Predicate cannot use .contains() on to-many relationships (labels)
        // 2. Combining search + sync conditions in a single #Predicate causes
        //    Swift type-checker timeout ("unable to type-check this expression")
        //
        // Sync filtering (applied in filteredItems):
        // - Concealed items excluded (passwords should never appear in browseable history)
        // - Remote image/file items excluded (no displayable content on receiving device)
        // - Items with empty originDeviceID (pre-v1.5 legacy) treated as local
        let predicate: Predicate<ClipboardItem>
        if !searchText.isEmpty {
            let search = searchText
            predicate = #Predicate<ClipboardItem> { item in
                item.textContent?.localizedStandardContains(search) == true ||
                item.sourceAppName?.localizedStandardContains(search) == true ||
                item.title?.localizedStandardContains(search) == true
            }
        } else {
            // Fetch all items (no fetchLimit): required for in-memory label post-filtering.
            // SwiftData #Predicate cannot use .contains() on to-many relationships.
            predicate = #Predicate<ClipboardItem> { _ in true }
        }

        _items = Query(
            filter: predicate,
            sort: \ClipboardItem.timestamp,
            order: .reverse
        )
        _selectedIndex = selectedIndex
        self.isShiftHeld = isShiftHeld
        self.onPaste = onPaste
        self.onPastePlainText = onPastePlainText
        self.onCopy = onCopy
        self.onPasteItems = onPasteItems
        self.onTypeToSearch = onTypeToSearch
        self.onDragStarted = onDragStarted
        self.onCycleLabelFilter = onCycleLabelFilter
        self.onFocusSearch = onFocusSearch
    }

    var body: some View {
        Group {
            if visibleItems.isEmpty {
                    SwiftUI.Label("No matching items", systemImage: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
            } else if isHorizontal {
                // Horizontal layout for top/bottom edges
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: PanelLayout.cardSpacing) {
                            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                                cardView(for: item, at: index)
                                    .frame(width: PanelLayout.horizontalCardWidth, height: PanelLayout.cardMaxHeight)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: selectedIndex) { _, newValue in
                        if let newValue, newValue < visibleItems.count {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(visibleItems[newValue].persistentModelID, anchor: .center)
                            }
                        }
                    }
                }
            } else {
                // Vertical layout for left/right edges
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: PanelLayout.cardSpacing) {
                            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                                cardView(for: item, at: index)
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { _, newValue in
                        if let newValue, newValue < visibleItems.count {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(visibleItems[newValue].persistentModelID, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters)) { keyPress in
            // Don't intercept Cmd/Ctrl modified keys (those go to quick paste or system)
            guard !keyPress.modifiers.contains(.command),
                  !keyPress.modifiers.contains(.control) else { return .ignored }

            // Forward unmodified character presses to search field
            if let char = keyPress.characters.first, let onTypeToSearch {
                onTypeToSearch(char)
                return .handled
            }
            return .ignored
        }
        .onAppear {
            selectedIndex = nil
            selectionAnchor = nil
            displayLimit = pageSize
            filteredItems = computeFilteredItems(from: items)
            installKeyboardMonitor()
        }
        .onChange(of: items) { _, newItems in
            filteredItems = computeFilteredItems(from: newItems)
        }
        .onChange(of: appState.deletionManager.softDeletedIDs) { _, _ in
            // Recompute after soft-delete or undo without view recreation (preserves scroll position).
            // Wrap in withAnimation to ensure the slide-left removal transition plays correctly,
            // since the animation context from the original withAnimation in deleteItem() may not
            // propagate through the onChange handler.
            withAnimation(.easeOut(duration: 0.2)) {
                filteredItems = computeFilteredItems(from: items)
            }
            // A multi-selection range can't survive index shifts from deletion; collapse it.
            selectionAnchor = nil
            // Advance selection after deletion: if deleted item was last, select new last;
            // if in middle, same index now points to next item (shifted up).
            if let idx = selectedIndex, idx >= visibleItems.count {
                selectedIndex = visibleItems.isEmpty ? nil : visibleItems.count - 1
            }
        }
        .onChange(of: showCount) { _, _ in
            // Refresh data on panel reopen without view recreation (preserves scroll position).
            displayLimit = pageSize
            filteredItems = computeFilteredItems(from: items)
            selectedIndex = nil
            selectionAnchor = nil
        }
        .onChange(of: selectedLabelIDs) { _, _ in
            // Re-run the in-memory label post-filter without rebuilding @Query or recreating
            // the view. Label filtering is not part of the predicate (see init), so the
            // existing `items` array is still correct — only the filter output changes.
            displayLimit = pageSize
            filteredItems = computeFilteredItems(from: items)
            selectedIndex = nil
            selectionAnchor = nil
        }
        .onChange(of: labelFilterSignature) { _, _ in
            filteredItems = computeFilteredItems(from: items)
        }
        .onChange(of: appState.pinRevision) { _, _ in
            // Re-partition after a pin toggle. `items` is unchanged (the mutation was
            // to a property of an existing model object), so only the ordering moves.
            withAnimation(.easeInOut(duration: 0.2)) {
                filteredItems = computeFilteredItems(from: items)
            }
            // The item the user pinned just jumped position; a range selection
            // anchored to old indices no longer describes anything meaningful.
            selectionAnchor = nil
            selectedIndex = nil
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    // MARK: - Private Helpers

    /// Shared card rendering used by both horizontal and vertical layouts.
    /// Horizontal-specific `.frame()` and `.clipped()` are applied by the caller.
    @ViewBuilder
    private func cardView(for item: ClipboardItem, at index: Int) -> some View {
        let badge: Int? = quickPasteEnabled && index < 9 ? index + 1 : nil
        ClipboardCardView(
            item: item,
            isSelected: selectedIndices.contains(index),
            allLabels: allLabels,
            badgePosition: badge,
            isDropTarget: dropTargetIndex == index,
            isShiftHeld: isShiftHeld
        )
        .onDrag {
            onDragStarted?()
            return DragItemProviderService.createItemProvider(for: item)
        }
        .onTapGesture(count: 2) {
            pasteLog("[PASTE] origin=double-click index=\(index) shift=\(NSEvent.modifierFlags.contains(.shift))")
            if NSEvent.modifierFlags.contains(.shift) {
                onPastePlainText(item)
            } else {
                onPaste(item)
            }
        }
        .onTapGesture(count: 1) {
            selectionAnchor = nil
            selectedIndex = index
            // Option+click copies the clicked item (full fidelity) without pasting,
            // mirroring the Shift+double-click plain-text paste convention.
            if NSEvent.modifierFlags.contains(.option) {
                pasteLog("[PASTE] origin=option-click index=\(index) COPY")
                onCopy([item])
            }
        }
        .dropDestination(for: String.self) { strings, _ in
            guard let encodedID = strings.first,
                  let labelID = PersistentIdentifier.fromTransferString(encodedID),
                  let label = try? modelContext.model(for: labelID) as? Label else {
                return false
            }
            // Append label if not already assigned
            guard !item.safeLabels.contains(where: {
                $0.persistentModelID == label.persistentModelID
            }) else { return true }
            item.safeLabels.append(label)
            item.refreshLabelKey()
            saveWithLogging(modelContext, operation: "label drop assignment")
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                dropTargetIndex = targeted ? index : nil
            }
        }
        .transition(.asymmetric(
            insertion: .opacity,
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .onAppear {
            if index >= displayLimit - 10 && displayLimit < filteredItems.count {
                displayLimit += pageSize
            }
        }
        .id(item.persistentModelID)
    }

    /// Install NSEvent local monitor for keyboard handling (arrows, Enter, Cmd+digit activation).
    /// NSEvent monitors operate at the AppKit level and are immune to SwiftUI re-render
    /// interruptions and focus issues, enabling reliable keyboard interaction in NSPanel contexts.
    private func installKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // The panel deliberately stays visible behind secondary windows — see the
            // global click monitor in PanelController, which excludes Settings/Edit —
            // so this app-wide monitor is still installed while one of them is focused.
            // Without this guard, arrow keys and Return typed into the snippet editor
            // would drive the card list instead of the text, and be consumed on the way.
            guard event.window is SlidingPanel else { return event }
            switch event.keyCode {
            case 123: // Left arrow
                if event.modifierFlags.contains(.command) {
                    onCycleLabelFilter?(-1)
                } else if isHorizontal {
                    moveOrExtend(by: -1, shift: event.modifierFlags.contains(.shift))
                } else {
                    return event // pass through in vertical mode
                }
                return nil // consumed
            case 124: // Right arrow
                if event.modifierFlags.contains(.command) {
                    onCycleLabelFilter?(1)
                } else if isHorizontal {
                    moveOrExtend(by: 1, shift: event.modifierFlags.contains(.shift))
                } else {
                    return event
                }
                return nil
            case 125: // Down arrow
                if !isHorizontal {
                    moveOrExtend(by: 1, shift: event.modifierFlags.contains(.shift))
                    return nil
                }
                return event
            case 126: // Up arrow
                if !isHorizontal {
                    moveOrExtend(by: -1, shift: event.modifierFlags.contains(.shift))
                    return nil
                }
                return event
            case 0x24, 0x4C: // Return, Keypad Enter
                let selected = selectedItems
                if selected.count > 1 {
                    // Multi-selection: paste all selected items (concatenated text).
                    pasteLog("[PASTE] origin=Return-key multi count=\(selected.count)")
                    onPasteItems(selected)
                    return nil // consumed
                }
                if let index = selectedIndex, index < visibleItems.count {
                    pasteLog("[PASTE] origin=Return-key index=\(index) shift=\(event.modifierFlags.contains(.shift))")
                    if event.modifierFlags.contains(.shift) {
                        onPastePlainText(visibleItems[index])
                    } else {
                        onPaste(visibleItems[index])
                    }
                    return nil // consumed
                }
                return event // no valid selection, pass through
            case 0x08: // kVK_ANSI_C — Cmd+C copies the current selection (1 or many)
                if event.modifierFlags.contains(.command),
                   !event.modifierFlags.contains(.option) {
                    let selected = selectedItems
                    guard !selected.isEmpty else { return event } // let search-field copy through
                    pasteLog("[PASTE] origin=Cmd+C count=\(selected.count)")
                    onCopy(selected)
                    return nil // consumed
                }
                return event
            case 0x06: // kVK_ANSI_Z — Cmd+Z undo last deletion
                if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        appState.deletionManager.undo(in: modelContext)
                    }
                    return nil // consumed
                }
                return event
            case 0x03: // kVK_ANSI_F — Cmd+F focuses the search field
                if event.modifierFlags.contains(.command),
                   !event.modifierFlags.contains(.shift),
                   !event.modifierFlags.contains(.option) {
                    onFocusSearch?()
                    return nil // consumed
                }
                return event
            case 0x2D: // kVK_ANSI_N — Cmd+N authors a new snippet (matches Paste)
                if event.modifierFlags.contains(.command),
                   !event.modifierFlags.contains(.shift),
                   !event.modifierFlags.contains(.option) {
                    EditItemWindow.showNewSnippet(appState: appState, modelContext: modelContext)
                    return nil // consumed
                }
                return event
            case 0x0E: // kVK_ANSI_E — Cmd+E edits the selected item (matches Paste)
                if event.modifierFlags.contains(.command),
                   !event.modifierFlags.contains(.shift),
                   !event.modifierFlags.contains(.option),
                   let index = selectedIndex, index < visibleItems.count {
                    EditItemWindow.show(
                        for: visibleItems[index],
                        modelContainer: modelContext.container
                    )
                    return nil // consumed
                }
                return event
            case 0x33: // kVK_Delete (Backspace) — Cmd+Delete soft-deletes selected item
                if event.modifierFlags.contains(.command) {
                    if let index = selectedIndex, index < visibleItems.count {
                        let item = visibleItems[index]
                        withAnimation(.easeOut(duration: 0.2)) {
                            appState.deletionManager.softDelete(item, in: modelContext)
                        }
                        appState.itemCount -= 1
                        return nil // consumed
                    }
                }
                return event
            default:
                // Cmd+1-9 paste / Cmd+Shift+1-9 paste plain / Cmd+Ctrl+1-9 copy
                if event.modifierFlags.contains(.command),
                   let digit = Self.digitKeyCodeMap[event.keyCode] {
                    guard quickPasteEnabled else {
                        pasteLog("[PASTE] origin=Cmd+digit blocked: quickPasteEnabled=false")
                        return event
                    }
                    let index = digit - 1
                    guard index < visibleItems.count else {
                        pasteLog("[PASTE] origin=Cmd+digit digit=\(digit) but only \(visibleItems.count) items")
                        return event
                    }
                    let target = visibleItems[index]
                    if event.modifierFlags.contains(.control) {
                        // Cmd+Ctrl+digit — copy the Nth item instead of pasting.
                        pasteLog("[PASTE] origin=Cmd+Ctrl+digit digit=\(digit) index=\(index) COPY")
                        onCopy([target])
                    } else if event.modifierFlags.contains(.shift) {
                        pasteLog("[PASTE] origin=Cmd+Shift+digit digit=\(digit) index=\(index)")
                        onPastePlainText(target)
                    } else {
                        pasteLog("[PASTE] origin=Cmd+digit digit=\(digit) index=\(index)")
                        onPaste(target)
                    }
                    return nil // consumed
                }
                return event // pass through all other keys
            }
        }
    }

    /// Route an arrow key to single-move or shift-extend depending on the Shift key.
    private func moveOrExtend(by offset: Int, shift: Bool) {
        if shift {
            extendSelection(by: offset)
        } else {
            moveSelection(by: offset)
        }
    }

    /// Move the cursor by `offset`, collapsing any multi-selection to a single item.
    private func moveSelection(by offset: Int) {
        guard !visibleItems.isEmpty else { return }
        selectionAnchor = nil
        if let current = selectedIndex {
            let newIndex = max(0, min(visibleItems.count - 1, current + offset))
            selectedIndex = newIndex
            // Load more items if navigating near the end
            if newIndex >= displayLimit - 10 && displayLimit < filteredItems.count {
                displayLimit += pageSize
            }
        } else {
            selectedIndex = 0
        }
    }

    /// Extend the contiguous selection by moving the cursor while keeping the anchor.
    /// Establishes the anchor at the current cursor on the first Shift+arrow.
    private func extendSelection(by offset: Int) {
        guard !visibleItems.isEmpty else { return }
        guard let current = selectedIndex else {
            // No cursor yet — start a selection at the first item.
            selectedIndex = 0
            return
        }
        if selectionAnchor == nil {
            selectionAnchor = current
        }
        let newIndex = max(0, min(visibleItems.count - 1, current + offset))
        selectedIndex = newIndex
        if newIndex >= displayLimit - 10 && displayLimit < filteredItems.count {
            displayLimit += pageSize
        }
    }
}
