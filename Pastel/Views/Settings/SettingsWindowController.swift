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

    /// In-flight activation hand-off (see `hideYieldingActivation`). Held on the
    /// instance rather than captured, so the observer block carries nothing across
    /// the concurrency boundary but `Sendable` values.
    private var activationObserver: NSObjectProtocol?
    private var activationBackstop: DispatchWorkItem?
    private var activationCompletion: ((Bool) -> Void)?

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
        // A paste from Settings leaves the app hidden (see `hideYieldingActivation`),
        // and `makeKeyAndOrderFront` on a hidden app does not reliably show anything.
        NSApp.unhide(nil)

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

        // 1000pt, not 820. The History tab's card grid is the widest thing in this
        // window, and at 820pt (minus the ~200pt sidebar) it could only fit a single
        // column, which made the "browse everything" surface show less per screen
        // than the 320pt panel. Every other tab is content-light and unaffected.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.contentView = hostingView
        window.title = "Pastel Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 500)
        window.titlebarSeparatorStyle = .automatic
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    /// Order the Settings window out, if it is up.
    ///
    /// Paste-back needs this. Unlike the panel, Settings is a normal activating
    /// window, so while it is key a posted ⌘V lands *in Settings* rather than in the
    /// app the user is aiming at. The user reopens from the menu bar.
    ///
    /// Asking the controller for its own window replaces a `NSApp.windows.first { $0.title == … }`
    /// scan, which broke on any title change and silently matched nothing.
    ///
    /// - Returns: `true` if a visible window was ordered out.
    @discardableResult
    func hide() -> Bool {
        guard let window, window.isVisible else { return false }
        window.orderOut(nil)
        return true
    }

    /// Order Settings out, hand activation back to whatever app macOS puts in front
    /// next, and report when it is safe to post ⌘V there.
    ///
    /// `hide()` alone is not enough. Pastel is an `LSUIElement` app that made itself
    /// active in `showSettings`, and `orderOut` hides a *window* — it does not
    /// deactivate the *app*. Pastel stays frontmost with no key window, and a ⌘V
    /// posted into that gap reaches no responder and is silently dropped.
    ///
    /// `NSApp.hide` pops Pastel off the activation stack and lets the system choose
    /// the successor from the real front-to-back order, which is why nothing here
    /// tracks "the previous app" — that shadow copy would go stale every time the
    /// recorded app quit, hid, or moved Spaces.
    ///
    /// Activation is cross-process and asynchronous, so the successor is awaited
    /// rather than assumed. If it never arrives, `completion(false)` says so and the
    /// caller keeps the content on the clipboard instead of posting blind.
    func hideYieldingActivation(completion: @escaping (Bool) -> Void) {
        hide()

        // Not active means there is nothing to yield — nobody has to move for us.
        guard NSApp.isActive else {
            pasteLog("[PASTE] Pastel was not active — posting without yielding")
            completion(true)
            return
        }

        // Whatever was in flight is not this hand-off. Settle it so its observer and
        // backstop are torn down rather than leaked.
        settleActivation(false, reason: "superseded")
        activationCompletion = completion

        // Installed before `NSApp.hide` so a fast successor cannot beat the observer.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            // Read the app out here and carry only strings across: the queue is
            // `.main`, but `NSRunningApplication` is not `Sendable` and the compiler
            // has no way to know that.
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            let bundleID = activated?.bundleIdentifier
            let name = activated?.localizedName

            MainActor.assumeIsolated {
                // Another Pastel surface coming forward is not the app we are aiming
                // at; keep waiting for a real successor.
                guard let bundleID, bundleID != Bundle.main.bundleIdentifier else { return }
                SettingsWindowController.shared.settleActivation(true, reason: name ?? bundleID)
            }
        }

        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                SettingsWindowController.shared.settleActivation(false, reason: "backstop")
            }
        }
        activationBackstop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)

        NSApp.hide(nil)
    }

    /// Resolve the in-flight hand-off exactly once, tearing down both wake-up paths.
    ///
    /// No-op when nothing is in flight, which is what makes the observer and the
    /// backstop safe to race.
    private func settleActivation(_ succeeded: Bool, reason: String) {
        guard let completion = activationCompletion else { return }
        activationCompletion = nil

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        activationBackstop?.cancel()
        activationBackstop = nil

        pasteLog("[PASTE] settings yielded activation (\(reason))")
        completion(succeeded)
    }
}
