import SwiftUI
import SwiftData

/// Responsive card grid for the History tab in Settings.
///
/// Follows the same init-based @Query pattern as FilteredCardListView but uses
/// LazyVGrid instead of LazyVStack, and adds multi-selection via Cmd-click toggle,
/// Shift-click range, Cmd+A select all, and Escape deselect.
///
/// Label filtering is done in-memory (OR logic) because SwiftData #Predicate
/// cannot use .contains() on to-many relationships.
///
/// Context menus are selection-aware: right-clicking a selected item shows bulk
/// actions for all selected items; right-clicking an unselected item selects it
/// and shows single-item actions.
struct HistoryGridView: View {

    @Query private var items: [ClipboardItem]
    @Environment(\.modelContext) private var modelContext

    // Multi-selection state (owned by parent HistoryBrowserView)
    @Binding var selectedIDs: Set<PersistentIdentifier>
    // Resolved items exposed to parent for bulk operations
    @Binding var resolvedItems: [ClipboardItem]
    @State private var lastClickedID: PersistentIdentifier? = nil
    @State private var memoizedFilteredItems: [ClipboardItem] = []
    @State private var displayLimit: Int = 100
    private let pageSize: Int = 100

    // Labels passed from parent for ClipboardCardView context menus
    let allLabels: [Label]
    // Label filtering (in-memory, same reason as FilteredCardListView)
    private let selectedLabelIDs: Set<PersistentIdentifier>

