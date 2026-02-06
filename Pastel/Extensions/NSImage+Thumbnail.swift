import AppKit
import ImageIO

extension NSImage {
    /// Generate a thumbnail using CGImageSource for fast, memory-efficient resizing.
    ///
    /// Uses `CGImageSourceCreateThumbnailAtIndex` which is ~40x faster than
    /// NSImage-based resizing per domain research. The CGImageSource approach
    /// decodes only the pixels needed for the target size.
    ///
    /// - Parameters:
    ///   - imageData: Raw image data (TIFF, PNG, JPEG, etc.)
    ///   - maxPixelSize: Maximum dimension (width or height) of the output thumbnail.
    /// - Returns: An NSImage thumbnail, or nil if the data cannot be decoded.
    static func thumbnail(from imageData: Data, maxPixelSize: Int = 200) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
