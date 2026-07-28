import AppKit

/// In-memory cache for application icons keyed by bundle identifier.
///
/// Eliminates redundant `urlForApplication` + `icon(forFile:)` disk I/O
/// when rendering clipboard cards for previously-seen source apps.
/// All access is from @MainActor (SwiftUI views, ClipboardMonitor pre-warming).
@MainActor
final class AppIconCache {

    static let shared = AppIconCache()

    private var cache: [String: NSImage] = [:]
    private var menuCache: [String: NSImage] = [:]

    private init() {}

    /// Returns the cached app icon for the given bundle identifier,
    /// performing the lookup and caching on first access.
    func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] {
            return cached
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        cache[bundleID] = image
        return image
    }

    /// Returns a menu-sized copy of the app icon, cached separately from the full-size one.
    ///
    /// SwiftUI does not apply `.resizable()` / `.frame()` to an image inside a `Menu`:
    /// the row is bridged to an `NSMenuItem`, which draws the image at its own `size`.
    /// A full-size icon would render at whatever `icon(forFile:)` returned, so the
    /// scaling has to happen on the `NSImage` itself. Copied rather than mutated in
    /// place because the same instance backs the 24pt card icons.
    func menuIcon(forBundleID bundleID: String, size: CGFloat = 14) -> NSImage? {
        let key = "\(bundleID)@\(size)"
        if let cached = menuCache[key] {
            return cached
        }

        guard let full = icon(forBundleID: bundleID),
              let scaled = full.copy() as? NSImage else {
            return nil
        }

        scaled.size = NSSize(width: size, height: size)
        menuCache[key] = scaled
        return scaled
    }
}
