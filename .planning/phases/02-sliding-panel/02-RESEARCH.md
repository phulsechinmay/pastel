# Phase 2: Sliding Panel - Research

**Researched:** 2026-02-06
**Domain:** macOS NSPanel + SwiftUI integration, screen-edge sliding panel, clipboard history card UI
**Confidence:** HIGH

## Summary

Phase 2 introduces the core visual interface: a screen-edge sliding panel that displays clipboard history as rich content cards. The implementation requires bridging AppKit's NSPanel (for non-activating floating window behavior) with SwiftUI (for the card-based content UI), adding an NSVisualEffectView for dark vibrancy material, and animating the panel in/out from the right screen edge.

The architecture is well-understood. NSPanel with `.nonactivatingPanel` style mask is the established pattern for floating utility panels on macOS -- used by Spotlight, Alfred, Raycast, and Maccy (which shares our exact stack: NSPanel + SwiftUI + SwiftData). The critical constraint is that `.nonactivatingPanel` must be set at initialization time, not afterward. SwiftUI content is hosted inside the panel via NSHostingView.

For the card list, SwiftUI `List` outperforms `LazyVStack` for large datasets due to view recycling (inherited from UICollectionView/NSTableView), but `LazyVStack` provides the unlimited customization needed for our card designs. Given the expected dataset size (<10K items visible at once) and the need for custom card layouts, `LazyVStack` inside `ScrollView` is the right choice, with careful attention to keeping card views lightweight.

**Primary recommendation:** Build PanelController as an AppKit class owning an NSPanel subclass. Host all SwiftUI content via NSHostingView. Use NSAnimationContext with the window animator proxy for slide animation. Use NSVisualEffectView as the panel's content view background. Detect mouse screen via NSEvent.mouseLocation + NSScreen.screens iteration. Dismiss via NSEvent global+local monitors.

## Standard Stack

### Core

| Library/API | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| NSPanel | AppKit (system) | Non-activating floating window | Only way to create a floating panel that does not steal focus. `.nonactivatingPanel` style mask is the critical differentiator from NSWindow. Used by every production clipboard manager. |
| NSHostingView | SwiftUI (system) | Bridge SwiftUI views into NSPanel | Standard bridge for embedding SwiftUI view hierarchies inside AppKit containers. The panel's `contentView` is set to an NSHostingView wrapping the SwiftUI panel content. |
| NSVisualEffectView | AppKit (system) | Dark vibrancy material background | Provides behind-window blur with configurable material. For dark panel: use `.dark` material with `.behindWindow` blending and `.active` state. Must be bridged via NSViewRepresentable or set as the panel's root content view. |
| NSAnimationContext | AppKit (system) | Window slide animation | Wraps the panel's `animator().setFrame()` call with configurable duration and timing function. Default animation is 0.25s; we target 0.2s with easeOut. |
| NSEvent monitors | AppKit (system) | Click-outside dismiss + Escape key | `addGlobalMonitorForEvents` detects clicks outside the panel. `addLocalMonitorForEvents` detects Escape key press within the panel. |
| NSScreen | AppKit (system) | Multi-display detection | `NSScreen.screens` + `NSEvent.mouseLocation` to determine which screen the cursor is on for panel placement. |
| SwiftUI List/LazyVStack | SwiftUI (system) | Scrollable card list | Vertical scrollable list of clipboard history cards. LazyVStack for custom card layouts with lazy instantiation. |
| SwiftData @Query | SwiftData (system) | Reactive data binding | Fetches ClipboardItem models sorted by timestamp descending, auto-refreshes the card list when new items are captured. |

### Supporting

