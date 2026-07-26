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
    static let horizontalPanelHeight: CGFloat = 270
    static let horizontalCardWidth: CGFloat = 260

    // Section spacing (between header, search, chips, cards)
    static let sectionSpacing: CGFloat = 6

    // Chip dimensions
    /// Uniform height for all chip-bar chips (label chips, "+", and the inline
    /// create chip). Fixing this makes the create chip match normal chips and gives
    /// the horizontal-panel resize a precise single-row baseline.
    static let chipHeight: CGFloat = 24
    /// Vertical spacing between wrapped chip rows (matches CenteredFlowLayout usage).
    static let chipRowSpacing: CGFloat = 6

    // Card dimensions
    static let cardSpacing: CGFloat = 8
    static let cardHorizontalPadding: CGFloat = 14
    static let cardVerticalPadding: CGFloat = 10
    static let cardMinHeightDefault: CGFloat = 80
    static let cardMinHeightImage: CGFloat = 120
    static let cardMinHeightURL: CGFloat = 140
    static let cardMaxHeight: CGFloat = 200
}
