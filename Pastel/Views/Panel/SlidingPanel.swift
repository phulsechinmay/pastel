import AppKit

/// Borderless, non-activating `NSPanel` subclass that slides in from the screen edge.
///
/// Uses `.nonactivatingPanel` so the previous app keeps frontmost status — the panel
/// becomes key (and receives keyboard input) without making Pastel the active app.
/// That keeps Pastel's other windows (Settings, Edit) from being pushed behind
/// another app when the panel dismisses, and makes paste-back simpler because the
/// target app's focus is never disturbed in the first place.
final class SlidingPanel: NSPanel {

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.fullSizeContentView, .borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        // Floating behavior -- above Dock (20), below Screenshot overlay (24)
        isFloatingPanel = true
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        level = NSWindow.Level(rawValue: dockLevel + 3)  // 23
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        // Transparent background -- NSVisualEffectView / NSGlassEffectView
        // in PanelController provides the material.
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

    /// Allow key status so the panel can receive keyboard events even though
    /// the app itself does not activate.
    override var canBecomeKey: Bool { true }

    /// Never become main window -- the user's previous app retains main status.
    override var canBecomeMain: Bool { false }
}

// MARK: - First-Mouse Content View

/// Custom NSView that accepts the first mouse click immediately.
/// Used as the container view for SlidingPanel so clicks on the panel
/// register without requiring a separate activation click first.
final class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
