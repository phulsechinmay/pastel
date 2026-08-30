import SwiftUI

/// Centralized namespace for every colour, elevation, and type decision in the UI.
///
/// The sibling of `PanelLayout`, which owns geometry. Same doctrine: no raw
/// `Color.white.opacity(_:)` and no raw `.system(size:)` should appear in any view
/// file. Before this existed the two directories had accumulated twelve distinct
/// white opacities (including both `0.1` and `0.10`) and sixteen hardcoded point
/// sizes, so "one step up from the card" meant a different value in every file.
///
/// Two deliberate decisions worth knowing about:
///
/// 1. **Surfaces derive from `Color.primary`, not `Color.white`.** The panel used to
///    be pinned to `.preferredColorScheme(.dark)`, which is what made hardcoded white
///    overlays safe. Now that it follows the system appearance, an overlay has to
///    invert with it. `Color.primary` does that for free and is what the native
///    materials do.
///
/// 2. **Neutrals are not tinted toward the brand hue.** The usual rule is to push
///    every neutral a few points toward the accent. That rule assumes an opaque
///    surface. These overlays sit on translucent glass over whatever the user
///    happens to have on screen, so a hue-tinted overlay would shift unpredictably
///    against the backdrop instead of reading as a consistent tint. The accent
///    earns its keep on selection and active state instead.
enum PanelStyle {

    // MARK: - Surfaces
    //
    // A four-step elevation ramp plus one recessed step. Every filled rectangle,
    // capsule, and well in the app picks one of these. Nothing picks its own number.

    /// Wells that sit *below* the resting surface: image placeholders, the screen
    /// diagram body. Reads as a hole, not a card.
    static let surfaceRecessed = Color.primary.opacity(0.04)

    /// The resting surface. Cards at rest, search fields, text editors, swatch wells.
    static let surface = Color.primary.opacity(0.06)

    /// One step up: things that sit *on* a surface. Chips, badges, keycaps.
    static let surfaceRaised = Color.primary.opacity(0.10)

    /// Pointer is over it. Must be visibly distinct from `surfaceRaised` at a glance,
    /// which is why the ramp steps by 0.04 here rather than the 0.01 increments the
    /// old ad-hoc values had drifted into.
    static let surfaceHover = Color.primary.opacity(0.14)

    /// Pressed, or the selected cell inside a picker (the chosen emoji, say).
    static let surfaceActive = Color.primary.opacity(0.20)

    // MARK: - Strokes

    /// Hairline borders and dividers on a resting surface.
    static let stroke = Color.primary.opacity(0.10)

    /// Borders that need to hold their own against a filled or coloured surface,
    /// e.g. the outline on a colour card whose fill is arbitrary.
    static let strokeStrong = Color.primary.opacity(0.18)

    // MARK: - Selection
    //
    // Selection is the single most important state in a keyboard-driven panel: arrow
    // keys move it and Return acts on it. It gets an exclusive visual signal that
    // content can never imitate.
    //
    // The signal is a ring drawn *outside* the card's bounds, floating in the layout
    // gutter (see `PanelLayout.selectionRingInset`). A `.color` clip whose value
    // happens to be the accent used to be indistinguishable from a selected card,
    // because both were "a blue rectangle". A detached ring is structural: content
    // cannot draw outside its own frame, so the ambiguity is gone by construction
    // rather than by picking a luckier colour.

    /// The outset ring. The primary and sufficient selection signal.
    static let selectionRing = Color.accentColor

    /// Optional interior wash on selected cards. Deliberately weak: it is a supporting
    /// cue, not the signal. Colour cards skip it entirely so their value stays true.
    static let selectionFill = Color.accentColor.opacity(0.18)

    /// Drop targets use interior fill + inset border, a different geometry from
    /// selection's outset ring, so the two states never read as the same thing.
    static let dropTargetFill = Color.accentColor.opacity(0.15)
    static let dropTargetStroke = Color.accentColor

    /// Active chip / active filter menu.
    static let chipActiveFill = Color.accentColor.opacity(0.28)
    static let chipActiveStroke = Color.accentColor.opacity(0.60)

