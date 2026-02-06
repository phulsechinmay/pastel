import AppKit

/// Defines the four screen edges where the sliding panel can appear.
///
/// The enum drives all frame calculations for show/hide animations,
/// replacing the hard-coded right-edge logic in PanelController.
/// The user's preference is persisted via `@AppStorage("panelEdge")`.
enum PanelEdge: String, CaseIterable {
    case left, right, top, bottom

    /// Whether the panel slides horizontally (left/right) and occupies the full screen height.
    var isVertical: Bool { self == .left || self == .right }

    /// Panel dimensions for the given screen frame.
    ///
    /// Vertical edges: 320pt wide, full height.
    /// Horizontal edges: full width, 300pt tall.
    func panelSize(screenFrame: NSRect) -> NSSize {
        if isVertical {
            return NSSize(width: 320, height: screenFrame.height)
        } else {
            return NSSize(width: screenFrame.width, height: 300)
        }
    }

    /// The visible (on-screen) frame for the panel on the given screen.
    func onScreenFrame(screenFrame: NSRect) -> NSRect {
        let size = panelSize(screenFrame: screenFrame)
        switch self {
        case .right:
            return NSRect(
                x: screenFrame.maxX - size.width,
                y: screenFrame.origin.y,
                width: size.width,
                height: size.height
            )
        case .left:
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: size.width,
                height: size.height
            )
        case .top:
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.maxY - size.height,
                width: size.width,
                height: size.height
            )
        case .bottom:
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: size.width,
                height: size.height
            )
        }
    }

    /// The off-screen frame used as the start/end position for slide animations.
    func offScreenFrame(screenFrame: NSRect) -> NSRect {
        let size = panelSize(screenFrame: screenFrame)
        switch self {
        case .right:
            return NSRect(
                x: screenFrame.maxX,
                y: screenFrame.origin.y,
                width: size.width,
                height: size.height
            )
        case .left:
            return NSRect(
                x: screenFrame.origin.x - size.width,
                y: screenFrame.origin.y,
                width: size.width,
                height: size.height
            )
        case .top:
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.maxY,
                width: size.width,
                height: size.height
            )
        case .bottom:
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y - size.height,
                width: size.width,
                height: size.height
            )
        }
    }
}
