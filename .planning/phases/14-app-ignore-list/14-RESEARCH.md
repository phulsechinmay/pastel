# Phase 14: App Ignore List - Research

**Researched:** 2026-02-09
**Domain:** macOS app discovery, clipboard monitoring filtering, SwiftUI Table, UserDefaults storage
**Confidence:** HIGH

## Summary

This phase adds privacy-focused app filtering to Pastel's clipboard monitoring. Users configure an ignore list of applications (via a Privacy tab in Settings), and ClipboardMonitor skips clipboard captures when the frontmost app is on that list. The implementation touches three areas: (1) a data model for storing ignored app bundle IDs, (2) an app discovery mechanism to browse installed apps, and (3) filtering logic in ClipboardMonitor.

The codebase already captures `sourceAppBundleID` via `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` in `ClipboardMonitor.processPasteboardContent()` and `processImageContent()`. The filtering check is a simple `Set.contains()` guard inserted early in those methods. The UI is a new "Privacy" tab in SettingsView with a SwiftUI `Table` for the ignore list and a sheet-based app picker for adding apps.

**Primary recommendation:** Store the ignore list as `[String]` (bundle IDs) in UserDefaults via `@AppStorage`, discover installed apps by scanning `/Applications` + `/System/Applications` + `~/Applications` with `FileManager.contentsOfDirectory`, and use SwiftUI `Table` with `KeyPathComparator` for sortable columns.

## Standard Stack

### Core (all built-in -- no new dependencies)

| Library/API | Purpose | Why Standard |
|-------------|---------|--------------|
| `UserDefaults` / `@AppStorage` | Persist ignore list (array of bundle IDs) | Matches existing project pattern for all settings (panelEdge, pasteBehavior, etc.) |
| `FileManager` | Enumerate `.app` bundles in `/Applications` etc. | Standard Foundation API, no private frameworks needed |
| `Bundle` | Extract `bundleIdentifier` and `localizedName` from `.app` bundles | Standard Foundation API |
| `NSWorkspace` | Get app icons via existing `appIcon(forBundleIdentifier:)` extension, and `frontmostApplication` for filtering | Already used in codebase for source app capture and icon resolution |
| SwiftUI `Table` | Sortable multi-column ignore list display | Available macOS 13+; project targets macOS 14 |
| `NSOpenPanel` | File picker for manually selecting `.app` files | Standard AppKit API for file selection |
| `UTType.application` | Filter NSOpenPanel to `.app` bundles only | Standard UniformTypeIdentifiers framework |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| FileManager scan | `NSMetadataQuery` (Spotlight) | Spotlight is async and may miss apps not indexed; FileManager is simpler and synchronous |
| FileManager scan | `LSApplicationWorkspace` (private API) | Private API, not recommended for production; could break with OS updates |
| UserDefaults array | SwiftData model | Overkill for a simple list of strings; UserDefaults is consistent with all other settings |
| SwiftUI Table | LazyVStack custom rows | Table provides built-in column sorting, selection, and macOS-native look |

**No new dependencies required.** Everything uses existing frameworks.

## Architecture Patterns

### Recommended Project Structure (new files only)

```
Pastel/
├── Services/
│   └── AppDiscoveryService.swift       # Scans system for installed apps
├── Views/Settings/
│   ├── PrivacySettingsView.swift        # Privacy tab (ignore list table + controls)
│   └── AppPickerView.swift             # Sheet: searchable list of installed apps
```

### Pattern 1: UserDefaults Array for Ignore List

**What:** Store ignored app bundle IDs as `[String]` in UserDefaults, with a companion `[String: Date]` dictionary for "date added" metadata.

**When to use:** Simple flat lists of strings that don't need relationships or complex querying.

**Why not SwiftData:** The ignore list is a small list of strings (typically 5-20 entries). SwiftData would require a new model, schema migration considerations, and adds complexity for no benefit. All other settings in Pastel use UserDefaults.

**Example:**
```swift
// Storage keys
// "ignoredAppBundleIDs" -> [String] array of bundle IDs
// "ignoredAppDates" -> [String: Double] dictionary of bundleID -> timeIntervalSince1970

// Reading in ClipboardMonitor (service context, no @AppStorage)
let ignoredBundleIDs = Set(UserDefaults.standard.stringArray(forKey: "ignoredAppBundleIDs") ?? [])

// Reading in SwiftUI view
@AppStorage("ignoredAppBundleIDs") private var ignoredBundleIDsData: Data = Data()
// Note: @AppStorage doesn't directly support [String], need wrapper -- see Pattern 3
```

