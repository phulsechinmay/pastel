import AppKit

extension NSWorkspace {

    /// Resolve a bundle identifier to the application's icon.
    ///
    /// Uses `urlForApplication(withBundleIdentifier:)` to locate the app,
    /// then returns its icon via `icon(forFile:)`.
    ///
    /// - Parameter bundleID: The bundle identifier (e.g., "com.apple.Safari").
    /// - Returns: The app icon, or nil if the bundle ID cannot be resolved.
    func appIcon(forBundleIdentifier bundleID: String) -> NSImage? {
        guard let appURL = urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return icon(forFile: appURL.path)
    }
}
