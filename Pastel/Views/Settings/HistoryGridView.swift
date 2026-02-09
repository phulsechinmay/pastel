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

    init(searchText: String, selectedLabelIDs: Set<PersistentIdentifier>, selectedIDs: Binding<Set<PersistentIdentifier>>, resolvedItems: Binding<[ClipboardItem]>, onBulkCopy: @escaping () -> Void = {}, onBulkPaste: @escaping () -> Void = {}, onRequestBulkDelete: @escaping () -> Void = {}, onPastePlainText: @escaping (ClipboardItem) -> Void = { _ in }) {
        self.selectedLabelIDs = selectedLabelIDs
        _selectedIDs = selectedIDs
        _resolvedItems = resolvedItems
        self.onBulkCopy = onBulkCopy
        self.onBulkPaste = onBulkPaste
        self.onRequestBulkDelete = onRequestBulkDelete
        self.onPastePlainText = onPastePlainText

        let predicate: Predicate<ClipboardItem>
        if !searchText.isEmpty {
            let search = searchText
            predicate = #Predicate<ClipboardItem> { item in
                item.textContent?.localizedStandardContains(search) == true ||
                item.sourceAppName?.localizedStandardContains(search) == true ||
                item.title?.localizedStandardContains(search) == true
            }
        } else {
            predicate = #Predicate<ClipboardItem> { _ in true }
        }

        _items = Query(filter: predicate, sort: \ClipboardItem.timestamp, order: .reverse)
    }

    /// Items filtered by selected labels (in-memory, OR logic).
    /// If no labels selected, returns all items from @Query.
    private var filteredItems: [ClipboardItem] {
        guard !selectedLabelIDs.isEmpty else { return items }
        return items.filter { item in
            item.labels.contains { label in
                selectedLabelIDs.contains(label.persistentModelID)
            }
        }
    }

    var body: some View {
        Group {
            if filteredItems.isEmpty {
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
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            let isInSelection = selectedIDs.contains(item.persistentModelID)
                            ClipboardCardView(
                                item: item,
                                isSelected: isInSelection,
                                hideContextMenu: true
                            )
                            .onTapGesture {
                                handleTap(item: item, index: index)
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
            // Cmd+A: select all visible items
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            selectedIDs = Set(filteredItems.map(\.persistentModelID))
            return .handled
        }
        .onKeyPress(.escape) {
            // Escape: deselect all
            selectedIDs.removeAll()
            lastClickedID = nil
            return .handled
        }
        .onAppear { resolvedItems = filteredItems }
        .onChange(of: items) { _, _ in resolvedItems = filteredItems }
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
            guard let anchorIndex = filteredItems.firstIndex(where: { $0.persistentModelID == anchorID }) else {
                // Anchor no longer in filtered results, treat as single select
                selectedIDs = [id]
                lastClickedID = id
                return
            }
            let range = min(anchorIndex, index)...max(anchorIndex, index)
            for i in range {
                selectedIDs.insert(filteredItems[i].persistentModelID)
            }
            // Do NOT update lastClickedID on shift-click (anchor stays)
        } else {
            // Plain click: single selection (clears previous)
            selectedIDs = [id]
            lastClickedID = id
        }
    }
}
