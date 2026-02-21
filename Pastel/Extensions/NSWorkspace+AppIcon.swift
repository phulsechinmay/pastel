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
}
