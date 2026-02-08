import AppKit
import SwiftUI

/// Singleton NSWindow manager for the first-launch onboarding window.
///
/// Follows the same NSWindow + NSHostingView pattern as `SettingsWindowController`.
/// The window is non-resizable, dark-themed, and centered on screen.
@MainActor
final class OnboardingWindowController {

    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    /// Show the onboarding window, or bring it to front if already visible.
    ///
    /// - Parameter appState: The app state for environment injection into the onboarding view.
    func showOnboarding(appState: AppState) {
        // If already visible, just bring to front
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView(onDismiss: { [weak self] in
            self?.window?.close()
            self?.window = nil
        })
        .preferredColorScheme(.dark)
        .environment(appState)

        let hostingView = NSHostingView(rootView: onboardingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.contentView = hostingView
        window.title = "Welcome to Pastel"
        window.center()
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    /// Close the onboarding window and release the reference.
    func close() {
        window?.close()
        window = nil
    }
}
