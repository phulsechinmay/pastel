import SwiftUI
import SwiftData

/// Root view for the History tab in Settings.
///
/// Provides a full history browser with search field and label chip bar
/// for filtering. Reuses the same `SearchFieldView` and `ChipBarView`
/// components from the panel, with the same 200ms debounce pattern.
/// The grid area is a placeholder until Plan 02.
struct HistoryBrowserView: View {

    @Query(sort: \Label.sortOrder) private var labels: [Label]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedLabelIDs: Set<PersistentIdentifier> = []

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: search + chip bar
            SearchFieldView(searchText: $searchText)
            ChipBarView(labels: labels, selectedLabelIDs: $selectedLabelIDs)

            Divider()

            // Grid area (placeholder until Plan 02)
            Text("History grid coming soon")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(.secondary)
        }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
    }
}
