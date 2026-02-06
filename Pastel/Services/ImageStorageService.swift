import AppKit
import CryptoKit
import ImageIO
import OSLog

/// Disk-based image storage service with background processing and thumbnail generation.
///
/// All disk I/O runs on a dedicated serial queue at `.utility` QoS.
/// Pasteboard data must be read on the main thread before calling `saveImage`
/// because NSPasteboard is NOT thread-safe.
///
/// Storage layout:
/// - `~/Library/Application Support/Pastel/images/{UUID}.png` -- full image (capped at 4K)
/// - `~/Library/Application Support/Pastel/images/{UUID}_thumb.png` -- 200px thumbnail
///
/// The database stores only filenames (not full paths). Paths are resolved at runtime
/// via `resolveImageURL(_:)`.
final class ImageStorageService: Sendable {

    // MARK: - Singleton

    static let shared = ImageStorageService()

    // MARK: - Properties

    private let imagesDirectory: URL
    private let backgroundQueue = DispatchQueue(label: "app.pastel.imageStorage", qos: .utility)

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "ImageStorageService"
    )

    /// Maximum pixel dimension for stored images (4K resolution cap)
    private static let maxFullImageSize = 3840

    /// Maximum pixel dimension for thumbnails
    private static let thumbnailSize = 200

    // MARK: - Initialization

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        self.imagesDirectory = appSupport
            .appendingPathComponent("Pastel", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)

        // Create images directory if needed (with intermediates)
        try? FileManager.default.createDirectory(
            at: imagesDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Public Methods

    /// Save image data to disk with a thumbnail, executing all I/O on a background queue.
    ///
    /// - Parameters:
    ///   - data: Raw image data (read from pasteboard on the main thread).
    ///   - completion: Called on the **main thread** with (imageFilename, thumbnailFilename),
    ///     or (nil, nil) if saving failed.
    func saveImage(data: Data, completion: @escaping @Sendable (String?, String?) -> Void) {
        backgroundQueue.async { [imagesDirectory] in
            let uuid = UUID().uuidString

            // -- Full image: downscale if larger than 4K --
            let fullImageData: Data
            if let downscaled = Self.downscaleIfNeeded(data: data, maxSize: Self.maxFullImageSize) {
                fullImageData = downscaled
            } else {
                // If downscale check fails to read dimensions, save original data as-is
                fullImageData = data
            }

            let imageFilename = "\(uuid).png"
            let imageURL = imagesDirectory.appendingPathComponent(imageFilename)

            do {
                try fullImageData.write(to: imageURL)
            } catch {
                Self.logger.error("Failed to write full image: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }

            // -- Thumbnail: 200px max dimension --
            var thumbnailFilename: String?
            if let thumbImage = NSImage.thumbnail(from: data, maxPixelSize: Self.thumbnailSize),
               let thumbData = Self.pngData(from: thumbImage) {
                let thumbName = "\(uuid)_thumb.png"
                let thumbURL = imagesDirectory.appendingPathComponent(thumbName)
                do {
                    try thumbData.write(to: thumbURL)
                    thumbnailFilename = thumbName
                } catch {
                    Self.logger.warning("Failed to write thumbnail: \(error.localizedDescription)")
                    // Non-fatal: proceed with full image only
                }
            } else {
                Self.logger.warning("Failed to generate thumbnail for image")
            }

            Self.logger.info("Saved image: \(imageFilename), thumb: \(thumbnailFilename ?? "none")")
            DispatchQueue.main.async { completion(imageFilename, thumbnailFilename) }
        }
    }

    /// Delete image and thumbnail files from disk.
    ///
    /// - Parameters:
    ///   - imagePath: Filename of the full image (e.g., "UUID.png"), or nil.
    ///   - thumbnailPath: Filename of the thumbnail (e.g., "UUID_thumb.png"), or nil.
    func deleteImage(imagePath: String?, thumbnailPath: String?) {
        backgroundQueue.async { [imagesDirectory] in
            if let imagePath {
                let url = imagesDirectory.appendingPathComponent(imagePath)
                try? FileManager.default.removeItem(at: url)
            }
            if let thumbnailPath {
                let url = imagesDirectory.appendingPathComponent(thumbnailPath)
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Resolve a stored filename to its full URL on disk.
    ///
    /// - Parameter filename: The filename stored in the database (e.g., "UUID.png").
    /// - Returns: Full file URL in the images directory.
    func resolveImageURL(_ filename: String) -> URL {
        imagesDirectory.appendingPathComponent(filename)
    }

    /// Compute a fast hash of image data for deduplication.
    ///
    /// Hashes only the first 4096 bytes for speed -- sufficient to distinguish
    /// different images without the cost of hashing multi-megabyte data.
    ///
    /// - Parameter data: Raw image data.
    /// - Returns: Hex-encoded SHA256 hash string.
    static func computeImageHash(data: Data) -> String {
        let prefix = data.prefix(4096)
        let digest = SHA256.hash(data: prefix)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private Helpers

    /// Downscale image data if its dimensions exceed `maxSize`.
    ///
    /// Uses CGImageSource for efficient decoding. Returns PNG data if downscaled,
    /// or the original data if already within limits.
    private static func downscaleIfNeeded(data: Data, maxSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        // Check dimensions
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            // Can't read dimensions -- return original data unchanged
            return data
        }

        let maxDimension = max(width, height)
        if maxDimension <= maxSize {
            // Already within limits -- convert to PNG for consistent storage
            return pngDataFromSource(source)
        }

        // Downscale using CGImageSource thumbnail API (fast, memory-efficient)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return data // Downscale failed, use original
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return pngData(from: nsImage) ?? data
    }

    /// Convert a CGImageSource's first image to PNG data.
    private static func pngDataFromSource(_ source: CGImageSource) -> Data? {
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return pngData(from: nsImage)
    }

    /// Convert an NSImage to PNG Data.
    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return pngData
    }
}
