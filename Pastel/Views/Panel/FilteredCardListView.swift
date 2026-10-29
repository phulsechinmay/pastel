import SwiftUI
import SwiftData
import AppKit
import OSLog

/// Paged card list. The search/label service scans off the UI thread and returns
/// only IDs for the current page; at most three pages of card models stay resident.
/// Handles keyboard navigation and mouse interaction for the loaded page.
///
/// Adapts layout based on panel edge: vertical edges (left/right) use LazyVStack
/// with up/down arrow navigation; horizontal edges (top/bottom) use LazyHStack
/// with left/right arrow navigation.
struct FilteredCardListView: View {

    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue
    @AppStorage("quickPasteEnabled") private var quickPasteEnabled: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var keyMonitor: Any? = nil
    @State private var filteredItems: [ClipboardItem] = []
    @State private var cursor = HistoryPageCursor()
    @State private var isLoading = false
    @State private var isReplacingResults = false
    @State private var showRefreshIndicator = false
    @State private var refreshIndicatorTask: Task<Void, Never>?
    @State private var pageTask: Task<Void, Never>?
    @State private var queryGeneration = 0
    @State private var selectedItemID: PersistentIdentifier?
    @State private var selectedIdentityIDs: Set<PersistentIdentifier> = []
    @State private var selectionIDsBeforeReload: Set<PersistentIdentifier> = []
    @State private var selectionBeforeReload: PersistentIdentifier?
    @State private var indexBeforeReload: Int = 0
    @State private var resetSelectionOnLoad = false
    @State private var restorePageSize = 12
    @State private var loadedQuery: String?
    @State private var pendingActivationQuery: String?
    @State private var windowStart = 0
    @State private var loadError: String?
    private let pageSize = HistoryPageLoader.pageSize
    private let firstPageSize = 12
    private let maxResidentItems = 150
    private let logger = Logger(subsystem: "app.pastel.Pastel", category: "PanelResults")

    /// Anchor index for Shift+arrow range selection. `nil` means single selection
    /// (only `selectedIndex`). When set, the selection is the contiguous range
    /// between `selectionAnchor` and `selectedIndex` (the cursor).
    @State private var selectionAnchor: Int? = nil

    let allLabels: [Label]
    @Binding var selectedIndex: Int?
    var isShiftHeld: Bool
    /// Incremented each time the panel is shown; triggers a page refresh
    /// without view recreation (preserves scroll position across dismiss/reopen).
    var showCount: Int
    var activationRequestID: Int
    var activationCancelID: Int
    var navigationRequestID: Int
    var navigationOffset: Int
    var onPaste: (ClipboardItem) -> Void
    var onPastePlainText: (ClipboardItem) -> Void
    /// Copy the current selection (one or many items). Single copies full fidelity;
    /// multiple concatenate as newline-joined text. Invoked by Cmd+C and Cmd+Ctrl+digit.
    var onCopy: ([ClipboardItem]) -> Void
    /// Paste the current multi-selection (concatenated text). Invoked by Enter when
    /// more than one item is selected.
    var onPasteItems: ([ClipboardItem]) -> Void
    var onSelectionChanged: ([ClipboardItem]) -> Void
    var onResultsResolved: (Bool, Bool) -> Void
    var onShowActions: () -> Void
    var onPreview: (ClipboardItem) -> Void
    var onDragStarted: (() -> Void)?
    /// Callback for Cmd+Left/Right label cycling. Direction: -1 = previous, +1 = next.
    var onCycleLabelFilter: ((Int) -> Void)?
    /// Callback for Cmd+F to focus the panel's search field.
    var onFocusSearch: (() -> Void)?

    /// Selected label IDs for indexed membership filtering (OR logic).
    private let selectedLabelIDs: Set<PersistentIdentifier>

    /// Type/app/date filters applied by the result service.
    private let searchFilters: SearchFilters
    private let searchText: String
    private let rawSearchText: String

