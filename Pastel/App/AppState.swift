import SwiftUI
import SwiftData

@MainActor
@Observable
final class AppState {

    /// The clipboard monitoring service (optional because it requires ModelContext)
    var clipboardMonitor: ClipboardMonitor?

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
}
