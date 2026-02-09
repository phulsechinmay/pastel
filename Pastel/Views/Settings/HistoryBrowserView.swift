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
/// `HistoryGridView` when filters change, giving it a fresh @Query.
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
            // Top bar: search + chip bar
            SearchFieldView(searchText: $searchText)
                .frame(maxWidth: 350)
                .frame(maxWidth: .infinity)
            ChipBarView(labels: labels, selectedLabelIDs: $selectedLabelIDs)

            Divider()

            // Responsive card grid with multi-selection
            HistoryGridView(
                searchText: debouncedSearchText,
                selectedLabelIDs: selectedLabelIDs,
                selectedIDs: $selectedIDs,
                resolvedItems: $resolvedItems,
                onBulkCopy: { bulkCopy() },
                onBulkPaste: { bulkPaste() },
                onRequestBulkDelete: { showDeleteConfirmation = true },
                onPastePlainText: { item in singlePastePlainText(item) }
            )
            .environment(PanelActions())
            .id("\(debouncedSearchText)\(selectedLabelIDs.sorted(by: { "\($0)" < "\($1)" }).map { "\($0)" }.joined())")

            // Bottom action bar (visible when items are selected)
            if !selectedIDs.isEmpty {
                Divider()
                HStack(spacing: 16) {
                    Text("\(selectedIDs.count) item\(selectedIDs.count == 1 ? "" : "s") selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Copy") {
                        bulkCopy()
                    }
                    .buttonStyle(.bordered)

                    Button("Paste") {
                        bulkPaste()
                    }
                    .buttonStyle(.bordered)

                    Button("Delete", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
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

        let concatenated = textParts.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(concatenated, forType: .string)

        // Self-paste loop prevention
        appState.clipboardMonitor?.skipNextChange = true
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
            let source = CGEventSource(stateID: .combinedSessionState)
            let vKeyCode: CGKeyCode = 0x09
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cgSessionEventTap)
            keyUp?.post(tap: .cgSessionEventTap)
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
            // Clean up disk images (both regular and URL metadata images)
            ImageStorageService.shared.deleteImage(
                imagePath: item.imagePath,
                thumbnailPath: item.thumbnailPath
            )
            ImageStorageService.shared.deleteImage(
                imagePath: item.urlFaviconPath,
                thumbnailPath: item.urlPreviewImagePath
            )
            // Clear many-to-many label relationships before delete (SwiftData MTM requirement)
            item.labels.removeAll()
            modelContext.delete(item)
        }
        try? modelContext.save()
        selectedIDs.removeAll()
    }
}
