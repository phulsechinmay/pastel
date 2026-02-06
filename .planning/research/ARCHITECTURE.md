# Architecture Research

**Domain:** macOS clipboard manager (native Swift + SwiftUI)
**Researched:** 2026-02-05
**Confidence:** MEDIUM (based on training knowledge of macOS APIs and open-source clipboard managers like Maccy, Clipy; web verification tools unavailable during research)

## Confidence Note

WebSearch and WebFetch were unavailable during this research session. All findings are based on training knowledge of macOS development patterns, Apple framework APIs, and analysis of open-source clipboard managers (Maccy, Clipy, CopyClip patterns). Key architectural claims about NSPasteboard polling, CGEvent paste simulation, and SwiftUI/AppKit interop are well-established patterns with HIGH confidence. Newer API details (SwiftData maturity on macOS, latest NSPanel behaviors) are MEDIUM confidence and should be verified against current Apple documentation during implementation.

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                          UI Layer (SwiftUI)                          │
│  ┌──────────────┐  ┌─────────────────┐  ┌────────────────────────┐  │
│  │  Menu Bar     │  │  Sliding Panel   │  │  Settings Window       │  │
│  │  (NSStatusItem│  │  (NSPanel +      │  │  (SwiftUI Window)      │  │
│  │   + Popover)  │  │   SwiftUI)       │  │                        │  │
│  └──────┬───────┘  └────────┬─────────┘  └───────────┬────────────┘  │
│         │                   │                        │               │
├─────────┴───────────────────┴────────────────────────┴───────────────┤
│                     Application Services Layer                       │
│  ┌───────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │ Clipboard      │  │ Hotkey        │  │ Paste-Back               │  │
│  │ Monitor        │  │ Manager       │  │ Service                  │  │
│  │ (NSPasteboard  │  │ (Carbon/      │  │ (CGEvent + Accessibility │  │
│  │  polling)      │  │  CGEvent)     │  │  API)                    │  │
│  └───────┬───────┘  └──────┬───────┘  └──────────┬───────────────┘  │
│          │                  │                     │                  │
├──────────┴──────────────────┴─────────────────────┴──────────────────┤
│                        Data Layer                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐   │
│  │ ClipboardItem │  │ Image Storage │  │ Label / Search           │   │
│  │ Store         │  │ (Disk Files + │  │ Index                    │   │
│  │ (SwiftData/   │  │  Thumbnails)  │  │                          │   │
│  │  SQLite)      │  │               │  │                          │   │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **ClipboardMonitor** | Polls NSPasteboard for changes, detects new content, classifies type | Timer-based polling of `NSPasteboard.general.changeCount` every 0.5-1s |
| **ClipboardItem Store** | Persists clipboard entries with metadata (type, timestamp, source app, label) | SwiftData model or SQLite via GRDB/direct; stores text inline, images as file references |
| **ImageStorage** | Saves full images to disk, generates thumbnails, manages disk cache | Application Support directory; thumbnails at fixed size (e.g., 200px) via Core Graphics |
| **SlidingPanel** | Screen-edge overlay panel showing clipboard history with search and labels | NSPanel subclass (non-activating, floating) hosting SwiftUI content via NSHostingView |
| **MenuBarController** | Status bar icon, minimal dropdown for quick access/settings | NSStatusItem with NSPopover or NSMenu |
| **HotkeyManager** | Registers global hotkeys, dispatches to panel toggle and Cmd+1-9 paste | Carbon RegisterEventHotKey API or modern CGEvent tap approach |
| **PasteBackService** | Writes selected item to pasteboard, simulates Cmd+V in the frontmost app | Write to NSPasteboard, then post CGEvent for Cmd+V keystroke |
| **SettingsWindow** | User preferences: retention, paste behavior, sidebar position, hotkeys | Standard SwiftUI Settings scene or Window scene |
| **LabelManager** | CRUD for labels, assignment to items, filtering | SwiftData relationships or simple SQLite join table |
| **SearchEngine** | Full-text search across text content, combinable with label filters | SQLite FTS5 or SwiftData predicates with manual text matching |

---

## Recommended Project Structure

