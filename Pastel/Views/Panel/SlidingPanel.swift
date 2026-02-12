import AppKit

/// Borderless NSPanel subclass that slides in from the screen edge.
///
/// Does NOT use `.nonactivatingPanel` — the panel activates Pastel when shown
/// so it can receive keyboard events. PanelController re-activates the previous
/// app on dismiss. Since the app uses `LSUIElement = true`, activation is invisible
/// (no Dock icon or Cmd+Tab entry).
final class SlidingPanel: NSPanel {

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )

        // Floating behavior -- above regular windows and the dock
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        // Transparent background -- NSVisualEffectView in PanelController provides the material
        isOpaque = false
        backgroundColor = .clear

        // Chrome and shadow
        hasShadow = true
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        appearance = NSAppearance(named: .darkAqua)
    }

    // MARK: - Key / Main Behavior

    /// Allow key status so the panel can receive keyboard events
    /// (forward-compatible for Phase 4 search field).
    override var canBecomeKey: Bool { true }

    /// Never become main window -- the active app retains main status.
    override var canBecomeMain: Bool { false }

}

// MARK: - First-Mouse Content View

/// Custom NSView that accepts the first mouse click immediately.
/// Used as the container view for SlidingPanel so clicks on the panel
/// register without requiring a separate activation click first.
final class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
