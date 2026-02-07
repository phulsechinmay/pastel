import SwiftUI

/// Card content for `.color` clipboard items.
///
/// Renders the entire card background as the detected color with a large
/// monospaced hex title overlaid. The hex text uses a contrasting color
/// (white or black) for readability. For non-hex formats (rgb, hsl),
/// the original text is shown as a smaller subtitle.
struct ColorCardView: View {

    let item: ClipboardItem
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    /// Parses the 6-digit hex string (no #) into a SwiftUI Color.
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

    /// Returns white or black text based on the luminance of the detected color.
    private var contrastingTextColor: Color {
        guard let hex = item.detectedColorHex, hex.count == 6 else {
            return .white
        }
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else { return .white }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        // Relative luminance (WCAG formula)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.5 ? .black : .white
    }

    /// Whether the original text is a non-hex format that warrants a subtitle.
    private var showsOriginalSubtitle: Bool {
        guard let text = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        let upper = text.uppercased()
        let hexDisplay = "#\(item.detectedColorHex ?? "")"
        // Show subtitle if the original text isn't just the hex value
        return upper != hexDisplay.uppercased() && upper != (item.detectedColorHex ?? "").uppercased()
    }

    var body: some View {
        ZStack {
            // Full card background color
            RoundedRectangle(cornerRadius: 8)
                .fill(swatchColor)

            // Subtle border for very dark colors
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)

            // Text overlay
            VStack(alignment: .leading, spacing: 2) {
                // Large hex title
                Text("#\(item.detectedColorHex ?? "------")")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(contrastingTextColor)

                // Original format subtitle (for rgb/hsl)
                if showsOriginalSubtitle {
                    Text(item.textContent ?? "")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(contrastingTextColor.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}
