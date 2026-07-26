import AppKit
import ImageIO

/// Loads and caches fully-decoded, size-capped images from disk off the main thread.
///
/// Unlike `NSImage(contentsOf:)` — which only reads the file header and defers the
/// actual pixel decode until the image is *drawn* on the main thread — this uses
/// CGImageSource's thumbnail API with `kCGImageSourceShouldCacheImmediately` to
/// produce an already-decoded bitmap sized for display. The result draws cheaply on
/// the main thread, eliminating the scroll/render hitches that image and URL cards
/// otherwise cause when they appear.
///
/// Decoding down to a target pixel size (rather than loading the 4K original) keeps
/// decode cost low while preserving enough resolution for a crisp card preview.
///
/// Decoded images are cached in-memory (`NSCache`, keyed by filename + target size),
/// so re-filtering label chips and scrolling back over prior cards are cache hits
/// with no disk I/O or re-decode. `NSCache` is thread-safe and evicts automatically
/// under memory pressure.
final class ThumbnailLoader: @unchecked Sendable {

    static let shared = ThumbnailLoader()

    /// Target max pixel dimension for full-width image / URL banner previews.
    /// ~3x the linear resolution of the stored 200px thumbnail (crisp on Retina),
    /// yet ~40x fewer pixels than the 4K original (fast to decode).
    static let cardPreviewMaxPixelSize = 600

    /// Target max pixel dimension for favicons (displayed at ≤64pt).
    static let faviconMaxPixelSize = 128

    /// Target max pixel dimension for the full-screen image viewer. Matches the
    /// stored full-image cap (4K) so zooming reveals real detail, not upscaled pixels.
    static let fullImageMaxPixelSize = 4096

    /// Thread-safe; access is unsynchronized by design.
    private let cache = NSCache<NSString, NSImage>()

    /// Concurrent so multiple cards can decode in parallel.
    private let queue = DispatchQueue(
        label: "app.pastel.thumbnailLoader",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private init() {
        cache.countLimit = 200
    }

    /// Return an already-decoded image synchronously if it is cached, else nil.
    /// Lets callers avoid a placeholder flash when the image is already warm.
    func cached(filename: String, maxPixelSize: Int) -> NSImage? {
        cache.object(forKey: Self.cacheKey(filename, maxPixelSize))
    }

    /// Load a fully-decoded, size-capped image for `filename`, decoding on a
    /// background queue. Returns nil if the file is missing or cannot be decoded.
    func load(filename: String, maxPixelSize: Int) async -> NSImage? {
        let key = Self.cacheKey(filename, maxPixelSize)
        if let hit = cache.object(forKey: key) { return hit }

        let url = ImageStorageService.shared.resolveImageURL(filename)
        let image: NSImage? = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.decode(url: url, maxPixelSize: maxPixelSize))
            }
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    // MARK: - Private

    private static func cacheKey(_ filename: String, _ maxPixelSize: Int) -> NSString {
        "\(filename)@\(maxPixelSize)" as NSString
    }

    /// Decode a downsampled, fully-rendered image using CGImageSource.
    ///
    /// `kCGImageSourceShouldCacheImmediately` forces the decode to happen here on the
    /// background queue rather than lazily at draw time on the main thread. The
    /// thumbnail API decodes straight to the target size without materializing the
    /// full-resolution bitmap, so downsizing a 4K image stays cheap.
    private static func decode(url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