| Library/API | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| KeyboardShortcuts | 2.4+ (already in project) | Cmd+Shift+V temporary shortcut | Register a global keyboard shortcut for panel toggle during Phase 2 testing. Already a dependency from Phase 1 project setup. |
| CAMediaTimingFunction | Core Animation (system) | Animation easing curve | Use `.easeOut` for panel slide-in (fast start, gentle deceleration) and `.easeIn` for slide-out (gentle start, fast exit). |
| NSWorkspace | AppKit (system) | Source app icon resolution | Resolve `sourceAppBundleID` to an app icon for display on cards. Use `NSWorkspace.shared.icon(forFile:)` with the app bundle path. |
| RelativeDateTimeFormatter | Foundation (system) | "2m ago" timestamp formatting | Format `ClipboardItem.timestamp` as relative time for card display. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| LazyVStack in ScrollView | SwiftUI List | List has view recycling (better for 10K+ items) but limited card customization. List cannot achieve the visual card designs specified. LazyVStack is correct for our custom card requirements with <10K typical visible history. |
| NSAnimationContext + animator proxy | Core Animation CABasicAnimation on window layer | CABasicAnimation gives finer control but NSAnimationContext is simpler and sufficient for frame-based slide animation. No need for layer-level animation. |
| NSVisualEffectView (AppKit bridge) | SwiftUI `.background(.ultraThinMaterial)` | Native SwiftUI materials provide less control over blending than NSVisualEffectView. The AppKit bridge gives us exact material control (`.dark` material, `.behindWindow` blending). |
| NSEvent global monitor for click-outside | NSPanel `hidesOnDeactivate` | `hidesOnDeactivate` hides the panel when the app loses focus, but our nonactivating panel never truly "activates" -- so this property behaves differently. Explicit event monitoring is more reliable. |

## Architecture Patterns

### Recommended Project Structure Additions

```
Pastel/
├── Views/
│   └── Panel/
│       ├── PanelController.swift           # NSPanel lifecycle, animation, positioning
│       ├── SlidingPanel.swift              # NSPanel subclass with nonactivatingPanel config
│       ├── PanelContentView.swift          # Root SwiftUI view inside the panel
│       ├── ClipboardCardView.swift         # Individual card view (dispatches by content type)
│       ├── TextCardView.swift              # Text/rich text card variant
│       ├── ImageCardView.swift             # Image thumbnail card variant
│       ├── URLCardView.swift               # URL card variant (accent colored)
│       ├── FileCardView.swift              # File path card variant
│       └── EmptyStateView.swift            # "Copy something to get started" view
├── Views/
│   └── Shared/
│       └── VisualEffectView.swift          # NSViewRepresentable for NSVisualEffectView
└── Extensions/
    └── NSWorkspace+AppIcon.swift           # Resolve bundle ID to app icon
```

### Pattern 1: NSPanel Subclass with nonactivatingPanel

**What:** Create a custom NSPanel subclass configured for non-activating floating behavior at init time.

**When to use:** Always -- this is the panel window itself.

**Critical caveat:** The `.nonactivatingPanel` style mask MUST be set in the initializer. Changing it after init does not update the WindowServer's internal `_preventsActivation` tag. This is a known AppKit behavior documented in FB16484811.

**Example:**
```swift
// Source: Apple Developer Documentation + verified via philz.blog/nspanel-nonactivating-style-mask-flag
final class SlidingPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )

        // Floating behavior
        isFloatingPanel = true
        level = .floating

        // Stay visible across spaces and in fullscreen
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Do not hide when app loses focus (critical for nonactivating panel)
        hidesOnDeactivate = false

        // Transparent background (NSVisualEffectView provides the background)
        isOpaque = false
        backgroundColor = .clear

        // Enable window shadow on the leading edge
        hasShadow = true

        // Do not release when closed (we reuse the panel)
        isReleasedWhenClosed = false

        // No title bar
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // Fixed in place -- user cannot drag
        isMovableByWindowBackground = false
    }

    // Allow key status for future search field (Phase 4)
    // For Phase 2, this could be false, but setting true is forward-compatible
    override var canBecomeKey: Bool { true }

    // Never become main window
    override var canBecomeMain: Bool { false }
}
```

**Confidence:** HIGH -- NSPanel nonactivatingPanel is the established pattern. The init-time requirement is verified via the philz.blog deep dive and Apple feedback FB16484811.

### Pattern 2: PanelController Lifecycle Management

**What:** A controller class that owns the panel instance, manages show/hide animation, handles positioning, and coordinates event monitors for dismissal.

**When to use:** The central orchestrator for all panel behavior.

