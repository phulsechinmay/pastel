import SwiftUI

/// Card content for `.color` clipboard items.
///
/// Shows a large monospaced hex title. For non-hex formats (rgb, hsl),
/// the original text is shown as a smaller subtitle. The actual card
/// background color is handled by ClipboardCardView which colors the
/// entire card (including header) for `.color` items.
struct ColorCardView: View {

    let item: ClipboardItem
    var isCompactStrip = false

    /// Whether the original text differs from the current detected hex.
    private var showsOriginalSubtitle: Bool {
        guard let text = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        let upper = text.uppercased()
        let hexDisplay = "#\(item.detectedColorHex ?? "")"
        return upper != hexDisplay.uppercased() && upper != (item.detectedColorHex ?? "").uppercased()
    }

    /// Whether the original text was a hex format (user edited the color)
    /// vs a non-hex format like rgb()/hsl() (original was always different).
    private var originalWasHex: Bool {
        guard let text = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        let hexPattern = /^#?[0-9a-fA-F]{3}([0-9a-fA-F]{3})?$/
        return text.wholeMatch(of: hexPattern) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Large hex title
            Text("#\(item.detectedColorHex ?? "------")")
                .font(PanelStyle.Text.display.weight(.bold).monospaced())

            // Original format subtitle (for rgb/hsl or edited hex)
            if !isCompactStrip && showsOriginalSubtitle {
                Text(originalWasHex ? "Original: \(item.textContent ?? "")" : item.textContent ?? "")
                    .font(PanelStyle.Text.meta.monospaced())
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Color Parsing Helpers

/// Parses a 6-digit hex string (no #) into a SwiftUI Color.
func colorFromHex(_ hex: String?) -> Color {
    guard let hex, hex.count == 6 else { return .gray }
    let scanner = Scanner(string: hex)
    var rgb: UInt64 = 0
    guard scanner.scanHexInt64(&rgb) else { return .gray }
    return Color(
        red: Double((rgb >> 16) & 0xFF) / 255.0,
        green: Double((rgb >> 8) & 0xFF) / 255.0,
        blue: Double(rgb & 0xFF) / 255.0
    )
}

/// Returns white or black based on the luminance of a 6-digit hex color.
func contrastingColor(forHex hex: String?) -> Color {
    guard let hex, hex.count == 6 else { return .white }
    let scanner = Scanner(string: hex)
    var rgb: UInt64 = 0
    guard scanner.scanHexInt64(&rgb) else { return .white }
    let r = Double((rgb >> 16) & 0xFF) / 255.0
    let g = Double((rgb >> 8) & 0xFF) / 255.0
    let b = Double(rgb & 0xFF) / 255.0
    func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    // Choose whichever foreground has the stronger WCAG contrast ratio.
    return luminance > 0.179 ? .black : .white
}
