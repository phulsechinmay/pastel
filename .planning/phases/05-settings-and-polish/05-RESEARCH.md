# Phase 5: Settings and Polish - Research

**Researched:** 2026-02-06
**Domain:** macOS settings window, launch-at-login, panel position refactoring, label management UI
**Confidence:** HIGH

## Summary

Phase 5 adds a settings window, launch-at-login, configurable panel position (all 4 edges), hotkey customization, history retention, and label management. The codebase already has both key dependencies wired up: `KeyboardShortcuts` (v2.4.0) for hotkey recording and `LaunchAtLogin-Modern` (v1.1.0) for login item management -- both declared in `project.yml` and ready to import.

The primary technical challenge is refactoring `PanelController` to support 4 screen edges instead of just the right edge. Currently, `show()` and `hide()` have hard-coded right-edge frame calculations and animation directions. This must be generalized with an edge enum that drives frame computation and slide direction. The settings window itself follows the existing NSWindow pattern already proven in the `AccessibilityPromptView` onboarding window -- a standalone `NSWindow` hosting a SwiftUI view, with `.darkAqua` appearance.

Settings persistence should use `@AppStorage` for all preferences (panel position, history retention period). This is the idiomatic SwiftUI approach for simple user preferences, provides automatic UI reactivity, and is what `LaunchAtLogin` already uses internally. The history retention auto-purge should run at app launch and on a periodic timer (e.g., hourly) to clean expired items.

**Primary recommendation:** Use standalone NSWindow (not SwiftUI Settings scene) for the settings window, `@AppStorage` for all preferences, and refactor PanelController with an edge enum driving frame calculations.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| LaunchAtLogin (sindresorhus/LaunchAtLogin-Modern) | 1.1.0 | Launch at login toggle | Already in project.yml; wraps SMAppService with SwiftUI Toggle; 3 lines of code |
| KeyboardShortcuts (sindresorhus/KeyboardShortcuts) | 2.4.0 | Hotkey recorder view | Already in project.yml; provides `KeyboardShortcuts.Recorder` SwiftUI view with automatic UserDefaults persistence and conflict detection |
| ServiceManagement (Apple) | System | Underlying login item API | Used internally by LaunchAtLogin; SMAppService.mainApp is the modern API (macOS 13+) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| @AppStorage (SwiftUI) | System | Settings persistence | All user preferences (panel edge, retention period) |
| NSWindow (AppKit) | System | Settings window host | Standalone window for menu-bar-only app |
| NSAnimationContext (AppKit) | System | Panel slide animation | Already used; extend for all 4 edge directions |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Standalone NSWindow | SwiftUI Settings scene | Settings scene is unreliable in menu-bar-only apps (requires hidden windows, activation policy juggling, timing delays). NSWindow approach already proven in this codebase (AccessibilityPromptView). |
| Standalone NSWindow | SettingsAccess library (orchetect) | Adds dependency just to work around SwiftUI Settings scene bugs. Not worth it when NSWindow works perfectly. |
| @AppStorage | UserDefaults directly | @AppStorage gives automatic SwiftUI view updates for free. No reason to use raw UserDefaults for simple preferences. |
| LaunchAtLogin-Modern | Manual SMAppService calls | LaunchAtLogin wraps the boilerplate perfectly. Already a dependency. |

**Installation:**
```bash
# Already in project.yml -- no new dependencies needed
# KeyboardShortcuts: 2.4.0
# LaunchAtLogin: 1.1.0 (LaunchAtLogin-Modern)
```

## Architecture Patterns

### Recommended File Structure
```
Pastel/Views/Settings/
    SettingsWindowController.swift  # NSWindow lifecycle, show/hide, singleton
    SettingsView.swift              # Root view with custom tab bar (keyogre pattern)
    GeneralSettingsView.swift       # Launch at login, hotkey, position, retention
    LabelSettingsView.swift         # Label CRUD list
    ScreenEdgePicker.swift          # Visual screen diagram with clickable edges

Pastel/Models/
    PanelEdge.swift                 # Enum: left, right, top, bottom + frame math

Pastel/Services/
    RetentionService.swift          # History auto-purge based on retention setting
```

