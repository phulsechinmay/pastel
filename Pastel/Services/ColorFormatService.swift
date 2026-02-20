import Foundation

/// Converts 6-digit uppercase hex color strings (no # prefix) to various color format representations.
///
/// Input format: "FF5733" (6-character uppercase hex, as stored by ColorDetectionService).
/// Supports Hex (#FF5733), RGB, HSL, and CMYK output formats.
struct ColorFormatService {

    // MARK: - Public Conversion Methods

    /// Returns hex with # prefix: "#FF5733"
    static func toHex(_ hex: String) -> String {
        "#\(hex.uppercased())"
    }

    /// Returns CSS rgb() notation: "rgb(255, 87, 51)"
    static func toRGB(_ hex: String) -> String {
        guard let (r, g, b) = hexToRGB(hex) else { return "#\(hex)" }
        return "rgb(\(r), \(g), \(b))"
    }

    /// Returns CSS hsl() notation: "hsl(11, 100%, 60%)"
    static func toHSL(_ hex: String) -> String {
        guard let (r, g, b) = hexToRGB(hex) else { return "#\(hex)" }

        let rNorm = Double(r) / 255.0
        let gNorm = Double(g) / 255.0
        let bNorm = Double(b) / 255.0

        let maxC = max(rNorm, gNorm, bNorm)
        let minC = min(rNorm, gNorm, bNorm)
        let delta = maxC - minC

        // Lightness
        let l = (maxC + minC) / 2.0

        // Saturation
        let s: Double
        if delta == 0 {
            s = 0
        } else {
            s = delta / (1.0 - abs(2.0 * l - 1.0))
        }

        // Hue
        var h: Double = 0
        if delta > 0 {
            if maxC == rNorm {
                h = 60.0 * (((gNorm - bNorm) / delta).truncatingRemainder(dividingBy: 6.0))
            } else if maxC == gNorm {
                h = 60.0 * (((bNorm - rNorm) / delta) + 2.0)
            } else {
                h = 60.0 * (((rNorm - gNorm) / delta) + 4.0)
            }
        }
        if h < 0 { h += 360.0 }

        let hInt = Int(h.rounded())
        let sInt = Int((s * 100.0).rounded())
        let lInt = Int((l * 100.0).rounded())

        return "hsl(\(hInt), \(sInt)%, \(lInt)%)"
    }

    /// Returns CMYK notation: "cmyk(0%, 66%, 80%, 0%)"
    static func toCMYK(_ hex: String) -> String {
        guard let (r, g, b) = hexToRGB(hex) else { return "#\(hex)" }

        let rPrime = Double(r) / 255.0
        let gPrime = Double(g) / 255.0
        let bPrime = Double(b) / 255.0

        let k = 1.0 - max(rPrime, gPrime, bPrime)

        if k == 1.0 {
            return "cmyk(0%, 0%, 0%, 100%)"
        }

        let c = (1.0 - rPrime - k) / (1.0 - k)
        let m = (1.0 - gPrime - k) / (1.0 - k)
        let y = (1.0 - bPrime - k) / (1.0 - k)

        let cInt = Int((c * 100.0).rounded())
        let mInt = Int((m * 100.0).rounded())
        let yInt = Int((y * 100.0).rounded())
        let kInt = Int((k * 100.0).rounded())

        return "cmyk(\(cInt)%, \(mInt)%, \(yInt)%, \(kInt)%)"
    }

    // MARK: - Private Helpers

    /// Parse a 6-character hex string to RGB integer tuple.
    private static func hexToRGB(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        guard hex.count == 6 else { return nil }
        var hexValue: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&hexValue) else { return nil }
        let r = Int((hexValue >> 16) & 0xFF)
        let g = Int((hexValue >> 8) & 0xFF)
        let b = Int(hexValue & 0xFF)
        return (r, g, b)
    }
}