**Example:**
```swift
// Source: Architecture research + Maccy 2.0 patterns
@MainActor
final class PanelController {
    private var panel: SlidingPanel?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?

    /// The panel width (~300px as specified)
    private let panelWidth: CGFloat = 300

    /// Animation duration (0.2s as specified)
    private let animationDuration: TimeInterval = 0.2

    /// Whether the panel is currently visible
    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let screen = screenWithMouse()
        let visibleFrame = screen.visibleFrame

        // Create panel if needed (reuse across shows)
        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        // Final position: right edge, full height
        let onScreenFrame = NSRect(
            x: visibleFrame.maxX - panelWidth,
            y: visibleFrame.minY,
            width: panelWidth,
            height: visibleFrame.height
        )

        // Start position: just off the right edge
        let offScreenFrame = NSRect(
            x: visibleFrame.maxX,
            y: visibleFrame.minY,
            width: panelWidth,
            height: visibleFrame.height
        )

        panel.setFrame(offScreenFrame, display: false)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(onScreenFrame, display: true)
        }

        installEventMonitors()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }

        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let offScreenFrame = NSRect(
            x: visibleFrame.maxX,
            y: panel.frame.minY,
            width: panelWidth,
            height: panel.frame.height
        )

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offScreenFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.removeEventMonitors()
        })
    }

    // ... (event monitors, screen detection detailed below)
}
```

**Confidence:** HIGH -- This is the standard window controller pattern for macOS utility panels.

### Pattern 3: NSVisualEffectView as Panel Background

**What:** Use NSVisualEffectView with dark material for the panel's vibrancy/blur background. Either set it directly as the panel's content view (with NSHostingView as a subview) or bridge it into SwiftUI via NSViewRepresentable.

**When to use:** For the panel background.

**Recommended approach:** Set NSVisualEffectView as the panel's content view, then add the NSHostingView as a subview. This is simpler than the NSViewRepresentable bridge and gives direct control over the visual effect at the window level.

**Example:**
```swift
// Source: Apple Developer Documentation + ohanaware.com/swift/macOSVibrancy.html
private func createPanel() {
    let panel = SlidingPanel()

    // Visual effect background
    let visualEffect = NSVisualEffectView()
    visualEffect.material = .dark         // Dark blur material
    visualEffect.blendingMode = .behindWindow  // Blur content behind window
    visualEffect.state = .active          // Always active (not .followsWindowActiveState)
    visualEffect.appearance = NSAppearance(named: .darkAqua)  // Force dark appearance

    panel.contentView = visualEffect

    // SwiftUI content hosted inside the visual effect view
    let hostingView = NSHostingView(rootView:
        PanelContentView()
            .environment(\.colorScheme, .dark)  // Force dark color scheme in SwiftUI
    )
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    visualEffect.addSubview(hostingView)

    NSLayoutConstraint.activate([
        hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
        hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
        hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
    ])

    self.panel = panel
}
```

**Confidence:** HIGH -- NSVisualEffectView configuration for dark panels is well-documented. The `.dark` material + `.behindWindow` blending is the standard approach.

### Pattern 4: Multi-Display Screen Detection

**What:** Determine which screen the mouse cursor is on and position the panel on that screen.

**When to use:** Every time the panel is shown.

**Example:**
```swift
// Source: Apple Developer Documentation (NSScreen, NSEvent.mouseLocation)
private func screenWithMouse() -> NSScreen {
    let mouseLocation = NSEvent.mouseLocation
    for screen in NSScreen.screens {
        if screen.frame.contains(mouseLocation) {
            return screen
        }
    }
    return NSScreen.main ?? NSScreen.screens[0]
}
```

**Confidence:** HIGH -- `NSEvent.mouseLocation` returns the cursor position in global screen coordinates. `NSScreen.screens` contains all connected displays. Simple iteration with `frame.contains()` determines the correct screen.

### Pattern 5: Event Monitor Dismiss (Click-Outside + Escape)

**What:** Dismiss the panel when the user clicks outside it or presses Escape.

**When to use:** After panel is shown, removed when hidden.

**Example:**
```swift
// Source: Apple Developer Documentation + community patterns
private func installEventMonitors() {
    // Global monitor: clicks outside the panel (in other apps or desktop)
    globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
        self?.hide()
    }

    // Local monitor: Escape key within the panel
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        if event.keyCode == 53 { // kVK_Escape = 53
            self?.hide()
            return nil  // Consume the event (prevents system beep)
        }
        return event
    }
}

private func removeEventMonitors() {
    if let monitor = globalClickMonitor {
        NSEvent.removeMonitor(monitor)
        globalClickMonitor = nil
    }
    if let monitor = localKeyMonitor {
        NSEvent.removeMonitor(monitor)
        localKeyMonitor = nil
    }
}
```

