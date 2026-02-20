import CoreGraphics

/// Centralized namespace for all panel layout dimension constants.
///
/// Every numeric literal that controls panel sizing, card dimensions,
/// spacing, padding, or corner radii lives here. No raw numbers should
/// appear in frame/padding/cornerRadius calls across panel files.
enum PanelLayout {
    // Panel outer dimensions
    static let edgeInset: CGFloat = 10
    static let panelOuterPadding: CGFloat = 10
    static let panelCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 10

    // Vertical panel (left/right edges)
    static let verticalPanelWidth: CGFloat = 320

    // Horizontal panel (top/bottom edges)
    static let horizontalPanelHeight: CGFloat = 265
    static let horizontalCardWidth: CGFloat = 260

    // Card dimensions
    static let cardSpacing: CGFloat = 8
    static let cardHorizontalPadding: CGFloat = 14
    static let cardVerticalPadding: CGFloat = 10
    static let cardMinHeightDefault: CGFloat = 80
    static let cardMinHeightImage: CGFloat = 120
    static let cardMinHeightURL: CGFloat = 140
    static let cardMaxHeight: CGFloat = 195
}
