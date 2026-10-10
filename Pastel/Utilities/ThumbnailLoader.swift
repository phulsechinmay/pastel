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
    /// Card-sized decoded images are cached in-memory, keyed by filename and target
    /// size. Full-size viewer images stay owned by the viewer and leave with it.
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
    private let inFlightLock = NSLock()
    private var inFlight: [String: [CheckedContinuation<NSImage?, Never>]] = [:]

    /// Keep simultaneous decodes bounded when many cards enter the viewport.
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "app.pastel.thumbnailLoader"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    /// Return an already-decoded image synchronously if it is cached, else nil.
    /// Lets callers avoid a placeholder flash when the image is already warm.
    func cached(filename: String, maxPixelSize: Int) -> NSImage? {
        guard maxPixelSize <= Self.cardPreviewMaxPixelSize else { return nil }
        return cache.object(forKey: Self.cacheKey(filename, maxPixelSize) as NSString)
    }

    /// Load a fully-decoded, size-capped image for `filename`, decoding on a
    /// background queue. Returns nil if the file is missing or cannot be decoded.
    func load(filename: String, maxPixelSize: Int) async -> NSImage? {
        let key = Self.cacheKey(filename, maxPixelSize)
        if maxPixelSize <= Self.cardPreviewMaxPixelSize,
           let hit = cache.object(forKey: key as NSString) { return hit }

        return await withCheckedContinuation { continuation in
            inFlightLock.lock()
            if inFlight[key] != nil {
                inFlight[key]?.append(continuation)
                inFlightLock.unlock()
                return
            }
            inFlight[key] = [continuation]
            inFlightLock.unlock()

            let url = ImageStorageService.shared.resolveImageURL(filename)
            queue.addOperation { [self] in
                let decoded = Self.decode(url: url, maxPixelSize: maxPixelSize)
                if maxPixelSize <= Self.cardPreviewMaxPixelSize, let decoded {
                    cache.setObject(decoded.image, forKey: key as NSString, cost: decoded.cost)
                }
                inFlightLock.lock()
                let waiters = inFlight.removeValue(forKey: key) ?? []
                inFlightLock.unlock()
                for waiter in waiters { waiter.resume(returning: decoded?.image) }
            }
        }
    }

    // MARK: - Private

    private static func cacheKey(_ filename: String, _ maxPixelSize: Int) -> String {
        "\(filename)@\(maxPixelSize)"
    }

    /// Decode a downsampled, fully-rendered image using CGImageSource.
    ///
    /// `kCGImageSourceShouldCacheImmediately` forces the decode to happen here on the
    /// background queue rather than lazily at draw time on the main thread. The
    /// thumbnail API decodes straight to the target size without materializing the
    /// full-resolution bitmap, so downsizing a 4K image stays cheap.
    private static func decode(url: URL, maxPixelSize: Int) -> (image: NSImage, cost: Int)? {
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
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return (image, cgImage.bytesPerRow * cgImage.height)
    }
}