**Note on click detection:** `addGlobalMonitorForEvents` only fires for events in OTHER applications' windows. For clicks in our own app's windows but outside the panel, we also need a local monitor checking the click location. However, since our app has no other visible windows (menu bar only), the global monitor is sufficient for Phase 2.

**Confidence:** HIGH -- This is the standard dismiss pattern used by Spotlight-like floating panels.

### Pattern 6: SwiftUI Card Views with Content Type Dispatch

**What:** A card view that dispatches to type-specific subviews based on the ClipboardItem's content type.

**When to use:** For every item in the scrollable list.

**Example:**
```swift
// Source: SwiftUI standard patterns
struct ClipboardCardView: View {
    let item: ClipboardItem

    var body: some View {
        HStack(spacing: 8) {
            // Source app icon (small, left side)
            if let bundleID = item.sourceAppBundleID {
                AppIconView(bundleID: bundleID)
                    .frame(width: 20, height: 20)
            }

            // Content preview (center, fills space)
            contentPreview
                .frame(maxWidth: .infinity, alignment: .leading)

            // Relative timestamp (right side)
            Text(item.timestamp, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: cardHeight)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .text, .richText:
            Text(item.textContent ?? "")
                .font(.system(.body, design: .default))
                .lineLimit(3)
                .foregroundStyle(.primary)

        case .image:
            if let thumbPath = item.thumbnailPath {
                AsyncThumbnailView(filename: thumbPath)
            }

        case .url:
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .foregroundStyle(.blue)
                Text(item.textContent ?? "")
                    .foregroundStyle(.blue)
                    .lineLimit(2)
            }

        case .file:
            HStack(spacing: 4) {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                Text(item.textContent ?? "")
                    .lineLimit(2)
            }
        }
    }

    private var cardHeight: CGFloat {
        switch item.type {
        case .image: return 90
        default: return 72
        }
    }
}
```

**Confidence:** HIGH -- Standard SwiftUI view composition patterns.

### Anti-Patterns to Avoid

- **Using SwiftUI Window/WindowGroup for the panel:** SwiftUI windows steal focus, appear in the Window menu, and cannot be configured as nonactivating. This is the #1 architectural mistake and requires a full rewrite to fix.

- **Setting `.nonactivatingPanel` after init:** The WindowServer tag is only set during NSPanel initialization. Changing the style mask later creates a panel that appears to work but has subtle focus-stealing bugs.

- **Creating the panel on every show:** Allocating NSPanel + NSHostingView on every toggle adds 50-100ms latency. Pre-allocate the panel once and reuse it by toggling visibility with `orderFront`/`orderOut`.

- **Loading full-size images in card views:** Cards should display only the 200px thumbnail (already generated in Phase 1). Loading full images would cause memory pressure and scroll jank. Use `ImageStorageService.resolveImageURL()` to load only the thumbnail file.

- **Using `@Query` with no fetch limit in the panel:** Without a fetch limit, SwiftData will load ALL clipboard items at once. Use `fetchLimit` on the initial query and implement pagination or rely on LazyVStack's lazy loading to keep memory bounded.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Non-activating floating window | Custom NSWindow with focus hacks | NSPanel with `.nonactivatingPanel` | Focus management is complex; NSPanel handles it correctly at the WindowServer level |
| Window blur/vibrancy background | Custom blur shader or Core Image filter | NSVisualEffectView with `.dark` material | System-provided materials match macOS design, adapt to wallpaper, and are GPU-accelerated |
| Relative time formatting ("2m ago") | Manual string formatting with if/else | `RelativeDateTimeFormatter` or `Text(date, format: .relative)` | Handles localization, "just now", minutes, hours, days automatically |
| App icon from bundle ID | Manual plist parsing or NSWorkspace.shared.icon | `NSWorkspace.shared.icon(forFile: path)` with `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` | Handles missing icons, default icons, and icon caching automatically |
| Window animation | Manual timer-based frame updates | `NSAnimationContext` + `window.animator().setFrame()` | System animation framework handles timing, easing, and display sync |
| Global keyboard shortcut (Cmd+Shift+V) | Raw Carbon RegisterEventHotKey | KeyboardShortcuts library (already a dependency) | Already in the project; provides clean Swift API and will be needed for user-configurable shortcuts in Phase 5 |

**Key insight:** Every macOS system-level behavior (focus management, blur materials, window animation, keyboard shortcuts) has a first-party AppKit API. Using them ensures correctness across macOS versions and reduces maintenance burden.

## Common Pitfalls

