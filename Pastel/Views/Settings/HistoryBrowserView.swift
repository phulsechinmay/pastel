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
/// `HistoryGridView` only when the @Query predicate changes (search text).
/// Label filtering is in-memory, so label chip changes flow through
/// HistoryGridView's onChange(of: selectedLabelIDs) instead — preserving the
/// existing @Query (and its reactivity to inserts/edits/deletes) and scroll
/// position across chip taps.
/// Selection state lives here (not in the grid) so it persists across
/// recreations, but is cleared on filter changes to avoid stale IDs.
///
/// When items are selected, a bottom action bar appears with Copy, Paste,
/// and Delete buttons. Copy concatenates text content with newlines.
/// Paste copies then simulates Cmd+V. Delete shows a confirmation dialog.
struct HistoryBrowserView: View {

    @Query(sort: \Label.sortOrder) private var labels: [Label]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedLabelIDs: Set<PersistentIdentifier> = []
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var resolvedItems: [ClipboardItem] = []
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: search + chip bar.
            //
            // Both used to be centred inside a left-aligned pane, so neither shared an
            // edge with the grid below or the sidebar beside them. They now hang off
            // the pane's leading edge on the same 12pt inset as the grid's padding.
            VStack(alignment: .leading, spacing: 8) {
                SearchFieldView(searchText: $searchText)
                    .frame(maxWidth: 350, alignment: .leading)
                ChipBarView(labels: labels, selectedLabelIDs: $selectedLabelIDs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Responsive card grid with multi-selection
            HistoryGridView(
                searchText: debouncedSearchText,
                selectedLabelIDs: selectedLabelIDs,
                allLabels: labels,
                selectedIDs: $selectedIDs,
                resolvedItems: $resolvedItems,
                onBulkCopy: { bulkCopy() },
                onBulkPaste: { bulkPaste() },
                onRequestBulkDelete: { showDeleteConfirmation = true },
                onPastePlainText: { item in singlePastePlainText(item) }
            )
            .environment(PanelActions())
            .id(debouncedSearchText)

            // Bottom action bar (visible when items are selected).
            //
            // Slides up from the window edge rather than appearing instantly, which is
            // what it used to do: the bar materialised and the grid jumped by its height
            // in the same frame, so the card you had just clicked moved out from under
            // the pointer.
            if !selectedIDs.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    actionBar
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: selectedIDs.isEmpty)
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
        .fontDesign(.rounded)
        .onChange(of: debouncedSearchText) { _, _ in selectedIDs.removeAll() }
        .onChange(of: selectedLabelIDs) { _, _ in selectedIDs.removeAll() }
        .alert("Delete \(selectedIDs.count) Items", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                bulkDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(selectedIDs.count) clipboard item\(selectedIDs.count == 1 ? "" : "s"). This action cannot be undone.")
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 16) {
            // The count rolls between values instead of being replaced. Cmd-clicking
            // through a dozen cards is a counting task, and the digits now behave like
            // a counter rather than like a label that keeps getting rewritten.
            Text("\(selectedIDs.count) item\(selectedIDs.count == 1 ? "" : "s") selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.18), value: selectedIDs.count)

            Spacer()

            Button("Copy") {
                bulkCopy()
            }
            .buttonStyle(.bordered)

            Button("Paste") {
                bulkPaste()
            }
            .buttonStyle(.bordered)

            // Tinted, not just role-tagged: `.bordered` renders a destructive
            // role identically to its neighbours, so Delete sat in a row with
            // Copy and Paste looking exactly like them.
            Button("Delete") {
                showDeleteConfirmation = true
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Bulk Actions

    /// The items currently selected, in the grid's own order.
    private var selection: [ClipboardItem] {
        resolvedItems.filter { selectedIDs.contains($0.persistentModelID) }
    }

    /// Copy the selection to the pasteboard. Non-text items (images, files) are skipped.
    private func bulkCopy() {
        appState.copyItems(selection, from: .settings)
    }

    /// Copy the selection, order the Settings window out, and simulate Cmd+V.
    ///
    /// This used to hand-roll the whole sequence: its own pasteboard write, its own
    /// suppression flag, a silent permission bail with no prompt, no secure-input
    /// check at all, a `title == "Pastel Settings"` window scan, and a fifth magic
    /// delay. Routing it through `PasteService` means it gains all the guards the
    /// panel paths already had, and there is one sequence left to fix instead of four.
    private func bulkPaste() {
        appState.pasteItems(selection, from: .settings)
    }

    /// Paste a single item as plain text (same flow as panel paste-as-plain-text).
    ///
    /// `.settings` is load-bearing: without it the panel is asked to hide (it is not
    /// visible, so nothing happens) and ⌘V is posted while Settings still holds
    /// keyboard focus — pasting into Pastel's own window.
    private func singlePastePlainText(_ item: ClipboardItem) {
        appState.pastePlainText(item: item, from: .settings)
    }

    /// Delete selected items with full cleanup: disk images, label relationships, and model deletion.
    /// Clears selection after deletion.
    private func bulkDelete() {
        let itemsToDelete = selection
        for item in itemsToDelete {
            deleteClipboardItemWithCleanup(item, from: modelContext)
        }
        saveWithLogging(modelContext, operation: "bulk delete")
        appState.itemCount -= itemsToDelete.count
        selectedIDs.removeAll()
    }
}
