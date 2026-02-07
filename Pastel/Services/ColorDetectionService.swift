import Foundation

/// Detects standalone color values in clipboard text and normalizes them to 6-digit hex.
///
/// Supports hex (#RGB, #RRGGBB), rgb(), rgba(), hsl(), and hsla() formats.
/// Only matches when the ENTIRE trimmed text is a color value (not embedded in prose).
/// Returns uppercase 6-digit hex without the # prefix (e.g., "FF5733").
struct ColorDetectionService {

    /// Attempts to detect a standalone color value in the text.
    ///
    /// - Parameter text: The clipboard text to analyze.
    /// - Returns: A 6-digit uppercase hex string (no `#` prefix) if the text is a standalone color value, nil otherwise.
    static func detectColor(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip empty or multi-line text (not a standalone color value)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return nil }

        // Try hex patterns first: #RGB, #RRGGBB
        if let hex = matchHex(trimmed) { return hex }

        // Try bare hex: RGB, RRGGBB (without #)
        if let hex = matchBareHex(trimmed) { return hex }

        // Try rgb()/rgba()
        if let hex = matchRGB(trimmed) { return hex }

        // Try hsl()/hsla()
        if let hex = matchHSL(trimmed) { return hex }

        return nil
    }

    // MARK: - Hex Matching

    /// Match #RGB or #RRGGBB hex color values.
    private static func matchHex(_ text: String) -> String? {
        let hexPattern = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/
        guard let match = text.wholeMatch(of: hexPattern) else { return nil }
        let hex = String(match.1)
        if hex.count == 3 {
            // Expand #RGB to RRGGBB by doubling each character
            return hex.map { "\($0)\($0)" }.joined().uppercased()
        }
        return hex.uppercased()
    }

    // MARK: - Bare Hex Matching

    /// Match bare hex color values without # prefix: RGB or RRGGBB (case-insensitive).
    private static func matchBareHex(_ text: String) -> String? {
        let bareHexPattern = /^([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/
        guard let match = text.wholeMatch(of: bareHexPattern) else { return nil }
        let hex = String(match.1)
        if hex.count == 3 {
            return hex.map { "\($0)\($0)" }.joined().uppercased()
        }
        return hex.uppercased()
    }

    // MARK: - RGB/RGBA Matching

    /// Match rgb(R, G, B) or rgba(R, G, B, A) color values.
    private static func matchRGB(_ text: String) -> String? {
        let rgbPattern = /^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*[\d.]+\s*)?\)$/
        guard let match = text.wholeMatch(of: rgbPattern) else { return nil }
        guard let r = Int(match.1), let g = Int(match.2), let b = Int(match.3),
              (0...255).contains(r), (0...255).contains(g), (0...255).contains(b) else { return nil }
        return String(format: "%02X%02X%02X", r, g, b)
    }

    // MARK: - HSL/HSLA Matching

    /// Match hsl(H, S%, L%) or hsla(H, S%, L%, A) color values.
    private static func matchHSL(_ text: String) -> String? {
        let hslPattern = /^hsla?\(\s*(\d{1,3})\s*,\s*(\d{1,3})%\s*,\s*(\d{1,3})%\s*(?:,\s*[\d.]+\s*)?\)$/
        guard let match = text.wholeMatch(of: hslPattern) else { return nil }
        guard let h = Int(match.1), let s = Int(match.2), let l = Int(match.3),
              (0...360).contains(h), (0...100).contains(s), (0...100).contains(l) else { return nil }
        return hslToHex(h: h, s: s, l: l)
    }

    // MARK: - HSL to Hex Conversion

    /// Converts HSL values to a 6-digit uppercase hex string.
    ///
    /// Uses the standard HSL-to-RGB algorithm (NOT NSColor HSB which is a different color model).
    /// - Parameters:
    ///   - h: Hue in degrees (0-360)
    ///   - s: Saturation as percentage (0-100)
    ///   - l: Lightness as percentage (0-100)
    /// - Returns: 6-digit uppercase hex string (e.g., "FF0000" for red)
    private static func hslToHex(h: Int, s: Int, l: Int) -> String {
        let hNorm = Double(h) / 360.0
        let sNorm = Double(s) / 100.0
        let lNorm = Double(l) / 100.0

        let r: Double
        let g: Double
        let b: Double

        if sNorm == 0 {
            // Achromatic (gray)
            r = lNorm
            g = lNorm
            b = lNorm
        } else {
            let q = lNorm < 0.5 ? lNorm * (1.0 + sNorm) : lNorm + sNorm - lNorm * sNorm
            let p = 2.0 * lNorm - q
            r = hueToRGB(p: p, q: q, t: hNorm + 1.0 / 3.0)
            g = hueToRGB(p: p, q: q, t: hNorm)
            b = hueToRGB(p: p, q: q, t: hNorm - 1.0 / 3.0)
        }

        let rInt = Int(round(r * 255.0))
        let gInt = Int(round(g * 255.0))
        let bInt = Int(round(b * 255.0))

        return String(format: "%02X%02X%02X", rInt, gInt, bInt)
    }

    /// Helper for HSL-to-RGB conversion: converts a single hue channel.
    private static func hueToRGB(p: Double, q: Double, t: Double) -> Double {
        var t = t
        // Normalize t to [0, 1]
        if t < 0 { t += 1.0 }
        if t > 1 { t -= 1.0 }

        if t < 1.0 / 6.0 {
            return p + (q - p) * 6.0 * t
        }
        if t < 1.0 / 2.0 {
            return q
        }
        if t < 2.0 / 3.0 {
            return p + (q - p) * (2.0 / 3.0 - t) * 6.0
        }
        return p
    }
}