### Pattern 1: Standalone NSWindow for Settings (Proven in Codebase)
**What:** Create an NSWindow programmatically, host SwiftUI content via NSHostingView, manage show/hide via a controller.
**When to use:** Settings window in a menu-bar-only app.
**Example:**
```swift
// Source: Existing pattern from AppState.checkAccessibilityOnLaunch()
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func showSettings(modelContainer: ModelContainer) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .preferredColorScheme(.dark)
            .modelContainer(modelContainer)

        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.contentView = hostingView
        window.title = "Pastel Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
```

### Pattern 2: PanelEdge Enum Driving Frame Calculations
**What:** Extract panel position logic into an enum that computes on-screen and off-screen frames for any edge.
**When to use:** Generalizing the current right-edge-only PanelController.
**Example:**
```swift
// Source: Derived from existing PanelController.show() pattern
enum PanelEdge: String, CaseIterable {
    case left, right, top, bottom

    var isVertical: Bool { self == .left || self == .right }

    func panelSize(screenFrame: NSRect) -> NSSize {
        if isVertical {
            return NSSize(width: 320, height: screenFrame.height)
        } else {
            return NSSize(width: screenFrame.width, height: 300)
        }
    }

    func onScreenFrame(screenFrame: NSRect) -> NSRect {
        let size = panelSize(screenFrame: screenFrame)
        switch self {
        case .right:
            return NSRect(x: screenFrame.maxX - size.width,
                          y: screenFrame.origin.y,
                          width: size.width, height: size.height)
        case .left:
            return NSRect(x: screenFrame.origin.x,
                          y: screenFrame.origin.y,
                          width: size.width, height: size.height)
        case .top:
            return NSRect(x: screenFrame.origin.x,
                          y: screenFrame.maxY - size.height,
                          width: size.width, height: size.height)
        case .bottom:
            return NSRect(x: screenFrame.origin.x,
                          y: screenFrame.origin.y,
                          width: size.width, height: size.height)
        }
    }

    func offScreenFrame(screenFrame: NSRect) -> NSRect {
        let size = panelSize(screenFrame: screenFrame)
        switch self {
        case .right:
            return NSRect(x: screenFrame.maxX,
                          y: screenFrame.origin.y,
                          width: size.width, height: size.height)
        case .left:
            return NSRect(x: screenFrame.origin.x - size.width,
                          y: screenFrame.origin.y,
                          width: size.width, height: size.height)
        case .top:
            return NSRect(x: screenFrame.origin.x,
                          y: screenFrame.maxY,
                          width: size.width, height: size.height)
        case .bottom:
            return NSRect(x: screenFrame.origin.x,
                          y: screenFrame.origin.y - size.height,
                          width: size.width, height: size.height)
        }
    }
}
```

### Pattern 3: Custom Tab Bar (keyogre Reference)
**What:** Horizontal centered tab bar with icon + text buttons, glassmorphism background, accent color selection.
**When to use:** Settings window tab navigation.
**Example:**
```swift
// Source: keyogre/KeyOgre/Views/SettingsView.swift (reference implementation)
enum SettingsTab: String, CaseIterable {
    case general = "General"
    case labels = "Labels"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .labels: return "tag"
        }
    }
}

struct TabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 20, height: 20)
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? Color.accentColor : Color.white.opacity(0.6))
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
```

### Pattern 4: @AppStorage for Settings Persistence
**What:** Use @AppStorage property wrappers for all user preferences.
**When to use:** Simple key-value settings that need to drive UI reactivity.
**Example:**
```swift
// Source: Apple SwiftUI documentation
// Define keys as constants to avoid typos
enum SettingsKeys {
    static let panelEdge = "panelEdge"
    static let historyRetention = "historyRetention"
}

// In any SwiftUI view:
@AppStorage(SettingsKeys.panelEdge) private var panelEdge: String = PanelEdge.right.rawValue
@AppStorage(SettingsKeys.historyRetention) private var retentionDays: Int = 90 // 3 months default

// In non-SwiftUI code (PanelController):
let edge = PanelEdge(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.panelEdge) ?? "right") ?? .right
```