```
Pastel/
├── App/
│   ├── PastelApp.swift              # @main, App lifecycle, MenuBarExtra
│   ├── AppDelegate.swift            # NSApplicationDelegate for AppKit integration
│   └── AppState.swift               # Global app state (ObservableObject)
│
├── Services/
│   ├── ClipboardMonitor.swift       # NSPasteboard polling, change detection
│   ├── PasteBackService.swift       # CGEvent paste simulation
│   ├── HotkeyManager.swift         # Global hotkey registration
│   ├── ImageStorageService.swift    # Disk storage, thumbnail generation
│   └── RetentionService.swift       # Prune old items per user settings
│
├── Models/
│   ├── ClipboardItem.swift          # Core data model (SwiftData @Model)
│   ├── Label.swift                  # Label model
│   ├── ClipboardItemType.swift      # Enum: text, image, url, file, code, color
│   └── PasteConfiguration.swift     # User paste behavior settings
│
├── Views/
│   ├── Panel/
│   │   ├── SlidingPanelController.swift   # NSPanel subclass + window management
│   │   ├── PanelContentView.swift         # Root SwiftUI view for panel
│   │   ├── ClipboardItemCard.swift        # Individual item card view
│   │   ├── SearchBar.swift                # Search input + label filter chips
│   │   └── LabelChipView.swift            # Label filter UI
│   ├── MenuBar/
│   │   ├── MenuBarView.swift              # NSStatusItem content
│   │   └── MenuBarController.swift        # NSStatusItem setup
│   ├── Settings/
│   │   ├── SettingsView.swift             # Root settings view
│   │   ├── GeneralSettingsView.swift      # Retention, paste behavior
│   │   ├── AppearanceSettingsView.swift   # Panel position, theme
│   │   └── HotkeySettingsView.swift       # Hotkey configuration
│   └── Shared/
│       ├── ThumbnailView.swift            # Async image loading from disk
│       ├── SyntaxHighlightView.swift      # Code snippet rendering
│       ├── ColorSwatchView.swift          # Color preview
│       └── URLPreviewView.swift           # URL card with favicon/title
│
├── Utilities/
│   ├── NSPasteboard+Extensions.swift      # Pasteboard reading helpers
│   ├── CGEvent+Paste.swift                # Paste simulation helpers
│   ├── String+Detection.swift             # Content type detection (URL, code, color)
│   └── Permissions.swift                  # Accessibility permission check/request
│
├── Resources/
│   ├── Assets.xcassets                    # App icons, images
│   └── Pastel.entitlements               # Accessibility entitlement
│
└── Tests/
    ├── ClipboardMonitorTests.swift
    ├── ImageStorageTests.swift
    ├── ContentTypeDetectionTests.swift
    └── RetentionServiceTests.swift
```

### Structure Rationale