### Pattern 2: Early-Exit Guard in ClipboardMonitor

**What:** Add an ignored-app check as the very first thing after `processPasteboardContent()` determines there's new content, before any content reading or classification.

**When to use:** The filtering should happen before any processing work (classification, hashing, dedup, persistence).

**Example:**
```swift
private func processPasteboardContent() {
    // Check if source app is on ignore list
    let sourceApp = NSWorkspace.shared.frontmostApplication
    let sourceBundleID = sourceApp?.bundleIdentifier ?? ""
    if ignoredBundleIDs.contains(sourceBundleID) {
        Self.logger.debug("Skipping capture from ignored app: \(sourceApp?.localizedName ?? sourceBundleID)")
        return
    }

    // ... existing classification and capture logic ...
}
```

**Critical note:** The frontmost app check must happen in BOTH `processPasteboardContent()` AND `processImageContent()`. Currently, `processPasteboardContent()` captures `sourceApp` midway through, and `processImageContent()` captures it separately. The ignore check must be moved to the TOP of both methods, or factored into `checkForChanges()` before either method is called.

**Recommended approach:** Add the ignore check in `checkForChanges()` itself, right after the `skipNextChange` guard. This way it applies to ALL content types uniformly, including images.

### Pattern 3: @AppStorage for [String] via RawRepresentable

**What:** SwiftUI's `@AppStorage` doesn't directly support `[String]`. Use a `RawRepresentable` conformance on `[String]` or store as JSON-encoded `Data`.

**Example (JSON Data approach -- simpler):**
```swift
// In the view:
@State private var ignoredBundleIDs: [String] = {
    UserDefaults.standard.stringArray(forKey: "ignoredAppBundleIDs") ?? []
}()

// Save helper:
private func saveIgnoredApps() {
    UserDefaults.standard.set(ignoredBundleIDs, forKey: "ignoredAppBundleIDs")
}
```

**Note:** `UserDefaults.standard.stringArray(forKey:)` natively supports `[String]` storage. No JSON encoding needed. The limitation is only with `@AppStorage` property wrapper, which can be worked around with `@State` + manual UserDefaults read/write, or by using `onChange` to sync.

### Pattern 4: App Discovery via FileManager

**What:** Scan standard macOS application directories for `.app` bundles and extract metadata.

**Example:**
```swift
struct DiscoveredApp: Identifiable {
    let bundleID: String
    let name: String
    let url: URL
    var id: String { bundleID }
}

func discoverInstalledApps() -> [DiscoveredApp] {
    let directories = [
        URL(filePath: "/Applications"),
        URL(filePath: "/System/Applications"),
        URL(filePath: NSHomeDirectory()).appending(path: "Applications")
    ]

    var apps: [String: DiscoveredApp] = [:] // Dedup by bundleID

    for dir in directories {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isApplicationKey],
            options: [.skipsHiddenFiles]
        ) else { continue }

        for url in contents where url.pathExtension == "app" {
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else { continue }
            let name = bundle.infoDictionary?["CFBundleName"] as? String
                ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            if apps[bundleID] == nil {
                apps[bundleID] = DiscoveredApp(bundleID: bundleID, name: name, url: url)
            }
        }
    }

    return apps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}
```

**Important:** Use `contentsOfDirectory` (shallow, not recursive) with `.skipsHiddenFiles`. Do NOT use `enumerator` with `.skipsPackageDescendants` for `/Applications` because `.app` bundles ARE packages -- the enumerator would descend into them by default and find nested helper apps. Shallow scan of the top-level directory is the correct approach.

### Pattern 5: SwiftUI Table with Sort + Selection + Delete

**What:** Use SwiftUI's native `Table` view for the ignore list, with sortable columns and single selection.

**Example:**
```swift
struct IgnoredApp: Identifiable {
    let bundleID: String
    let name: String
    let dateAdded: Date
    var id: String { bundleID }
}

@State private var sortOrder = [KeyPathComparator(\IgnoredApp.name)]
@State private var selectedApp: IgnoredApp.ID?

Table(ignoredApps, selection: $selectedApp, sortOrder: $sortOrder) {
    TableColumn("Name", value: \.name) { app in
        HStack(spacing: 8) {
            // App icon
            if let icon = NSWorkspace.shared.appIcon(forBundleIdentifier: app.bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(app.name)
        }
    }
    TableColumn("Date Added", value: \.dateAdded) { app in
        Text(app.dateAdded, style: .date)
    }
}
.onChange(of: sortOrder) { _, newOrder in
    ignoredApps.sort(using: newOrder)
}
.onDeleteCommand {
    if let selected = selectedApp {
        removeApp(bundleID: selected)
    }
}
```