### Pattern 5: LaunchAtLogin-Modern Toggle
**What:** Drop-in SwiftUI toggle for login item registration.
**When to use:** Launch at login setting.
**Example:**
```swift
// Source: github.com/sindresorhus/LaunchAtLogin-Modern README
import LaunchAtLogin

// In GeneralSettingsView:
LaunchAtLogin.Toggle("Launch at login")
    .toggleStyle(.switch)
```

### Pattern 6: KeyboardShortcuts.Recorder
**What:** SwiftUI view for recording/customizing a keyboard shortcut.
**When to use:** Hotkey customization in settings.
**Example:**
```swift
// Source: github.com/sindresorhus/KeyboardShortcuts README
import KeyboardShortcuts

// Existing name already defined in AppState.swift:
// extension KeyboardShortcuts.Name {
//     static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.command, .shift]))
// }

// In GeneralSettingsView:
KeyboardShortcuts.Recorder("Panel Toggle Hotkey:", name: .togglePanel)
```

### Anti-Patterns to Avoid
- **Using SwiftUI Settings scene in menu-bar-only app:** Unreliable -- requires hidden windows, activation policy juggling, timing delays. Use standalone NSWindow.
- **Storing panel edge in SwiftData:** Overkill. @AppStorage (UserDefaults) is the right tool for simple preferences. SwiftData is for structured data with relationships.
- **Recreating the panel on every edge change:** Expensive. Instead, re-calculate the frame and animate to the new position. Only recreate if the panel's content layout needs to change (vertical vs horizontal).
- **Not reading SMAppService.mainApp.status:** LaunchAtLogin handles this, but if you were doing it manually, never cache the login item state locally -- always read from SMAppService because users can disable login items from System Settings.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Launch at login | Manual SMAppService register/unregister + status checking + UI binding | `LaunchAtLogin.Toggle()` | Already a dependency; handles all edge cases (user disabling from System Settings, status polling, SwiftUI binding) in one line |
| Hotkey recording | Custom key-capture field with modifier detection + conflict checking | `KeyboardShortcuts.Recorder(name:)` | Already a dependency; handles recording UI, UserDefaults persistence, system shortcut conflict detection, and menu item conflict warnings |
| Settings persistence | SwiftData model for preferences, or manual UserDefaults + NotificationCenter | `@AppStorage` property wrapper | Built into SwiftUI; automatic view updates, type-safe, no boilerplate |
| Settings window opening from menu bar | SwiftUI Settings scene + SettingsAccess library + activation policy hacks | Standalone NSWindow (existing pattern) | Already proven in this codebase (AccessibilityPromptView). Zero new dependencies. |

**Key insight:** Both third-party dependencies (LaunchAtLogin-Modern, KeyboardShortcuts) are already declared in `project.yml` and provide SwiftUI-native views that slot directly into the settings form. No new dependencies needed for Phase 5.

## Common Pitfalls

### Pitfall 1: Panel Content Layout Not Adapting to Horizontal Orientation
**What goes wrong:** When panel moves to top/bottom edge, cards still render in a vertical LazyVStack, wasting the horizontal space and creating a poor layout.
**Why it happens:** The current `FilteredCardListView` uses `LazyVStack` unconditionally.
**How to avoid:** Pass the panel edge to the SwiftUI content view. When the edge is `.top` or `.bottom`, switch from `LazyVStack` to `LazyHStack` inside a horizontal `ScrollView(.horizontal)`. Cards in horizontal mode should be fixed-width (e.g., 260pt) instead of full-width.
**Warning signs:** Cards appear as thin horizontal slivers in top/bottom panel position.

