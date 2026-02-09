import SwiftUI
import SwiftData

/// Root view for the History tab in Settings.
///
/// Provides a full history browser with search field, label chip bar,
/// and a responsive card grid with multi-selection. Reuses the same
/// `SearchFieldView` and `ChipBarView` components from the panel,
/// with the same 200ms debounce pattern.
///
/// The `.id()` modifier forces SwiftUI to destroy and recreate
/// `HistoryGridView` when filters change, giving it a fresh @Query.
/// Selection state lives here (not in the grid) so it persists across
/// recreations, but is cleared on filter changes to avoid stale IDs.
struct HistoryBrowserView: View {

    @Query(sort: \Label.sortOrder) private var labels: [Label]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedLabelIDs: Set<PersistentIdentifier> = []
    @State private var selectedIDs: Set<PersistentIdentifier> = []

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: search + chip bar
            SearchFieldView(searchText: $searchText)
            ChipBarView(labels: labels, selectedLabelIDs: $selectedLabelIDs)

            Divider()

            // Responsive card grid with multi-selection
            HistoryGridView(
                searchText: debouncedSearchText,
                selectedLabelIDs: selectedLabelIDs,
                selectedIDs: $selectedIDs
            )
            .environment(PanelActions())
            .id("\(debouncedSearchText)\(selectedLabelIDs.sorted(by: { "\($0)" < "\($1)" }).map { "\($0)" }.joined())")
        }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
        .onChange(of: debouncedSearchText) { _, _ in selectedIDs.removeAll() }
        .onChange(of: selectedLabelIDs) { _, _ in selectedIDs.removeAll() }
    }
}