### Pattern 6: NSOpenPanel for Manual .app Selection

**What:** Allow users to pick `.app` files from anywhere on disk (for helper apps, non-standard locations).

**Example:**
```swift
import UniformTypeIdentifiers

func pickAppManually() {
    let panel = NSOpenPanel()
    panel.message = "Select an application to ignore"
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(filePath: "/Applications")

    if panel.runModal() == .OK, let url = panel.url {
        if let bundle = Bundle(url: url),
           let bundleID = bundle.bundleIdentifier {
            addToIgnoreList(bundleID: bundleID, name: bundle.appName, url: url)
        }
    }
}
```

### Anti-Patterns to Avoid

- **Using `LSApplicationWorkspace`:** Private API. Will cause App Store rejection (not relevant for direct distribution, but still fragile across OS updates). FileManager scan is more reliable.
- **Storing full app paths instead of bundle IDs:** Apps can move, be updated, or reinstalled at different paths. Bundle IDs are the stable identifier. `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` returns the bundle ID, so the comparison must be against bundle IDs.
- **Recursive enumeration of `/Applications`:** `.app` bundles are directories. A recursive scan enters them and finds internal helper apps. Use shallow `contentsOfDirectory`, not `enumerator`.
- **Loading app icons eagerly for all installed apps:** There could be 200+ installed apps. Load icons lazily in the picker view, or use `NSWorkspace.shared.icon(forFile:)` which is fast.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sortable table | Custom sort buttons + VStack rows | SwiftUI `Table` with `sortOrder` binding | Built-in column headers, sort indicators, accessibility, selection |
| App icon loading | Custom icon extraction from .icns files | `NSWorkspace.shared.icon(forFile: appURL.path)` or existing `appIcon(forBundleIdentifier:)` extension | Handles all icon formats, retina, catalog icons automatically |
| File picker for .app | Custom file browser view | `NSOpenPanel` with `allowedContentTypes: [.application]` | Native macOS file picker, respects user preferences, handles permissions |
| Delete key handling | Custom `onKeyPress` for delete | `.onDeleteCommand(perform:)` modifier | Standard macOS pattern, handles both backspace and forward delete |

## Common Pitfalls

### Pitfall 1: Frontmost App Timing in ClipboardMonitor

**What goes wrong:** The clipboard `changeCount` changes AFTER the copy command finishes. By the time ClipboardMonitor's 0.5s timer fires, the user may have switched to a different app. The "frontmost app" at poll time might not be the app that performed the copy.

**Why it happens:** NSPasteboard polling is asynchronous relative to user actions. The 0.5s interval means there's up to 0.5s of delay.

**How to avoid:** This is an inherent limitation of polling-based clipboard monitoring. In practice, users rarely switch apps within 0.5s of copying. The existing codebase already uses `NSWorkspace.shared.frontmostApplication` for source attribution and it works well enough. Do NOT try to solve this with KVO on frontmostApplication -- the complexity is not worth the marginal improvement.

**Warning signs:** Users report that copying in an ignored app still captures items. This is most likely if they Cmd+Tab immediately after copying.

### Pitfall 2: @AppStorage Doesn't Support [String]

**What goes wrong:** `@AppStorage` property wrapper only supports `Bool`, `Int`, `Double`, `String`, `URL`, and `Data`. Trying to use `[String]` directly will fail to compile.

**Why it happens:** SwiftUI limitation.

**How to avoid:** Use `UserDefaults.standard.stringArray(forKey:)` / `.set(array, forKey:)` directly in @State with manual sync. Or encode as JSON Data for @AppStorage. The cleanest pattern for this codebase is `@State` + explicit UserDefaults read in `onAppear` + save on mutation.

### Pitfall 3: Ignore List Not Updating in ClipboardMonitor After Settings Change

**What goes wrong:** If ClipboardMonitor caches the ignore list at startup, changes in Settings won't take effect until app restart.

**Why it happens:** ClipboardMonitor is a service (not a SwiftUI view), so it doesn't get `@AppStorage` reactivity.

