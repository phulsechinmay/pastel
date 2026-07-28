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
    @Environment(\.modelContext) private var modelContext
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

    @Query(sort: \Label.sortOrder) private var labels: [Label]

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedLabelIDs: Set<PersistentIdentifier> = []

    /// Whether the Type/App/Date filter row is revealed. Collapsed by default so it
    /// costs no vertical space until asked for — the panel is already tight, and the
    /// chip bar above it grows a row whenever labels wrap.
    @State private var showFilters = false
    @State private var searchFilters = SearchFilters()
    /// Source apps offered by the app filter, refreshed when the row is revealed
    /// rather than held in a standing @Query that would duplicate the card list's fetch.
    @State private var availableApps: [SourceAppOption] = []

    /// Horizontal-mode height contributions, tracked separately because the panel takes
    /// a single combined figure and either source can change independently.
    @State private var chipExtraHeight: CGFloat = 0
    @State private var filterRowHeight: CGFloat = 0
    @State private var selectedIndex: Int? = nil
    @State private var isShiftHeld = false
    @State private var flagsMonitor: Any?

    private enum PanelFocus: Hashable {
        case cardList
    }

    @FocusState private var panelFocus: PanelFocus?
    /// Monotonic counter — incremented by callers that want the search field to
    /// take focus (Cmd+F, type-to-search). FocusableTextField observes the
    /// change in `updateNSView` and calls `makeFirstResponder`. A Bool is
    /// insufficient because once it's `true` it can't fire another false→true
    /// edge if focus is later moved to the card list (e.g. by Cmd+Left/Right
    /// label cycling), so a second Cmd+F would be invisible.
    @State private var searchFocusRequestID = 0

    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    /// Uniform rounded rectangle for glass effect — all 4 corners rounded.
    private var glassShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PanelLayout.panelCornerRadius)
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

                    SearchFieldView(
                        searchText: $searchText,
                        focusRequestID: searchFocusRequestID,
                        isFilterExpanded: showFilters,
                        isFilterActive: !searchFilters.isEmpty,
                        onToggleFilters: toggleFilters
                    )
                    .frame(maxWidth: 240)

                    ChipBarView(
                        labels: labels,
                        selectedLabelIDs: $selectedLabelIDs,
                        isAllHistoryActive: selectedLabelIDs.isEmpty,
                        onSelectAllHistory: { selectedLabelIDs.removeAll() }
                    )
                    // Grow the horizontal panel by a row when the chips wrap to two lines.
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { chipBarHeight in
                        chipExtraHeight = max(0, chipBarHeight - PanelLayout.chipHeight)
                        reportHorizontalExtraHeight()
                    }

                    Spacer()

                    toolbarButtons
                }
                .padding(.bottom, PanelLayout.sectionSpacing)

                if showFilters {
                    FilterBarView(filters: $searchFilters, availableApps: availableApps)
                        .padding(.bottom, PanelLayout.sectionSpacing)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        // A horizontal panel is a fixed height, so the filter row has to
                        // buy its own space or it eats into the single row of cards.
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            filterRowHeight = height + PanelLayout.sectionSpacing
                            reportHorizontalExtraHeight()
                        }
                }
            } else {
                // Vertical mode: header on top, search and chips stacked below
                HStack {
                    Image("PastelLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 38)
                    Spacer()
                    toolbarButtons
                }
                .padding(.bottom, PanelLayout.sectionSpacing)

                Divider()

                SearchFieldView(
                    searchText: $searchText,
                    focusRequestID: searchFocusRequestID,
                    isFilterExpanded: showFilters,
                    isFilterActive: !searchFilters.isEmpty,
                    onToggleFilters: toggleFilters
                )
                .padding(.vertical, PanelLayout.sectionSpacing)
                ChipBarView(
                    labels: labels,
                    selectedLabelIDs: $selectedLabelIDs,
                    isAllHistoryActive: selectedLabelIDs.isEmpty,
                    onSelectAllHistory: { selectedLabelIDs.removeAll() }
                )
                .padding(.bottom, PanelLayout.sectionSpacing)

                if showFilters {
                    FilterBarView(filters: $searchFilters, availableApps: availableApps)
                        .padding(.bottom, PanelLayout.sectionSpacing)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Filtered content area with keyboard navigation
            FilteredCardListView(
                searchText: debouncedSearchText,
                selectedLabelIDs: selectedLabelIDs,
                searchFilters: searchFilters,
                allLabels: labels,
                selectedIndex: $selectedIndex,
                isShiftHeld: isShiftHeld,
                showCount: panelActions.showCount,
                onPaste: { item in pasteItem(item) },
                onPastePlainText: { item in pastePlainTextItem(item) },
                onCopy: { items in panelActions.copyItems?(items) },
                onPasteItems: { items in panelActions.pasteItems?(items) },
                onTypeToSearch: { char in
                    searchText.append(char)
                    panelFocus = nil
                    searchFocusRequestID &+= 1
                },
                onDragStarted: {
                    panelActions.onDragStarted?()
                },
                onCycleLabelFilter: { direction in
                    cycleLabelFilter(direction: direction)
                },
                onFocusSearch: {
                    panelFocus = nil
                    searchFocusRequestID &+= 1
                }
            )
            .focused($panelFocus, equals: .cardList)
            // .id() triggers full view recreation only when the @Query predicate changes
            // (search text). Label filtering is in-memory, so changing labels does not
            // require a new @Query and is handled via onChange(of: selectedLabelIDs)
            // inside FilteredCardListView — preserving scroll position, dominant-color
            // caches, and the keyboard NSEvent monitor across chip taps.
            // showCount is intentionally EXCLUDED so scroll position survives panel dismiss/reopen.
            .id(debouncedSearchText)
        }
        .fontDesign(.rounded)
        .padding(PanelLayout.panelOuterPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(GlassEffectModifier(shape: glassShape))
        .defaultFocus($panelFocus, .cardList)
        .onAppear {
            DispatchQueue.main.async {
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
            // Reset to "All History" — clear label filter
            selectedLabelIDs.removeAll()
            // Clear search text so panel opens fresh
            searchText = ""
            debouncedSearchText = ""
            // Type/app/date filters reset with everything else (plan decision Q4.4):
            // a sticky filter the user forgot about looks like missing history.
            searchFilters.removeAll()
            showFilters = false
            // Focus card list, not search
            panelFocus = .cardList
        }
        .onChange(of: selectedLabelIDs) { _, _ in
            panelFocus = .cardList
        }
        .onChange(of: showFilters) { _, isShown in
            // The row's geometry reader stops reporting once it's gone, so give the
            // height back explicitly or the horizontal panel stays permanently taller.
            if !isShown {
                filterRowHeight = 0
                reportHorizontalExtraHeight()
            }
            panelFocus = .cardList
        }
        .onChange(of: panelEdgeRaw) {
            appState.panelController.handleEdgeChange(reopen: true)
        }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Toolbar Buttons

    /// Color picker, position switcher, and settings gear — shared between both layouts.
    private var toolbarButtons: some View {
        HStack(spacing: 4) {
            Button {
                EditItemWindow.showNewSnippet(appState: appState, modelContext: modelContext)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
            }
            .modifier(AdaptiveGlassButtonStyle())
            .help("New Snippet (\u{2318}N)")

            Button {
                ColorToolController.shared.showColorPicker()
            } label: {
                Image(systemName: "eyedropper")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
            }
            .modifier(AdaptiveGlassButtonStyle())

            Menu {
                ForEach(Array(PanelEdge.allCases), id: \.self) { (edge: PanelEdge) in
                    Button {
                        panelEdgeRaw = edge.rawValue
                    } label: {
                        HStack {
                            Text(edge.rawValue.capitalized)
                            if edge.rawValue == panelEdgeRaw {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "rectangle.leadinghalf.inset.filled.arrow.leading")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
            }
            .modifier(AdaptiveGlassButtonStyle())
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                if let container = appState.modelContainer {
                    SettingsWindowController.shared.showSettings(
                        modelContainer: container,
                        appState: appState
                    )
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
            }
            .modifier(AdaptiveGlassButtonStyle())
        }
    }

    // MARK: - Private Helpers

    /// Rebuild the app filter's options from recent history.
    ///
    /// Run on demand when the filter row opens rather than from a standing `@Query`,
    /// which would duplicate the card list's fetch on every panel show. Bounded to the
    /// most recent slice — the apps a user filters by are the ones they copy from now,
    /// and scanning an entire multi-thousand-item history for a menu isn't worth it.
    /// Reveal or hide the Type/App/Date filter row.
    private func toggleFilters() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showFilters.toggle()
        }
        if showFilters {
            refreshAvailableApps()
        } else {
            // Collapsing must clear, or a filter the user can no longer see keeps
            // narrowing results and reads as missing history.
            searchFilters.removeAll()
        }
    }

    /// Tell the panel how much taller than baseline the header has become.
    private func reportHorizontalExtraHeight() {
        panelActions.onHorizontalExtraHeightChange?(chipExtraHeight + filterRowHeight)
    }

    private func refreshAvailableApps() {
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 2000
        let recent = (try? modelContext.fetch(descriptor)) ?? []
        availableApps = SourceAppOption.derive(from: recent)
    }

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
                if let firstID = labelIDs.first {
                    selectedLabelIDs = [firstID]
                }
            } else {
                // Backward: go to last label
                if let lastID = labelIDs.last {
                    selectedLabelIDs = [lastID]
                }
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
        // Use `.plain` on all versions: `.borderless` applies control vibrancy that
        // dims the glyph relative to the position `Menu`, which renders undimmed.
        // `.plain` renders label content as-is, keeping all toolbar icons the same brightness.
        content.buttonStyle(.plain)
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