    // Old cards can remain on screen during a filter transition, but must not
    // remain keyboard targets for a paste from the newly selected filter.
    // v3: never empty the visible list during a replace. The stale page
    // stays on screen (with a refresh indicator) and stays clickable;
    // emptying it + disabling hit-testing is what turned 'slow' into
    // 'dead after a click or two'.
    private var visibleItems: [ClipboardItem] { filteredItems }

    /// Indices (into `visibleItems`) currently selected. A single cursor when
    /// `selectionAnchor` is nil, otherwise the contiguous anchor…cursor range.
    private var selectedIndices: Set<Int> {
        guard let cursor = selectedIndex, cursor < visibleItems.count else { return [] }
        if selectionAnchor == nil, selectedIdentityIDs.count > 1 {
            return Set(visibleItems.indices.filter {
                selectedIdentityIDs.contains(visibleItems[$0].persistentModelID)
            })
        }
        guard let anchor = selectionAnchor, anchor < visibleItems.count else { return [cursor] }
        return Set(min(anchor, cursor)...max(anchor, cursor))
    }

    /// Selected items in display order (top to bottom), for copy/paste.
    private var selectedItems: [ClipboardItem] {
        selectedIndices.sorted().map { visibleItems[$0] }
    }

    /// Compact signature for label metadata that affects labelKey filtering.
    private var labelFilterSignature: String {
        allLabels
            .map { "\($0.persistentModelID)|\($0.stableID)" }
            .joined(separator: ",")
    }

    private func reload(resetSelection: Bool = false, scanAll: Bool = false) {
        let lastSelectedIndex = isReplacingResults
            ? max(0, restorePageSize - 2)
            : (selectedIndices.max() ?? selectedIndex ?? 0)
        selectionBeforeReload = resetSelection ? nil : selectedItemID
        selectionIDsBeforeReload = resetSelection ? [] : selectedIdentityIDs
        indexBeforeReload = resetSelection ? 0 : (selectedIndex ?? 0)
        resetSelectionOnLoad = resetSelection
        restorePageSize = SelectionReconciliation.pageSize(
            reset: resetSelection, scanAll: scanAll, lastSelectedIndex: lastSelectedIndex,
            initial: firstPageSize, maximum: maxResidentItems)
        pageTask?.cancel()
        refreshIndicatorTask?.cancel()
        queryGeneration &+= 1
        isLoading = false
        isReplacingResults = !filteredItems.isEmpty
        onSelectionChanged([])
        showRefreshIndicator = false
        windowStart = 0
        cursor = HistoryPageCursor()
        loadMore()
    }

