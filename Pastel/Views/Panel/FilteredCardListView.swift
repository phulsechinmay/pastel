import SwiftUI
import SwiftData

/// Dynamic query child view that constructs its @Query predicate at init time.
///
/// This pattern is required because SwiftData's @Query cannot be changed dynamically
/// after view creation. When the parent passes new searchText or selectedLabelID values,
/// SwiftUI recreates this view with a fresh @Query containing the updated predicate.
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

    @Binding var selectedIndex: Int?
    var onPaste: (ClipboardItem) -> Void
    var onPastePlainText: (ClipboardItem) -> Void

    /// Whether the panel is on a horizontal edge (top/bottom), requiring horizontal card layout.
    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    init(
        searchText: String,
        selectedLabelID: PersistentIdentifier?,
        selectedIndex: Binding<Int?>,
        onPaste: @escaping (ClipboardItem) -> Void,
        onPastePlainText: @escaping (ClipboardItem) -> Void
    ) {
        let predicate: Predicate<ClipboardItem>

        if let labelID = selectedLabelID {
            if searchText.isEmpty {
                predicate = #Predicate<ClipboardItem> { item in
                    item.label?.persistentModelID == labelID
                }
            } else {
                let search = searchText
                predicate = #Predicate<ClipboardItem> { item in
                    item.label?.persistentModelID == labelID &&
                    (item.textContent?.localizedStandardContains(search) == true ||
                     item.sourceAppName?.localizedStandardContains(search) == true)
                }
            }
        } else if !searchText.isEmpty {
            let search = searchText
            predicate = #Predicate<ClipboardItem> { item in
                item.textContent?.localizedStandardContains(search) == true ||
                item.sourceAppName?.localizedStandardContains(search) == true
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
        self.onPaste = onPaste
        self.onPastePlainText = onPastePlainText
    }

    var body: some View {
        Group {
            if items.isEmpty {
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
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                ClipboardCardView(
                                    item: item,
                                    isSelected: selectedIndex == index
                                )
                                .frame(width: 260, height: 195)
                                .clipped()
                                .id(index)
                                .onTapGesture(count: 2) {
                                    onPaste(item)
                                }
                                .onTapGesture(count: 1) {
                                    selectedIndex = index
                                }
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
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                ClipboardCardView(
                                    item: item,
                                    isSelected: selectedIndex == index
                                )
                                .id(index)
                                .onTapGesture(count: 2) {
                                    onPaste(item)
                                }
                                .onTapGesture(count: 1) {
                                    selectedIndex = index
                                }
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
        .onKeyPress(.return) {
            if let index = selectedIndex, index < items.count {
                onPaste(items[index])
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
            guard index < items.count else { return .ignored }

            let item = items[index]

            if keyPress.modifiers.contains(.shift) {
                // Cmd+Shift+N: Plain text paste
                onPastePlainText(item)
            } else {
                // Cmd+N: Normal paste (preserving formatting)
                onPaste(item)
            }

            return .handled
        }
        .onAppear {
            selectedIndex = nil
        }
    }

    // MARK: - Private Helpers

    private func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        if let current = selectedIndex {
            selectedIndex = max(0, min(items.count - 1, current + offset))
        } else {
            selectedIndex = 0
        }
    }
}
