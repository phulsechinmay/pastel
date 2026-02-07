import AppKit
import CoreImage
import SwiftUI

/// Extracts and caches the dominant color from application icons.
///
/// Uses CIFilter.areaAverage() for GPU-accelerated single-color extraction.
/// Results are cached per bundle identifier for zero-cost subsequent lookups.
@MainActor
final class AppIconColorService {

    static let shared = AppIconColorService()

    private var cache: [String: Color] = [:]
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    /// Returns the dominant color of the app icon for the given bundle identifier.
    /// Returns nil if the bundle ID is nil or the icon cannot be processed.
    func dominantColor(forBundleID bundleID: String?) -> Color? {
        guard let bundleID else { return nil }

        if let cached = cache[bundleID] {
            return cached
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        let nsImage = NSWorkspace.shared.icon(forFile: appURL.path)
        guard let tiffData = nsImage.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return nil
        }

        // Use areaAverage to get a single color from the entire image
        let extent = ciImage.extent
        guard let filter = CIFilter(name: "CIAreaAverage",
                                     parameters: [kCIInputImageKey: ciImage,
                                                  kCIInputExtentKey: CIVector(cgRect: extent)]),
              let outputImage = filter.outputImage else {
            return nil
        }

        // Read the single pixel
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(outputImage,
                       toBitmap: &pixel,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0

        // Skip near-white or near-black averages (generic/dull icons)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luminance > 0.85 || luminance < 0.08 {
            cache[bundleID] = nil
            return nil
        }

        let color = Color(red: r, green: g, blue: b)
        cache[bundleID] = color
        return color
    }
}
