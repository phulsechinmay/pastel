import SwiftUI
import SwiftData

/// Root SwiftUI view hosted inside the sliding panel.
///
/// Delegates item display, filtering, and keyboard navigation to
/// `FilteredCardListView` which pages visible items through the history loader
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
    @State private var appListTask: Task<Void, Never>?

    /// Horizontal-mode height contributions, tracked separately because the panel takes
    /// a single combined figure and either source can change independently.
    @State private var chipExtraHeight: CGFloat = 0
    @State private var filterRowHeight: CGFloat = 0
    @State private var selectedIndex: Int? = nil
    @State private var selectedItems: [ClipboardItem] = []
    @State private var showActions = false
    @State private var navigationRequestID = 0
    @State private var navigationOffset = 0
    @AppStorage("pasteBehavior") private var pasteBehaviorRaw: String = PasteBehavior.copy.rawValue
    @State private var activationRequestID = 0
    @State private var activationCancelID = 0
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
                // Horizontal mode: single inline row with header, search, chips, and gear.
                // No brand mark here: this is the tightest layout in the app and the
                // user reached it with a hotkey, so identifying the app costs more
                // than it returns. The vertical layout keeps a small one.
                HStack(spacing: 8) {
                    SearchFieldView(
                        searchText: $searchText,
                        focusRequestID: searchFocusRequestID,
                        isPanelSearch: true,
                        isFilterExpanded: showFilters,
                        isFilterActive: !searchFilters.isEmpty,
                        onToggleFilters: toggleFilters,
                        onSubmit: submitSearch,
                        onTab: focusResults
                    )
                    .frame(minWidth: 190, idealWidth: 230, maxWidth: 240)
                    .layoutPriority(2)

                    ChipBarView(
                        labels: labels,
                        selectedLabelIDs: $selectedLabelIDs,
                        isAllHistoryActive: selectedLabelIDs.isEmpty,
                        onSelectAllHistory: { selectedLabelIDs.removeAll() }
                    )
                    // Use the space between search and the actions before wrapping.
                    // The flow layout still wraps on genuinely narrow panels.
                    .layoutPriority(1)
                    // Grow the horizontal panel by a row when the chips wrap to two lines.
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { chipBarHeight in
                        chipExtraHeight = max(0, chipBarHeight - PanelLayout.chipSingleRowHeight)
                        reportHorizontalExtraHeight()
                    }

                    Spacer()

                    horizontalActions
                    horizontalToolbarButtons
                }
                .padding(.bottom, PanelLayout.sectionSpacing)

                if showFilters {
                    FilterBarView(filters: $searchFilters, availableApps: availableApps)
                        .padding(.bottom, PanelLayout.sectionSpacing)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        // Buy the filter row's measured height instead of taking it
                        // from the cards (the measurement includes bottom padding).
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            filterRowHeight = height
                            reportHorizontalExtraHeight()
                        }
                }
            } else {
                // Vertical mode: header on top, search and chips stacked below
                HStack {
                    // Was 38pt of full-colour wordmark, the largest and most saturated
                    // element in a panel whose job is to disappear into a paste.
                    Image("PastelLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: PanelLayout.brandMarkHeight)
                        .opacity(0.9)
                        .accessibilityHidden(true)
                    Spacer()
                    toolbarButtons
                }
                .padding(.bottom, PanelLayout.sectionSpacing)

                Divider()

                SearchFieldView(
                    searchText: $searchText,
                    focusRequestID: searchFocusRequestID,
                    isPanelSearch: true,
                    isFilterExpanded: showFilters,
                    isFilterActive: !searchFilters.isEmpty,
                    onToggleFilters: toggleFilters,
                    onSubmit: submitSearch,
                    onTab: focusResults
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

            if appState.searchIndexBuilding {
                Text("Indexing older clips; more matches may appear")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Filtered content area with keyboard navigation
            FilteredCardListView(
                searchText: debouncedSearchText,
                rawSearchText: searchText,
                activationRequestID: activationRequestID,
                activationCancelID: activationCancelID,
                navigationRequestID: navigationRequestID,
                navigationOffset: navigationOffset,
                selectedLabelIDs: selectedLabelIDs,
                searchFilters: searchFilters,
                allLabels: labels,
                selectedIndex: $selectedIndex,
                isShiftHeld: isShiftHeld,
                showCount: panelActions.showCount,
                onPaste: { item in pasteItem(item) },
                onPastePlainText: { item in pastePlainTextItem(item) },
                onCopy: { items in panelActions.copyItems?(items) },
                onPasteItems: { items in activateItems(items) },
                onSelectionChanged: { items in
                    selectedItems = items
                    if let item = items.last, ClipPreviewWindow.isVisible {
                        ClipPreviewWindow.update(for: item, actionTitle: primaryActionTitle,
                                                 selectionNote: selectionNote(for: item),
                                                 onActivate: { activateSelection() })
                    }
                },
                onResultsResolved: { hasResults, retainedPreviewItem in
                    if !hasResults || !retainedPreviewItem { ClipPreviewWindow.close() }
                },
                onShowActions: { showActions = true },
                onPreview: { item in preview(item) },
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focused($panelFocus, equals: .cardList)
            // Keep the result view alive while typing. It resets its cursor when
            // the debounced query changes, without rebuilding its focus/scroll tree.

            if !isHorizontal {
                actionBar
            }
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
            showActions = false
            ClipPreviewWindow.close()
            if let monitor = flagsMonitor {
                NSEvent.removeMonitor(monitor)
                flagsMonitor = nil
            }
            isShiftHeld = false
        }
        .onChange(of: panelActions.showCount) { _, _ in
            selectedItems = []
            showActions = false
            ClipPreviewWindow.close()
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
        .onChange(of: isShiftHeld) { _, _ in
            if let item = selectedItems.last, ClipPreviewWindow.isVisible {
                ClipPreviewWindow.update(for: item, actionTitle: primaryActionTitle,
                                         selectionNote: selectionNote(for: item),
                                         onActivate: { activateSelection() })
            }
        }
        .onChange(of: selectedLabelIDs) { _, _ in
            ClipPreviewWindow.close()
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
            // A one- or two-character query scans the normalized SQLite text.
            // Give a continuing keystroke a little more time before doing that work.
            let delay = searchText.unicodeScalars.count > 0 && searchText.unicodeScalars.count < 3
                ? 350 : 200
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
        .onChange(of: searchText) { _, _ in ClipPreviewWindow.close() }
        .onChange(of: searchFilters) { _, _ in ClipPreviewWindow.close() }
    }

    // MARK: - Toolbar Buttons

    private var actionReady: Bool {
        !selectedItems.isEmpty && searchText == debouncedSearchText &&
            (selectedItems.count == 1 || bulkTextCount > 0)
    }

    private var bulkTextCount: Int {
        selectedItems.filter { item in
            switch item.type {
            case .text, .richText, .url, .code, .color:
                return !(item.textContent ?? "").isEmpty
            case .image, .file:
                return false
            }
        }.count
    }

    private var primaryActionTitle: String {
        let isCopy = PasteBehavior.resolved(pasteBehaviorRaw) == .copy
        let hasDestination = appState.panelController.pasteTargetPID != nil
        let count = selectedItems.count
        let canUsePlainText = selectedItems.first.map {
            $0.type != .image && $0.type != .file
        } ?? false
        if count > 1 {
            if bulkTextCount == 0 { return "No text clips in selection" }
            let verb = isCopy || !hasDestination ? "Copy" : "Paste"
            return bulkTextCount == count
                ? "\(verb) \(count) clips as Text"
                : "\(verb) \(bulkTextCount) of \(count) as Text"
        }
        if isCopy || !hasDestination {
            return isShiftHeld && canUsePlainText ? "Copy as Plain Text" : "Copy to Clipboard"
        }
        let destination = appState.panelController.pasteTargetName
        let verb = isShiftHeld && canUsePlainText ? "Paste Plain Text" : "Paste"
        return destination.map { "\(verb) into \($0)" } ?? "\(verb) into active app"
    }

    private var compactPrimaryTitle: String {
        let verb = PasteBehavior.resolved(pasteBehaviorRaw) == .copy ||
            appState.panelController.pasteTargetPID == nil ? "Copy" : "Paste"
        if selectedItems.count > 1 {
            if bulkTextCount == 0 { return "\(selectedItems.count) selected" }
            return "\(verb) \(bulkTextCount)/\(selectedItems.count)"
        }
        let supportsPlainText = selectedItems.first.map { $0.type != .image && $0.type != .file } ?? false
        return isShiftHeld && supportsPlainText ? "\(verb) Text" : verb
    }

    private var explicitCopyTitle: String {
        let count = selectedItems.count
        guard count > 1 else { return "Copy" }
        return bulkTextCount == count
            ? "Copy \(count) clips as Text"
            : "Copy \(bulkTextCount) of \(count) as Text"
    }

    private var explicitPasteTitle: String {
        let count = selectedItems.count
        if count > 1 {
            return bulkTextCount == count
                ? "Paste \(count) clips as Text"
                : "Paste \(bulkTextCount) of \(count) as Text"
        }
        return appState.panelController.pasteTargetName.map { "Paste into \($0)" } ?? "Paste"
    }

    private var horizontalActions: some View {
        HStack(spacing: 2) {
            Button(action: activateSelection) {
                HStack(spacing: 4) {
                    Text("↵").foregroundStyle(.secondary)
                    Text(compactPrimaryTitle).lineLimit(1)
                }
                .font(PanelStyle.Text.control.weight(.medium))
                .padding(.horizontal, 6)
                .frame(height: PanelLayout.toolbarButtonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!actionReady)
            .accessibilityLabel(primaryActionTitle)
            .help(actionReady ? primaryActionTitle : "Select a matching clip to continue")

            Button { showActions = true } label: {
                Image(systemName: "ellipsis")
                    .font(PanelStyle.Icon.action)
                    .frame(width: PanelLayout.toolbarButtonSize, height: PanelLayout.toolbarButtonSize)
            }
            .modifier(AdaptiveGlassButtonStyle())
            .disabled(selectedItems.isEmpty || searchText != debouncedSearchText)
            .accessibilityLabel(selectedItems.count > 1
                ? "More actions for \(selectedItems.count) selected clips"
                : "More actions for selected clip")
            .help("Actions (⌘K)")
            .popover(isPresented: $showActions, arrowEdge: .bottom) { actionsPopover }
        }
        .fixedSize()
        .layoutPriority(2)
    }

    private var actionBar: some View {
        HStack(spacing: PanelLayout.sectionSpacing) {
            Button {
                activateSelection()
            } label: {
                HStack(spacing: PanelLayout.sectionSpacing) {
                    Image(systemName: PasteBehavior.resolved(pasteBehaviorRaw) == .copy ||
                          appState.panelController.pasteTargetPID == nil
                          ? "doc.on.doc" : "arrow.uturn.forward")
                    Text(primaryActionTitle)
                        .lineLimit(1)
                    Text("↵")
                        .foregroundStyle(.secondary)
                }
                .font(PanelStyle.Text.control)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!actionReady)
            .help(actionReady ? primaryActionTitle : "Select a matching clip to continue")

            Button {
                showActions = true
            } label: {
                HStack(spacing: PanelLayout.sectionSpacing) {
                    Text("Actions")
                    Text("⌘K").foregroundStyle(.secondary)
                }
                .font(PanelStyle.Text.control)
            }
            .buttonStyle(.plain)
            .disabled(!actionReady)
            .popover(isPresented: $showActions, arrowEdge: .top) { actionsPopover }
        }
        .padding(.horizontal, PanelLayout.sectionSpacing)
        .padding(.top, PanelLayout.sectionSpacing)
        .overlay(alignment: .top) { Divider() }
    }

    private var actionsPopover: some View {
        VStack(alignment: .leading, spacing: PanelLayout.sectionSpacing) {
            Button(primaryActionTitle) { activateSelection() }
                .disabled(!actionReady)
            Divider()
            Button(explicitCopyTitle) { panelActions.copyItems?(selectedItems) }
                .disabled(!actionReady)
            if selectedItems.count == 1, let item = selectedItems.first, item.type == .richText {
                Button("Copy as Plain Text") { panelActions.copyPlainTextItem?(item) }
            }
            Button(explicitPasteTitle) { explicitPasteSelection() }
                .disabled(!actionReady || appState.panelController.pasteTargetPID == nil)
            if selectedItems.count == 1, let item = selectedItems.first {
                Button("Paste as Plain Text") { panelActions.pastePlainTextItem?(item) }
                    .disabled(appState.panelController.pasteTargetPID == nil ||
                              item.type == .image || item.type == .file)
                Button("Preview") { preview(item) }
                Divider()
                Button(item.isPinned ? "Unpin" : "Pin to Top") {
                    appState.togglePin(item, in: modelContext)
                    showActions = false
                }
                Button("Edit…") {
                    showActions = false
                    EditItemWindow.show(for: item, modelContainer: modelContext.container)
                }
                if !labels.isEmpty {
                    Menu("Labels") {
                        ForEach(labels, id: \.persistentModelID) { label in
                            Button {
                                let id = label.persistentModelID
                                if item.safeLabels.contains(where: { $0.persistentModelID == id }) {
                                    item.safeLabels.removeAll { $0.persistentModelID == id }
                                } else {
                                    item.safeLabels.append(label)
                                }
                                item.refreshLabelKey()
                                saveWithLogging(modelContext, operation: "panel action label toggle")
                            } label: {
                                if item.safeLabels.contains(where: { $0.persistentModelID == label.persistentModelID }) {
                                    SwiftUI.Label(label.name, systemImage: "checkmark")
                                } else {
                                    Text(label.name)
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Delete", role: .destructive) {
                    appState.deletionManager.softDelete(item, in: modelContext)
                    appState.itemCount -= 1
                    showActions = false
                }
            }
        }
        .buttonStyle(.plain)
        .font(PanelStyle.Text.control)
        .padding(12)
        .frame(minWidth: 220, alignment: .leading)
        .onExitCommand { showActions = false }
    }

    private func activateSelection() {
        guard actionReady else { return }
        if appState.panelController.pasteTargetPID == nil {
            if isShiftHeld, selectedItems.count == 1, let item = selectedItems.first {
                panelActions.copyPlainTextItem?(item)
            } else {
                panelActions.copyItems?(selectedItems)
            }
            return
        }
        if selectedItems.count > 1 {
            activateItems(selectedItems)
        } else if let item = selectedItems.first {
            if isShiftHeld { pastePlainTextItem(item) }
            else { pasteItem(item) }
        }
    }

    private func explicitPasteSelection() {
        guard actionReady else { return }
        if selectedItems.count > 1 { panelActions.explicitPasteItems?(selectedItems) }
        else if let item = selectedItems.first { panelActions.pasteItem?(item) }
    }

    private func preview(_ item: ClipboardItem) {
        showActions = false
        ClipPreviewWindow.toggle(for: item, beside: appState.panelController,
                                 actionTitle: primaryActionTitle,
                                 selectionNote: selectionNote(for: item),
                                 onActivate: { activateSelection() },
                                 onNavigate: { offset in
                                     navigationOffset = offset
                                     navigationRequestID &+= 1
                                 })
    }

    private func selectionNote(for item: ClipboardItem) -> String? {
        guard selectedItems.count > 1,
              let index = selectedItems.firstIndex(where: { $0.persistentModelID == item.persistentModelID })
        else { return nil }
        return "\(index + 1) of \(selectedItems.count) selected"
    }

    /// Color picker, position switcher, and settings gear — shared between both layouts.
    ///
    /// Each button now carries an explicit `toolbarButtonSize` frame and a hover fill.
    /// They were bare 14pt glyphs with no chrome, so the effective hit area was roughly
    /// the glyph's own bounds and nothing indicated they were pressable at all. Every
    /// one also carries a `.help()` now; only the first one used to.
    private var horizontalToolbarButtons: some View {
        HStack(spacing: 2) {
            Button {
                activationCancelID &+= 1
                EditItemWindow.showNewSnippet(appState: appState, modelContext: modelContext)
            } label: {
                Image(systemName: "plus")
                    .font(PanelStyle.Icon.action)
            }
            .modifier(AdaptiveGlassButtonStyle())
            .help("New Snippet (⌘N)")

            Menu {
                Button("Pick a Colour from Screen", systemImage: "eyedropper") {
                    ColorToolController.shared.showColorPicker()
                }
                Menu("Panel Position") {
                    ForEach(Array(PanelEdge.allCases), id: \.self) { edge in
                        Button {
                            panelEdgeRaw = edge.rawValue
                        } label: {
                            HStack {
                                Text(edge.rawValue.capitalized)
                                if edge.rawValue == panelEdgeRaw {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(PanelStyle.Icon.action)
            }
            .modifier(AdaptiveGlassButtonStyle())
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Panel Tools")

            Button {
                activationCancelID &+= 1
                if let container = appState.modelContainer {
                    SettingsWindowController.shared.showSettings(
                        modelContainer: container, appState: appState)
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(PanelStyle.Icon.action)
            }
            .modifier(AdaptiveGlassButtonStyle())
            .help("Settings (⌘,)")
        }
        .fixedSize()
    }

    private var toolbarButtons: some View {
        HStack(spacing: 2) {
            Button {
                activationCancelID &+= 1
                EditItemWindow.showNewSnippet(appState: appState, modelContext: modelContext)
            } label: {
                Image(systemName: "plus")
                    .font(PanelStyle.Icon.action)
                    .foregroundStyle(.primary)
            }
            .modifier(AdaptiveGlassButtonStyle())
            .help("New Snippet (\u{2318}N)")

            Button {
                ColorToolController.shared.showColorPicker()
            } label: {
                Image(systemName: "eyedropper")
                    .font(PanelStyle.Icon.action)
                    .foregroundStyle(.primary)
            }
            .modifier(AdaptiveGlassButtonStyle())
            .help("Pick a Colour from Screen")

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
                    .font(PanelStyle.Icon.action)
                    .foregroundStyle(.primary)
            }
            .modifier(AdaptiveGlassButtonStyle())
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Panel Position")

            Button {
                activationCancelID &+= 1
                if let container = appState.modelContainer {
                    SettingsWindowController.shared.showSettings(
                        modelContainer: container,
                        appState: appState
                    )
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(PanelStyle.Icon.action)
                    .foregroundStyle(.primary)
            }
            .modifier(AdaptiveGlassButtonStyle())
            .help("Settings (\u{2318},)")
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
            appListTask?.cancel()
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
        appListTask?.cancel()
        guard let worker = appState.historyPageWorker else { return }
        appListTask = Task {
            guard let apps = try? await worker.recentSourceApps(),
                  !Task.isCancelled, showFilters else { return }
            availableApps = apps
        }
    }

    private func pasteItem(_ item: ClipboardItem) {
        if appState.panelController.pasteTargetPID == nil {
            panelActions.copyOnlyItem?(item)
        } else {
            panelActions.activateItem?(item)
        }
    }

    private func submitSearch() {
        // Flush the debounce. The list accepts this request only after the page
        // for this exact query has arrived, so Return cannot use old results.
        debouncedSearchText = searchText
        activationRequestID &+= 1
    }

    private func focusResults() {
        activationCancelID &+= 1
        NSApp.keyWindow?.makeFirstResponder(nil)
        panelFocus = nil
        DispatchQueue.main.async { panelFocus = .cardList }
    }

    private func pastePlainTextItem(_ item: ClipboardItem) {
        if appState.panelController.pasteTargetPID == nil {
            panelActions.copyPlainTextItem?(item)
        } else {
            panelActions.activatePlainTextItem?(item)
        }
    }

    private func activateItems(_ items: [ClipboardItem]) {
        if appState.panelController.pasteTargetPID == nil {
            panelActions.copyItems?(items)
        } else {
            panelActions.pasteItems?(items)
        }
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
///
/// Also supplies the hit target and hover affordance the toolbar was missing.
private struct AdaptiveGlassButtonStyle: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        // Use `.plain` on all versions: `.borderless` applies control vibrancy that
        // dims the glyph relative to the position `Menu`, which renders undimmed.
        // `.plain` renders label content as-is, keeping all toolbar icons the same brightness.
        content
            .buttonStyle(.plain)
            .frame(width: PanelLayout.toolbarButtonSize, height: PanelLayout.toolbarButtonSize)
            .background(
                isHovered ? PanelStyle.surfaceHover : .clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
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
