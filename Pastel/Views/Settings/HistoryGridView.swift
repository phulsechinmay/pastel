import SwiftUI
import SwiftData
import OSLog

/// Responsive card grid for the History tab in Settings.
///
/// Uses the shared bounded page loader and adds multi-selection for the loaded
/// window via Cmd-click, Shift-click, Cmd+A, and Escape.
///
/// Context menus are selection-aware: right-clicking a selected item shows bulk
/// actions for all selected items; right-clicking an unselected item selects it
/// and shows single-item actions.
struct HistoryGridView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    // Multi-selection state (owned by parent HistoryBrowserView)
    @Binding var selectedIDs: Set<PersistentIdentifier>
    // Resolved items in the loaded window, exposed to parent for bulk operations
    @Binding var resolvedItems: [ClipboardItem]
    @State private var lastClickedID: PersistentIdentifier? = nil
    @State private var memoizedFilteredItems: [ClipboardItem] = []
    @State private var cursor = HistoryPageCursor(pinnedExhausted: true)
    @State private var isLoading = false
    @State private var isReplacingResults = false
    @State private var showRefreshIndicator = false
    @State private var refreshIndicatorTask: Task<Void, Never>?
    @State private var pageTask: Task<Void, Never>?
    @State private var queryGeneration = 0
    @State private var windowStart = 0
    @State private var loadError: String?
    private let pageSize = 100
    private let firstPageSize = 12
    private let maxResidentItems = 300
    private let logger = Logger(subsystem: "app.pastel.Pastel", category: "HistoryResults")
    private let searchText: String

    // Labels passed from parent for ClipboardCardView context menus
    let allLabels: [Label]
    // Indexed label filtering
    private let selectedLabelIDs: Set<PersistentIdentifier>

    // Bulk action closures (provided by parent HistoryBrowserView)
    private let onBulkCopy: () -> Void
    private let onBulkPaste: () -> Void
    private let onRequestBulkDelete: () -> Void
    private let onPastePlainText: (ClipboardItem) -> Void

    /// The grid used to be `.adaptive(minimum: 280, maximum: 400)`. At the settings
    /// window's default 820pt width, minus a ~200pt sidebar, the detail pane fits
    /// exactly one 400pt column: a "grid" that rendered as a single centred column
    /// with ~100pt of dead gutter on either side, showing less per screen than the
    /// 320pt panel it was supposed to expand on. A 320pt ceiling fits two columns at
    /// the default width and keeps filling out as the window grows.
    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 12)
    ]

    init(searchText: String, selectedLabelIDs: Set<PersistentIdentifier>, allLabels: [Label] = [], selectedIDs: Binding<Set<PersistentIdentifier>>, resolvedItems: Binding<[ClipboardItem]>, onBulkCopy: @escaping () -> Void = {}, onBulkPaste: @escaping () -> Void = {}, onRequestBulkDelete: @escaping () -> Void = {}, onPastePlainText: @escaping (ClipboardItem) -> Void = { _ in }) {
        self.searchText = searchText
        self.allLabels = allLabels
        self.selectedLabelIDs = selectedLabelIDs
        _selectedIDs = selectedIDs
        _resolvedItems = resolvedItems
        self.onBulkCopy = onBulkCopy
        self.onBulkPaste = onBulkPaste
        self.onRequestBulkDelete = onRequestBulkDelete
        self.onPastePlainText = onPastePlainText
    }

    private var visibleItems: [ClipboardItem] { isReplacingResults ? [] : memoizedFilteredItems }

    /// Compact signature for label metadata that affects labelKey filtering.
    private var labelFilterSignature: String {
        allLabels
            .map { "\($0.persistentModelID)|\($0.stableID)" }
            .joined(separator: ",")
    }

    private func reload() {
        pageTask?.cancel()
        refreshIndicatorTask?.cancel()
        queryGeneration &+= 1
        isLoading = false
        isReplacingResults = !memoizedFilteredItems.isEmpty
        showRefreshIndicator = false
        windowStart = 0
        resolvedItems.removeAll(keepingCapacity: false)
        cursor = HistoryPageCursor(pinnedExhausted: true)
        loadMore()
    }

    private func loadMore() {
        guard !isLoading, !cursor.isExhausted,
              isReplacingResults || memoizedFilteredItems.count < maxResidentItems else { return }
        isLoading = true
        let generation = queryGeneration
        let replacing = isReplacingResults
        let firstPage = replacing || memoizedFilteredItems.isEmpty
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
                    softDeletedIDs: appState.deletionManager.softDeletedIDs,
                    searchIndex: appState.searchIndex, worker: appState.historyPageWorker,
                    pinsFirst: false, pageSize: firstPage ? firstPageSize : pageSize
                )
                guard !Task.isCancelled, generation == queryGeneration else { return }
                cursor = nextCursor
                if replacing {
                    memoizedFilteredItems = page
                    isReplacingResults = false
                } else {
                    memoizedFilteredItems.append(contentsOf: page)
                }
                resolvedItems = memoizedFilteredItems
                loadError = nil
                if firstPage {
                    let elapsed = started.duration(to: .now)
                    let milliseconds = elapsed.components.seconds * 1000 +
                        elapsed.components.attoseconds / 1_000_000_000_000_000
                    logger.info("History first page ready in \(milliseconds, privacy: .public) ms; \(page.count, privacy: .public) clips")
                }
            } catch {
                if generation == queryGeneration && !Task.isCancelled {
                    if replacing {
                        memoizedFilteredItems.removeAll(keepingCapacity: false)
                        isReplacingResults = false
                    }
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
        windowStart += memoizedFilteredItems.count
        selectedIDs.removeAll()
        lastClickedID = nil
        memoizedFilteredItems.removeAll(keepingCapacity: false)
        resolvedItems.removeAll(keepingCapacity: false)
        loadMore()
    }

    var body: some View {
        Group {
            if memoizedFilteredItems.isEmpty && isLoading {
                Group {
                    if showRefreshIndicator {
                        ProgressView("Loading history…")
                            .controlSize(.small)
                            .font(.caption)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError, memoizedFilteredItems.isEmpty {
                Text("Could not load history: \(loadError)")
                    .foregroundStyle(.secondary)
            } else if memoizedFilteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(PanelStyle.Icon.empty)
                        .foregroundStyle(.tertiary)
                    Text("No items found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        if windowStart > 0 {
                            Button("Newest results") { reload() }
                        }
                        ForEach(Array(memoizedFilteredItems.enumerated()), id: \.element.id) { index, item in
                            let isInSelection = selectedIDs.contains(item.persistentModelID)
                            ClipboardCardView(
                                item: item,
                                isSelected: isInSelection,
                                allLabels: allLabels,
                                hideContextMenu: true,
                                // Dropping a label on a card that is part of the current
                                // selection labels the whole selection. Cmd-click a dozen
                                // clips, drag one chip, done. Dropping on an unselected
                                // card still hits only that card, so the gesture never
                                // does more than what is visibly highlighted.
                                labelDropTargets: {
                                    isInSelection ? selectedItems() : [item]
                                },
                                onPaste: {
                                    selectedIDs = [item.persistentModelID]
                                    onBulkPaste()
                                }
                            )
                            .onTapGesture {
                                handleTap(item: item, index: index)
                            }
                            .onAppear {
                                if index >= memoizedFilteredItems.count - 6 { loadMore() }
                            }
                            .contextMenu {
                                if isInSelection && selectedIDs.count > 1 {
                                    // Bulk actions for multi-selection
                                    Button("Copy \(selectedIDs.count) Items") {
                                        onBulkCopy()
                                    }
                                    Button("Paste \(selectedIDs.count) Items") {
                                        onBulkPaste()
                                    }
                                    Divider()
                                    Button("Delete \(selectedIDs.count) Items", role: .destructive) {
                                        onRequestBulkDelete()
                                    }
                                } else {
                                    // Single-item actions (auto-selects this item)
                                    Button("Copy") {
                                        selectedIDs = [item.persistentModelID]
                                        onBulkCopy()
                                    }
                                    Button("Paste") {
                                        selectedIDs = [item.persistentModelID]
                                        onBulkPaste()
                                    }
                                    Button("Paste as Plain Text") {
                                        onPastePlainText(item)
                                    }
                                    Divider()
                                    Button("Edit...") {
                                        EditItemWindow.show(for: item, modelContainer: modelContext.container)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        selectedIDs = [item.persistentModelID]
                                        onRequestBulkDelete()
                                    }
                                }
                            }
                        }
                        if memoizedFilteredItems.count >= maxResidentItems && !cursor.isExhausted {
                            Button("Older results") { advanceToOlderResults() }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .allowsHitTesting(!isReplacingResults)
        .overlay {
            if isReplacingResults && showRefreshIndicator {
                ProgressView("Loading history…")
                    .controlSize(.small)
                    .font(.caption)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(characters: .init(charactersIn: "aA")) { keyPress in
            // Cmd+A selects the loaded window; distant pages are not kept in memory.
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            selectedIDs = Set(visibleItems.map(\.persistentModelID))
            return .handled
        }
        .onKeyPress(.escape) {
            // Escape: deselect all
            selectedIDs.removeAll()
            lastClickedID = nil
            return .handled
        }
        .onAppear { reload() }
        .onChange(of: appState.itemCount) { _, _ in reload() }
        .onChange(of: appState.pinRevision) { _, _ in reload() }
        .onChange(of: appState.searchIndexRevision) { _, _ in reload() }
        .onChange(of: searchText) { _, _ in reload() }
        .onChange(of: appState.deletionManager.softDeletedIDs) { _, _ in reload() }
        .onChange(of: selectedLabelIDs) { _, _ in reload() }
        .onChange(of: labelFilterSignature) { _, _ in reload() }
        .onDisappear {
            pageTask?.cancel()
            refreshIndicatorTask?.cancel()
            memoizedFilteredItems.removeAll(keepingCapacity: false)
            resolvedItems.removeAll(keepingCapacity: false)
        }
    }

    // MARK: - Multi-Selection

    /// The currently selected items, resolved from IDs against the filtered set.
    private func selectedItems() -> [ClipboardItem] {
        memoizedFilteredItems.filter { selectedIDs.contains($0.persistentModelID) }
    }

    private func handleTap(item: ClipboardItem, index: Int) {
        let id = item.persistentModelID
        let modifiers = NSEvent.modifierFlags

        if modifiers.contains(.command) {
            // Cmd-click: toggle individual selection
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
            lastClickedID = id
        } else if modifiers.contains(.shift), let anchorID = lastClickedID {
            // Shift-click: range selection from anchor to clicked item
            guard let anchorIndex = visibleItems.firstIndex(where: { $0.persistentModelID == anchorID }) else {
                // Anchor no longer in visible results, treat as single select
                selectedIDs = [id]
                lastClickedID = id
                return
            }
            let range = min(anchorIndex, index)...max(anchorIndex, index)
            for i in range {
                selectedIDs.insert(visibleItems[i].persistentModelID)
            }
            // Do NOT update lastClickedID on shift-click (anchor stays)
        } else {
            // Plain click: single selection (clears previous)
            selectedIDs = [id]
            lastClickedID = id
        }
    }
}
