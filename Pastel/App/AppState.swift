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

    /// History auto-purge service based on user-configured retention period
    var retentionService: RetentionService?

    /// The model container, stored so settings views can access SwiftData
    var modelContainer: ModelContainer?

    /// Total number of captured clipboard items (delegates to monitor)
    var itemCount: Int {
        clipboardMonitor?.itemCount ?? 0
    }

    /// Whether clipboard monitoring is active (delegates to monitor)
    var isMonitoring: Bool {
        clipboardMonitor?.isMonitoring ?? false
    }

    /// Initialize the clipboard monitor with a SwiftData model context and start capturing.
    ///
    /// Called from PastelApp.init after the ModelContainer is created.
    func setup(modelContext: ModelContext) {
        let monitor = ClipboardMonitor(modelContext: modelContext)
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

        // Register global hotkey for panel toggle
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            MainActor.assumeIsolated {
                self?.togglePanel()
            }
        }
    }

    /// Toggle the sliding panel open/closed.
    func togglePanel() {
        panelController.toggle()
    }

    // MARK: - Accessibility Onboarding

    /// NSWindow for the accessibility permission onboarding prompt.
    private var accessibilityWindow: NSWindow?

    /// Show accessibility permission onboarding if not already granted.
    ///
    /// Called once at app launch. If the user already granted permission,
    /// this is a no-op. Otherwise, a centered dark-themed window explains
    /// why the permission is needed and offers buttons to grant it.
    func checkAccessibilityOnLaunch() {
        guard !AccessibilityService.isGranted else { return }

        let promptView = AccessibilityPromptView(onDismiss: { [weak self] in
            self?.accessibilityWindow?.close()
            self?.accessibilityWindow = nil
        })
        .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: promptView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
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
        self.accessibilityWindow = window
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

            // Delete all image files from disk
            for item in allItems {
                ImageStorageService.shared.deleteImage(
                    imagePath: item.imagePath,
                    thumbnailPath: item.thumbnailPath
                )
                // Clean up URL metadata cached images
                ImageStorageService.shared.deleteImage(
                    imagePath: item.urlFaviconPath,
                    thumbnailPath: item.urlPreviewImagePath
                )
            }

            // Batch delete all clipboard items
            try modelContext.delete(model: ClipboardItem.self)
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
        guard let clipboardMonitor else { return }
        pasteService.paste(item: item, clipboardMonitor: clipboardMonitor, panelController: panelController)
    }

    /// Paste a clipboard item as plain text (RTF stripped) into the frontmost app.
    ///
    /// Delegates to PasteService.pastePlainText which omits RTF data from the pasteboard,
    /// causing receiving apps to fall back to their default text styling.
    func pastePlainText(item: ClipboardItem) {
        guard let clipboardMonitor else { return }
        pasteService.pastePlainText(item: item, clipboardMonitor: clipboardMonitor, panelController: panelController)
    }

    /// Copy a clipboard item to the pasteboard without simulating Cmd+V.
    func copyOnly(item: ClipboardItem) {
        guard let clipboardMonitor else { return }
        pasteService.copyOnly(item: item, clipboardMonitor: clipboardMonitor, panelController: panelController)
    }
}
