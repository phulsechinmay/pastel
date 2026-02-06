import SwiftUI
import SwiftData

/// Root SwiftUI view hosted inside the sliding panel.
///
/// Delegates item display, filtering, and keyboard navigation to
/// `FilteredCardListView` which uses an init-based `@Query` predicate
/// for dynamic search and label filtering.
///
/// Layout: Header -> Divider -> SearchField -> FilteredCardList
struct PanelContentView: View {

    @Environment(PanelActions.self) private var panelActions

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedLabel: Label? = nil
    @State private var selectedIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Minimal header
            HStack {
                Text("Pastel")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Search field
            SearchFieldView(searchText: $searchText)

            // Filtered content area with keyboard navigation
            FilteredCardListView(
                searchText: debouncedSearchText,
                selectedLabelID: selectedLabel?.persistentModelID,
                selectedIndex: $selectedIndex,
                onPaste: { item in pasteItem(item) }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Private Helpers

    private func pasteItem(_ item: ClipboardItem) {
        panelActions.pasteItem?(item)
    }
}
