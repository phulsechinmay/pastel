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

    #if SPARKLE
    /// Set once when the menu bar popover first appears (in `StatusPopoverView`).
    /// Lets the Settings window's `GeneralSettingsView` access the same Sparkle controller.
    var updaterService: UpdaterService?
    #endif

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

        let baseView = SettingsView(initialTab: initialTab)
            .preferredColorScheme(.dark)
            .modelContainer(modelContainer)
            .environment(appState)
            .environment(syncMonitor)

        // Conditionally inject the Sparkle updater service so the General tab
        // can bind to it. AppStore builds skip this block entirely.
        let settingsView: AnyView
        #if SPARKLE
        if let updaterService {
            settingsView = AnyView(baseView.environmentObject(updaterService))
        } else {
            settingsView = AnyView(baseView)
        }
        #else
        settingsView = AnyView(baseView)
        #endif

        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.contentView = hostingView
        window.title = "Pastel Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 500)
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarSeparatorStyle = .automatic
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