- **App/**: Thin app lifecycle layer. `AppDelegate` is needed because SwiftUI's `MenuBarExtra` alone cannot manage NSPanel windows and Carbon hotkey registration -- AppKit integration is required.
- **Services/**: Stateful singletons (or actor-isolated types) that run independent of UI. ClipboardMonitor runs on a timer, HotkeyManager holds Carbon event references, etc. These are the "engines" of the app.
- **Models/**: Pure data types. SwiftData `@Model` classes for persistence, enums for type classification. Keep these free of UI or service concerns.
- **Views/Panel/**: The most complex UI area. The panel controller is AppKit (NSPanel subclass), but its content is SwiftUI via NSHostingView. This split is intentional -- NSPanel provides the window-level behaviors (floating, non-activating, screen-edge positioning) that pure SwiftUI cannot.
- **Views/Settings/**: Standard SwiftUI views. Settings are the one area where pure SwiftUI works well on macOS.
- **Utilities/**: Extensions and helpers. Keep these stateless and testable.

---

## Architectural Patterns

### Pattern 1: NSPasteboard Polling with Change Count

**What:** Monitor the system clipboard by polling `NSPasteboard.general.changeCount` on a timer. When the count changes, read the new content and process it.

**When to use:** Always. This is the only reliable way to detect clipboard changes on macOS. There is no notification-based API for clipboard changes.

**Confidence:** HIGH -- this is the established pattern used by every macOS clipboard manager (Maccy, Clipy, Paste, etc.)

**Trade-offs:**
- Pros: Simple, reliable, works with all clipboard content types
- Cons: Polling introduces slight latency (0.5-1s); wastes trivial CPU when clipboard is idle
- A 0.5s interval is the sweet spot: fast enough to feel instant, slow enough to be negligible on CPU

**Example:**
```swift
import AppKit
import Combine

@MainActor
class ClipboardMonitor: ObservableObject {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general

    @Published var latestItem: ClipboardItem?

    func startMonitoring() {
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
    }

    private func checkForChanges() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Read new clipboard content
        if let content = readPasteboardContent() {
            latestItem = content
            // Persist via data layer
        }
    }

    private func readPasteboardContent() -> ClipboardItem? {
        // Check types in priority order: image, URL, file, rich text, plain text
        // Detect special types: color hex strings, code blocks, etc.
        // Return structured ClipboardItem
        return nil // placeholder
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
```

### Pattern 2: NSPanel for Floating Non-Activating Overlay

**What:** Use an NSPanel subclass (not NSWindow) for the sliding clipboard history panel. Configure it as non-activating and floating so it appears over other apps without stealing focus from the frontmost app.

**When to use:** For the screen-edge sliding panel. This is critical -- if the panel activates (takes focus), paste-back breaks because the target app is no longer frontmost.

**Confidence:** HIGH -- this is the standard pattern for app overlays that need to interact without stealing focus (Spotlight, Alfred, PastePal all use this approach).

**Trade-offs:**
- Pros: Does not steal focus from frontmost app, can float above all windows, enables paste-back to work
- Cons: Requires AppKit code (cannot be done in pure SwiftUI), adds complexity to window management
- SwiftUI content goes inside via NSHostingView -- you get the best of both worlds

**Example:**
```swift
import AppKit
import SwiftUI

class SlidingPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )

        self.level = .floating           // Float above normal windows
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false   // Stay visible when app loses focus
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.contentView = contentView
    }

    // Prevent the panel from becoming key window (keeps focus on target app)
    override var canBecomeKey: Bool { true }  // Need key for search field
    override var canBecomeMain: Bool { false }
}

class PanelController {
    private var panel: SlidingPanel?
    private let edge: ScreenEdge  // .left, .right, .top, .bottom

    func toggle() {
        if let panel = panel, panel.isVisible {
            animateOut()
        } else {
            animateIn()
        }
    }

    private func animateIn() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let panelSize = calculatePanelSize(for: edge, screen: screen)

        // Position off-screen at the configured edge
        let startFrame = offScreenFrame(for: edge, screen: screen, size: panelSize)
        let endFrame = onScreenFrame(for: edge, screen: screen, size: panelSize)

        let hostingView = NSHostingView(rootView: PanelContentView())
        panel = SlidingPanel(contentView: hostingView)
        panel?.setFrame(startFrame, display: false)
        panel?.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel?.animator().setFrame(endFrame, display: true)
        }
    }

    private func animateOut() { /* reverse animation, then orderOut */ }
    private func calculatePanelSize(for edge: ScreenEdge, screen: NSScreen) -> NSSize { /* ... */ }
    private func offScreenFrame(for edge: ScreenEdge, screen: NSScreen, size: NSSize) -> NSRect { /* ... */ }
    private func onScreenFrame(for edge: ScreenEdge, screen: NSScreen, size: NSSize) -> NSRect { /* ... */ }
}
```

### Pattern 3: CGEvent Paste Simulation

**What:** To paste an item back into the user's active app, write it to NSPasteboard.general, then simulate a Cmd+V keystroke using the CGEvent API.

**When to use:** For all paste-back operations (double-click item, Cmd+1-9 hotkeys).

**Confidence:** HIGH -- this is the standard approach. Maccy, Clipy, and Paste all use CGEvent-based Cmd+V simulation. The alternative (Accessibility API `AXUIElementPerformAction`) is less reliable across apps.

**Trade-offs:**
- Pros: Works with virtually all macOS apps, simple to implement
- Cons: Requires Accessibility permission (user must grant in System Settings > Privacy & Security > Accessibility); the original clipboard content is overwritten
- Mitigation for overwrite: Save previous clipboard content before paste, restore it after a short delay (though this can be flaky with rapid pastes)

**Example:**
```swift
import CoreGraphics
import AppKit

class PasteBackService {
    func paste(item: ClipboardItem) {
        // 1. Write item to system pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.type {
        case .text, .code, .url:
            pasteboard.setString(item.textContent!, forType: .string)
        case .image:
            if let imageData = loadImageData(for: item) {
                pasteboard.setData(imageData, forType: .tiff)
            }
        case .color:
            pasteboard.setString(item.textContent!, forType: .string)
        case .file:
            // Write file URL to pasteboard
            break
        }

