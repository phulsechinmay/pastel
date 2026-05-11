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
    var onDragStarted: (() -> Void)?
    /// Incremented each time the panel is shown; observed by PanelContentView to reset focus
    /// and by FilteredCardListView to refresh data without view recreation.
    var showCount = 0
}

/// Manages the lifecycle of the sliding clipboard panel: creation, show/hide
/// animation, screen detection, and dismiss-on-click-outside / Escape monitors.
///
/// The panel is a non-activating `NSPanel`: it becomes the key window (so it
/// receives keyboard events) but never activates Pastel as an app. The user's
/// previously frontmost app keeps focus throughout, which makes paste-back
/// trivial and means dismissing the panel doesn't push Settings/Edit windows
/// behind some other app.
@MainActor
final class PanelController {

    // MARK: - Constants

    /// Set to `false` to keep the panel open for testing (disables all auto-dismiss triggers).
    private let autoDismissEnabled = true
    private let animationDuration: TimeInterval = 0.1

    // MARK: - Private State

    private var panel: SlidingPanel?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var dragEndMonitor: Any?
    private var screenChangeObserver: Any?
    private var modelContainer: ModelContainer?
    private var appState: AppState?

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

    /// Whether a drag session is in progress from a clipboard card.
    /// When true, the global click monitor will NOT dismiss the panel.
    var isDragging: Bool = false

    /// Callback invoked when a drag session starts from a clipboard card.
    /// Set by AppState to wire into ClipboardMonitor.skipNextChange.
    var onDragStarted: (() -> Void)?

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