    // Bulk action closures (provided by parent HistoryBrowserView)
    private let onBulkCopy: () -> Void
    private let onBulkPaste: () -> Void
    private let onRequestBulkDelete: () -> Void
    private let onPastePlainText: (ClipboardItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 12)
    ]

    init(searchText: String, selectedLabelIDs: Set<PersistentIdentifier>, allLabels: [Label] = [], selectedIDs: Binding<Set<PersistentIdentifier>>, resolvedItems: Binding<[ClipboardItem]>, onBulkCopy: @escaping () -> Void = {}, onBulkPaste: @escaping () -> Void = {}, onRequestBulkDelete: @escaping () -> Void = {}, onPastePlainText: @escaping (ClipboardItem) -> Void = { _ in }) {
        self.allLabels = allLabels
        self.selectedLabelIDs = selectedLabelIDs
        _selectedIDs = selectedIDs
        _resolvedItems = resolvedItems
        self.onBulkCopy = onBulkCopy
        self.onBulkPaste = onBulkPaste
        self.onRequestBulkDelete = onRequestBulkDelete
        self.onPastePlainText = onPastePlainText

        // Text-only predicate. Label filtering AND sync filtering are done in-memory
        // via filteredItems because:
        // 1. #Predicate cannot use .contains() on to-many relationships (labels)
        // 2. Combining search + sync conditions in a single #Predicate causes
        //    Swift type-checker timeout ("unable to type-check this expression")
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

        _items = Query(filter: predicate, sort: \ClipboardItem.timestamp, order: .reverse)
    }

    /// Items visible after pagination (first `displayLimit` of memoizedFilteredItems).
    private var visibleItems: [ClipboardItem] {
        Array(memoizedFilteredItems.prefix(displayLimit))
    }

    /// Compact signature for label metadata that affects labelKey filtering.
    private var labelFilterSignature: String {
        allLabels
            .map { "\($0.persistentModelID)|\($0.stableID)" }
            .joined(separator: ",")
    }

    /// Compute items filtered by sync rules and selected labels (in-memory).
    ///
    /// Sync filtering (applied first):
    /// - Concealed items excluded (passwords never appear in browseable history)
    /// - Remote image/file items excluded (no displayable content on receiving device)
    /// - Items with empty originDeviceID (pre-v1.5 legacy) treated as local
    ///
    /// Label filtering (applied second, OR logic):
    /// If no labels selected, returns all sync-filtered items. Otherwise checks
    /// each item's denormalized `labelKey` string — a fast column read that does
    /// NOT fault the labels relationship.
    private func computeFilteredItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        let localDeviceID = DeviceIdentifier.current
        let syncFiltered = items.filter { item in
            // Exclude concealed items (passwords should never appear in browseable history)
            guard !item.isConcealed else { return false }
            // Allow local items and pre-v1.5 legacy items (empty originDeviceID)
            let isLocal = item.originDeviceID == localDeviceID || item.originDeviceID.isEmpty
            if isLocal { return true }
            // Remote items: allow only if NOT image/file (those have no displayable content)
            return item.type != .image && item.type != .file
        }
        guard !selectedLabelIDs.isEmpty else { return syncFiltered }

        let knownStableIDs = Set(allLabels.map(\.stableID).filter { !$0.isEmpty })
        return syncFiltered.filter { item in
            itemMatchesSelectedLabels(
                item,
                selectedLabelIDs: selectedLabelIDs,
                allLabels: allLabels,
                knownStableIDs: knownStableIDs
            )
        }
    }

    var body: some View {
        Group {
            if memoizedFilteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No items found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                            let isInSelection = selectedIDs.contains(item.persistentModelID)
                            ClipboardCardView(
                                item: item,
                                isSelected: isInSelection,
                                allLabels: allLabels,
                                hideContextMenu: true
                            )
                            .onTapGesture {
                                handleTap(item: item, index: index)
                            }
                            .onAppear {
                                if index >= displayLimit - 10 && displayLimit < memoizedFilteredItems.count {
                                    displayLimit += pageSize
                                }
                            }
                            .contextMenu {
                                if isInSelection && selectedIDs.count > 1 {
                                    // Bulk actions for multi-selection
                                    Button("Copy \(selectedIDs.count) Items") {
                                        onBulkCopy()
                                    }
                                    Button("Paste \(selectedIDs.count) Items") {
                                        onBulkPaste()
                                    }
                                    Divider()
                                    Button("Delete \(selectedIDs.count) Items", role: .destructive) {
                                        onRequestBulkDelete()
                                    }
                                } else {
                                    // Single-item actions (auto-selects this item)
                                    Button("Copy") {
                                        selectedIDs = [item.persistentModelID]
                                        onBulkCopy()
                                    }
                                    Button("Paste") {
                                        selectedIDs = [item.persistentModelID]
                                        onBulkPaste()
                                    }
                                    Button("Paste as Plain Text") {
                                        onPastePlainText(item)
                                    }
                                    Divider()
                                    Button("Edit...") {
                                        EditItemWindow.show(for: item, modelContainer: modelContext.container)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        selectedIDs = [item.persistentModelID]
                                        onRequestBulkDelete()
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(characters: .init(charactersIn: "aA")) { keyPress in
            // Cmd+A: select all filtered items (not just visible, for bulk operations)
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            selectedIDs = Set(memoizedFilteredItems.map(\.persistentModelID))
            return .handled
        }
        .onKeyPress(.escape) {
            // Escape: deselect all
            selectedIDs.removeAll()
            lastClickedID = nil
            return .handled
        }
        .onAppear {
            displayLimit = pageSize
            memoizedFilteredItems = computeFilteredItems(from: items)
            resolvedItems = memoizedFilteredItems
        }
        .onChange(of: items) { _, newItems in
            memoizedFilteredItems = computeFilteredItems(from: newItems)
            resolvedItems = memoizedFilteredItems
        }
        .onChange(of: selectedLabelIDs) { _, _ in
            // Re-run the in-memory label post-filter without rebuilding @Query or recreating
            // the view. Label filtering is not part of the predicate (see init), so the
            // existing `items` array is still correct — only the filter output changes.
            displayLimit = pageSize
            memoizedFilteredItems = computeFilteredItems(from: items)
            resolvedItems = memoizedFilteredItems
        }
        .onChange(of: labelFilterSignature) { _, _ in
            memoizedFilteredItems = computeFilteredItems(from: items)
            resolvedItems = memoizedFilteredItems
        }
    }

    // MARK: - Multi-Selection

    private func handleTap(item: ClipboardItem, index: Int) {
        let id = item.persistentModelID
        let modifiers = NSEvent.modifierFlags

        if modifiers.contains(.command) {
            // Cmd-click: toggle individual selection
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
            lastClickedID = id
        } else if modifiers.contains(.shift), let anchorID = lastClickedID {
            // Shift-click: range selection from anchor to clicked item
            guard let anchorIndex = visibleItems.firstIndex(where: { $0.persistentModelID == anchorID }) else {
                // Anchor no longer in visible results, treat as single select
                selectedIDs = [id]
                lastClickedID = id
                return
            }
            let range = min(anchorIndex, index)...max(anchorIndex, index)
            for i in range {
                selectedIDs.insert(visibleItems[i].persistentModelID)
            }
            // Do NOT update lastClickedID on shift-click (anchor stays)
        } else {
            // Plain click: single selection (clears previous)
            selectedIDs = [id]
            lastClickedID = id
        }
    }
}