    /// Selection ring for swatches whose own fill *is* the content: label colours,
    /// emoji cells. Neutral rather than accent, and drawn outside the swatch, for the
    /// same reason the card ring exists. An accent ring around a blue swatch
    /// reintroduces exactly the ambiguity the card ring was built to remove, and a
    /// white ring (what this used to be) disappears against a yellow one.
    static let swatchSelectionRing = Color.primary

    // MARK: - Text
    //
    // Five steps at roughly a 1.2 ratio, expressed as system text styles rather than
    // point sizes so the panel inherits platform metrics and accessibility text
    // sizing. The old ladder had 11pt and 12pt as separate "levels", a 1.09 ratio
    // that no one can see, while 8pt and 9pt sat below the platform's legibility
    // floor entirely. Those collapse into `meta`.

    enum Text {
        /// ~10pt. Timestamps, keycap badges, language badges, compact label chips.
        static let meta = Font.caption

        /// ~11pt. Interactive control labels: chips, filter menus, toolbar affordances.
        static let control = Font.subheadline

        /// ~12pt. Card content, search input, editor body.
        static let body = Font.callout

        /// ~13pt semibold. Card titles and inline section heads.
        static let title = Font.headline

        /// ~26pt. Reserved for the one display moment in the app: the hex value on a
        /// colour card, where the type *is* the content.
        static let display = Font.largeTitle
    }

    // MARK: - Icons
    //
    // SF Symbols follow the same ladder so a glyph and its adjacent label stay in
    // proportion. Symbols take explicit sizes because they are not body text and
    // should not reflow, but the sizes are derived from the steps above.

    enum Icon {
        /// Pairs with `Text.meta`. Pin glyphs, chevrons, inline status dots.
        static let meta = Font.system(size: 10)

        /// Pairs with `Text.control`. Search magnifier, clear buttons, chip glyphs.
        static let control = Font.system(size: 12)

        /// Toolbar actions. Sized for a comfortable hit target, see
        /// `PanelLayout.toolbarButtonSize`.
        static let action = Font.system(size: 14)

        /// Leading glyphs inside card content: globe, document, photo placeholder.
        static let content = Font.system(size: 16)

        /// Empty and unavailable states.
        static let empty = Font.system(size: 40)
    }

    // MARK: - Helpers

    /// Foreground for text drawn on an arbitrary user colour (colour cards), where
    /// `.primary` and `.secondary` cannot be trusted. `tint` is the contrast colour
    /// already computed from the swatch's luminance.
    static func onColor(_ tint: Color, secondary: Bool = false) -> Color {
        secondary ? tint.opacity(0.70) : tint
    }

    /// Surface for a chip or badge drawn on an arbitrary user colour.
    static func surfaceOnColor(_ tint: Color) -> Color {
        tint.opacity(0.15)
    }
}

// MARK: - Chip Chrome

/// The single chip specification, applied by every capsule control in the panel.
///
/// There used to be two: the label chips (24pt fixed height, 10pt padding,
/// `white.opacity(0.1)`) and the Type/App/Date filter menus (4pt vertical padding,
/// 8pt horizontal, `white.opacity(0.07)` with a `0.10` border). They render one
/// directly above the other in the panel, close enough to look like a mistake rather
/// than a distinction. This is now the only place either shape is described.
struct ChipChrome: ViewModifier {
    var isActive: Bool = false
    /// Overrides the resting fill for chips drawn on an arbitrary user colour.
    var tintOverride: Color?
    /// Compact chips (card footers) shrink-wrap their content instead of taking the
    /// full control height.
    var isCompact: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, isCompact ? 5 : PanelLayout.chipHorizontalPadding)
            .padding(.vertical, isCompact ? 2 : 0)
            .frame(height: isCompact ? nil : PanelLayout.chipHeight)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(strokeColor, lineWidth: 1))
    }

    private var fill: Color {
        if let tintOverride { return PanelStyle.surfaceOnColor(tintOverride) }
        return isActive ? PanelStyle.chipActiveFill : PanelStyle.surfaceRaised
    }

    private var strokeColor: Color {
        isActive ? PanelStyle.chipActiveStroke : .clear
    }
}

extension View {
    /// Apply the shared chip capsule: fill, border, height, and padding.
    func chipChrome(isActive: Bool = false, tintOverride: Color? = nil, isCompact: Bool = false) -> some View {
        modifier(ChipChrome(isActive: isActive, tintOverride: tintOverride, isCompact: isCompact))
    }
}
