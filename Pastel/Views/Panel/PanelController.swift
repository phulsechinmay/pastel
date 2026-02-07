import AppKit
import SwiftUI
import SwiftData
import OSLog

/// Observable class that bridges paste actions from SwiftUI views to AppKit.
///
/// Passed into the SwiftUI environment so PanelContentView can trigger paste
/// without coupling to AppKit or PanelController directly.
@MainActor @Observable
final class PanelActions {
    var pasteItem: ((ClipboardItem) -> Void)?
    var pastePlainTextItem: ((ClipboardItem) -> Void)?
    var copyOnlyItem: ((ClipboardItem) -> Void)?
    /// Incremented each time the panel is shown; observed by PanelContentView to reset focus.
    var showCount = 0
}

/// Manages the lifecycle of the sliding clipboard panel: creation, show/hide
/// animation, screen detection, and dismiss-on-click-outside / Escape monitors.
@MainActor
final class PanelController {

    // MARK: - Constants

    private let animationDuration: TimeInterval = 0.2

    // MARK: - Private State

    private var panel: SlidingPanel?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var modelContainer: ModelContainer?
    private var appState: AppState?

    /// The app that was frontmost before the panel was shown.
    /// Captured in show() so paste-back targets the correct app.
    private var previousApp: NSRunningApplication?

    /// Observable actions bridge for SwiftUI views.
    let panelActions = PanelActions()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "PanelController"
    )

    /// The currently configured panel edge, read from UserDefaults.
    private var currentEdge: PanelEdge {
        PanelEdge(rawValue: UserDefaults.standard.string(forKey: "panelEdge") ?? "right") ?? .right
    }

    // MARK: - Public API

    /// Callback invoked when a SwiftUI view triggers a paste action.
    /// Set by AppState during setupPanel() to wire into PasteService.
    var onPasteItem: ((ClipboardItem) -> Void)?

    /// Callback invoked when a SwiftUI view triggers a plain text paste action.
    /// Set by AppState during setupPanel() to wire into PasteService.pastePlainText.
    var onPastePlainTextItem: ((ClipboardItem) -> Void)?

    /// Callback invoked when a SwiftUI view triggers an explicit copy-only action.
    /// Set by AppState during setupPanel() to wire into PasteService.copyOnly.
    var onCopyOnlyItem: ((ClipboardItem) -> Void)?

    /// Whether the panel is currently visible on screen.
    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    /// Toggle the panel: show if hidden, hide if visible.
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Store the model container so the hosted SwiftUI view can access SwiftData.
    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    /// Store the app state so the panel's SwiftUI views can observe item count changes.
    func setAppState(_ state: AppState) {
        self.appState = state
    }

    // MARK: - Show / Hide

    /// Slide the panel in from the configured screen edge.
    func show() {
        // Capture the frontmost app BEFORE showing the panel.
        // Because the panel uses .nonactivatingPanel, Pastel never becomes frontmost,
        // but we store this reference for edge cases and future use.
        previousApp = NSWorkspace.shared.frontmostApplication

        let edge = currentEdge
        let screen = screenWithMouse()
        let screenFrame = screen.visibleFrame

        // If the panel exists but orientation changed (vertical<->horizontal), recreate it.
        if let existingPanel = panel {
            let existingIsVertical = existingPanel.frame.width < existingPanel.frame.height
            if existingIsVertical != edge.isVertical {
                existingPanel.orderOut(nil)
                self.panel = nil
            }
        }

        if panel == nil {
            createPanel()
        }

        // Sync paste callbacks to panelActions (in case they were set after panel creation)
        panelActions.pasteItem = onPasteItem
        panelActions.pastePlainTextItem = onPastePlainTextItem
        panelActions.copyOnlyItem = onCopyOnlyItem
        panelActions.showCount += 1

        guard let panel else { return }

        let onScreen = edge.onScreenFrame(screenFrame: screenFrame)
        let offScreen = edge.offScreenFrame(screenFrame: screenFrame)

        panel.setFrame(offScreen, display: false)
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(onScreen, display: true)
        }

        installEventMonitors()
        logger.info("Panel shown on \(edge.rawValue) edge of screen: \(screen.localizedName)")
    }

    /// Slide the panel off-screen in the direction of the configured edge and order it out.
    func hide() {
        guard let panel, panel.isVisible else { return }

        let edge = currentEdge
        let screenFrame = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        let offScreen = edge.offScreenFrame(screenFrame: screenFrame)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offScreen, display: true)
        } completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.removeEventMonitors()
            self?.previousApp = nil
        }

        logger.info("Panel hidden from \(edge.rawValue) edge")
    }

    /// Handle a panel edge change from Settings.
    ///
    /// If the panel is visible, hide it immediately. Then destroy the panel
    /// so it gets recreated with the correct orientation on next toggle.
    func handleEdgeChange() {
        if isVisible {
            // Quick hide without animation
            panel?.orderOut(nil)
            removeEventMonitors()
            previousApp = nil
        }
        panel = nil
        let newEdge = currentEdge
        logger.info("Panel edge changed to \(newEdge.rawValue), panel will recreate on next toggle")
    }

    // MARK: - Screen Detection

    /// Find the NSScreen that currently contains the mouse cursor.
    private func screenWithMouse() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return screen
            }
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - Event Monitors

    /// Install monitors to dismiss the panel on click-outside or Escape key.
    private func installEventMonitors() {
        // Dismiss on any mouse click outside the panel
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.hide()
        }

        // Dismiss on Escape key (local monitor so we can consume the event)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.hide()
                return nil // consume the event
            }
            return event
        }
    }

    /// Remove all event monitors.
    private func removeEventMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    // MARK: - Panel Creation

    /// Create the SlidingPanel with NSVisualEffectView background and hosted SwiftUI content.
    private func createPanel() {
        let slidingPanel = SlidingPanel()

        // Dark vibrancy material background
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.appearance = NSAppearance(named: .darkAqua)

        slidingPanel.contentView = visualEffectView

        // Sync paste callbacks into panelActions before creating SwiftUI view
        panelActions.pasteItem = onPasteItem
        panelActions.pastePlainTextItem = onPastePlainTextItem
        panelActions.copyOnlyItem = onCopyOnlyItem

        // Host SwiftUI content inside the visual effect view
        let contentView = PanelContentView()
            .environment(\.colorScheme, .dark)
            .environment(panelActions)

        let hostingView: NSView
        if let container = modelContainer, let appState {
            let hv = NSHostingView(rootView: contentView
                .environment(appState)
                .modelContainer(container))
            hv.translatesAutoresizingMaskIntoConstraints = false
            hostingView = hv
        } else if let container = modelContainer {
            let hv = NSHostingView(rootView: contentView.modelContainer(container))
            hv.translatesAutoresizingMaskIntoConstraints = false
            hostingView = hv
            logger.warning("Panel created without AppState -- live refresh will not work")
        } else {
            let hv = NSHostingView(rootView: contentView)
            hv.translatesAutoresizingMaskIntoConstraints = false
            hostingView = hv
            logger.warning("Panel created without ModelContainer -- @Query will not work")
        }

        visualEffectView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
        ])

        self.panel = slidingPanel
    }
}
