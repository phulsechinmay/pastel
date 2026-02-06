import AppKit
import SwiftUI
import SwiftData

/// Singleton NSWindow manager for the Pastel Settings window.
///
/// Follows the same NSWindow + NSHostingView pattern used by
/// `AppState.checkAccessibilityOnLaunch()` for the accessibility prompt.
/// The window is non-resizable, dark-themed, and centered on screen.
@MainActor
final class SettingsWindowController {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// Show the settings window, or bring it to front if already visible.
    ///
    /// - Parameters:
    ///   - modelContainer: The SwiftData model container so settings views
    ///     can access the database (e.g., for label management in Plan 02).
    ///   - appState: The app state so settings can trigger panel edge changes.
    func showSettings(modelContainer: ModelContainer, appState: AppState) {
        // If already visible, just bring to front
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .preferredColorScheme(.dark)
            .modelContainer(modelContainer)
            .environment(appState)

        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.contentView = hostingView
        window.title = "Pastel Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
