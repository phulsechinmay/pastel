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
    @State private var dropTargetIndex: Int? = nil
    @State private var keyMonitor: Any? = nil

    @Binding var selectedIndex: Int?
    var isShiftHeld: Bool
    var onPaste: (ClipboardItem) -> Void
    var onPastePlainText: (ClipboardItem) -> Void
    var onTypeToSearch: ((Character) -> Void)?
    var onDragStarted: (() -> Void)?
    /// Callback for Cmd+Left/Right label cycling. Direction: -1 = previous, +1 = next.
    var onCycleLabelFilter: ((Int) -> Void)?

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
        onTypeToSearch: ((Character) -> Void)? = nil,
        onDragStarted: (() -> Void)? = nil,
        onCycleLabelFilter: ((Int) -> Void)? = nil
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
        self.onDragStarted = onDragStarted
        self.onCycleLabelFilter = onCycleLabelFilter
    }

    var body: some View {
        Group {
            if filteredItems.isEmpty {
                    SwiftUI.Label("No matching items", systemImage: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
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
                                    guard !item.labels.contains(where: {
                                        $0.persistentModelID == label.persistentModelID
                                    }) else { return true }
                                    item.labels.append(label)
                                    saveWithLogging(modelContext, operation: "label drop assignment")
                                    return true
                                } isTargeted: { targeted in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        dropTargetIndex = targeted ? index : nil
                                    }
                                }
                                .id(index)
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
                                    guard !item.labels.contains(where: {
                                        $0.persistentModelID == label.persistentModelID
                                    }) else { return true }
                                    item.labels.append(label)
                                    saveWithLogging(modelContext, operation: "label drop assignment")
                                    return true
                                } isTargeted: { targeted in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        dropTargetIndex = targeted ? index : nil
                                    }
                                }
                                .id(index)
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
            // Cmd+N: Normal paste (preserving formatting)
            guard quickPasteEnabled, keyPress.modifiers.contains(.command) else { return .ignored }

            guard let digit = keyPress.characters.first,
                  let number = digit.wholeNumberValue,
                  number >= 1, number <= 9 else { return .ignored }

            let index = number - 1
            guard index < filteredItems.count else { return .ignored }

            onPaste(filteredItems[index])
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "!@#$%^&*(")) { keyPress in
            // Cmd+Shift+N: Plain text paste
            // Shift+1-9 produces !@#$%^&*( so .decimalDigits won't match
            guard quickPasteEnabled,
                  keyPress.modifiers.contains(.command),
                  keyPress.modifiers.contains(.shift) else { return .ignored }

            let shiftedDigitMap: [Character: Int] = [
                "!": 1, "@": 2, "#": 3, "$": 4, "%": 5,
                "^": 6, "&": 7, "*": 8, "(": 9
            ]

            guard let char = keyPress.characters.first,
                  let number = shiftedDigitMap[char] else { return .ignored }

            let index = number - 1
            guard index < filteredItems.count else { return .ignored }

            onPastePlainText(filteredItems[index])
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
            installArrowKeyMonitor()
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    // MARK: - Private Helpers

    /// Install NSEvent local monitor for arrow key handling.
    /// NSEvent monitors operate at the AppKit level and are immune to SwiftUI re-render
    /// interruptions, enabling reliable key repeat for card navigation.
    private func installArrowKeyMonitor() {
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
            default:
                return event // pass through all other keys
            }
        }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        if let current = selectedIndex {
            selectedIndex = max(0, min(filteredItems.count - 1, current + offset))
        } else {
            selectedIndex = 0
        }
    }
}