**How to avoid:** Read `UserDefaults.standard.stringArray(forKey: "ignoredAppBundleIDs")` directly inside `checkForChanges()` on every poll cycle. This is a trivial read (Set creation from a small array) and costs nothing at 0.5s intervals. Alternatively, cache a `Set<String>` and refresh it via `NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)`. The direct-read approach is simpler and consistent with how `RetentionService` reads `historyRetention`.

**Recommended:** Direct read per poll (matches `RetentionService` pattern at line 40 of RetentionService.swift).

### Pitfall 4: Bundle(url:) Returns nil for Some Apps

**What goes wrong:** Not all `.app` bundles in `/Applications` can be loaded with `Bundle(url:)`. Some may be symbolic links, broken, or have unusual structures.

**Why it happens:** System utilities, old apps, or apps installed via non-standard methods may have incomplete bundle structures.

**How to avoid:** Always use `guard let bundle = Bundle(url:), let bundleID = bundle.bundleIdentifier else { continue }` to skip unloadable apps silently. The user can still add these via the manual file picker if needed.

### Pitfall 5: SwiftUI Table Column Width with App Icons

**What goes wrong:** Table columns with mixed icon+text content can have inconsistent alignment or icon sizing.

**Why it happens:** SwiftUI Table cells need explicit frame constraints on images.

**How to avoid:** Always use `.frame(width: 20, height: 20)` on icon images within table rows. Use `.resizable().aspectRatio(contentMode: .fit)` before the frame.

### Pitfall 6: processImageContent() Also Needs Ignore Check

**What goes wrong:** Image captures bypass the ignore check if it's only added to `processPasteboardContent()`.

**Why it happens:** `processImageContent()` is a separate code path called from `processPasteboardContent()` AFTER the content type check but the source app is captured independently.

**How to avoid:** Place the ignore check in `checkForChanges()` BEFORE `processPasteboardContent()` is called. This ensures ALL content types (text, image, URL, file) are filtered uniformly. This is the cleanest insertion point.

## Code Examples

### Example 1: IgnoredApp Model (for UI display)

```swift
/// Represents an app in the ignore list, used for table display.
struct IgnoredApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let dateAdded: Date
    var id: String { bundleID }
}
```

### Example 2: Filtering in checkForChanges()

```swift
/// In ClipboardMonitor.checkForChanges():
private func checkForChanges() {
    guard isMonitoring else { return }

    let currentChangeCount = pasteboard.changeCount
    guard currentChangeCount != lastChangeCount else { return }
    lastChangeCount = currentChangeCount

    // Phase 3 self-paste prevention
    if skipNextChange {
        skipNextChange = false
        return
    }

    // Phase 14: App ignore list filtering
    if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
        let ignored = Set(UserDefaults.standard.stringArray(forKey: "ignoredAppBundleIDs") ?? [])
        if ignored.contains(bundleID) {
            return  // Skip capture from ignored app
        }
    }

    processPasteboardContent()
}
```

### Example 3: Password Manager Bundle ID Detection

```swift
/// Known password manager bundle ID patterns for the default ignore suggestion.
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
    ("com.apple.Passwords", "Apple Passwords"), // macOS 15+ standalone app
    ("com.enpass.Enpass", "Enpass"),
    ("com.roboform.roboform", "RoboForm"),
]

/// Scan installed apps and return those matching known password manager patterns.
func detectInstalledPasswordManagers(from installedApps: [DiscoveredApp]) -> [DiscoveredApp] {
    installedApps.filter { app in
        Self.passwordManagerPatterns.contains { pattern in
            app.bundleID.hasPrefix(pattern.prefix)
        }
    }
}
```

### Example 4: App Discovery Service

```swift
@MainActor
enum AppDiscoveryService {

    static func discoverInstalledApps() -> [DiscoveredApp] {
        let searchDirs = [
            URL(filePath: "/Applications"),
            URL(filePath: "/System/Applications"),
            URL(filePath: NSHomeDirectory()).appending(path: "Applications"),
        ]

        var seen = Set<String>() // Dedup by bundleID
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
}
```

### Example 5: NSOpenPanel for Manual App Selection

