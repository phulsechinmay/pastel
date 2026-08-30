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
    /// Vertical spacing between wrapped chip rows (matches WrappingFlowLayout usage).
    static let chipRowSpacing: CGFloat = 6
    /// Horizontal spacing between chips in a row.
    static let chipSpacing: CGFloat = 6
    /// Leading/trailing padding inside a chip. Shared by the label chips and the
    /// Type/App/Date filter menus, which used to run 10pt and 8pt respectively and
    /// sit directly above each other looking almost-but-not-quite aligned.
    static let chipHorizontalPadding: CGFloat = 10
    /// Hard ceiling on wrapped chip rows before the remainder collapses into a
    /// "+N" overflow chip. Without a cap the filter bar grows without bound and a
    /// user with a dozen labels gets a panel that is mostly chrome.
    static let chipMaxRows: Int = 2

    // Toolbar
    /// Hit target for the panel's toolbar buttons. The glyphs are 14pt; without an
    /// explicit frame the tappable area collapsed to roughly the glyph's own bounds.
    static let toolbarButtonSize: CGFloat = 24
    /// Height of the panel's brand mark. Small on purpose: the user invoked this
    /// panel with a hotkey and knows what app it is, so the mark identifies without
    /// competing with the content it sits above.
    static let brandMarkHeight: CGFloat = 20

    // Card dimensions
    static let cardSpacing: CGFloat = 8
    static let cardHorizontalPadding: CGFloat = 14
    static let cardVerticalPadding: CGFloat = 10
    static let cardMinHeightDefault: CGFloat = 80
    static let cardMinHeightImage: CGFloat = 120
    static let cardMinHeightURL: CGFloat = 140
    static let cardMaxHeight: CGFloat = 200

    /// How far outside the card the selection ring is drawn. Sits in the layout
    /// gutter (`cardSpacing` is 8), which is what makes the ring unmistakably chrome
    /// rather than something the card's own content could have produced.
    static let selectionRingInset: CGFloat = 3
    /// Ring thickness. 2pt so it survives against a saturated colour card.
    static let selectionRingWidth: CGFloat = 2
    /// Padding reserved inside the card scroll views so the outset ring has somewhere
    /// to be drawn. A `ScrollView` clips to its own bounds, and a `LazyHStack` sizes
    /// exactly to its cards, so without this gutter the ring's top and bottom edges are
    /// cut off on every card and its leading/trailing edges are cut off on the first and
    /// last. Drawing outside the frame only works if the frame has room outside it.
    static let selectionRingGutter: CGFloat = selectionRingInset

    /// Height of the source-app colour wash at the top of a card. Confined to the
    /// header row so it reads as an app tint. It used to run a 0.5-opacity gradient
    /// across the top half of the whole card, which meant a Chrome clip got a heavy
    /// gold wash and a VS Code clip got almost nothing, and the Chrome card looked
    /// selected when it was not.
    static let cardAppWashHeight: CGFloat = 44

    /// Ceiling on an image card's preview. Keeps one tall screenshot from dominating
    /// a grid row in the History browser while still filling the card in the panel.
    static let cardImageMaxHeight: CGFloat = 120

    // URL cards
    /// Fixed height of a URL card's og:image banner.
    ///
    /// The banner used to run at a pure 2:1 aspect, which at the panel's ~265pt card
    /// width made it 132pt: 65% of the card, and enough to push the enriched state
    /// past `cardMaxHeight` before its own text had been laid out. That is why the raw
    /// URL was dropped from this state in the first place. The banner is also the
    /// least discriminating thing on the card (two links to the same site produce the
    /// same picture), so it is what pays for the URL line.
    ///
    /// Fixed rather than capped-proportional on purpose: every URL card gets the same
    /// banner, so their text blocks line up down a scrolling list instead of drifting
    /// with the panel's width.
    ///
    /// 106 rather than the 96 this started at. 96 left a visible gap between the URL
    /// line and the card's footer row, and dead space under the content is worse than
    /// a slightly taller picture: it reads as a layout that failed to fill itself.
    /// The banner absorbs the slack because it is the only element here that can
    /// change size without changing what the card says.
    static let cardURLBannerHeight: CGFloat = 106
    static let cardURLBannerCornerRadius: CGFloat = 6
    /// Favicon that stands in for a banner when the site's og:image is favicon-sized.
    /// Centred inside a full-height `cardURLBannerHeight` slot rather than shrinking
    /// the slot to fit, so the text below it lands where a banner card's text does.
    static let cardURLSmallImageSize: CGFloat = 64
    static let cardURLSmallImageCornerRadius: CGFloat = 8
    /// Leading glyph (favicon or globe) on a URL card's metadata rows.
    static let urlGlyphSize: CGFloat = 16
    /// Gap between that glyph and the text beside it. The URL line is inset by glyph
    /// plus gap so it shares a left edge with the title above it rather than starting
    /// under the favicon.
    static let urlGlyphSpacing: CGFloat = 6
    /// Gap between the title and the URL beneath it. Tighter than `cardSpacing`
    /// because the two are one block, not two.
    static let urlMetadataLineSpacing: CGFloat = 2
}
