import AppKit
import SwiftUI
import SwiftData
import OSLog

/// Manages the lifecycle of the sliding clipboard panel: creation, show/hide
/// animation, screen detection, and dismiss-on-click-outside / Escape monitors.
@MainActor
final class PanelController {

    // MARK: - Constants

    private let panelWidth: CGFloat = 300
    private let animationDuration: TimeInterval = 0.2

    // MARK: - Private State

    private var panel: SlidingPanel?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var modelContainer: ModelContainer?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "PanelController"
    )

    // MARK: - Public API

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

    // MARK: - Show / Hide

    /// Slide the panel in from the right edge of the screen containing the mouse cursor.
    func show() {
        let screen = screenWithMouse()
        let visibleFrame = screen.visibleFrame

        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        // On-screen: right-aligned within the visible frame, full height
        let onScreenFrame = NSRect(
            x: visibleFrame.maxX - panelWidth,
            y: visibleFrame.origin.y,
            width: panelWidth,
            height: visibleFrame.height
        )

        // Off-screen: just beyond the right edge
        let offScreenFrame = NSRect(
            x: visibleFrame.maxX,
            y: visibleFrame.origin.y,
            width: panelWidth,
            height: visibleFrame.height
        )

        panel.setFrame(offScreenFrame, display: false)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(onScreenFrame, display: true)
        }

        installEventMonitors()
        logger.info("Panel shown on screen: \(screen.localizedName)")
    }

    /// Slide the panel off-screen to the right and order it out.
    func hide() {
        guard let panel, panel.isVisible else { return }

        let visibleFrame = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        let offScreenFrame = NSRect(
            x: visibleFrame.maxX,
            y: panel.frame.origin.y,
            width: panelWidth,
            height: panel.frame.height
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offScreenFrame, display: true)
        } completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.removeEventMonitors()
        }

        logger.info("Panel hidden")
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

        // Host SwiftUI content inside the visual effect view
        let contentView = PanelContentView()
            .environment(\.colorScheme, .dark)

        let hostingView: NSView
        if let container = modelContainer {
            let hv = NSHostingView(rootView: contentView.modelContainer(container))
            hv.translatesAutoresizingMaskIntoConstraints = false
            hostingView = hv
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