```swift
import UniformTypeIdentifiers

func selectAppManually(completion: @escaping (DiscoveredApp?) -> Void) {
    let panel = NSOpenPanel()
    panel.message = "Select an application"
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(filePath: "/Applications")

    panel.begin { response in
        guard response == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else {
            completion(nil)
            return
        }
        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        completion(DiscoveredApp(bundleID: bundleID, name: name, url: url))
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `LSCopyApplicationURLsForBundleIdentifier` | Deprecated; use `NSWorkspace.urlsForApplications(withBundleIdentifier:)` | macOS 12+ | Use NSWorkspace method instead |
| `allowedFileTypes: ["app"]` on NSOpenPanel | `allowedContentTypes: [.application]` with UTType | macOS 12+ | Must import UniformTypeIdentifiers |
| `NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier:)` | `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` | macOS 10.15+ | Returns URL instead of path |

**Deprecated/outdated:**
- `LSCopyApplicationURLsForBundleIdentifier`: Use NSWorkspace equivalent
- NSOpenPanel `allowedFileTypes`: Use `allowedContentTypes` with UTType

## Open Questions

1. **App icon caching in picker**
   - What we know: `NSWorkspace.shared.icon(forFile:)` is fast but creates an NSImage per call
   - What's unclear: Whether loading 200+ icons simultaneously causes visible lag in the picker
   - Recommendation: Load icons lazily via `LazyVStack` -- SwiftUI will only render visible rows. If needed, add a simple in-memory cache dictionary

2. **Exact password manager bundle IDs**
   - What we know: Common patterns like `com.agilebits.onepassword`, `com.bitwarden.desktop`, `org.keepassxc.keepassxc`
   - What's unclear: Exact bundle IDs vary by distribution channel (App Store vs direct download), version (1Password 7 vs 8), and helper processes
   - Recommendation: Use prefix matching (`hasPrefix`) rather than exact matching. The curated list covers the major password managers. Users can always add more manually.

3. **macOS 15 Apple Passwords app**
   - What we know: macOS 15 Sequoia ships a standalone Passwords app (`com.apple.Passwords`)
   - What's unclear: Whether this app copies passwords via standard NSPasteboard or uses a different mechanism
   - Recommendation: Include `com.apple.Passwords` in the password manager detection list. It likely uses `org.nspasteboard.ConcealedType` which Pastel already handles, but including it in the default suggestion is good UX.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `ClipboardMonitor.swift`, `SettingsView.swift`, `AppState.swift`, `NSWorkspace+AppIcon.swift` -- direct code inspection
- Apple Developer Documentation: `NSWorkspace.frontmostApplication`, `NSOpenPanel`, `FileManager.contentsOfDirectory`
- Apple Developer Documentation: `SwiftUI Table`, `KeyPathComparator`, `onDeleteCommand`

### Secondary (MEDIUM confidence)
- [Stack Overflow: How to get all installed applications on Mac](https://stackoverflow-com.translate.goog/questions/78357623/how-to-get-all-installed-applications-and-their-detailed-info-on-mac-not-just?_x_tr_sl=en&_x_tr_tl=es&_x_tr_hl=es&_x_tr_pto=tc) -- FileManager scan approach verified with official Apple APIs
- [Apple Developer Forums: How to get a list of installed apps using Swift](https://forums.developer.apple.com/forums/thread/678004) -- Confirms no comprehensive system API; FileManager scan is standard
- [SwiftUI Tables Quick Guide (Use Your Loaf)](https://useyourloaf.com/blog/swiftui-tables-quick-guide/) -- Table sort pattern verified
- [SwiftUI: Add Sorting to Table (Level Up Coding)](https://levelup.gitconnected.com/swiftui-add-sorting-to-table-f229bc87856b) -- KeyPathComparator pattern
- [Apple: onDeleteCommand documentation](https://developer.apple.com/documentation/swiftui/view/ondeletecommand(perform:)) -- Delete key handling

### Tertiary (LOW confidence)
- Password manager bundle IDs: Assembled from multiple indirect sources (App Store listings, Homebrew cask files, community forums). Prefix matching compensates for uncertainty.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all native frameworks, no new dependencies, patterns proven in codebase
- Architecture: HIGH -- follows existing codebase patterns (UserDefaults, service classes, settings tabs)
- Filtering logic: HIGH -- `frontmostApplication.bundleIdentifier` already used in codebase for source attribution
- App discovery: HIGH -- FileManager scan is well-documented and widely used
- SwiftUI Table: HIGH -- available on macOS 13+, project targets macOS 14
- Password manager detection: MEDIUM -- bundle IDs assembled from indirect sources; prefix matching mitigates risk
- Pitfalls: HIGH -- based on direct codebase analysis of ClipboardMonitor code paths

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (stable -- all native APIs, no third-party dependencies)