    private func loadMore() {
        guard !isLoading, !cursor.isExhausted,
              isReplacingResults || filteredItems.count < maxResidentItems else { return }
        isLoading = true
        let generation = queryGeneration
        let replacing = isReplacingResults
        let firstPage = replacing || filteredItems.isEmpty
        let started = ContinuousClock.now
        if firstPage {
            refreshIndicatorTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, generation == queryGeneration, isLoading else { return }
                showRefreshIndicator = true
            }
        }
        var nextCursor = cursor
        pageTask = Task {
            do {
                let page = try await HistoryPageLoader.nextPage(
                    in: modelContext, cursor: &nextCursor, searchText: searchText,
                    selectedLabelIDs: selectedLabelIDs, allLabels: allLabels,
                    filters: searchFilters, softDeletedIDs: appState.deletionManager.softDeletedIDs,
                    searchIndex: appState.searchIndex, worker: appState.historyPageWorker,
                    pageSize: firstPage ? restorePageSize : pageSize
                )
                guard !Task.isCancelled, generation == queryGeneration else { return }
                cursor = nextCursor
                if replacing {
                    filteredItems = page
                    isReplacingResults = false
                } else {
                    filteredItems.append(contentsOf: page)
                }
                if firstPage {
                    let displayedIDs = filteredItems.map(\.persistentModelID)
                    selectedIndex = SelectionReconciliation.index(
                        priorID: resetSelectionOnLoad ? nil : selectionBeforeReload,
                        priorIndex: indexBeforeReload, displayedIDs: displayedIDs)
                    selectionAnchor = nil
                    selectedItemID = selectedIndex.map { filteredItems[$0].persistentModelID }
                    selectedIdentityIDs = SelectionReconciliation.identities(
                        previous: selectionIDsBeforeReload, selectedID: selectedItemID,
                        displayedIDs: displayedIDs, reset: resetSelectionOnLoad)
                    onResultsResolved(!filteredItems.isEmpty,
                        resetSelectionOnLoad || selectionBeforeReload == selectedItemID)
                    onSelectionChanged(selectedItems)
                    loadedQuery = searchText
                    if pendingActivationQuery == searchText, rawSearchText == searchText {
                        pendingActivationQuery = nil
                        if let index = selectedIndex { onPaste(filteredItems[index]) }
                    }
                }
                loadError = nil
                if firstPage {
                    let elapsed = started.duration(to: .now)
                    let milliseconds = elapsed.components.seconds * 1000 +
                        elapsed.components.attoseconds / 1_000_000_000_000_000
                    logger.info("Panel first page ready in \(milliseconds, privacy: .public) ms; \(page.count, privacy: .public) clips; labels selected: \(!selectedLabelIDs.isEmpty, privacy: .public)")
                }
            } catch {
                if generation == queryGeneration && !Task.isCancelled {
                    if replacing {
                        filteredItems.removeAll(keepingCapacity: false)
                        isReplacingResults = false
                    }
                    selectedIndex = nil
                    selectedItemID = nil
                    selectedIdentityIDs = []
                    onSelectionChanged([])
                    pendingActivationQuery = nil
                    loadError = error.localizedDescription
                }
            }
            if generation == queryGeneration {
                refreshIndicatorTask?.cancel()
                showRefreshIndicator = false
                isLoading = false
            }
        }
    }

    private func advanceToOlderResults() {
        windowStart += filteredItems.count
        filteredItems.removeAll(keepingCapacity: false)
        selectedIndex = nil
        selectedItemID = nil
        selectedIdentityIDs = []
        onSelectionChanged([])
        selectionBeforeReload = nil
        indexBeforeReload = 0
        resetSelectionOnLoad = true
        restorePageSize = firstPageSize
        selectionAnchor = nil
        loadMore()
    }

    /// Static dictionary mapping NSEvent.keyCode to digit value (1-9).
    /// Key codes are non-sequential because they map to physical ANSI key positions.
    private static let digitKeyCodeMap: [UInt16: Int] = [
        0x12: 1,  // kVK_ANSI_1
        0x13: 2,  // kVK_ANSI_2
        0x14: 3,  // kVK_ANSI_3
        0x15: 4,  // kVK_ANSI_4
        0x17: 5,  // kVK_ANSI_5
        0x16: 6,  // kVK_ANSI_6
        0x1A: 7,  // kVK_ANSI_7
        0x1C: 8,  // kVK_ANSI_8
        0x19: 9,  // kVK_ANSI_9
    ]

    /// Whether the panel is on a horizontal edge (top/bottom), requiring horizontal card layout.
    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    init(
        searchText: String,
        rawSearchText: String? = nil,
        activationRequestID: Int = 0,
        activationCancelID: Int = 0,
        navigationRequestID: Int = 0,
        navigationOffset: Int = 0,
        selectedLabelIDs: Set<PersistentIdentifier>,
        searchFilters: SearchFilters = SearchFilters(),
        allLabels: [Label] = [],
        selectedIndex: Binding<Int?>,
        isShiftHeld: Bool = false,
        showCount: Int = 0,
        onPaste: @escaping (ClipboardItem) -> Void,
        onPastePlainText: @escaping (ClipboardItem) -> Void,
        onCopy: @escaping ([ClipboardItem]) -> Void = { _ in },
        onPasteItems: @escaping ([ClipboardItem]) -> Void = { _ in },
        onSelectionChanged: @escaping ([ClipboardItem]) -> Void = { _ in },
        onResultsResolved: @escaping (Bool, Bool) -> Void = { _, _ in },
        onShowActions: @escaping () -> Void = {},
        onPreview: @escaping (ClipboardItem) -> Void = { _ in },
        onDragStarted: (() -> Void)? = nil,
        onCycleLabelFilter: ((Int) -> Void)? = nil,
        onFocusSearch: (() -> Void)? = nil
    ) {
        self.allLabels = allLabels
        self.selectedLabelIDs = selectedLabelIDs
        self.searchFilters = searchFilters
        self.showCount = showCount

        self.searchText = searchText
        self.rawSearchText = rawSearchText ?? searchText
        self.activationRequestID = activationRequestID
        self.activationCancelID = activationCancelID
        self.navigationRequestID = navigationRequestID
        self.navigationOffset = navigationOffset
        _selectedIndex = selectedIndex
        self.isShiftHeld = isShiftHeld
        self.onPaste = onPaste
        self.onPastePlainText = onPastePlainText
        self.onCopy = onCopy
        self.onPasteItems = onPasteItems
        self.onSelectionChanged = onSelectionChanged
        self.onResultsResolved = onResultsResolved
        self.onShowActions = onShowActions
        self.onPreview = onPreview
        self.onDragStarted = onDragStarted
        self.onCycleLabelFilter = onCycleLabelFilter
        self.onFocusSearch = onFocusSearch
    }

    @ViewBuilder
    private var resultsContent: some View {
        Group {
            if filteredItems.isEmpty && isLoading {
                Group {
                    if showRefreshIndicator {
                        ProgressView("Loading clips…")
                            .controlSize(.small)
                            .font(.caption)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let loadError, filteredItems.isEmpty {
                Text("Could not load clips: \(loadError)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if filteredItems.isEmpty {
                    SwiftUI.Label("No matching items", systemImage: "magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
            } else if isHorizontal {
                // Horizontal layout for top/bottom edges
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: PanelLayout.cardSpacing) {
                            if windowStart > 0 {
                                Button("Newest results") { reload() }
                            }
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                cardView(for: item, at: index)
                                    // Height is whatever is left under the header row, not a
                                    // hardcoded 200. The panel is a fixed height, so a fixed
                                    // card height left a dead band below the row whose size
                                    // depended on how tall the search field happened to render.
                                    .frame(width: PanelLayout.horizontalCardWidth)
                                    .frame(maxHeight: .infinity)
                            }
                            if filteredItems.count >= maxResidentItems && !cursor.isExhausted {
                                Button("Older results") { advanceToOlderResults() }
                            }
                        }
                        .padding(PanelLayout.selectionRingGutter)
                    }
                    .frame(maxHeight: .infinity)
                    .onChange(of: selectedIndex) { _, newValue in
                        if let newValue, newValue < visibleItems.count {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(visibleItems[newValue].persistentModelID, anchor: .center)
                            }
                        }
                    }
                }
            } else {
                // Vertical layout for left/right edges
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: PanelLayout.cardSpacing) {
                            if windowStart > 0 {
                                Button("Newest results") { reload() }
                            }
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                cardView(for: item, at: index)
                            }
                            if filteredItems.count >= maxResidentItems && !cursor.isExhausted {
                                Button("Older results") { advanceToOlderResults() }
                            }
                        }
                        .padding(PanelLayout.selectionRingGutter)
                    }
                    .onChange(of: selectedIndex) { _, newValue in
                        if let newValue, newValue < visibleItems.count {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(visibleItems[newValue].persistentModelID, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        resultsContent
        .allowsHitTesting(true)
        .overlay {
            if isReplacingResults && showRefreshIndicator {
                ProgressView("Loading clips…")
                    .controlSize(.small)
                    .font(.caption)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onAppear {
            selectedIndex = nil
            onSelectionChanged([])
            selectedItemID = nil
            selectedIdentityIDs = []
            selectionAnchor = nil
            reload(resetSelection: true)
            installKeyboardMonitor()
        }
        .onChange(of: appState.itemCount) { _, _ in reload() }
        .onChange(of: appState.deletionManager.softDeletedIDs) { _, _ in
            reload()
            selectionAnchor = nil
            if let idx = selectedIndex, idx >= visibleItems.count {
                selectedIndex = visibleItems.isEmpty ? nil : visibleItems.count - 1
            }
        }
        .onChange(of: showCount) { _, _ in
            pendingActivationQuery = nil
            reload(resetSelection: true)
            selectedIndex = nil
            selectedItemID = nil
            selectedIdentityIDs = []
            selectionAnchor = nil
        }
        .onChange(of: searchText) { _, _ in
            reload(resetSelection: true)
            selectedIndex = nil
            selectedItemID = nil
            selectedIdentityIDs = []
            selectionAnchor = nil
        }
        .onChange(of: rawSearchText) { _, newValue in
            if pendingActivationQuery != newValue { pendingActivationQuery = nil }
        }
        .onChange(of: activationRequestID) { _, _ in
            let query = rawSearchText
            guard pendingActivationQuery == nil else { return }
            if loadedQuery == query, searchText == query, !isLoading,
               !isReplacingResults, let index = selectedIndex, index < visibleItems.count {
                onPaste(visibleItems[index])
            } else {
                pendingActivationQuery = query
            }
        }
        .onChange(of: activationCancelID) { _, _ in
            pendingActivationQuery = nil
        }
        .onChange(of: navigationRequestID) { _, _ in
            guard rawSearchText == searchText else { return }
            moveSelection(by: navigationOffset)
        }
        .onChange(of: selectedLabelIDs) { _, _ in
            reload(resetSelection: true)
            selectedIndex = nil
            selectedItemID = nil
            selectedIdentityIDs = []
            selectionAnchor = nil
        }
        .onChange(of: labelFilterSignature) { _, _ in reload() }
        .onChange(of: searchFilters) { _, _ in
            reload(resetSelection: true)
            selectedIndex = nil
            selectedItemID = nil
            selectedIdentityIDs = []
            selectionAnchor = nil
        }
        .onChange(of: appState.searchIndexRevision) { _, _ in
            // v3: gate reloads while building; the ready transition
            // (building already false when the revision bumps) still reloads.
            if !appState.searchIndexBuilding { reload(scanAll: true) }
        }
        .onChange(of: appState.pinRevision) { _, _ in
            reload(scanAll: true)
        }
        .onDisappear {
            pendingActivationQuery = nil
            pageTask?.cancel()
            refreshIndicatorTask?.cancel()
            filteredItems.removeAll(keepingCapacity: false)
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    // MARK: - Private Helpers

    /// Shared card rendering used by both horizontal and vertical layouts.
    /// Horizontal-specific `.frame()` and `.clipped()` are applied by the caller.
    @ViewBuilder
    private func cardView(for item: ClipboardItem, at index: Int) -> some View {
        let badge: Int? = quickPasteEnabled && index < 9 ? index + 1 : nil
        ClipboardCardView(
            item: item,
            presentation: isHorizontal ? .panelStrip : .panelList,
            isSelected: selectedIndices.contains(index),
            allLabels: allLabels,
            badgePosition: badge,
            isShiftHeld: isShiftHeld,
            onPaste: { onPaste(item) },
            onPreview: {
                selectionAnchor = nil
                selectedIndex = index
                selectedItemID = item.persistentModelID
                selectedIdentityIDs = [item.persistentModelID]
                onSelectionChanged([item])
                onPreview(item)
            }
        )
        .onDrag {
            onDragStarted?()
            return DragItemProviderService.createItemProvider(for: item)
        }
        .onTapGesture(count: 2) {
            pendingActivationQuery = nil
            pasteLog("[PASTE] origin=double-click index=\(index) shift=\(NSEvent.modifierFlags.contains(.shift))")
            if NSEvent.modifierFlags.contains(.shift) {
                onPastePlainText(item)
            } else {
                onPaste(item)
            }
        }
        .onTapGesture(count: 1) {
            pendingActivationQuery = nil
            selectionAnchor = nil
            selectedIndex = index
            selectedItemID = item.persistentModelID
            selectedIdentityIDs = [item.persistentModelID]
            onSelectionChanged([item])
            // Option+click copies the clicked item (full fidelity) without pasting,
            // mirroring the Shift+double-click plain-text paste convention.
            if NSEvent.modifierFlags.contains(.option) {
                pasteLog("[PASTE] origin=option-click index=\(index) COPY")
                onCopy([item])
            }
        }
        .transition(.asymmetric(
            insertion: .opacity,
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .onAppear {
            if index >= filteredItems.count - 3 { loadMore() }
        }
        .id(item.persistentModelID)
    }

    /// Install NSEvent local monitor for keyboard handling (arrows, Enter, Cmd+digit activation).
    /// NSEvent monitors operate at the AppKit level and are immune to SwiftUI re-render
    /// interruptions and focus issues, enabling reliable keyboard interaction in NSPanel contexts.
    private func installKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // The panel deliberately stays visible behind secondary windows — see the
            // global click monitor in PanelController, which excludes Settings/Edit —
            // so this app-wide monitor is still installed while one of them is focused.
            // Without this guard, arrow keys and Return typed into the snippet editor
            // would drive the card list instead of the text, and be consumed on the way.
            guard event.window is SlidingPanel else { return event }
            // The field editor owns its own arrows, Return, Undo and Copy.
            if event.window?.firstResponder is NSTextView { return event }
            // A pending debounce must never activate the previous query's cards.
            if rawSearchText != searchText { return event }

            // ⌘-letter shortcuts dispatch on the character the key actually produces,
            // not on where it sits. Virtual key codes name positions: 0x08 is C's
            // position on ANSI, but on Dvorak that key produces "J", so a keycode
            // switch means ⌘C does not copy and ⌘F does not focus the search field.
            // `charactersIgnoringModifiers` already reports QWERTY letters under
            // "Dvorak - QWERTY ⌘", which is what that layout exists to do.
            //
            // The switch below stays keycode-based, correctly: arrows, Return and
            // Delete carry no letter and sit in the same place on every layout.
            if event.modifierFlags.contains(.command),
               let letter = event.charactersIgnoringModifiers?.lowercased(),
               handleCommandLetter(letter, modifiers: event.modifierFlags) {
                return nil // consumed
            }

            switch event.keyCode {
            case 0x30: // Tab returns to search; text-field Tab returns here.
                onFocusSearch?()
                return nil
            case 0x31: // Space previews the focused clip.
                if let index = selectedIndex, index < visibleItems.count,
                   !event.modifierFlags.contains(.command),
                   !event.modifierFlags.contains(.control) {
                    onPreview(visibleItems[index])
                    return nil
                }
                return event
            case 123: // Left arrow
                if event.modifierFlags.contains(.command) {
                    onCycleLabelFilter?(-1)
                } else if isHorizontal {
                    moveOrExtend(by: -1, shift: event.modifierFlags.contains(.shift))
                } else {
                    return event // pass through in vertical mode
                }
                return nil // consumed
            case 124: // Right arrow
                if event.modifierFlags.contains(.command) {
                    onCycleLabelFilter?(1)
                } else if isHorizontal {
                    moveOrExtend(by: 1, shift: event.modifierFlags.contains(.shift))
                } else {
                    return event
                }
                return nil
            case 125: // Down arrow
                if !isHorizontal {
                    moveOrExtend(by: 1, shift: event.modifierFlags.contains(.shift))
                    return nil
                }
                return event
            case 126: // Up arrow
                if !isHorizontal {
                    moveOrExtend(by: -1, shift: event.modifierFlags.contains(.shift))
                    return nil
                }
                return event
            case 0x24, 0x4C: // Return, Keypad Enter
                let selected = selectedItems
                if selected.count > 1 {
                    // Multi-selection: paste all selected items (concatenated text).
                    pasteLog("[PASTE] origin=Return-key multi count=\(selected.count)")
                    onPasteItems(selected)
                    return nil // consumed
                }
                if let index = selectedIndex, index < visibleItems.count {
                    pasteLog("[PASTE] origin=Return-key index=\(index) shift=\(event.modifierFlags.contains(.shift))")
                    if event.modifierFlags.contains(.shift) {
                        onPastePlainText(visibleItems[index])
                    } else {
                        onPaste(visibleItems[index])
                    }
                    return nil // consumed
                }
                return event // no valid selection, pass through
            case 0x33: // kVK_Delete (Backspace) — Cmd+Delete soft-deletes selected item
                if event.modifierFlags.contains(.command) {
                    if let index = selectedIndex, index < visibleItems.count {
                        let item = visibleItems[index]
                        withAnimation(.easeOut(duration: 0.2)) {
                            appState.deletionManager.softDelete(item, in: modelContext)
                        }
                        appState.itemCount -= 1
                        return nil // consumed
                    }
                }
                return event
            default:
                // Cmd+1-9 paste / Cmd+Shift+1-9 paste plain / Cmd+Ctrl+1-9 copy
                if event.modifierFlags.contains(.command),
                   let digit = Self.digitKeyCodeMap[event.keyCode] {
                    guard quickPasteEnabled else {
                        pasteLog("[PASTE] origin=Cmd+digit blocked: quickPasteEnabled=false")
                        return event
                    }
                    let index = digit - 1
                    guard index < visibleItems.count else {
                        pasteLog("[PASTE] origin=Cmd+digit digit=\(digit) but only \(visibleItems.count) items")
                        return event
                    }
                    let target = visibleItems[index]
                    if event.modifierFlags.contains(.control) {
                        // Cmd+Ctrl+digit — copy the Nth item instead of pasting.
                        pasteLog("[PASTE] origin=Cmd+Ctrl+digit digit=\(digit) index=\(index) COPY")
                        onCopy([target])
                    } else if event.modifierFlags.contains(.shift) {
                        pasteLog("[PASTE] origin=Cmd+Shift+digit digit=\(digit) index=\(index)")
                        onPastePlainText(target)
                    } else {
                        pasteLog("[PASTE] origin=Cmd+digit digit=\(digit) index=\(index)")
                        onPaste(target)
                    }
                    return nil // consumed
                }
                if !event.modifierFlags.contains(.command),
                   !event.modifierFlags.contains(.control),
                   !event.modifierFlags.contains(.option),
                   let characters = event.characters, !characters.isEmpty,
                   characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                    PanelSearchFieldFocus.focusForIncomingKey()
                }
                return event // AppKit delivers the complete event to the search editor
            }
        }
    }

    /// Handle the panel's ⌘-letter shortcuts.
    ///
    /// - Parameters:
    ///   - letter: `charactersIgnoringModifiers`, lowercased.
    ///   - modifiers: the event's modifier flags; Command is already known to be held.
    /// - Returns: `true` if the event was consumed. `false` falls through to the
    ///   keycode switch and, failing that, to the app — which is how ⌘C reaches the
    ///   search field when no cards are selected.
    private func handleCommandLetter(_ letter: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch letter {
        case "c": // Copy the current selection (1 or many)
            guard !modifiers.contains(.option) else { return false }
            let selected = selectedItems
            guard !selected.isEmpty else { return false } // let search-field copy through
            pasteLog("[PASTE] origin=Cmd+C count=\(selected.count)")
            onCopy(selected)
            return true

        case "z": // Undo last deletion
            guard !modifiers.contains(.shift) else { return false }
            withAnimation(.easeOut(duration: 0.2)) {
                appState.deletionManager.undo(in: modelContext)
            }
            return true

        case "f": // Focus the search field
            guard !modifiers.contains(.shift), !modifiers.contains(.option) else { return false }
            pendingActivationQuery = nil
            onFocusSearch?()
            return true

        case "k": // Actions for the selected clip
            guard !modifiers.contains(.shift), !modifiers.contains(.option),
                  !selectedItems.isEmpty else { return false }
            onShowActions()
            return true

        case "n": // Author a new snippet (matches Paste)
            guard !modifiers.contains(.shift), !modifiers.contains(.option) else { return false }
            pendingActivationQuery = nil
            EditItemWindow.showNewSnippet(appState: appState, modelContext: modelContext)
            return true

        case "e": // Edit the selected item (matches Paste)
            guard !modifiers.contains(.shift), !modifiers.contains(.option),
                  let index = selectedIndex, index < visibleItems.count else { return false }
            pendingActivationQuery = nil
            EditItemWindow.show(
                for: visibleItems[index],
                modelContainer: modelContext.container
            )
            return true

        default:
            return false
        }
    }

    /// Route an arrow key to single-move or shift-extend depending on the Shift key.
    private func moveOrExtend(by offset: Int, shift: Bool) {
        if shift {
            extendSelection(by: offset)
        } else {
            moveSelection(by: offset)
        }
    }

    /// Move the cursor by `offset`, collapsing any multi-selection to a single item.
    private func moveSelection(by offset: Int) {
        pendingActivationQuery = nil
        guard !visibleItems.isEmpty else { return }
        selectionAnchor = nil
        if let current = selectedIndex {
            let newIndex = max(0, min(visibleItems.count - 1, current + offset))
            selectedIndex = newIndex
            selectedItemID = visibleItems[newIndex].persistentModelID
            selectedIdentityIDs = [visibleItems[newIndex].persistentModelID]
            onSelectionChanged(selectedItems)
            // Load more items if navigating near the end
            if newIndex >= filteredItems.count - 10 { loadMore() }
        } else {
            selectedIndex = 0
            selectedItemID = visibleItems[0].persistentModelID
            selectedIdentityIDs = [visibleItems[0].persistentModelID]
            onSelectionChanged(selectedItems)
        }
    }

    /// Extend the contiguous selection by moving the cursor while keeping the anchor.
    /// Establishes the anchor at the current cursor on the first Shift+arrow.
    private func extendSelection(by offset: Int) {
        pendingActivationQuery = nil
        guard !visibleItems.isEmpty else { return }
        guard let current = selectedIndex else {
            // No cursor yet — start a selection at the first item.
            selectedIndex = 0
            selectedItemID = visibleItems[0].persistentModelID
            selectedIdentityIDs = [visibleItems[0].persistentModelID]
            onSelectionChanged(selectedItems)
            return
        }
        if selectionAnchor == nil {
            selectionAnchor = current
        }
        let newIndex = max(0, min(visibleItems.count - 1, current + offset))
        selectedIndex = newIndex
        selectedItemID = visibleItems[newIndex].persistentModelID
        selectedIdentityIDs = Set((min(selectionAnchor ?? current, newIndex)...max(selectionAnchor ?? current, newIndex))
            .map { visibleItems[$0].persistentModelID })
        onSelectionChanged(selectedItems)
        if newIndex >= filteredItems.count - 10 { loadMore() }
    }
}
