# Stack Research

**Domain:** Native macOS Clipboard Manager
**Project:** Pastel
**Researched:** 2026-02-05
**Confidence:** MEDIUM-HIGH

> **Note on sources:** WebSearch and WebFetch were unavailable during this research session. All recommendations are based on training knowledge of Apple's frameworks and macOS development ecosystem. Apple's first-party frameworks (AppKit, SwiftUI, SwiftData, Core Graphics) are stable, well-documented, and unlikely to have changed significantly since training cutoff. Third-party library versions should be verified against current releases before implementation. Confidence levels reflect this.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| Swift | 6.0+ | Primary language | Only sensible choice for native macOS. Swift 6 adds complete concurrency checking which matters for clipboard polling on background threads. Swift 5.10+ is also fine if Swift 6 migration overhead is too high. | HIGH |
| SwiftUI | macOS 14+ (Sonoma) | UI framework | Modern declarative UI. MenuBarExtra (macOS 13+) and improved window management make it viable for menu bar apps. macOS 14 adds Observable macro which replaces ObservableObject for cleaner state management. | HIGH |
| AppKit (bridged) | macOS 14+ | Window management, clipboard, system integration | SwiftUI alone cannot handle NSPanel, NSPasteboard, or accessibility APIs. AppKit bridging via NSViewRepresentable/NSHostingView is essential. This is the standard pattern for pro macOS apps. | HIGH |
| Xcode | 16+ | IDE and build system | Required for macOS app development. Xcode 16 ships with Swift 6, modern SwiftUI previews, and current macOS SDK. | HIGH |

### Clipboard Monitoring

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| NSPasteboard | AppKit (system) | Read clipboard contents | The only API for reading macOS clipboard. Use `NSPasteboard.general` to access the system clipboard. No alternative exists. | HIGH |
| Timer-based polling | Foundation (system) | Detect clipboard changes | NSPasteboard has no notification/delegate for changes. The standard approach used by every macOS clipboard manager (Maccy, Clipy, Paste) is to poll `changeCount` on a timer. 0.5-1.0 second interval is the sweet spot. | HIGH |
| NSPasteboard.changeCount | AppKit (system) | Change detection | Integer that increments on every clipboard change. Compare previous vs current value on each poll tick. This is the canonical detection mechanism. | HIGH |

**Clipboard monitoring detail:**

```swift
// The standard pattern — every macOS clipboard manager uses this
class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = 0

    func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    private func checkForChanges() {
        let currentCount = NSPasteboard.general.changeCount
        if currentCount != lastChangeCount {
            lastChangeCount = currentCount
            // Read and process new clipboard content
        }
    }
}
```

**Why not event-based?** Apple does not provide a clipboard change notification. There is no `NSPasteboard.didChangeNotification`. The `NSPasteboardDidChange` notification that some sources mention does not exist in the public API. Polling `changeCount` is the only reliable approach and is used by all production clipboard managers on macOS.

### Database / Persistence

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| SwiftData | macOS 14+ (Sonoma) | Clipboard history metadata storage | Apple's modern persistence framework. Swift-native with `@Model` macro, automatic SwiftUI integration via `@Query`, built-in sorting/filtering/predicates. Eliminates Core Data boilerplate. Backed by SQLite under the hood. | MEDIUM-HIGH |

**Why SwiftData over alternatives:**

SwiftData is the recommended choice because:
1. **Swift-native API** -- `@Model` macro instead of `.xcdatamodeld` files and NSManagedObject subclasses
2. **SwiftUI integration** -- `@Query` property wrapper auto-refreshes views when data changes, `modelContainer` modifier sets up the stack
3. **Automatic migrations** -- Lightweight schema migration works automatically for simple changes
4. **Predicate macro** -- Type-safe `#Predicate` replaces NSPredicate string-based queries
5. **Simpler than Core Data** -- No MOC/PSC/entity description ceremony

**Model example for clipboard items:**

```swift
@Model
class ClipboardItem {
    var content: String          // text content or file path
    var type: ClipboardItemType  // text, image, url, file, code, color
    var timestamp: Date
    var changeCount: Int         // NSPasteboard changeCount when captured
    var sourceApp: String?       // bundle ID of the app that copied
    var imagePath: String?       // relative path to stored image file
    var thumbnailPath: String?   // relative path to thumbnail
    var labels: [Label]          // many-to-many relationship
    var isPinned: Bool

    init(...) { ... }
}

@Model
class Label {
    var name: String
    var color: String            // hex color
    var items: [ClipboardItem]   // inverse relationship
}
```

