import AppKit
import SwiftUI
import SwiftData

/// Singleton NSWindow manager for the Pastel Settings window.
///
/// Follows the same NSWindow + NSHostingView pattern used by
/// `AppState.checkAccessibilityOnLaunch()` for the accessibility prompt.
/// The window is resizable (for the History tab), dark-themed, and centered on screen.
@MainActor
final class SettingsWindowController {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// Set once from PastelApp during init when sync is enabled.
    /// Stored here so every call site (panel gear button, menu bar popover) injects it automatically.
    var syncMonitor: SyncMonitor?

    /// Notification posted to switch tabs when the Settings window is already visible.
    static let switchTab = Notification.Name("SettingsWindowSwitchTab")

    /// Show the settings window, or bring it to front if already visible.
    ///
    /// - Parameters:
    ///   - modelContainer: The SwiftData model container so settings views
    ///     can access the database (e.g., for label management in Plan 02).
    ///   - appState: The app state so settings can trigger panel edge changes.
    ///   - initialTab: The tab to display when opening (default: .general).
    func showSettings(modelContainer: ModelContainer, appState: AppState, initialTab: SettingsTab = .general) {
        // If already visible, just bring to front and switch tab via notification
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(
                name: Self.switchTab,
                object: nil,
                userInfo: ["tab": initialTab.rawValue]
            )
            return
        }

        let settingsView = SettingsView(initialTab: initialTab)
            .preferredColorScheme(.dark)
            .modelContainer(modelContainer)
            .environment(appState)
            .environment(syncMonitor)

        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 550),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.contentView = hostingView
        window.title = "Pastel Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 480)
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarSeparatorStyle = .none
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