### Pitfall 2: Panel Not Dismissing Before Edge Change
**What goes wrong:** If the user changes panel position while the panel is visible, the old panel stays on screen at the old position while the new position takes effect.
**Why it happens:** Position change updates the stored preference but the visible panel frame is not recalculated.
**How to avoid:** When the panel edge setting changes, if the panel is visible, hide it first (animate out from old edge), then destroy the panel content view (layout may differ for vertical vs horizontal), then show at the new edge on next toggle.

### Pitfall 3: Settings Window Appearing Behind Other Windows
**What goes wrong:** `NSApp.activate(ignoringOtherApps: true)` is not called, so the settings window opens behind the frontmost app.
**Why it happens:** Menu-bar-only apps have `.accessory` activation policy. Windows created programmatically do not automatically come to front.
**How to avoid:** Always call `NSApp.activate(ignoringOtherApps: true)` after `makeKeyAndOrderFront`. This is already done correctly in the existing `checkAccessibilityOnLaunch()` pattern.

### Pitfall 4: History Retention Purge Deleting Images Without Disk Cleanup
**What goes wrong:** Old ClipboardItems are deleted from SwiftData but their image files remain on disk, causing disk space leaks.
**Why it happens:** Batch delete via SwiftData predicate does not trigger custom cleanup logic.
**How to avoid:** Fetch all items to be purged first (to collect imagePath/thumbnailPath), delete their disk files via `ImageStorageService.shared.deleteImage()`, then delete from SwiftData. This is the same pattern used in `AppState.clearAllHistory()`.

### Pitfall 5: Label Deletion Cascade
**What goes wrong:** Deleting a label might seem to require finding and updating all items that reference it.
**Why it happens:** Misunderstanding SwiftData relationship delete rules.
**How to avoid:** The `Label` model already has `@Relationship(deleteRule: .nullify, inverse: \ClipboardItem.label)`. Deleting a label automatically sets `item.label = nil` for all associated items. No manual cascade needed.

### Pitfall 6: @AppStorage String for Enum
**What goes wrong:** Using `@AppStorage` with a custom enum type fails because @AppStorage only supports primitive types (String, Int, Bool, Double, Data, URL).
**Why it happens:** Swift enums are not directly storable in @AppStorage.
**How to avoid:** Store the enum's `rawValue` (String) in @AppStorage, then convert on read. Example: `@AppStorage("panelEdge") var panelEdgeRaw: String = "right"` with a computed property `var panelEdge: PanelEdge { PanelEdge(rawValue: panelEdgeRaw) ?? .right }`.

## Code Examples

Verified patterns from official sources and existing codebase:

### Settings Window Access Points

Two access points need to be wired:

```swift
// 1. Gear icon in panel header (PanelContentView.swift)
HStack {
    Text("Pastel")
        .font(.headline)
        .foregroundStyle(.secondary)
    Spacer()
    Button {
        SettingsWindowController.shared.showSettings(modelContainer: modelContainer)
    } label: {
        Image(systemName: "gearshape")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
}

// 2. Right-click menu bar item (StatusPopoverView.swift or PastelApp.swift)
// Add "Settings..." button in the StatusPopoverView
Button(action: {
    SettingsWindowController.shared.showSettings(modelContainer: modelContainer)
}) {
    HStack {
        Image(systemName: "gearshape")
        Text("Settings...")
        Spacer()
    }
}
.buttonStyle(.plain)
```

### History Retention Auto-Purge

```swift
// Source: Derived from existing ExpirationService + clearAllHistory patterns
@MainActor
final class RetentionService {
    private let modelContext: ModelContext
    private var timer: Timer?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func startPeriodicPurge() {
        // Run immediately on start
        purgeExpiredItems()
        // Then hourly
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.purgeExpiredItems() }
        }
    }

    func purgeExpiredItems() {
        let retentionDays = UserDefaults.standard.integer(forKey: SettingsKeys.historyRetention)
        guard retentionDays > 0 else { return } // 0 = Forever

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now)!

        do {
            let descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate<ClipboardItem> { item in
                    item.timestamp < cutoffDate
                }
            )
            let expiredItems = try modelContext.fetch(descriptor)

            for item in expiredItems {
                ImageStorageService.shared.deleteImage(
                    imagePath: item.imagePath,
                    thumbnailPath: item.thumbnailPath
                )
            }

            try modelContext.delete(model: ClipboardItem.self, where: #Predicate<ClipboardItem> { item in
                item.timestamp < cutoffDate
            })
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }
}
```