### Image Storage

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| FileManager | Foundation (system) | Store images on disk | Images should NOT go in SwiftData/SQLite. Store as files in app's Application Support directory. Database stores only the relative path. This keeps the database fast and small. | HIGH |
| NSImage / CGImage | AppKit/CoreGraphics | Thumbnail generation | Resize images to ~200px thumbnails on capture. Store thumbnail alongside full image. Load full image only on demand (double-click). | HIGH |
| Application Support directory | macOS convention | Storage location | `~/Library/Application Support/Pastel/Images/` is the correct macOS convention for user data files. Use FileManager.default.urls(for: .applicationSupportDirectory). | HIGH |

**Image storage pattern:**

```
~/Library/Application Support/Pastel/
  Images/
    {uuid}.png          -- full-size image
    {uuid}_thumb.png    -- 200px thumbnail
```

**Why not store images in the database:**
- SQLite performance degrades with large BLOBs
- SwiftData has no efficient BLOB streaming
- File system provides OS-level caching and memory mapping
- Thumbnails can be loaded lazily in the sidebar
- Cleanup is straightforward (delete file + database row)

### Window Management (Screen-Edge Panel)

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| NSPanel | AppKit (system) | Floating screen-edge panel | NSPanel is a subclass of NSWindow designed for auxiliary panels. Key properties: `isFloatingPanel = true` (stays above normal windows), `becomesKeyOnlyIfNeeded = true` (doesn't steal focus), `hidesOnDeactivate = false` (stays visible). This is what PastePal and similar apps use. | HIGH |
| NSHostingView | SwiftUI (system) | Bridge SwiftUI into NSPanel | NSPanel is AppKit-only. Embed SwiftUI views inside it using NSHostingView. This gives you SwiftUI's declarative UI inside AppKit's window management. Standard pattern for pro macOS apps. | HIGH |

**Why NSPanel, not a SwiftUI Window:**
- SwiftUI `Window` and `WindowGroup` cannot be positioned at screen edges programmatically
- SwiftUI windows cannot be configured as floating panels
- SwiftUI windows always appear in the Window menu and can steal focus
- NSPanel provides `styleMask: [.nonactivatingPanel]` which is critical -- the panel must NOT deactivate the user's current app (otherwise paste-back fails)
- NSPanel with `.nonactivatingPanel` lets the user interact with the panel without losing focus on their target app

**Panel configuration pattern:**

```swift
class PanelController: NSObject {
    private var panel: NSPanel!

    func createPanel() {
        panel = NSPanel(
            contentRect: calculateFrame(),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: ClipboardPanelView())
        panel.animationBehavior = .utilityWindow
    }

    func calculateFrame() -> NSRect {
        // Position at screen edge based on user preference
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.visibleFrame
        // Example: right edge, full height, 320px wide
        return NSRect(x: screenFrame.maxX - 320, y: screenFrame.minY,
                      width: 320, height: screenFrame.height)
    }
}
```

### Menu Bar App Architecture

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| MenuBarExtra | SwiftUI macOS 13+ | Menu bar icon and dropdown | SwiftUI's native menu bar API. Two styles: `.menu` (standard dropdown) and `.window` (custom window). Use `.window` style for a richer settings dropdown, or `.menu` for a simple menu. | HIGH |
| NSApp.setActivationPolicy(.accessory) | AppKit (system) | Hide dock icon | Makes the app a menu bar-only (agent) app with no Dock icon. Set via Info.plist `LSUIElement = true` or programmatically. | HIGH |
| App protocol with @main | SwiftUI (system) | App lifecycle | Standard SwiftUI app entry point. Combine MenuBarExtra scene with Settings scene. | HIGH |

**App structure pattern:**

```swift
@main
struct PastelApp: App {
    @StateObject var appState = AppState()

    var body: some Scene {
        // Menu bar icon
        MenuBarExtra("Pastel", systemImage: "clipboard") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        // Settings window (Cmd+, opens this)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        // Note: The sliding panel is NOT a SwiftUI Scene.
        // It's an NSPanel managed by AppState/PanelController.
    }
}
```

**Why this architecture:**
- `MenuBarExtra` handles the menu bar icon and its dropdown natively
- `Settings` scene gives you the standard macOS Preferences window
- The sliding panel is managed separately via AppKit (NSPanel) because SwiftUI scenes cannot be non-activating floating panels
- `LSUIElement = true` in Info.plist hides the Dock icon

### Paste-Back (Accessibility)

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| CGEvent | CoreGraphics (system) | Simulate Cmd+V keystroke | Post synthetic keyboard events to paste content. Create a Cmd+V key event pair (down + up) and post it. Requires Accessibility permission. | HIGH |
| Accessibility permission | macOS system | Required for paste simulation | App must be granted Accessibility access in System Settings > Privacy & Security > Accessibility. Without this, CGEvent posting is silently ignored. | HIGH |
| NSPasteboard (write) | AppKit (system) | Place content on clipboard before paste | Write the selected history item to NSPasteboard.general, then simulate Cmd+V. The target app receives the paste normally. | HIGH |

**Paste-back flow:**

```
User clicks item in panel
  -> Write item to NSPasteboard.general
  -> Brief delay (~50ms) for pasteboard to sync
  -> Post CGEvent for Cmd+V (key down + key up)
  -> Target app receives paste
```

**CGEvent paste simulation:**

```swift
func simulatePaste() {
    // Virtual key code for 'V' is 9
    let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)

    // Add Cmd modifier
    keyDown?.flags = .maskCommand
    keyUp?.flags = .maskCommand

    // Post to the system
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}
```

**Critical: The panel must use `.nonactivatingPanel` style.** If the panel steals focus from the target app, Cmd+V goes to the panel, not the app. This is the #1 mistake in clipboard manager development.

### Global Hotkeys

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| CGEvent.tapCreate | CoreGraphics (system) | Global hotkey listener | Create an event tap to intercept keyboard events system-wide. Can filter for specific key combinations. Requires Accessibility permission. | HIGH |
| HotKey (third-party) | ~0.2.0 | Simplified hotkey registration | Popular Swift wrapper around Carbon's `RegisterEventHotKey`. Cleaner API than raw CGEvent taps for simple hotkey registration. GitHub: soffes/HotKey. | MEDIUM |
| NSEvent.addGlobalMonitorForEvents | AppKit (system) | Alternative global key monitoring | Monitors key events globally. Simpler than CGEvent taps but cannot intercept/consume events (only observe). Good for toggle hotkey where you don't need to swallow the keypress. | HIGH |

**Recommendation:** Use `NSEvent.addGlobalMonitorForEvents` for the panel toggle hotkey (simpler, no event interception needed). For Cmd+1-9 paste shortcuts within the panel, use regular SwiftUI keyboard shortcuts since the panel is your own window.

### Search

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| SwiftData #Predicate | macOS 14+ | Database-level search | Use `#Predicate` with `.contains()` for searching clipboard text content. SwiftData translates this to SQLite LIKE queries. Fast enough for typical clipboard history sizes (thousands of items). | MEDIUM-HIGH |
| NSTextField (for search bar) | AppKit (system) | Search input with focus | SwiftUI TextField may have focus issues in NSPanel context. If focus management is problematic, bridge an NSTextField via NSViewRepresentable. | MEDIUM |

### Supporting Libraries

| Library | Version | Purpose | When to Use | Confidence |
|---------|---------|---------|-------------|------------|
| HotKey (soffes/HotKey) | ~0.2 | Global hotkey registration | For panel toggle shortcut. Wraps Carbon RegisterEventHotKey in Swift API. | MEDIUM (verify current version) |
| LaunchAtLogin (sindresorhus) | ~5.0 | Launch at login functionality | For "Start at Login" preference. Handles modern macOS ServiceManagement API. | MEDIUM (verify current version) |
| Defaults (sindresorhus) | ~8.0 | UserDefaults wrapper | For strongly-typed app preferences (sidebar position, retention period, paste behavior). | MEDIUM (verify current version) |
| KeyboardShortcuts (sindresorhus) | ~2.0 | User-configurable hotkeys | If you want users to customize the panel toggle hotkey. More full-featured than HotKey, includes a SwiftUI recording view. | MEDIUM (verify current version) |
| Highlightr | ~2.1 | Syntax highlighting | For code snippet previews in the clipboard history panel. Wraps highlight.js. | LOW (verify current version and maintenance status) |

> **Version caveat:** Third-party library versions above are from training data. Verify against current GitHub releases before adding to Package.swift. Use Swift Package Manager for all dependencies.

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode 16+ | IDE, build, debug, notarize | Required. Use Xcode's SwiftUI previews for rapid UI iteration. |
| Swift Package Manager | Dependency management | Built into Xcode. No CocoaPods or Carthage needed. |
| Instruments (Xcode) | Performance profiling | Use for clipboard polling performance, memory usage with images, UI responsiveness. |
| `tccutil` | Reset Accessibility permissions during dev | `tccutil reset Accessibility com.yourteam.Pastel` to test permission flows. |
| Console.app | System log viewing | Debug NSPasteboard issues and event posting. |

---

## Alternatives Considered

### Database: SwiftData vs Core Data vs Raw SQLite

| Criterion | SwiftData (Recommended) | Core Data | Raw SQLite (GRDB/SQLite.swift) |
|-----------|------------------------|-----------|-------------------------------|
| **Swift-native API** | Yes (`@Model` macro) | No (NSManagedObject, .xcdatamodeld) | Varies by wrapper |
| **SwiftUI integration** | Excellent (`@Query`) | Good (`@FetchRequest`) | Manual (need ObservableObject wrapper) |
| **Schema management** | Automatic lightweight migration | Manual migration mapping | Manual SQL migrations |
| **Learning curve** | Low if familiar with SwiftUI | Medium (lots of ceremony) | Low-medium |
| **Maturity** | macOS 14+ (relatively new) | 15+ years, battle-tested | Battle-tested |
| **Complex queries** | Good (`#Predicate` macro) | Good (NSPredicate) | Full SQL power |
| **Relationship support** | Yes | Yes | Manual joins |
| **When to choose** | Default for new SwiftUI apps | Legacy apps or pre-macOS 14 | Need raw SQL performance or complex queries |

**Recommendation:** SwiftData. For a new macOS 14+ app with SwiftUI, SwiftData is the clear winner. It eliminates Core Data boilerplate while providing equivalent functionality for our use case (simple models, basic queries, SwiftUI views). The clipboard history data model is straightforward -- this is exactly what SwiftData was designed for.

**Fallback:** If SwiftData has issues during development (it is younger than Core Data), Core Data is the fallback. They share the same SQLite backend and similar concepts. Migration path is well-documented by Apple.

### Menu Bar: MenuBarExtra vs NSStatusItem

| Criterion | MenuBarExtra (Recommended) | NSStatusItem (AppKit) |
|-----------|---------------------------|----------------------|
| **SwiftUI-native** | Yes | No (requires bridging) |
| **Customization** | Window or menu style | Full control |
| **Minimum macOS** | 13.0 (Ventura) | Any version |
| **Ease of use** | Very high | Medium |
| **When to choose** | New SwiftUI apps targeting macOS 13+ | Need pre-Ventura support or deep customization |

**Recommendation:** MenuBarExtra. Since we're targeting macOS 14+ for SwiftData anyway, MenuBarExtra is available and provides the simplest path. Use `.window` style for a custom dropdown view, or `.menu` style for a standard menu.

### Window: NSPanel vs SwiftUI Window vs NSWindow

| Criterion | NSPanel (Recommended) | SwiftUI Window/WindowGroup | NSWindow |
|-----------|----------------------|---------------------------|----------|
| **Non-activating** | Yes (`.nonactivatingPanel`) | No | Possible but more work |
| **Floating** | Built-in (`isFloatingPanel`) | No | Manual level management |
| **Focus behavior** | `becomesKeyOnlyIfNeeded` | Always steals focus | Manual |
| **SwiftUI content** | Via NSHostingView | Native | Via NSHostingView |
| **When to choose** | Auxiliary panels, palettes, inspectors | Primary app windows | Custom window behaviors |

**Recommendation:** NSPanel. This is a hard requirement, not a preference. The clipboard panel MUST NOT steal focus from the user's active app, or paste-back breaks. Only NSPanel with `.nonactivatingPanel` style mask provides this behavior. Wrap SwiftUI views inside it via NSHostingView.

### Global Hotkeys: HotKey vs KeyboardShortcuts vs Raw CGEvent

| Criterion | HotKey | KeyboardShortcuts | CGEvent Tap |
|-----------|--------|-------------------|-------------|
| **API simplicity** | Very simple | Simple with UI | Complex |
| **User-configurable** | No | Yes (recording view) | No |
| **SwiftUI integration** | Minimal | Good | None |
| **When to choose** | Fixed hotkeys, simple case | User-customizable hotkeys with settings UI | Need event interception |

**Recommendation:** KeyboardShortcuts (sindresorhus). It provides a SwiftUI-compatible hotkey recorder that users can use to customize their panel toggle key. This is more user-friendly than hardcoded hotkeys and is the standard in the macOS indie app ecosystem. HotKey is fine if you want simpler code and don't need user customization.

### Image Thumbnail Generation: NSImage vs Core Image vs vImage

| Criterion | NSImage (Recommended) | Core Image | vImage |
|-----------|----------------------|------------|--------|
| **Simplicity** | Very simple | Medium | Complex |
| **Quality** | Good | Excellent | Excellent |
| **Performance** | Good enough | GPU-accelerated | SIMD-accelerated |
| **When to choose** | Standard thumbnails | Filter chains, effects | Batch processing, extreme perf |

**Recommendation:** NSImage. For generating ~200px thumbnails, NSImage's built-in scaling is perfectly adequate. Core Image and vImage are overkill. A simple `NSImage.resize(to:)` extension is all you need.

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Electron / web views | Defeats the purpose of native macOS. Clipboard managers need low latency, minimal memory, and deep system integration. Electron cannot access NSPasteboard or simulate key events natively. | Swift + SwiftUI + AppKit |
| Core Data (for new project) | Unnecessary boilerplate when SwiftData is available. `.xcdatamodeld` files, NSManagedObject subclasses, and fetch request controllers add ceremony with no benefit for this use case. | SwiftData |
| Realm | Third-party database that adds dependency weight. SwiftData/SQLite are first-party and sufficient. Realm's cloud sync features are irrelevant (no sync needed). | SwiftData |
| NSPasteboard notifications | Do not exist in the public API. Some outdated blog posts reference private/deprecated notifications. The only reliable approach is polling `changeCount`. | Timer-based polling of `changeCount` |
| SwiftUI Window for the panel | Cannot be configured as non-activating. Will steal focus from the active app and break paste-back. This is a showstopper. | NSPanel with NSHostingView |
| CocoaPods / Carthage | Outdated dependency managers. Swift Package Manager is built into Xcode and is the standard for pure Swift projects. | Swift Package Manager |
| Storing images in SQLite/SwiftData | Large BLOBs degrade query performance, increase database file size, and complicate backups. | FileManager + disk storage with path references in SwiftData |
| `NSEvent.addLocalMonitorForEvents` for global hotkeys | "Local" monitor only works when your app is the active app. For a menu bar app that needs to respond globally, you need global monitors. | `NSEvent.addGlobalMonitorForEvents` or HotKey/KeyboardShortcuts |
| UIKit | iOS framework. Does not exist on macOS. Use AppKit for macOS-specific APIs. | AppKit |
| Combine for simple state | Combine adds complexity for basic state management. SwiftUI's `@Observable` (macOS 14+) and `@State`/`@Binding` are simpler and sufficient. | `@Observable` macro, `@State`, `@Binding` |

---

## Stack Patterns by Variant

**If targeting macOS 13 (Ventura) minimum:**
- Use `ObservableObject` + `@Published` instead of `@Observable` macro
- Use Core Data instead of SwiftData (SwiftData requires macOS 14)
- MenuBarExtra is still available (macOS 13+)
- Everything else remains the same

**If targeting macOS 14 (Sonoma) minimum (RECOMMENDED):**
- Use `@Observable` macro for state management
- Use SwiftData for persistence
- Use MenuBarExtra for menu bar
- Full access to modern SwiftUI features

**If targeting macOS 15 (Sequoia) minimum:**
- Same as macOS 14 stack
- Gains access to latest SwiftUI improvements
- Smaller user base (users on older macOS)

**Recommendation:** Target macOS 14 (Sonoma). This gives access to SwiftData and `@Observable` while covering the vast majority of active macOS users. macOS 13 is increasingly old, and supporting it means giving up SwiftData (the biggest DX win in the stack).

---

## Version Compatibility Matrix

| Component | Minimum macOS | Notes |
|-----------|---------------|-------|
| SwiftUI | 10.15+ | But modern features (MenuBarExtra, Observable) require 13-14+ |
| MenuBarExtra | 13.0 (Ventura) | `.window` style also requires 13.0 |
| SwiftData | 14.0 (Sonoma) | Sets the floor for our deployment target |
| `@Observable` macro | 14.0 (Sonoma) | Replacement for ObservableObject |
| `#Predicate` macro | 14.0 (Sonoma) | Used with SwiftData queries |
| NSPanel | Any | Stable AppKit API, available on all macOS versions |
| NSPasteboard | Any | Stable AppKit API |
| CGEvent | Any | Requires Accessibility permission |
| FileManager | Any | Foundation, always available |

**Deployment target:** macOS 14.0 (Sonoma)
**Build with:** Xcode 16+ / Swift 6.0+

---

## Project Setup

### Package.swift Dependencies

```swift
// In Xcode project, add via File > Add Package Dependencies:

// Global hotkey registration with SwiftUI recorder
// https://github.com/sindresorhus/KeyboardShortcuts
// Version: verify latest on GitHub

// Launch at Login
// https://github.com/sindresorhus/LaunchAtLogin-Modern
// Version: verify latest on GitHub
// Note: "Modern" variant uses the ServiceManagement framework (macOS 13+)

// Optional: Syntax highlighting for code snippets
// https://github.com/raspu/Highlightr
// Version: verify latest on GitHub
```

### Info.plist Configuration

```xml
<!-- Menu bar only app (no dock icon) -->
<key>LSUIElement</key>
<true/>

<!-- App Sandbox entitlements -->
<!-- Note: Accessibility permission is requested at runtime, not via entitlement -->
```

### Entitlements

```xml
<!-- com.yourteam.Pastel.entitlements -->
<key>com.apple.security.app-sandbox</key>
<true/>

<!-- File access for image storage in Application Support -->
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

> **Sandbox note:** If distributing outside the Mac App Store, you can skip App Sandbox. If targeting the Mac App Store, you'll need to carefully configure sandbox entitlements. Accessibility permission (for paste-back) works with sandboxed apps but requires user approval in System Settings.

### Directory Structure

```
Pastel/
  PastelApp.swift              -- @main entry point, Scene definitions
  Models/
    ClipboardItem.swift        -- SwiftData @Model
    Label.swift                -- SwiftData @Model
    ClipboardItemType.swift    -- Enum for content types
  Services/
    ClipboardMonitor.swift     -- NSPasteboard polling
    PasteService.swift         -- CGEvent paste simulation
    ImageStorageService.swift  -- File system image management
    HotkeyService.swift        -- Global hotkey registration
  Views/
    Panel/
      ClipboardPanelView.swift -- Main panel SwiftUI view
      ClipboardCardView.swift  -- Individual item card
      SearchBar.swift          -- Search input
      LabelChipBar.swift       -- Label filter chips
    MenuBar/
      MenuBarView.swift        -- MenuBarExtra content
    Settings/
      SettingsView.swift       -- Preferences window
      GeneralSettings.swift    -- General tab
      AppearanceSettings.swift -- Appearance tab
  Controllers/
    PanelController.swift      -- NSPanel management
  Extensions/
    NSImage+Thumbnail.swift    -- Image resizing
    NSPasteboard+Read.swift    -- Typed pasteboard reading
  Resources/
    Assets.xcassets            -- App icon, colors
```

---

## Sources

All recommendations in this document are based on training knowledge of Apple's frameworks. The following should be consulted for verification:

- **Apple Developer Documentation** -- developer.apple.com/documentation (NSPasteboard, SwiftData, NSPanel, MenuBarExtra, CGEvent)
- **Apple WWDC sessions** -- WWDC23 "Meet SwiftData", WWDC23 "Build programmatic UI with Xcode", WWDC22 "Bring your app to the menu bar" (MenuBarExtra introduction)
- **Open-source clipboard managers** -- github.com/p0deje/Maccy (Swift, open-source clipboard manager using NSPasteboard polling), github.com/Clipy/Clipy (older but established architecture patterns)
- **sindresorhus GitHub** -- github.com/sindresorhus (KeyboardShortcuts, LaunchAtLogin, Defaults -- prolific macOS open-source developer, widely used libraries)
- **soffes/HotKey** -- github.com/soffes/HotKey (simple hotkey library)

**Confidence rationale:** Apple's first-party frameworks (AppKit, SwiftUI, SwiftData, CoreGraphics) are stable APIs documented by Apple. The patterns described (NSPasteboard polling, NSPanel for floating panels, CGEvent for paste simulation) are well-established in the macOS clipboard manager ecosystem and used by production apps (Maccy, Clipy, Paste, PastePal). Third-party library versions are from training data and should be verified.

---
*Stack research for: Pastel -- Native macOS Clipboard Manager*
*Researched: 2026-02-05*
