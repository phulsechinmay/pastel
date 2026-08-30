import SwiftUI
import SwiftData
import AppKit

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

    /// Concatenate text content of selected items with newlines and copy to pasteboard.
    /// Non-text items (images, files) are silently skipped.
    private func bulkCopy() {
        let selected = resolvedItems.filter { selectedIDs.contains($0.persistentModelID) }
        let textParts = selected.compactMap { item -> String? in
            switch item.type {
            case .text, .richText, .url, .code, .color:
                return item.textContent
            case .image, .file:
                return nil
            }
        }
        guard !textParts.isEmpty else { return }

        // Drain before writing: a copy the user made in the last ~600ms may not have
        // been polled yet, and overwriting it without draining loses it for good.
        appState.clipboardMonitor?.drainPendingChange()

        let concatenated = textParts.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(concatenated, forType: .string)

        // Self-paste loop prevention: suppress exactly our own write, not "the next
        // change", which would eat a copy the user makes before the next poll.
        appState.clipboardMonitor?.suppressChange(count: pasteboard.changeCount)
    }

    /// Copy concatenated text to pasteboard, hide settings window, and simulate Cmd+V.
    /// Falls back to copy-only if Accessibility permission is not granted.
    private func bulkPaste() {
        bulkCopy()

        // Check Accessibility before simulating Cmd+V
        guard AccessibilityService.isGranted else { return }

        // Hide the settings window instantly (user can reopen from menu bar)
        if let settingsWindow = NSApp.windows.first(where: { $0.title == "Pastel Settings" }) {
            settingsWindow.orderOut(nil)
        }

        // Simulate Cmd+V after delay (350ms > panel hide; settings window uses orderOut for instant hide)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            PasteService.simulatePaste()
        }
    }

    /// Paste a single item as plain text via AppState (same flow as panel paste-as-plain-text).
    private func singlePastePlainText(_ item: ClipboardItem) {
        appState.pastePlainText(item: item)
    }

    /// Delete selected items with full cleanup: disk images, label relationships, and model deletion.
    /// Clears selection after deletion.
    private func bulkDelete() {
        let itemsToDelete = resolvedItems.filter { selectedIDs.contains($0.persistentModelID) }
        for item in itemsToDelete {
            deleteClipboardItemWithCleanup(item, from: modelContext)
        }
        saveWithLogging(modelContext, operation: "bulk delete")
        appState.itemCount -= itemsToDelete.count
        selectedIDs.removeAll()
    }
}
