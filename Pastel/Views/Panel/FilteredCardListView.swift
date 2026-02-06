import SwiftUI
import SwiftData

/// Dynamic query child view that constructs its @Query predicate at init time.
///
/// This pattern is required because SwiftData's @Query cannot be changed dynamically
/// after view creation. When the parent passes new searchText or selectedLabelID values,
/// SwiftUI recreates this view with a fresh @Query containing the updated predicate.
///
/// Handles keyboard navigation (up/down arrows, Enter to paste) and mouse interaction
/// (single-click to select, double-click to paste) since it has direct access to the
/// queried items array.
struct FilteredCardListView: View {

    @Query private var items: [ClipboardItem]

    @Binding var selectedIndex: Int?
    var onPaste: (ClipboardItem) -> Void

    init(
        searchText: String,
        selectedLabelID: PersistentIdentifier?,
        selectedIndex: Binding<Int?>,
        onPaste: @escaping (ClipboardItem) -> Void
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
                    (item.textContent?.localizedStandardContains(search) ?? false ||
                     item.sourceAppName?.localizedStandardContains(search) ?? false)
                }
            }
        } else if !searchText.isEmpty {
            let search = searchText
            predicate = #Predicate<ClipboardItem> { item in
                item.textContent?.localizedStandardContains(search) ?? false ||
                item.sourceAppName?.localizedStandardContains(search) ?? false
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
            } else {
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
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            if let index = selectedIndex, index < items.count {
                onPaste(items[index])
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