        // 2. Simulate Cmd+V keystroke
        simulatePaste()
    }

    private func simulatePaste() {
        // Small delay to ensure pasteboard write completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .hidSystemState)

            // Key down: V with Cmd modifier
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)

            // Key up
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
```

### Pattern 4: Global Hotkeys via Carbon API or CGEvent Tap

**What:** Register system-wide hotkeys that work even when the app is not focused. The Carbon `RegisterEventHotKey` API is the most reliable approach for global hotkeys on macOS.

**When to use:** For the panel toggle hotkey and Cmd+1-9 paste shortcuts (when panel is visible).

**Confidence:** HIGH -- Carbon hotkey registration is battle-tested and still the standard approach (used by Maccy, Alfred, Raycast). Apple has not deprecated these Carbon APIs despite the age of the framework.

**Trade-offs:**
- Pros: Works globally, reliable, low overhead
- Cons: Carbon API is old C-based API, requires bridging to Swift; CGEvent tap alternative needs Accessibility permission
- Recommendation: Use Carbon `RegisterEventHotKey` for the global panel toggle; use SwiftUI `.onKeyPress` or NSEvent local monitor for Cmd+1-9 within the panel

**Example:**
```swift
import Carbon

class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?

    func registerPanelToggle(keyCode: UInt32, modifiers: UInt32) {
        var hotKeyID = EventHotKeyID(signature: OSType(0x50415354), // "PAST"
                                      id: 1)

        RegisterEventHotKey(
            keyCode,           // e.g., kVK_ANSI_V
            modifiers,         // e.g., cmdKey | shiftKey
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        // Install Carbon event handler for kEventHotKeyPressed
        installCarbonEventHandler()
    }

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                // Extract hotkey ID, dispatch to appropriate action
                var hotkeyID = EventHotKeyID()
                GetEventParameter(event!, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)

                // Post notification or call delegate based on hotkeyID.id
                NotificationCenter.default.post(name: .hotkeyPressed,
                                                 object: nil,
                                                 userInfo: ["id": hotkeyID.id])
                return noErr
            },
            1, &eventType, nil, nil
        )
    }
}
```

### Pattern 5: Hybrid AppKit/SwiftUI Architecture

**What:** Use SwiftUI for all view content but wrap it in AppKit containers (NSPanel, NSStatusItem, NSPopover) for window management. The app entry point uses `@main App` with `MenuBarExtra`, but an `AppDelegate` handles AppKit-specific setup.

**When to use:** Always, for any macOS menu bar app with advanced window behavior.

**Confidence:** HIGH -- this is the established pattern for macOS apps that need both modern UI (SwiftUI) and system-level window control (AppKit).

**Trade-offs:**
- Pros: Best of both worlds -- SwiftUI for reactive UI, AppKit for window management
- Cons: Two paradigms to manage; data flow between AppKit controllers and SwiftUI views needs careful bridging (ObservableObject, environment)
- SwiftUI's `MenuBarExtra` can be used for the status item itself, but NSPanel requires AppKit

---

## Data Flow

### Clipboard Capture Flow

```
NSPasteboard.general (System)
        │
        │ (poll every 0.5s, check changeCount)
        ▼
ClipboardMonitor
        │
        │ (read pasteboard types, detect content type)
        ▼
Content Type Detection
        │
        ├── Text/URL/Code/Color ──▶ Store text directly in database
        │
        └── Image ──▶ ImageStorageService
                          │
                          ├── Save full image to ~/Library/Application Support/Pastel/images/{uuid}.png
                          ├── Generate thumbnail (200px wide) → save to .../thumbnails/{uuid}.png
                          └── Store file path reference in database
        │
        ▼
ClipboardItem Store (SwiftData)
        │
        │ (@Query / @Published updates)
        ▼
UI Layer auto-updates (SwiftUI data binding)
```

### Paste-Back Flow

```
User Action (double-click item OR Cmd+N hotkey)
        │
        ▼
PanelContentView dispatches paste action
        │
        ▼
PasteBackService.paste(item:)
        │
        ├── 1. Write item content to NSPasteboard.general
        │       (text → setString, image → setData with .tiff/.png)
        │
        ├── 2. Dismiss sliding panel (animate out)
        │
        └── 3. After brief delay (~50ms), simulate Cmd+V via CGEvent
                │
                ▼
        Target app receives paste, inserts content
