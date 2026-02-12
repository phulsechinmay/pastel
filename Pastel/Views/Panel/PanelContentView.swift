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

    /// Uniform distance from panel glass edge to content — reusable constant for all edges.
    static let panelOuterPadding: CGFloat = 10

    @Environment(PanelActions.self) private var panelActions
    @Environment(AppState.self) private var appState
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

    @Query(sort: \Label.sortOrder) private var labels: [Label]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedLabelIDs: Set<PersistentIdentifier> = []
    @State private var selectedIndex: Int? = nil
    @State private var isShiftHeld = false
    @State private var flagsMonitor: Any?

    private enum PanelFocus: Hashable {
        case cardList
    }

    @FocusState private var panelFocus: PanelFocus?
    @State private var isSearchFocused = false

    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    /// Uniform rounded rectangle for glass effect — all 4 corners rounded.
    private var glassShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12)
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

                    SearchFieldView(searchText: $searchText, requestFocus: isSearchFocused)
                        .frame(maxWidth: 200)

                    ChipBarView(
                        labels: labels,
                        selectedLabelIDs: $selectedLabelIDs,
                        isAllHistoryActive: selectedLabelIDs.isEmpty,
                        onSelectAllHistory: { selectedLabelIDs.removeAll() }
                    )

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
                    .modifier(AdaptiveGlassButtonStyle())
                }
                .padding(.bottom, 4)
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
                    .modifier(AdaptiveGlassButtonStyle())
                }

                Divider()

                SearchFieldView(searchText: $searchText, requestFocus: isSearchFocused)
                ChipBarView(
                    labels: labels,
                    selectedLabelIDs: $selectedLabelIDs,
                    isAllHistoryActive: selectedLabelIDs.isEmpty,
                    onSelectAllHistory: { selectedLabelIDs.removeAll() }
                )
            }

            // Filtered content area with keyboard navigation
            FilteredCardListView(
                searchText: debouncedSearchText,
                selectedLabelIDs: selectedLabelIDs,
                selectedIndex: $selectedIndex,
                isShiftHeld: isShiftHeld,
                onPaste: { item in pasteItem(item) },
                onPastePlainText: { item in pastePlainTextItem(item) },
                onTypeToSearch: { char in
                    searchText.append(char)
                    panelFocus = nil
                    isSearchFocused = true
                },
                onDragStarted: {
                    panelActions.onDragStarted?()
                },
                onCycleLabelFilter: { direction in
                    cycleLabelFilter(direction: direction)
                }
            )
            .focused($panelFocus, equals: .cardList)
            .id("\(debouncedSearchText)\(selectedLabelIDs.sorted(by: { "\($0)" < "\($1)" }).map { "\($0)" }.joined())\(appState.itemCount)")
        }
        .fontDesign(.rounded)
        .padding(Self.panelOuterPadding)
        .frame(maxWidth: .infinity, alignment: .top)
        .modifier(GlassEffectModifier(shape: glassShape))
        .defaultFocus($panelFocus, .cardList)
        .onAppear {
            DispatchQueue.main.async {
                isSearchFocused = false
                panelFocus = .cardList
            }
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                isShiftHeld = event.modifierFlags.contains(.shift)
                return event
            }
        }
        .onDisappear {
            if let monitor = flagsMonitor {
                NSEvent.removeMonitor(monitor)
                flagsMonitor = nil
            }
            isShiftHeld = false
        }
        .onChange(of: panelActions.showCount) { _, _ in
            isSearchFocused = false
            panelFocus = .cardList
        }
        .onChange(of: selectedLabelIDs) { _, _ in
            panelFocus = .cardList
        }
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

    /// Cycle through label filters by direction (-1 = previous, +1 = next).
    /// Includes "All History" (empty selection) as a position between first and last labels.
    /// Cycle order: All History -> first label -> ... -> last label -> All History.
    private func cycleLabelFilter(direction: Int) {
        guard !labels.isEmpty else { return }

        let labelIDs = labels.map(\.persistentModelID)

        if selectedLabelIDs.isEmpty {
            // Currently on "All History"
            if direction > 0 {
                // Forward: go to first label
                selectedLabelIDs = [labelIDs.first!]
            } else {
                // Backward: go to last label
                selectedLabelIDs = [labelIDs.last!]
            }
        } else if let currentID = selectedLabelIDs.first,
                  let currentIndex = labelIDs.firstIndex(of: currentID) {
            let newIndex = currentIndex + direction
            if newIndex < 0 || newIndex >= labelIDs.count {
                // Wrap to "All History"
                selectedLabelIDs.removeAll()
            } else {
                selectedLabelIDs = [labelIDs[newIndex]]
            }
        }
    }
}

/// Availability-gated button style: `.borderless` on macOS 26+ (outer NSGlassEffectView
/// provides the glass backdrop; using `.glass` here would be glass-on-glass), `.plain` on older.
private struct AdaptiveGlassButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.borderless)
        } else {
            content.buttonStyle(.plain)
        }
    }
}

/// Availability-gated panel shape modifier.
/// On macOS 26+, glass is provided by NSGlassEffectView in PanelController — no SwiftUI glass needed.
/// On pre-26, clips to the rounded shape (NSVisualEffectView provides the blur).
private struct GlassEffectModifier: ViewModifier {
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            // Glass is rendered by NSGlassEffectView at the AppKit layer (PanelController)
            content
        } else {
            // NSVisualEffectView in PanelController provides the behind-window blur;
            // just clip to the rounded shape here.
            content.clipShape(shape)
        }
    }
}