### Visual Screen Edge Picker

```swift
// Source: Custom component for panel position selection
struct ScreenEdgePicker: View {
    @Binding var selectedEdge: String

    var body: some View {
        ZStack {
            // Screen rectangle
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.05))
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 160, height: 100)

            // Clickable edges (overlaid on each side)
            VStack(spacing: 0) {
                edgeBar(.top).frame(width: 120, height: 12)
                Spacer()
                edgeBar(.bottom).frame(width: 120, height: 12)
            }
            .frame(width: 160, height: 100)

            HStack(spacing: 0) {
                edgeBar(.left).frame(width: 12, height: 70)
                Spacer()
                edgeBar(.right).frame(width: 12, height: 70)
            }
            .frame(width: 160, height: 100)
        }
    }

    private func edgeBar(_ edge: PanelEdge) -> some View {
        let isSelected = selectedEdge == edge.rawValue
        return RoundedRectangle(cornerRadius: 3)
            .fill(isSelected ? Color.accentColor : Color.white.opacity(0.15))
            .onTapGesture { selectedEdge = edge.rawValue }
    }
}
```

### Horizontal Card Layout for Top/Bottom Panel

```swift
// Source: Adaptation of existing FilteredCardListView for horizontal orientation
// When panel edge is top or bottom, use horizontal scrolling:
ScrollView(.horizontal, showsIndicators: false) {
    LazyHStack(spacing: 8) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            ClipboardCardView(item: item, isSelected: selectedIndex == index)
                .frame(width: 260) // Fixed width cards in horizontal mode
                .id(index)
                .onTapGesture(count: 2) { onPaste(item) }
                .onTapGesture(count: 1) { selectedIndex = index }
        }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
}
```

### Inline Label Editing Row