```

### Panel Toggle Flow

```
Global Hotkey Pressed (e.g., Cmd+Shift+V)
        │
        ▼
HotkeyManager receives Carbon event
        │
        ▼
PanelController.toggle()
        │
        ├── Panel hidden? → Remember frontmost app, animate panel in from screen edge
        │
        └── Panel visible? → Animate panel out, refocus previous app
```

### State Management

```
AppState (ObservableObject, shared via @EnvironmentObject)
    │
    ├── clipboardItems: [ClipboardItem]  ← SwiftData @Query or manual fetch
    ├── labels: [Label]                  ← SwiftData @Query
    ├── searchText: String               ← bound to SearchBar
    ├── selectedLabels: Set<Label>       ← bound to label chips
    ├── filteredItems: [ClipboardItem]   ← computed from search + labels
    ├── panelVisible: Bool               ← toggled by HotkeyManager
    └── settings: UserSettings           ← @AppStorage or SwiftData

Services observe/mutate AppState:
    ClipboardMonitor ──writes──▶ clipboardItems
    HotkeyManager ──toggles──▶ panelVisible
    PasteBackService ──reads──▶ clipboardItems[index]
    RetentionService ──deletes──▶ old clipboardItems
```

### Key Data Flows

1. **Copy flow:** System pasteboard changes → ClipboardMonitor detects → classifies content type → persists to SwiftData + disk (images) → UI updates via data binding
2. **Paste flow:** User selects item → PasteBackService writes to pasteboard → panel dismisses → CGEvent Cmd+V → target app pastes
3. **Search flow:** User types in search bar → searchText updates → filteredItems recomputed → UI updates
4. **Label flow:** User assigns label → SwiftData relationship update → filtered views update

---

## Scaling Considerations

These are framed for a single-user desktop app, not a server. "Scale" here means clipboard history size and performance.

| Concern | 100 items | 10K items | 100K items |
|---------|-----------|-----------|------------|
| **Database query** | Instant | Fast with index | Need pagination/lazy loading |
| **UI rendering** | All in memory | LazyVStack essential | LazyVStack + prefetching |
| **Image disk usage** | ~50 MB | ~5 GB | Retention policy critical |
| **Search** | String matching | FTS5 needed | FTS5 + debounce essential |
| **App launch** | Instant | 1-2s if loading all | Must load on-demand |

### Scaling Priorities

1. **First bottleneck: Image disk space.** Users who copy many screenshots will fill disk fast. Prevention: retention policy with automatic cleanup, configurable max storage size. Build this into Phase 1.
2. **Second bottleneck: List rendering performance.** At 1K+ items, naive List/ForEach will lag. Prevention: use `LazyVStack` inside `ScrollView`, load thumbnails asynchronously, implement virtual scrolling. This is a Phase 1 concern.
3. **Third bottleneck: Search performance.** At 5K+ items, naive string matching gets slow. Prevention: SQLite FTS5 or pre-indexed search. Can be deferred to Phase 2 if basic search works initially.

---

## Anti-Patterns

### Anti-Pattern 1: Pure SwiftUI Window Management for the Panel

**What people do:** Try to use SwiftUI's `Window` or `.popover` for the floating clipboard panel.
**Why it's wrong:** SwiftUI windows activate the app (steal focus), cannot be configured as non-activating floating panels, and lack screen-edge positioning control. The panel will steal focus from the target app, breaking paste-back entirely.
**Do this instead:** Use an `NSPanel` subclass with `.nonactivatingPanel` style mask. Host SwiftUI content inside via `NSHostingView`. This gives you AppKit window control with SwiftUI content.

### Anti-Pattern 2: Storing Full Images in the Database

**What people do:** Store image data as binary blobs in SQLite/SwiftData.
**Why it's wrong:** Database bloats rapidly (a single retina screenshot can be 5-10 MB). Queries slow down, backups become huge, and the database file becomes fragile.
**Do this instead:** Store images as files on disk in Application Support. Store only the file path (UUID-based) and a small thumbnail path in the database. Load full images lazily on demand.

### Anti-Pattern 3: Synchronous Pasteboard Reading on Main Thread

**What people do:** Read pasteboard contents (especially images) synchronously in the polling timer callback on the main thread.
**Why it's wrong:** Reading large images from the pasteboard blocks the main thread, causing UI stuttering. The 0.5s polling timer compounds this.
**Do this instead:** Detect change count on main thread (cheap), then dispatch pasteboard reading + image processing to a background queue. Update the data model back on the main thread.

### Anti-Pattern 4: Using NSEvent Global Monitor Instead of Carbon Hotkeys

**What people do:** Try `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` for global hotkeys.
**Why it's wrong:** Global event monitors only observe events -- they cannot consume them or prevent propagation. They also require Accessibility permission and are less reliable than Carbon hotkeys for this use case. Additionally, they receive ALL key events, requiring manual filtering.
**Do this instead:** Use Carbon `RegisterEventHotKey` for specific global hotkey combos. Use `NSEvent.addLocalMonitorForEvents` for key handling within your own windows (e.g., Cmd+1-9 in the panel).

### Anti-Pattern 5: Polling Too Frequently or Too Infrequently

**What people do:** Poll every 100ms (wasteful CPU) or every 2-3s (feels laggy).
**Why it's wrong:** 100ms polling uses noticeable CPU for no benefit. 2-3s polling means users copy something and it does not appear in history for seconds, which feels broken.
**Do this instead:** Poll at 0.5s intervals. This is the proven sweet spot used by established clipboard managers. It is imperceptible latency for users while being negligible on CPU.

### Anti-Pattern 6: Not Handling Self-Paste Loop

**What people do:** Forget that when the app writes to the pasteboard for paste-back, the ClipboardMonitor will detect that as a "new" clipboard change and create a duplicate entry.
**Why it's wrong:** Every paste-back creates a duplicate item in history, which pollutes the list and confuses users.
**Do this instead:** Before writing to pasteboard for paste-back, set a flag (e.g., `isPasting = true`) in ClipboardMonitor. When the next change is detected while the flag is set, skip it and reset the flag. Alternatively, compare the new change count to an expected value.

---

## Integration Points

### System Integration

| Integration | Pattern | Notes |
|-------------|---------|-------|
| **NSPasteboard** | Polling (Timer + changeCount) | Only reliable method; no notification API exists |
| **Accessibility API** | Permission request at first launch | Required for CGEvent paste; guide user to System Settings if denied |
| **CGEvent** | Post synthetic Cmd+V | Requires Accessibility permission; use `.cghidEventTap` posting location |
| **Carbon Events** | RegisterEventHotKey | For global hotkeys; not deprecated despite Carbon heritage |
| **NSStatusItem** | Menu bar presence | Use SwiftUI `MenuBarExtra` or manual NSStatusItem for more control |
| **NSPanel** | Floating overlay | Non-activating panel for the sliding history view |
| **File System** | Application Support directory | `~/Library/Application Support/Pastel/` for images and thumbnails |
| **UserDefaults / @AppStorage** | Settings persistence | For simple preferences (retention, position, paste behavior) |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| ClipboardMonitor → Data Layer | Direct write via SwiftData ModelContext | Monitor inserts new ClipboardItem on detection |
| Data Layer → Panel UI | SwiftUI @Query / @Published binding | Automatic UI update when data changes |
| HotkeyManager → PanelController | NotificationCenter or closure callback | Hotkey fires → panel toggles |
| Panel UI → PasteBackService | Direct method call with selected item | User double-clicks or presses Cmd+N |
| PasteBackService → ClipboardMonitor | Flag-based coordination | Set `isPasting` flag to prevent self-paste loop |
| RetentionService → Data Layer | Scheduled cleanup (Timer or app lifecycle) | Delete items older than retention period |
| ImageStorageService → File System | Direct file I/O | Save/load/delete in Application Support |

---

## Build Order Implications

The architecture has clear dependency chains that inform phase ordering.

### Dependency Graph

```
Phase 1 (Foundation):
    AppDelegate + MenuBarExtra setup
        └── ClipboardMonitor (NSPasteboard polling)
                └── ClipboardItem model + SwiftData persistence
                        └── Basic Panel (NSPanel + simple list view)

