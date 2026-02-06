import SwiftUI
import SwiftData
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
}
