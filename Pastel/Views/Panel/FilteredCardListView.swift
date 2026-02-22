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

    let allLabels: [Label]
    @Binding var selectedIndex: Int?
    var isShiftHeld: Bool
    /// Incremented each time the panel is shown; triggers filteredItems recomputation
    /// without view recreation (preserves scroll position across dismiss/reopen).
    var showCount: Int
    var onPaste: (ClipboardItem) -> Void
    var onPastePlainText: (ClipboardItem) -> Void
    var onTypeToSearch: ((Character) -> Void)?
    var onDragStarted: (() -> Void)?
    /// Callback for Cmd+Left/Right label cycling. Direction: -1 = previous, +1 = next.
    var onCycleLabelFilter: ((Int) -> Void)?

    /// Selected label IDs for in-memory post-filtering (OR logic).
    private let selectedLabelIDs: Set<PersistentIdentifier>

    /// Items visible after pagination (first `displayLimit` of filteredItems).
    private var visibleItems: [ClipboardItem] {
        Array(filteredItems.prefix(displayLimit))
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
    /// If no labels selected, returns all sync-filtered items.
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
        guard !selectedLabelIDs.isEmpty else { return syncFiltered }
        return syncFiltered.filter { item in
            item.safeLabels.contains { label in
                selectedLabelIDs.contains(label.persistentModelID)
            }
        }
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
        onTypeToSearch: ((Character) -> Void)? = nil,
        onDragStarted: (() -> Void)? = nil,
        onCycleLabelFilter: ((Int) -> Void)? = nil
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
        self.onTypeToSearch = onTypeToSearch
        self.onDragStarted = onDragStarted
        self.onCycleLabelFilter = onCycleLabelFilter
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
                        if let newValue {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(newValue, anchor: .center)
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
                        if let newValue {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(newValue, anchor: .center)
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
            displayLimit = pageSize
            filteredItems = computeFilteredItems(from: items)
            installKeyboardMonitor()
        }
        .onChange(of: items) { _, newItems in
            filteredItems = computeFilteredItems(from: newItems)
        }
        .onChange(of: appState.deletionManager.softDeletedIDs) { _, _ in
            // Recompute after soft-delete or undo without view recreation (preserves scroll position).
            filteredItems = computeFilteredItems(from: items)
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
            isSelected: selectedIndex == index,
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
            if NSEvent.modifierFlags.contains(.shift) {
                onPastePlainText(item)
            } else {
                onPaste(item)
            }
        }
        .onTapGesture(count: 1) {
            selectedIndex = index
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
        .id(index)
    }

    /// Install NSEvent local monitor for keyboard handling (arrows, Enter, Cmd+digit activation).
    /// NSEvent monitors operate at the AppKit level and are immune to SwiftUI re-render
    /// interruptions and focus issues, enabling reliable keyboard interaction in NSPanel contexts.
    private func installKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 123: // Left arrow
                if event.modifierFlags.contains(.command) {
                    onCycleLabelFilter?(-1)
                } else if isHorizontal {
                    moveSelection(by: -1)
                } else {
                    return event // pass through in vertical mode
                }
                return nil // consumed
            case 124: // Right arrow
                if event.modifierFlags.contains(.command) {
                    onCycleLabelFilter?(1)
                } else if isHorizontal {
                    moveSelection(by: 1)
                } else {
                    return event
                }
                return nil
            case 125: // Down arrow
                if !isHorizontal {
                    moveSelection(by: 1)
                    return nil
                }
                return event
            case 126: // Up arrow
                if !isHorizontal {
                    moveSelection(by: -1)
                    return nil
                }
                return event
            case 0x24, 0x4C: // Return, Keypad Enter
                if let index = selectedIndex, index < visibleItems.count {
                    if event.modifierFlags.contains(.shift) {
                        onPastePlainText(visibleItems[index])
                    } else {
                        onPaste(visibleItems[index])
                    }
                    return nil // consumed
                }
                return event // no valid selection, pass through
            case 0x06: // kVK_ANSI_Z — Cmd+Z undo last deletion
                if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        appState.deletionManager.undo(in: modelContext)
                    }
                    return nil // consumed
                }
                return event
            default:
                // Cmd+1-9 / Cmd+Shift+1-9 quick paste activation
                if event.modifierFlags.contains(.command),
                   let digit = Self.digitKeyCodeMap[event.keyCode] {
                    guard quickPasteEnabled else { return event }
                    let index = digit - 1
                    guard index < visibleItems.count else { return event }
                    if event.modifierFlags.contains(.shift) {
                        onPastePlainText(visibleItems[index])
                    } else {
                        onPaste(visibleItems[index])
                    }
                    return nil // consumed
                }
                return event // pass through all other keys
            }
        }
    }

    private func moveSelection(by offset: Int) {
        guard !visibleItems.isEmpty else { return }
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
}
