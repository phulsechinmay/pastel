import SwiftUI
import SwiftData

/// Root SwiftUI view hosted inside the sliding panel.
///
/// Delegates item display, filtering, and keyboard navigation to
/// `FilteredCardListView` which uses an init-based `@Query` predicate
/// for dynamic search and label filtering.
///
/// Layout: Header -> Divider -> SearchField -> ChipBar -> FilteredCardList
struct PanelContentView: View {

    @Environment(PanelActions.self) private var panelActions
    @Environment(AppState.self) private var appState
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

    @Query(sort: \Label.sortOrder) private var labels: [Label]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedLabel: Label? = nil
    @State private var selectedIndex: Int? = nil

    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    var body: some View {
        VStack(spacing: 0) {
            if isHorizontal {
                // Horizontal mode: single inline row with header, search, chips, and gear
                HStack(spacing: 8) {
                    Image("PastelLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 38)

                    SearchFieldView(searchText: $searchText)
                        .frame(maxWidth: 200)

                    ChipBarView(labels: labels, selectedLabel: $selectedLabel)

                    Spacer()

                    Button {
                        if let container = appState.modelContainer {
                            SettingsWindowController.shared.showSettings(
                                modelContainer: container,
                                appState: appState
                            )
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                // Vertical mode: header on top, search and chips stacked below
                HStack {
                    Image("PastelLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 38)
                    Spacer()
                    Button {
                        if let container = appState.modelContainer {
                            SettingsWindowController.shared.showSettings(
                                modelContainer: container,
                                appState: appState
                            )
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                SearchFieldView(searchText: $searchText)
                ChipBarView(labels: labels, selectedLabel: $selectedLabel)
            }

            // Filtered content area with keyboard navigation
            FilteredCardListView(
                searchText: debouncedSearchText,
                selectedLabelID: selectedLabel?.persistentModelID,
                selectedIndex: $selectedIndex,
                onPaste: { item in pasteItem(item) },
                onPastePlainText: { item in pastePlainTextItem(item) }
            )
            .id("\(debouncedSearchText)\(selectedLabel?.persistentModelID.hashValue ?? 0)\(appState.itemCount)")
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

    private func pastePlainTextItem(_ item: ClipboardItem) {
        panelActions.pastePlainTextItem?(item)
    }
}