### Pitfall 1: nonactivatingPanel Must Be Set at Init Time

**What goes wrong:** Developer creates an NSPanel, then tries to add `.nonactivatingPanel` to the style mask later. The panel appears to work but subtly steals focus from the target app.

**Why it happens:** AppKit's `-setStyleMask:` updates the style mask property but does NOT call the internal `-_setPreventsActivation:` method that sets the WindowServer tag. This tag is only set during init.

**How to avoid:** Always pass `.nonactivatingPanel` in the `styleMask` parameter of `NSPanel.init(contentRect:styleMask:backing:defer:)`. Never modify the style mask after creation to add/remove this flag.

**Warning signs:** When the panel appears, the menu bar switches to show Pastel's menus. The previously active app's window dims slightly.

**Confidence:** HIGH -- Verified via detailed reverse engineering blog post (philz.blog) and Apple feedback FB16484811.

### Pitfall 2: NSHostingView Steals First Responder

**What goes wrong:** Even with a nonactivating panel, NSHostingView's internal SwiftUI views may attempt to become first responder (e.g., when a focusable element is present), causing the panel to inadvertently activate.

**Why it happens:** SwiftUI's focus system doesn't fully understand the nonactivating panel context. Views with `.focusable()` or interactive controls may request focus.

**How to avoid:** For Phase 2, avoid adding any focusable views (TextField, TextEditor) to the panel content. Cards should use `.onTapGesture` or button actions, not focus-based interaction. When search is added in Phase 4, `canBecomeKey` will need to be conditionally managed.

**Warning signs:** Clicking a card causes the menu bar to flash or change.

**Confidence:** MEDIUM -- Based on community reports of SwiftUI focus issues in NSPanel contexts.

### Pitfall 3: Panel Pre-allocation vs On-Demand Creation Latency

**What goes wrong:** Creating the NSPanel + NSHostingView on every toggle adds visible latency (50-100ms for view hierarchy construction).

**Why it happens:** NSHostingView must build the entire SwiftUI view graph on creation. With a complex card list, this is not instantaneous.

**How to avoid:** Create the panel once on app startup (or on first toggle) and keep it allocated in memory. Toggle visibility with `orderFront`/`orderOut`. The panel is lightweight when hidden (no rendering).

**Warning signs:** Visible delay between pressing the hotkey and the panel appearing. Panel animation "jumps" because the window was being created during the animation.

**Confidence:** HIGH -- Standard pattern documented in macOS clipboard manager pitfalls research.

### Pitfall 4: LazyVStack Memory Growth on Long Scrolls

**What goes wrong:** LazyVStack creates views lazily but does NOT recycle them. Once a view is scrolled past, it remains in memory. Scrolling through 5000+ items accumulates all those views.

**Why it happens:** Unlike UITableView/List (which recycle cells), LazyVStack simply defers creation but retains all created views. This is a known SwiftUI limitation.

**How to avoid:** For Phase 2, this is acceptable -- users rarely scroll through thousands of items manually. The panel shows most recent items first, and most interaction happens in the top 50-100 items. If memory becomes an issue, migrate to `List` with custom row styling, or implement manual pagination.

**Warning signs:** Memory usage in Activity Monitor grows as the user scrolls deeper into history.

**Confidence:** HIGH -- Well-documented LazyVStack behavior, confirmed in multiple Apple Developer Forum threads and performance guides.

### Pitfall 5: Thumbnail Loading Blocks the Main Thread

**What goes wrong:** Loading thumbnail images from disk synchronously in card views causes scroll jank. Each card that scrolls into view triggers a disk read.

**Why it happens:** If the thumbnail is loaded with a simple `NSImage(contentsOfFile:)` in the view body, it blocks the main thread during view construction.

**How to avoid:** Load thumbnails asynchronously. Use SwiftUI's `AsyncImage` with a local file URL, or create a custom `AsyncThumbnailView` that loads the image on a background queue and displays it with a placeholder.

**Warning signs:** Scrolling stutters or pauses when image cards come into view.

**Confidence:** HIGH -- Standard async image loading pattern.

### Pitfall 6: visibleFrame vs frame for Screen Positioning

**What goes wrong:** Using `NSScreen.frame` instead of `NSScreen.visibleFrame` positions the panel behind the menu bar or Dock.

**Why it happens:** `NSScreen.frame` is the full screen rectangle. `NSScreen.visibleFrame` excludes the menu bar and Dock areas.

