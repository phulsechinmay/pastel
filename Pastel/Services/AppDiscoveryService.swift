import Foundation

/// A discovered application on the user's system.
struct DiscoveredApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let url: URL

    var id: String { bundleID }
}

/// Scans standard macOS application directories for installed apps
/// and detects known password managers via bundle ID prefix matching.
@MainActor
enum AppDiscoveryService {

    // MARK: - Password Manager Detection

    /// Known password manager bundle ID prefixes.
    /// Match by prefix to catch variants (e.g., com.agilebits.onepassword7 vs .onepassword-osx).
    private static let passwordManagerPatterns: [(prefix: String, name: String)] = [
        ("com.agilebits.onepassword", "1Password"),
        ("com.1password", "1Password"),
        ("2BUA8C4S2C.com.agilebits", "1Password (App Store)"),
        ("com.bitwarden.desktop", "Bitwarden"),
        ("com.dashlane.Dashlane", "Dashlane"),
        ("com.lastpass.LastPass", "LastPass"),
        ("org.keepassxc.keepassxc", "KeePassXC"),
        ("com.keepassium", "KeePassium"),
        ("de.devland.macpass", "MacPass"),
        ("com.apple.Passwords", "Apple Passwords"),
        ("com.enpass.Enpass", "Enpass"),
        ("com.roboform.roboform", "RoboForm"),
    ]

    // MARK: - Public Methods

    /// Discover installed applications by scanning standard macOS directories.
    ///
    /// Scans `/Applications`, `/System/Applications`, and `~/Applications` (shallow only).
    /// Deduplicates by bundle ID (first occurrence wins). Returns sorted alphabetically by name.
    static func discoverInstalledApps() -> [DiscoveredApp] {
        let searchDirs = [
            URL(filePath: "/Applications"),
            URL(filePath: "/System/Applications"),
            URL(filePath: NSHomeDirectory()).appending(path: "Applications"),
        ]

        var seen = Set<String>()
        var apps: [DiscoveredApp] = []

        for dir in searchDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)

                let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent

                apps.append(DiscoveredApp(bundleID: bundleID, name: name, url: url))
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Filter installed apps to find known password managers.
    ///
    /// Uses prefix matching against a curated list of password manager bundle IDs.
    /// Returns the original `DiscoveredApp` instances (preserving real app names, not pattern names).
    static func detectInstalledPasswordManagers(from installedApps: [DiscoveredApp]) -> [DiscoveredApp] {
        installedApps.filter { app in
            passwordManagerPatterns.contains { pattern in
                app.bundleID.hasPrefix(pattern.prefix)
            }
        }
    }
}
