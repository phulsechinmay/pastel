import SwiftUI
import SwiftData

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
    @State private var dropTargetIndex: Int? = nil

    @Binding var selectedIndex: Int?
    var isShiftHeld: Bool
    var onPaste: (ClipboardItem) -> Void
    var onPastePlainText: (ClipboardItem) -> Void
    var onTypeToSearch: ((Character) -> Void)?

    /// Selected label IDs for in-memory post-filtering (OR logic).
    private let selectedLabelIDs: Set<PersistentIdentifier>

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

    /// Whether the panel is on a horizontal edge (top/bottom), requiring horizontal card layout.
    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    init(
        searchText: String,
        selectedLabelIDs: Set<PersistentIdentifier>,
        selectedIndex: Binding<Int?>,
        isShiftHeld: Bool = false,
        onPaste: @escaping (ClipboardItem) -> Void,
        onPastePlainText: @escaping (ClipboardItem) -> Void,
        onTypeToSearch: ((Character) -> Void)? = nil
    ) {
        self.selectedLabelIDs = selectedLabelIDs

        // Text-only predicate. Label filtering is done in-memory via filteredItems
        // because #Predicate cannot use .contains() on to-many relationships.
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
    }

    var body: some View {
        Group {
            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No matching items")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isHorizontal {
                // Horizontal layout for top/bottom edges
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                let badge: Int? = quickPasteEnabled && index < 9 ? index + 1 : nil
                                ClipboardCardView(
                                    item: item,
                                    isSelected: selectedIndex == index,
                                    badgePosition: badge,
                                    isDropTarget: dropTargetIndex == index,
                                    isShiftHeld: isShiftHeld
                                )
                                .frame(width: 260, height: 195)
                                .clipped()
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
                                    guard !item.labels.contains(where: {
                                        $0.persistentModelID == label.persistentModelID
                                    }) else { return true }
                                    item.labels.append(label)
                                    try? modelContext.save()
                                    return true
                                } isTargeted: { targeted in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        dropTargetIndex = targeted ? index : nil
                                    }
                                }
                                .id(index)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
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
                        LazyVStack(spacing: 8) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                let badge: Int? = quickPasteEnabled && index < 9 ? index + 1 : nil
                                ClipboardCardView(
                                    item: item,
                                    isSelected: selectedIndex == index,
                                    badgePosition: badge,
                                    isDropTarget: dropTargetIndex == index,
                                    isShiftHeld: isShiftHeld
                                )
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
                                    guard !item.labels.contains(where: {
                                        $0.persistentModelID == label.persistentModelID
                                    }) else { return true }
                                    item.labels.append(label)
                                    try? modelContext.save()
                                    return true
                                } isTargeted: { targeted in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        dropTargetIndex = targeted ? index : nil
                                    }
                                }
                                .id(index)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
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
        .onKeyPress(.upArrow) {
            if !isHorizontal { moveSelection(by: -1) }
            return isHorizontal ? .ignored : .handled
        }
        .onKeyPress(.downArrow) {
            if !isHorizontal { moveSelection(by: 1) }
            return isHorizontal ? .ignored : .handled
        }
        .onKeyPress(.leftArrow) {
            if isHorizontal { moveSelection(by: -1) }
            return isHorizontal ? .handled : .ignored
        }
        .onKeyPress(.rightArrow) {
            if isHorizontal { moveSelection(by: 1) }
            return isHorizontal ? .handled : .ignored
        }
        .onKeyPress(keys: [.return]) { keyPress in
            if let index = selectedIndex, index < filteredItems.count {
                if keyPress.modifiers.contains(.shift) {
                    onPastePlainText(filteredItems[index])
                } else {
                    onPaste(filteredItems[index])
                }
            }
            return .handled
        }
        .onKeyPress(characters: .decimalDigits) { keyPress in
            // Only handle when Command is held and quick paste is enabled
            guard quickPasteEnabled, keyPress.modifiers.contains(.command) else { return .ignored }

            // Extract digit 1-9 (ignore 0)
            guard let digit = keyPress.characters.first,
                  let number = digit.wholeNumberValue,
                  number >= 1, number <= 9 else { return .ignored }

            let index = number - 1  // Convert 1-based to 0-based
            guard index < filteredItems.count else { return .ignored }

            let item = filteredItems[index]

            if keyPress.modifiers.contains(.shift) {
                // Cmd+Shift+N: Plain text paste
                onPastePlainText(item)
            } else {
                // Cmd+N: Normal paste (preserving formatting)
                onPaste(item)
            }

            return .handled
        }
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
        }
    }

    // MARK: - Private Helpers

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        if let current = selectedIndex {
            selectedIndex = max(0, min(filteredItems.count - 1, current + offset))
        } else {
            selectedIndex = 0
        }
    }
}