**How to avoid:** Always use `screen.visibleFrame` for panel positioning. This automatically accounts for menu bar height, Dock position, and Dock auto-hide.

**Warning signs:** Panel extends behind the menu bar or overlaps the Dock.

**Confidence:** HIGH -- Documented in Apple Developer Documentation for NSScreen.

## Code Examples

### Complete VisualEffectView Bridge (SwiftUI NSViewRepresentable)

```swift
// Source: Apple Developer Documentation + ohanaware.com/swift/macOSVibrancy.html
import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
```

### Async Thumbnail View for Image Cards

```swift
// Source: Standard SwiftUI async image pattern
struct AsyncThumbnailView: View {
    let filename: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .task(id: filename) {
            image = await loadThumbnail()
        }
    }

    private func loadThumbnail() async -> NSImage? {
        let url = ImageStorageService.shared.resolveImageURL(filename)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = NSImage(contentsOf: url)
                continuation.resume(returning: img)
            }
        }
    }
}
```

### Source App Icon Resolution

```swift
// Source: Apple Developer Documentation (NSWorkspace)
extension NSWorkspace {
    func appIcon(forBundleIdentifier bundleID: String) -> NSImage? {
        guard let url = urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return icon(forFile: url.path)
    }
}
```

### PanelContentView Root SwiftUI View

```swift
// Source: SwiftUI standard patterns
struct PanelContentView: View {
    @Query(sort: \ClipboardItem.timestamp, order: .reverse)
    private var items: [ClipboardItem]

    var body: some View {
        VStack(spacing: 0) {
            // Minimal header
            PanelHeaderView()

            if items.isEmpty {
                EmptyStateView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { item in
                            ClipboardCardView(item: item)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }
}
```

### Panel Toggle from Menu Bar

