import SwiftUI
import SwiftData
import AppKit
import KeyboardShortcuts

// MARK: - Keyboard Shortcut Names

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.command, .shift]))
}

@MainActor
@Observable
final class AppState {

    /// The clipboard monitoring service (optional because it requires ModelContext)
    var clipboardMonitor: ClipboardMonitor?

    /// Controller managing the sliding clipboard history panel
    let panelController = PanelController()

    /// Service for writing to pasteboard and simulating Cmd+V paste
    let pasteService = PasteService()

    /// Deletion manager for soft-delete with undo support
    let deletionManager = DeletionManager()

    /// History auto-purge service based on user-configured retention period
    var retentionService: RetentionService?

    /// The model container, stored so settings views can access SwiftData
    var modelContainer: ModelContainer?

    /// Total number of captured clipboard items (stored for @Observable reactivity).
    /// ClipboardMonitor is not @Observable, so a computed property delegating to it
    /// would not trigger SwiftUI updates. This stored property is synced via callback.
    var itemCount: Int = 0

    /// Bumped whenever an item's pin state changes, so the panel can re-partition
    /// its in-memory list. Mutating `isPinned` on a model object does not change the
    /// identity of the `@Query` array, so `onChange(of: items)` would never fire —
    /// this is the same reason `DeletionManager.softDeletedIDs` is observed separately.
    private(set) var pinRevision: Int = 0

    /// Whether clipboard monitoring is active (delegates to monitor)
    var isMonitoring: Bool {
        clipboardMonitor?.isMonitoring ?? false
    }

    /// Toggle an item's pin, stamping `pinnedAt` so pins can be ordered
    /// most-recently-pinned first. Bumps `pinRevision` for the panel.
    @MainActor
    func togglePin(_ item: ClipboardItem, in modelContext: ModelContext) {
        item.isPinned.toggle()
        item.pinnedAt = item.isPinned ? .now : nil
        saveWithLogging(modelContext, operation: "toggle pin")
        pinRevision &+= 1
    }

    /// Create an empty user-authored clip and return it for editing.
    ///
    /// Born pinned, so a snippet isn't buried by the next hour of copying, and
    /// retention-exempt for the same reason labeled items are.
    ///
    /// `contentHash` is deliberately left empty until the user types something:
    /// `DeduplicationService` skips empty hashes, so two blank drafts can never be
    /// merged into each other, and `applyEditedText` computes the real hash on the
    /// first edit. A draft closed without content is removed by `discardSnippet`.
    @MainActor
    func createSnippet(in modelContext: ModelContext) -> ClipboardItem {
        let item = ClipboardItem(contentType: .text, contentHash: "")
        item.isUserCreated = true
        item.isPinned = true
        item.pinnedAt = .now
        modelContext.insert(item)
        saveWithLogging(modelContext, operation: "create snippet")
        itemCount += 1
        pinRevision &+= 1
        return item
    }

    /// Remove a snippet draft the user closed without typing anything.
    ///
    /// Deliberately does NOT bump `pinRevision`. Deleting the row already changes the
    /// panel's `@Query` array, so `onChange(of: items)` re-partitions on its own. Bumping
    /// here would additionally run `computeFilteredItems` over the *pre-refresh* array,
    /// which still contains the row just deleted — and reading `isPinned` off an
    /// invalidated model traps. Callers must ensure nothing is still bound to `item`
    /// before calling this; see `EditItemWindow`'s close handler.
    @MainActor
    func discardSnippet(_ item: ClipboardItem, in modelContext: ModelContext) {
        deleteClipboardItemWithCleanup(item, from: modelContext)
        saveWithLogging(modelContext, operation: "discard empty snippet")
        itemCount -= 1
    }

    /// Initialize the clipboard monitor with a SwiftData model context and start capturing.
    ///
    /// Called from PastelApp.init after the ModelContainer is created.
    func setup(modelContext: ModelContext) {
        // Bounded repair to populate Label.stableID / ClipboardItem.labelKey
        // for rows created before those fields existed or synced later.
        backfillLabelIndex(in: modelContext)

        let monitor = ClipboardMonitor(modelContext: modelContext)
        monitor.onItemCountChanged = { [weak self] count in
            self?.itemCount = count
        }
        self.itemCount = monitor.itemCount
        monitor.start()
        self.clipboardMonitor = monitor

        let retention = RetentionService(modelContext: modelContext)
        retention.startPeriodicPurge()
        self.retentionService = retention
    }