Phase 2 (Core UX):
    Depends on Phase 1:
        └── PasteBackService (CGEvent + Accessibility)
        └── HotkeyManager (Carbon hotkeys for panel toggle)
        └── Screen-edge animation + positioning
        └── Content type detection + rich card previews

Phase 3 (Content Types):
    Depends on Phase 2:
        └── ImageStorageService (disk storage + thumbnails)
        └── URL preview cards
        └── Code syntax highlighting
        └── Color swatch detection

Phase 4 (Organization):
    Depends on Phase 1 data model:
        └── Label system (model + UI)
        └── Search (text + label filter)
        └── Retention settings + cleanup

Phase 5 (Polish):
    Depends on all above:
        └── Settings window (all preferences)
        └── Configurable sidebar position
        └── Always-dark theme refinement
        └── Edge cases + performance
```

### Why This Order

1. **Phase 1 must come first** because everything depends on clipboard monitoring and data persistence. Without these, nothing else can be built or tested.
2. **Phase 2 is the "product" phase** -- paste-back is the core value proposition. Without it, the app is just a viewer. Hotkeys and panel animation make it actually usable.
3. **Phase 3 builds content richness** -- images and rich previews make the app delightful but depend on the basic capture/display/paste pipeline being solid.
4. **Phase 4 adds organization** -- labels and search help at scale but are not needed when the user has 50 items. These can be built independently of content types.
5. **Phase 5 is polish** -- settings, configurability, and edge cases. Build this last because it depends on knowing what settings exist (which depends on all features being built).

---

## macOS-Specific Architectural Notes

### App Lifecycle

The app should be configured as a **menu bar only** application (no dock icon). This requires setting `LSUIElement = true` in Info.plist. SwiftUI's `MenuBarExtra` supports this natively.

**Confidence:** HIGH

### Accessibility Permission Flow

The app needs Accessibility permission for paste-back (CGEvent posting). The recommended flow:

1. On first launch, check `AXIsProcessTrusted()`
2. If not trusted, show an onboarding window explaining why the permission is needed
3. Call `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` to trigger the system prompt
4. Poll `AXIsProcessTrusted()` until granted (the system dialog is non-blocking)
5. Once granted, enable paste-back features

**Confidence:** HIGH -- this is the standard pattern for apps requiring Accessibility access.

### SwiftData vs SQLite Considerations

**SwiftData** (Apple's modern persistence framework, successor to Core Data):
- Pros: Native Swift integration, works with SwiftUI `@Query`, automatic CloudKit sync if needed later, less boilerplate
- Cons: Relatively new (introduced WWDC 2023), has had bugs in early releases, limited query flexibility compared to raw SQLite, no built-in full-text search

**Raw SQLite (via GRDB or direct)**:
- Pros: Battle-tested, FTS5 for full-text search, complete query control, tiny footprint
- Cons: More boilerplate, no automatic SwiftUI integration, manual migration management

**Recommendation:** Start with SwiftData for simplicity and native SwiftUI integration. If full-text search performance becomes an issue at scale, add a parallel FTS5 index via raw SQLite for the search feature specifically. This hybrid approach gets you rapid development with SwiftData while keeping the option for SQLite FTS5 where needed.

**Confidence:** MEDIUM -- SwiftData's maturity on macOS should be verified against latest Xcode release notes. It was stable enough for production by late 2024, but edge cases with complex queries may exist.

---

## Sources

- NSPasteboard API: Apple Developer Documentation (developer.apple.com/documentation/appkit/nspasteboard) -- HIGH confidence on API surface, could not verify latest changes
- CGEvent API: Apple Developer Documentation (developer.apple.com/documentation/coregraphics/cgevent) -- HIGH confidence, stable API
- Carbon RegisterEventHotKey: Apple Developer Documentation -- HIGH confidence, still functional despite Carbon heritage
- NSPanel: Apple Developer Documentation (developer.apple.com/documentation/appkit/nspanel) -- HIGH confidence
- SwiftData: Apple Developer Documentation (developer.apple.com/documentation/swiftdata) -- MEDIUM confidence on current maturity
- Open-source patterns: Maccy (github.com/p0deje/Maccy) and Clipy (github.com/Clipy/Clipy) architectures informed the polling, paste-back, and hotkey patterns -- MEDIUM confidence (based on training data, not live verification)
- SwiftUI MenuBarExtra: Apple Developer Documentation -- HIGH confidence on basic capability, MEDIUM on advanced features

---
*Architecture research for: macOS clipboard manager (Pastel)*
*Researched: 2026-02-05*