```swift
// Source: Existing PastelApp.swift architecture
// In PastelApp.swift or AppState.swift, integrate PanelController:

@MainActor
@Observable
final class AppState {
    var clipboardMonitor: ClipboardMonitor?
    let panelController = PanelController()

    // ... existing code ...

    func togglePanel() {
        panelController.toggle()
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ObservableObject + @Published | @Observable macro (macOS 14+) | WWDC 2023 | Simpler observation, no property wrapper ceremony. Already used in the project. |
| Core Data + @FetchRequest | SwiftData + @Query | WWDC 2023 | Native Swift persistence with automatic SwiftUI integration. Already used in the project. |
| NSMenu for clipboard popup | NSPanel + SwiftUI | Maccy 2.0 (2024-2025) | Rich visual cards instead of plain text menu items. Industry trend for modern clipboard managers. |
| UICollectionView bridged for lists | SwiftUI LazyVStack / List | SwiftUI matured 2022-2024 | Native SwiftUI lazy loading is now sufficient for most list use cases on macOS. |

**Deprecated/outdated:**
- Using `NSWindow` with manual focus management instead of `NSPanel.nonactivatingPanel` -- unnecessarily complex
- Using `NSImageView` for thumbnails in AppKit -- SwiftUI Image with async loading is cleaner
- Manual `NSView.animator()` frame animation without `NSAnimationContext` -- loses timing control

## Open Questions

1. **LazyVStack scrollbar appearance**
   - What we know: SwiftUI ScrollView shows scrollbars automatically. LazyVStack does not inherently provide scrollbar styling.
   - What's unclear: Whether the default scrollbar appearance is acceptable in a dark vibrancy panel or if custom styling is needed.
   - Recommendation: Use default scrollbar behavior for Phase 2. If it looks off against the dark material, apply `.scrollIndicators(.hidden)` and rely on scroll momentum. This is a polish item.

2. **SwiftData @Query performance with large datasets in NSHostingView context**
   - What we know: @Query works well in standard SwiftUI windows. NSHostingView should propagate the model container correctly.
   - What's unclear: Whether @Query observation triggers correctly when the hosting view is inside an NSPanel that is ordered out (hidden).
   - Recommendation: Pass the `modelContainer` to the NSHostingView's root view. Test with 500+ items to verify @Query updates propagate when the panel is shown. If issues arise, fall back to manual `FetchDescriptor` queries in the controller.

3. **Drop shadow on borderless panel left edge**
   - What we know: `NSWindow.hasShadow = true` adds an automatic shadow. Borderless windows may have different shadow behavior than titled windows.
   - What's unclear: Whether the automatic shadow is sufficient for the "drop shadow on the left edge" design specification, or if a custom NSShadow needs to be applied.
   - Recommendation: Enable `hasShadow = true` on the panel and verify the result visually. The system shadow should be adequate. If not, add a custom shadow layer on the leading edge of the content view.

## Sources

### Primary (HIGH confidence)
- [Apple Developer Documentation: NSPanel](https://developer.apple.com/documentation/appkit/nspanel) -- NSPanel class reference, style masks, floating panel behavior
- [Apple Developer Documentation: nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel) -- Style mask documentation
- [Apple Developer Documentation: NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview) -- SwiftUI-in-AppKit bridge
- [Apple Developer Documentation: NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview) -- Material and blending configuration
- [Apple Developer Documentation: NSScreen](https://developer.apple.com/documentation/appkit/nsscreen) -- Multi-display screen detection
- [Apple Developer Documentation: NSEvent.mouseLocation](https://developer.apple.com/documentation/appkit/nsevent/1533380-mouselocation) -- Cursor position
- [Apple Developer Documentation: addGlobalMonitorForEvents](https://developer.apple.com/documentation/appkit/nsevent/1535472-addglobalmonitorforevents) -- Global event monitoring
- [Apple Developer Documentation: addLocalMonitorForEvents](https://developer.apple.com/documentation/appkit/nsevent/1534971-addlocalmonitorforevents) -- Local event monitoring

### Secondary (MEDIUM confidence)
- [The Curious Case of NSPanel's Nonactivating Style Mask Flag (philz.blog)](https://philz.blog/nspanel-nonactivating-style-mask-flag/) -- Deep technical analysis of nonactivatingPanel init-time requirement, FB16484811
- [Create a Spotlight/Alfred-like window on macOS with SwiftUI (markusbodner.com)](https://www.markusbodner.com/til/2021/02/08/create-a-spotlight/alfred-like-window-on-macos-with-swiftui/) -- Complete floating panel + SwiftUI tutorial
- [Vibrancy, NSAppearance, and Visual Effects in Modern AppKit and SwiftUI (philz.blog)](https://philz.blog/vibrancy-nsappearance-and-visual-effects-in-modern-appkit-apps/) -- NSVisualEffectView configuration guidance
- [SwiftUI macOS Vibrancy (ohanaware.com)](https://ohanaware.com/swift/macOSVibrancy.html) -- NSViewRepresentable bridge code for NSVisualEffectView
- [List or LazyVStack - Choosing the Right Lazy Container (fatbobman.com)](https://fatbobman.com/en/posts/list-or-lazyvstack/) -- Detailed List vs LazyVStack comparison with performance analysis
- [Maccy 2.0 Release (GitHub)](https://github.com/p0deje/Maccy/releases/tag/2.0.0) -- Validates NSPanel + SwiftUI + SwiftData architecture for clipboard managers
- [Tuning Lazy Stacks and Grids in SwiftUI (Wesley Matlock, Medium)](https://medium.com/@wesleymatlock/tuning-lazy-stacks-and-grids-in-swiftui-a-performance-guide-2fb10786f76a) -- LazyVStack performance optimization guidance
- [How to animate NSWindow (onmyway133.com)](https://onmyway133.com/posts/how-to-animate-nswindow/) -- NSAnimationContext + animator proxy examples

### Tertiary (LOW confidence)
- [SwiftUI List performance is slow on macOS (Apple Developer Forums)](https://developer.apple.com/forums/thread/650238) -- Community reports of macOS-specific List performance issues; may be resolved in recent macOS versions

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All components are first-party Apple frameworks (NSPanel, NSHostingView, NSVisualEffectView, NSAnimationContext). Well-documented, stable APIs.
- Architecture: HIGH -- NSPanel + SwiftUI hosting pattern is established. Maccy 2.0 validates this exact stack combination for clipboard managers.
- Pitfalls: HIGH -- The nonactivatingPanel init-time caveat is verified via reverse engineering. Other pitfalls are standard macOS development concerns documented in Apple Forums and developer blogs.
- Card UI: MEDIUM -- Specific card dimensions and styling are design decisions, not verified patterns. The SwiftUI view composition approach is standard.

**Research date:** 2026-02-06
**Valid until:** 2026-03-08 (30 days -- stable Apple APIs unlikely to change)