    /// Pass the model container to the panel controller so @Query works inside the panel.
    func setupPanel(modelContainer: ModelContainer) {
        panelController.setModelContainer(modelContainer)
        panelController.setAppState(self)

        // Wire paste callback: SwiftUI -> PanelActions -> onPasteItem -> AppState.paste -> PasteService
        panelController.onPasteItem = { [weak self] item in
            self?.paste(item: item)
        }

        // Wire plain text paste callback: SwiftUI -> PanelActions -> onPastePlainTextItem -> AppState.pastePlainText -> PasteService
        panelController.onPastePlainTextItem = { [weak self] item in
            self?.pastePlainText(item: item)
        }

        // Wire copy-only callback: SwiftUI -> PanelActions -> onCopyOnlyItem -> AppState.copyOnly -> PasteService
        panelController.onCopyOnlyItem = { [weak self] item in
            self?.copyOnly(item: item)
        }

        // Wire multi-item copy/paste callbacks (keyboard selection: Cmd+C, Enter, Cmd+Ctrl+digit)
        panelController.onCopyItems = { [weak self] items in
            self?.copyItems(items)
        }
        panelController.onPasteItems = { [weak self] items in
            self?.pasteItems(items)
        }

        // Wire drag-started callback: SwiftUI -> PanelActions -> PanelController -> AppState -> ClipboardMonitor
        panelController.onDragStarted = { [weak self] in
            self?.clipboardMonitor?.skipNextChange = true
        }

        // Wire accessibility permission prompt: PasteService -> AppState
        pasteService.onAccessibilityRequired = { [weak self] in
            self?.showAccessibilityRequired()
        }

        // Register global hotkey for panel toggle.
        // Defer to next run loop iteration so NSApp.activate() works correctly —
        // Carbon event handler context blocks activation if called synchronously.
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            DispatchQueue.main.async {
                self?.togglePanel()
            }
        }

    }

    /// Toggle the sliding panel open/closed.
    func togglePanel() {
        panelController.toggle()
    }

    // MARK: - Onboarding & Accessibility

    /// Controller for the first-launch onboarding window.
    private var onboardingController = OnboardingWindowController.shared

    /// NSWindow for the contextual accessibility permission prompt.
    private var permissionPromptWindow: NSWindow?

    /// Show the contextual accessibility permission prompt.
    ///
    /// Called when the user attempts a paste action but accessibility is not granted.
    /// The item has already been copied to the clipboard by PasteService.
    func showAccessibilityRequired() {
        // Don't stack multiple prompts
        if let existing = permissionPromptWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let promptView = AccessibilityRequiredView(onDismiss: { [weak self] in
            self?.permissionPromptWindow?.close()
            self?.permissionPromptWindow = nil
        })

        let hostingView = NSHostingView(rootView: promptView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.contentView = hostingView
        window.title = "Pastel"
        window.center()
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.permissionPromptWindow = window
    }

    /// Handle first-launch onboarding.
    ///
    /// On first launch (hasCompletedOnboarding is false): show full onboarding.
    /// On subsequent launches: no-op. Accessibility is prompted contextually when the user
    /// tries to paste without permission (via PasteService.onAccessibilityRequired callback).
    func handleFirstLaunch() {
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        if !hasCompleted {
            onboardingController.showOnboarding(appState: self)
        }
    }

    /// Clear all clipboard history: delete all items, clean up image files, reset item count.
    ///
    /// Labels are preserved -- they are reusable organizational tools and should survive
    /// a history clear. Pending expiration timers for concealed items will harmlessly no-op
    /// when they fire (items already deleted).
    ///
    /// - Parameter modelContext: The SwiftData model context to delete from.
    func clearAllHistory(modelContext: ModelContext) {
        do {
            // Fetch all items to collect image paths before batch delete
            let descriptor = FetchDescriptor<ClipboardItem>()
            let allItems = try modelContext.fetch(descriptor)

            // Delete each item individually: clean up disk images and clear
            // many-to-many label relationships before removing the model.
            // Batch delete (modelContext.delete(model:)) cannot handle MTM relationships.
            for item in allItems {
                deleteClipboardItemWithCleanup(item, from: modelContext)
            }
            try modelContext.save()

            // Reset item count
            clipboardMonitor?.itemCount = 0
        } catch {
            modelContext.rollback()
        }
    }

    /// Paste a clipboard item into the frontmost app.
    ///
    /// Delegates to PasteService which handles: accessibility check, pasteboard write,
    /// self-paste loop prevention, panel hide, and CGEvent Cmd+V simulation.
    func paste(item: ClipboardItem) {
        guard let clipboardMonitor else {
            pasteLog("[PASTE] AppState.paste: no clipboardMonitor, dropping")
            return
        }
        pasteLog("[PASTE] AppState.paste relaying to PasteService")
        pasteService.paste(item: item, clipboardMonitor: clipboardMonitor, panelController: panelController, source: "AppState.paste")
    }

    /// Paste a clipboard item as plain text (RTF stripped) into the frontmost app.
    ///
    /// Delegates to PasteService.pastePlainText which omits RTF data from the pasteboard,
    /// causing receiving apps to fall back to their default text styling.
    func pastePlainText(item: ClipboardItem) {
        guard let clipboardMonitor else {
            pasteLog("[PASTE] AppState.pastePlainText: no clipboardMonitor, dropping")
            return
        }
        pasteLog("[PASTE] AppState.pastePlainText relaying to PasteService")
        pasteService.pastePlainText(item: item, clipboardMonitor: clipboardMonitor, panelController: panelController, source: "AppState.pastePlainText")
    }

    /// Copy a clipboard item to the pasteboard without simulating Cmd+V.
    func copyOnly(item: ClipboardItem) {
        guard let clipboardMonitor else { return }
        pasteService.copyOnly(item: item, clipboardMonitor: clipboardMonitor, panelController: panelController)
    }

    /// Copy a selection of one or more items to the pasteboard (no Cmd+V simulation).
    func copyItems(_ items: [ClipboardItem]) {
        guard let clipboardMonitor else { return }
        pasteService.copyOnly(items: items, clipboardMonitor: clipboardMonitor, panelController: panelController)
    }

    /// Paste a selection of one or more items into the frontmost app.
    func pasteItems(_ items: [ClipboardItem]) {
        guard let clipboardMonitor else { return }
        pasteService.paste(items: items, clipboardMonitor: clipboardMonitor, panelController: panelController, source: "AppState.pasteItems")
    }
}