    /// The CGWindowID of the panel, used for `screencapture -l` during visual verification.
    var panelWindowNumber: Int {
        panel?.windowNumber ?? 0
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

    /// Called when a card drag session begins.
    /// Installs a global mouse-up monitor to detect when the drag ends.
    func dragSessionStarted() {
        isDragging = true
        onDragStarted?() // Notify AppState to set clipboardMonitor.skipNextChange

        // Install one-shot mouse-up monitor to detect drag end
        dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            // Clean up this one-shot monitor immediately
            if let monitor = self?.dragEndMonitor {
                NSEvent.removeMonitor(monitor)
                self?.dragEndMonitor = nil
            }
            // Delay isDragging reset to allow receiving app to process the drop
            // and avoid the drop triggering a new clipboard history entry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.isDragging = false
                // Auto-dismiss panel after drag-to-paste if setting is enabled (default: true)
                // UserDefaults.bool(forKey:) returns false for unset keys, so check for nil explicitly
                let defaults = UserDefaults.standard
                let dismissAfterDrag = defaults.object(forKey: "dismissAfterDragPaste") == nil
                    || defaults.bool(forKey: "dismissAfterDragPaste")
                if dismissAfterDrag {
                    self?.hide()
                }
            }
        }
    }

    // MARK: - Show / Hide

    /// Slide the panel in from the configured screen edge.
    ///
    /// Because the panel is non-activating, the previous app stays frontmost
    /// throughout — no app switch happens, and no `previousApp` tracking is needed.
    func show() {
        let edge = currentEdge
        let screen = screenWithMouse()

        // Build a frame that covers the dock but not the menu bar.
        // screen.frame includes everything; screen.visibleFrame excludes dock + menu bar.
        // Menu bar is at the top (maxY in Cocoa coordinates).
        let fullFrame = screen.frame
        let menuBarHeight = fullFrame.maxY - screen.visibleFrame.maxY
        let screenFrame = NSRect(
            x: fullFrame.origin.x,
            y: fullFrame.origin.y,
            width: fullFrame.width,
            height: fullFrame.height - menuBarHeight
        )

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
        panelActions.onDragStarted = { [weak self] in
            self?.dragSessionStarted()
        }
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
        logger.info("Panel windowNumber (for screencapture -l): \(panel.windowNumber)")
    }

    /// Slide the panel off-screen in the direction of the configured edge and order it out.
    ///
    /// Because the panel never activated Pastel, focus is already with whichever
    /// app the user was using before; nothing needs to be re-activated on dismiss.
    func hide() {
        guard let panel, panel.isVisible else { return }

        // Commit any pending soft-deletion before hiding the panel.
        // This permanently deletes the item, clearing the undo buffer.
        if let modelContext = appState?.modelContainer?.mainContext {
            appState?.deletionManager.commitPendingDeletion(in: modelContext)
        }

        let edge = currentEdge

        // Compute expanded frame covering dock but not menu bar (mirrors show())
        let activeScreen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let fullFrame = activeScreen.frame
        let menuBarHeight = fullFrame.maxY - activeScreen.visibleFrame.maxY
        let screenFrame = NSRect(
            x: fullFrame.origin.x,
            y: fullFrame.origin.y,
            width: fullFrame.width,
            height: fullFrame.height - menuBarHeight
        )

        let offScreen = edge.offScreenFrame(screenFrame: screenFrame)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offScreen, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                self?.removeEventMonitors()
            }
        }

        logger.info("Panel hidden from \(edge.rawValue) edge")
    }

    /// Handle a panel edge change from Settings.
    ///
    /// If the panel is visible, hide it immediately. Then destroy the panel
    /// so it gets recreated with the correct orientation on next toggle.
    func handleEdgeChange(reopen: Bool = false) {
        let wasVisible = isVisible
        if wasVisible {
            // Quick hide without animation
            panel?.orderOut(nil)
            removeEventMonitors()
        }
        panel = nil
        let newEdge = currentEdge
        logger.info("Panel edge changed to \(newEdge.rawValue), panel will recreate on next toggle")

        if wasVisible || reopen {
            toggle()
        }
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

    /// Install monitors to dismiss the panel on click-outside, Escape key, or
    /// screen disconnect.
    private func installEventMonitors() {
        guard autoDismissEnabled else { return }

        // Dismiss on any mouse click outside the panel.
        // Global monitor fires for clicks in other apps; check against all visible
        // Pastel windows so secondary windows (Settings, Edit, etc.) don't trigger dismiss.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard self?.isDragging != true else { return }
            let clickLocation = NSEvent.mouseLocation
            let clickedInsideApp = NSApp.windows.contains { window in
                window.isVisible && window.frame.contains(clickLocation)
            }
            if !clickedInsideApp {
                self?.hide()
            }
        }

        // Dismiss on Escape key (local monitor so we can consume the event).
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.hide()
                return nil // consume the event
            }
            return event
        }

        // Dismiss when the panel's screen disconnects (hot-plug, sleep wake on
        // a different monitor layout, etc.) so the panel doesn't end up stranded.
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                // If the panel's screen is no longer in the screens list, dismiss.
                let stillConnected = NSScreen.screens.contains { screen in
                    screen.frame.intersects(panel.frame)
                }
                if !stillConnected {
                    self.hide()
                }
            }
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
        if let monitor = dragEndMonitor {
            NSEvent.removeMonitor(monitor)
            dragEndMonitor = nil
        }
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
        isDragging = false
    }

    // MARK: - Panel Creation

    /// Create the SlidingPanel with transparent background and hosted SwiftUI content.
    ///
    /// On macOS 26+, wraps the SwiftUI content in `NSGlassEffectView` for native Liquid Glass.
    /// On pre-26, uses `NSVisualEffectView(state: .active)` for consistent behind-window blur.
    private func createPanel() {
        let slidingPanel = SlidingPanel()

        // Transparent background — glass/blur is provided by AppKit views below
        slidingPanel.backgroundColor = .clear
        slidingPanel.isOpaque = false

        let containerView = FirstMouseView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor

        // Round all 4 corners uniformly. NSGlassEffectView also uses the same radius,
        // so both layers agree and no black corner gaps appear.
        containerView.layer?.cornerRadius = PanelLayout.panelCornerRadius
        containerView.layer?.masksToBounds = true

        slidingPanel.contentView = containerView

        // Sync paste callbacks into panelActions before creating SwiftUI view
        panelActions.pasteItem = onPasteItem
        panelActions.pastePlainTextItem = onPastePlainTextItem
        panelActions.copyOnlyItem = onCopyOnlyItem
        panelActions.onDragStarted = { [weak self] in
            self?.dragSessionStarted()
        }

        // Build SwiftUI content
        let contentView = PanelContentView()
            .environment(\.colorScheme, .dark)
            .environment(panelActions)

        let hostingView: NSView
        if let container = modelContainer, let appState {
            let hv = NSHostingView(rootView: contentView
                .environment(appState)
                .modelContainer(container))
            hv.translatesAutoresizingMaskIntoConstraints = false
            hv.sizingOptions = []
            hostingView = hv
        } else if let container = modelContainer {
            let hv = NSHostingView(rootView: contentView.modelContainer(container))
            hv.translatesAutoresizingMaskIntoConstraints = false
            hv.sizingOptions = []
            hostingView = hv
            logger.warning("Panel created without AppState -- live refresh will not work")
        } else {
            let hv = NSHostingView(rootView: contentView)
            hv.translatesAutoresizingMaskIntoConstraints = false
            hv.sizingOptions = []
            hostingView = hv
            logger.warning("Panel created without ModelContainer -- @Query will not work")
        }

        // Transparent hosting view so glass/blur shows through
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        // Glass/blur treatment
        if #available(macOS 26, *) {
            // NSGlassEffectView renders Liquid Glass at the AppKit/compositor level.
            let glassView = NSGlassEffectView()
            glassView.cornerRadius = PanelLayout.panelCornerRadius
            glassView.translatesAutoresizingMaskIntoConstraints = false
            glassView.contentView = hostingView
            containerView.addSubview(glassView)
            NSLayoutConstraint.activate([
                glassView.topAnchor.constraint(equalTo: containerView.topAnchor),
                glassView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                glassView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            ])
        } else {
            // Pre-macOS 26: NSVisualEffectView with forced active state for consistent blur
            let visualEffect = NSVisualEffectView()
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.material = .hudWindow
            visualEffect.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(visualEffect)
            NSLayoutConstraint.activate([
                visualEffect.topAnchor.constraint(equalTo: containerView.topAnchor),
                visualEffect.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                visualEffect.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                visualEffect.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            ])
            containerView.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            ])
        }

        self.panel = slidingPanel
    }
}