```swift
// Source: Standard SwiftUI inline editing pattern
struct LabelRow: View {
    @Bindable var label: Label
    @State private var isEditing = false
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Color dot (tap to recolor)
            Menu {
                ForEach(LabelColor.allCases, id: \.self) { color in
                    Button {
                        label.colorName = color.rawValue
                    } label: {
                        HStack {
                            Circle().fill(color.color).frame(width: 10, height: 10)
                            Text(color.rawValue.capitalized)
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
                    .frame(width: 14, height: 14)
            }

            // Name (click to edit)
            if isEditing {
                TextField("Label name", text: $label.name)
                    .textFieldStyle(.plain)
                    .onSubmit { isEditing = false }
            } else {
                Text(label.name)
                    .onTapGesture { isEditing = true }
            }

            Spacer()

            // Delete button
            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SMLoginItemSetEnabled | SMAppService.mainApp (via LaunchAtLogin-Modern) | macOS 13 (2022) | Old API deprecated; LaunchAtLogin-Modern wraps the new API |
| NSApp.sendAction(#selector(showSettingsWindow:)) | @Environment(\.openSettings) / SettingsLink | macOS 14 (2023) | Old approach broken in Sonoma; but both new approaches unreliable in menu-bar-only apps. Use standalone NSWindow. |
| Manual hotkey recording UI | KeyboardShortcuts.Recorder | Stable since 2020 | No need to build custom key-capture views |
| @ObservedObject + Combine for settings | @AppStorage property wrapper | SwiftUI 2.0 (2020) | Direct UserDefaults binding with automatic view updates |

**Deprecated/outdated:**
- `NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)` -- broken in macOS 14 Sonoma. Do not use.
- `SMLoginItemSetEnabled` -- deprecated in macOS 13. Use SMAppService via LaunchAtLogin-Modern.
- Custom hotkey recording views -- unnecessary when KeyboardShortcuts.Recorder exists.

## Open Questions

Things that couldn't be fully resolved:

1. **Keyboard navigation in horizontal mode**
   - What we know: Current `.onKeyPress(.upArrow)` / `.onKeyPress(.downArrow)` maps to vertical list navigation. In horizontal mode, left/right arrows would be more natural.
   - What's unclear: Whether to swap arrow key directions based on panel orientation, or always use up/down.
   - Recommendation: Swap. When panel is horizontal (top/bottom edge), map left/right arrows to item navigation. When vertical (left/right edge), keep up/down. This is Claude's discretion per CONTEXT.md.

2. **Panel content view recreation on edge change**
   - What we know: Vertical panel uses LazyVStack, horizontal should use LazyHStack. The SwiftUI content tree differs.
   - What's unclear: Whether to use a single adaptive view with conditionals, or destroy and recreate the panel entirely when switching between vertical/horizontal.
   - Recommendation: Use a single adaptive view with conditional layout (if/else on `panelEdge.isVertical`). Only destroy/recreate if SwiftUI layout bugs appear with conditional stacks.

3. **History retention dropdown values**
   - What we know: CONTEXT.md specifies "1 week, 1 month, 3 months, 1 year, Forever".
   - What's unclear: Exact day values for "1 month" and "3 months" (28 vs 30 vs 31, 90 vs 91).
   - Recommendation: Use 7, 30, 90, 365, 0 (where 0 = Forever). These are standard approximate values used by every history retention feature.

## Sources

### Primary (HIGH confidence)
- `project.yml` in codebase -- verified LaunchAtLogin-Modern v1.1.0 and KeyboardShortcuts v2.4.0 are already dependencies
- `AppState.swift`, `PanelController.swift`, `SlidingPanel.swift` in codebase -- verified current architecture and patterns
- `keyogre/KeyOgre/Views/SettingsView.swift` -- reference tab bar implementation read directly
- [sindresorhus/LaunchAtLogin-Modern GitHub](https://github.com/sindresorhus/LaunchAtLogin-Modern) -- API: `LaunchAtLogin.Toggle()`, `LaunchAtLogin.isEnabled`
- [sindresorhus/KeyboardShortcuts GitHub](https://github.com/sindresorhus/KeyboardShortcuts) -- API: `KeyboardShortcuts.Recorder(name:)`, automatic UserDefaults persistence

### Secondary (MEDIUM confidence)
- [Nil Coalescing: Launch at Login](https://nilcoalescing.com/blog/LaunchAtLoginSetting/) -- SMAppService pattern verified: `SMAppService.mainApp.register()`, `.status == .enabled`
- [Peter Steinberger: Settings from Menu Bar](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) -- Confirmed SwiftUI Settings scene is unreliable in menu-bar-only apps (2025)
- [orchetect/SettingsAccess GitHub](https://github.com/orchetect/SettingsAccess) -- Workaround library for Settings scene; validates our decision to use standalone NSWindow instead
- [Hacking with Swift Forums](https://www.hackingwithswift.com/forums/macos/how-to-open-settings-from-menu-bar-app-and-show-app-icon-in-dock/26267) -- NSApp.activate pattern for bringing windows to front

### Tertiary (LOW confidence)
- WebSearch results on horizontal panel layouts -- general SwiftUI patterns, not clipboard-manager specific

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- dependencies already in project, APIs verified via official GitHub READMEs
- Architecture: HIGH -- extends proven patterns already in codebase (NSWindow hosting, PanelController frame math, SwiftData CRUD)
- Pitfalls: HIGH -- derived from direct codebase analysis (existing delete/purge patterns, @Relationship delete rules, @AppStorage limitations)
- Panel position refactoring: MEDIUM -- frame math is straightforward but horizontal card layout adaptation is untested
- Settings window: HIGH -- follows exact same pattern as existing AccessibilityPromptView NSWindow

**Research date:** 2026-02-06
**Valid until:** 2026-03-06 (30 days -- stable domain, no fast-moving dependencies)
