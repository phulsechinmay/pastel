import AppKit

/// A non-activating NSPanel subclass that slides in from the screen edge.
///
/// Uses `.nonactivatingPanel` style mask so it never steals focus from the
/// frontmost application. Configured as a floating, borderless, transparent
/// panel with shadow for the sliding clipboard history browser.
final class SlidingPanel: NSPanel {

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )

        // Floating behavior -- always visible above regular windows
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        // Transparent background -- NSVisualEffectView provides the material
        isOpaque = false
        backgroundColor = .clear

        // Chrome and shadow
        hasShadow = true
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
    }

    // MARK: - Key / Main Behavior

    /// Allow key status so the panel can receive keyboard events
    /// (forward-compatible for Phase 4 search field).
    override var canBecomeKey: Bool { true }

    /// Never become main window -- the active app retains main status.
    override var canBecomeMain: Bool { false }
}
