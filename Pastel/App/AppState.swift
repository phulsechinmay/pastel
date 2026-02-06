import SwiftUI
import SwiftData

@MainActor
@Observable
final class AppState {
    var itemCount: Int = 0
    var isMonitoring: Bool = true

    // Will be populated by ClipboardMonitor in Plan 01-02
    // For now, just the state container
}
