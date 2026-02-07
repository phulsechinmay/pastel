import SwiftUI

/// Card content for `.color` clipboard items.
///
/// Displays a 32x32 color swatch alongside the original color text.
/// If the original text is a non-hex format (rgb, hsl), shows the
/// normalized hex value as a secondary label below the text.
/// Falls back to a gray swatch if `detectedColorHex` is nil or malformed.
///
/// In horizontal panel mode (top/bottom edges), increases line limit
/// to fill the taller fixed-height cards.
struct ColorCardView: View {

    let item: ClipboardItem
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    /// Parses the 6-digit hex string (no #) into a SwiftUI Color.
    /// Falls back to gray if the hex is nil or unparseable.
    private var swatchColor: Color {
        guard let hex = item.detectedColorHex, hex.count == 6 else {
            return .gray
        }
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else { return .gray }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }

    /// Whether the original text is a non-hex format (rgb/hsl) that
    /// warrants showing the normalized hex as a subtitle.
    private var showsHexSubtitle: Bool {
        guard let text = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        // If the original text doesn't start with '#', it's rgb/hsl format
        return !text.hasPrefix("#")
    }

    /// The normalized hex value formatted with a '#' prefix for display.
    private var normalizedHexDisplay: String {
        guard let hex = item.detectedColorHex else { return "" }
        return "#\(hex)"
    }

    var body: some View {
        HStack(spacing: 10) {
            // Color swatch
            RoundedRectangle(cornerRadius: 6)
                .fill(swatchColor)
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(item.textContent ?? "")
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(isHorizontal ? 4 : 2)
                    .foregroundStyle(.primary)

                if showsHexSubtitle {
                    Text(normalizedHexDisplay)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
