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
    }

    /// Pass the model container to the panel controller so @Query works inside the panel.
    func setupPanel(modelContainer: ModelContainer) {
        panelController.setModelContainer(modelContainer)

        // Wire paste callback: SwiftUI -> PanelActions -> onPasteItem -> AppState.paste -> PasteService
        panelController.onPasteItem = { [weak self] item in
            self?.paste(item: item)
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

    /// Paste a clipboard item into the frontmost app.
    ///
    /// Delegates to PasteService which handles: accessibility check, pasteboard write,
    /// self-paste loop prevention, panel hide, and CGEvent Cmd+V simulation.
    func paste(item: ClipboardItem) {
        guard let clipboardMonitor else { return }
        pasteService.paste(item: item, clipboardMonitor: clipboardMonitor, panelController: panelController)
    }
}
