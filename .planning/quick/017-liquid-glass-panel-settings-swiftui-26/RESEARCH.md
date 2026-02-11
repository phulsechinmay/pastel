# 017 — Liquid Glass Adoption for Pastel (macOS 26 / SwiftUI 26)

## Research Summary

This document covers all liquid glass APIs relevant to Pastel's adoption on macOS 26 (Tahoe),
with specific analysis of our NSPanel-based sliding panel, settings window, and menu bar popover.

---

## 1. Liquid Glass API Reference

### 1.1 Core Modifier: `glassEffect(_:in:)`

The primary way to apply liquid glass to custom views.

```swift
func glassEffect<S: Shape>(
    _ glass: Glass = .regular,
    in shape: S = DefaultGlassEffectShape,   // capsule by default
    isEnabled: Bool = true
) -> some View
```

**Availability:** macOS 26.0+, iOS 26.0+, iPadOS 26.0+, watchOS 26.0+, tvOS 26.0+

**Behavior:**
- Applies a translucent, refractive "lensing" material behind the content
- Text automatically receives vibrant color treatment for legibility
- Default shape is a capsule; pass any `Shape` to customize

**Example:**
```swift
Text("Hello")
    .padding()
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
```

### 1.2 Glass Struct — Variants

The `Glass` struct defines the material configuration:

| Variant      | Purpose                                   | Use Case                              |
|-------------|-------------------------------------------|---------------------------------------|
| `.regular`  | Standard translucent glass                | Toolbars, buttons, navigation         |
| `.clear`    | High transparency, more see-through       | Media-rich backgrounds only           |
| `.identity` | No visual effect (passthrough)            | Conditional disabling                 |

**Modifiers on Glass:**
```swift
Glass.regular.tint(.blue)           // Semantic color tint
Glass.regular.tint(.purple.opacity(0.6))
Glass.regular.interactive()         // iOS only — scales, bounces, shimmers on touch
```

**Tinting rules:** Tinting should only convey semantic meaning (primary action, destructive, etc.),
never decorative. Apply sparingly.

### 1.3 GlassEffectContainer

Groups multiple glass elements so they share a sampling region and can morph into each other.

```swift
GlassEffectContainer(spacing: 30) {
    // Multiple views with .glassEffect()
}
```

**Critical rule:** Glass cannot sample other glass. Nearby glass elements in *different*
containers produce inconsistent visuals. Always wrap co-located glass elements in one container.

The `spacing` parameter controls how close elements must be before they visually blend and
morph during transitions.

### 1.4 glassEffectID(_:in:) — Morphing Transitions

Enables smooth shape-morphing animations between glass views within the same container.

```swift
@Namespace private var namespace

GlassEffectContainer {
    if showExpanded {
        ExpandedView()
            .glassEffect()
            .glassEffectID("toggle", in: namespace)
    } else {
        CollapsedView()
            .glassEffect()
            .glassEffectID("toggle", in: namespace)
    }
}

// Trigger with:
withAnimation(.bouncy) { showExpanded.toggle() }
```

**Requirements:**
1. Both views must be in the same `GlassEffectContainer`
2. Both must have `.glassEffect()` applied
3. Both must share the same `glassEffectID` string and `@Namespace`
4. State change must be wrapped in `withAnimation`

### 1.5 Button Styles

```swift
Button("Secondary") { }
    .buttonStyle(.glass)            // Translucent, for secondary actions

Button("Primary") { }
    .buttonStyle(.glassProminent)   // Opaque glass, for primary actions
```

Both available on macOS 26.0+. Can be combined with `.tint()` for semantic color.

**Gotcha on macOS:** With certain tints, `.glassProminent` doesn't show the mouse-down
effect very distinctly (reported by community).

### 1.6 BackgroundExtensionEffect

Mirrors and blurs view content beyond its bounds into safe area regions.

```swift
Image("photo")
    .resizable()
    .scaledToFill()
    .backgroundExtensionEffect()
```

Used in `NavigationSplitView` to extend content behind floating sidebars/inspectors.
Unlikely to be directly relevant to Pastel's panel, but worth knowing about.

### 1.7 Toolbar Glass APIs

Toolbars automatically receive glass treatment when compiled with Xcode 26:

- **ToolbarSpacer** — new type to split toolbar items into groups:
  ```swift
  ToolbarSpacer(.flexible)  // Adaptable gap
  ToolbarSpacer(.fixed)     // Consistent gap
  ```
- **sharedBackgroundVisibility(_:)** — controls glass background visibility on toolbar items
- **toolbarBackgroundVisibility(.hidden, for: .windowToolbar)** — hides toolbar glass background
- **Automatic grouping:** Multiple toolbar buttons on macOS are grouped onto a single glass
  surface. Override with `NSToolbarItemGroup` or spacers.

### 1.8 containerBackground for Windows

```swift
WindowGroup {
    ContentView()
        .containerBackground(.thinMaterial, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
}
```

Replaces the window's opaque background with a translucent material. Can be combined with
hidden toolbar background for a unified glass look.

### 1.9 TabView Styles on macOS 26

Two styles relevant for settings windows:

- **Default:** Groups tabs in the toolbar, hides window title
- **sidebarAdaptable:** Tabs in a sidebar overlay, shows window title, supports
  `navigationSubtitle`

```swift
TabView {
    Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
    Tab("Labels", systemImage: "tag") { LabelSettingsView() }
}
.tabViewStyle(.sidebarAdaptable)
```

---

## 2. NSPanel + Liquid Glass: Critical Analysis

### 2.1 Current Pastel Panel Setup

**SlidingPanel.swift** — `NSPanel` subclass:
- Style mask: `[.nonactivatingPanel, .fullSizeContentView, .borderless]`
- `isFloatingPanel = true`, `level = .statusBar`
- `isOpaque = false`, `backgroundColor = .clear`
- `canBecomeKey = true`, `canBecomeMain = false`

**PanelController.swift** — hosts SwiftUI via `NSHostingView`:
- Creates `NSHostingView(rootView: PanelContentView())`
- Panel background is `.clear`
- Glass effect applied in SwiftUI layer via `GlassEffectModifier`

**PanelContentView.swift** — already has availability-gated glass:
```swift
private struct GlassEffectModifier: ViewModifier {
    let shape: UnevenRoundedRectangle
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(shape.fill(.ultraThinMaterial))
                .clipShape(shape)
        }
    }
}
```

### 2.2 Known Issue: Glass Degrades in Non-Activating Panel

**Problem:** When using `.glassEffect()` inside an `NSHostingView` within a non-activating
`NSPanel`, the glass effect **degrades to a simple blur when the owning app is not focused**.
This is reported by multiple developers on Hacking with Swift forums and Apple Developer Forums.

Since Pastel uses `.nonactivatingPanel` and never activates (the frontmost app retains focus),
the glass will appear as a basic blur rather than the full lensing + specular highlight effect
whenever the user invokes the panel while another app is frontmost — which is *always* in
normal usage.

**Root Cause:** macOS treats glass rendering differently for windows belonging to non-active
applications. The full liquid glass pipeline (lensing, specular highlights, motion response)
appears to require the window's owning application to be active.

### 2.3 Workarounds for NSPanel Glass

**Option A: Accept Degraded Glass (Recommended Start)**
The degraded blur is still visually appealing and consistent with the translucent material
aesthetic. It effectively becomes a nicer version of the current `.ultraThinMaterial` fallback.
This is the lowest-risk path.

**Option B: NSVisualEffectView with `.active` State**
For the pre-glass-era blur, `NSVisualEffectView` with `state = .active` forces the vibrancy
effect to render as if the window is active, regardless of app activation state.

```swift
let visualEffect = NSVisualEffectView()
visualEffect.blendingMode = .behindWindow
visualEffect.state = .active          // Forces active appearance
visualEffect.material = .hudWindow    // or .popover, .menu, etc.
```

This does NOT give you liquid glass lensing, but it ensures the translucent material looks
consistent. Could be used as a fallback layer underneath the SwiftUI content.

**Option C: Hybrid Approach**
- Use `.glassEffect()` in SwiftUI for the visual treatment
- Add an `NSVisualEffectView` as a background view in the `NSPanel` content view hierarchy
  with `state = .active` to ensure the behind-window blur is always active
- The glass lensing on top may still degrade, but the base blur will look correct

**Option D: File a Radar / Feedback**
This may be an intentional design limitation or an oversight. Filing feedback with Apple
requesting that `.glassEffect()` respects `NSVisualEffectView.State.active` semantics for
non-activating panels would be worthwhile.

### 2.4 What Needs to Change for the Panel

The current implementation is already well-structured. Key changes:

1. **`SlidingPanel.swift`** — No changes strictly needed. The transparent background + clear
   color setup is correct for hosting SwiftUI glass content. However, consider adding an
   `NSVisualEffectView` layer for consistent behind-window blur:

   ```swift
   // In SlidingPanel.init(), after setting backgroundColor:
   if #available(macOS 26, *) {
       // Let SwiftUI glassEffect handle the visual
   } else {
       let visualEffect = NSVisualEffectView()
       visualEffect.blendingMode = .behindWindow
       visualEffect.state = .active
       visualEffect.material = .hudWindow
       self.contentView = visualEffect
   }
   ```

2. **`PanelContentView.swift`** — The existing `GlassEffectModifier` is solid. Consider:
   - Adding `.tint()` for the panel's accent color if desired
   - Wrapping the header controls in a `GlassEffectContainer` if they get individual glass
     treatments (e.g., glass buttons in the header)
   - The `UnevenRoundedRectangle` shape for edge-aware corners is correct and works with
     `.glassEffect(in:)`

3. **`PanelController.swift`** — The `NSHostingView` setup is correct. No changes needed
   for glass adoption. The comment about `.glassEffect` is already present and accurate.

### 2.5 Dark Mode and Glass

Pastel forces dark mode with `.preferredColorScheme(.dark)` and
`.environment(\.colorScheme, .dark)`. On macOS 26:

- Liquid glass automatically adapts to the color scheme
- Dark mode glass has darker tinting and different specular behavior
- The forced dark scheme should work fine with glass — the material will render in dark mode

The `NSAppearance(named: .darkAqua)` set on the settings window also affects how glass renders
in that context.

---

## 3. Settings Window Changes

### 3.1 Current Setup

**SettingsWindowController.swift** uses a standard `NSWindow`:
- Style mask: `[.titled, .closable, .resizable]`
- `NSHostingView` with `SettingsView`
- `appearance = NSAppearance(named: .darkAqua)`

**SettingsView.swift** uses a custom tab bar with manual icon+text buttons and
`.background(.ultraThinMaterial)` on the tab bar.

### 3.2 Recommended Changes for macOS 26

**Option A: Adopt SwiftUI TabView (Recommended)**

Replace the custom tab bar with SwiftUI's `TabView` which automatically gets liquid glass
treatment on macOS 26:

```swift
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Labels", systemImage: "tag") {
                LabelSettingsView()
            }
            Tab("Privacy", systemImage: "hand.raised") {
                PrivacySettingsView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                HistoryBrowserView()
            }
        }
    }
}
```

This gives automatic glass toolbar tabs on macOS 26 with no additional code.

**Option B: Keep Custom Tab Bar with Glass Buttons**

If the custom tab bar layout is preferred, update the tab buttons to use glass styles:

```swift
ForEach(SettingsTab.allCases, id: \.self) { tab in
    Button { selectedTab = tab } label: {
        VStack(spacing: 4) {
            Image(systemName: tab.iconName).font(.system(size: 16))
            Text(tab.displayName).font(.system(size: 12))
        }
        .frame(width: 80, height: 52)
    }
    .buttonStyle(selectedTab == tab ? .glassProminent : .glass)
}
```

And wrap in a `GlassEffectContainer` for morphing:
```swift
GlassEffectContainer {
    HStack(spacing: 16) {
        ForEach(SettingsTab.allCases, id: \.self) { tab in
            // ... glass buttons
        }
    }
}
```

**Option C: Window-Level Glass Background**

If using SwiftUI `Settings` scene (or `WindowGroup` for settings), apply:
```swift
.containerBackground(.thinMaterial, for: .window)
.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
```

Since we use `NSWindow` directly via `SettingsWindowController`, this would require
migrating to a SwiftUI `Window` scene, which may not be desired given the current
NSWindow-based singleton pattern.

### 3.3 Settings Window — NSWindow Considerations

The settings window uses a standard `NSWindow` with a title bar. On macOS 26:
- The title bar and window chrome automatically adopt liquid glass styling when compiled
  with Xcode 26
- No code changes needed for the basic glass window frame
- The `.ultraThinMaterial` on the tab bar background will continue to work but may look
  different layered under the new glass title bar

### 3.4 History Browser Tab

`HistoryBrowserView.swift` also uses `.background(.ultraThinMaterial)`. On macOS 26, this
material still works but may look slightly different under glass. Consider whether this
background is still needed or if it should be removed in favor of the window's own glass
treatment.

---

## 4. Menu Bar Popover

### 4.1 Current Setup

`PastelApp.swift` uses `MenuBarExtra` with `.menuBarExtraStyle(.window)`, hosting
`StatusPopoverView` with standard buttons and toggles.

### 4.2 macOS 26 Behavior

- `MenuBarExtra` with `.window` style automatically receives liquid glass popover styling
  when compiled with Xcode 26
- No code changes needed for basic glass adoption
- The popover's background material is managed by the system
- Buttons inside could optionally adopt `.buttonStyle(.glass)` for consistency

### 4.3 Recommended Changes

```swift
// In StatusPopoverView, optionally update button styles:
Button(action: { appState.togglePanel() }) {
    HStack(spacing: 6) {
        Image(systemName: "clipboard.fill")
        Text("Show Panel")
        Spacer()
        if let desc = panelShortcutDescription {
            Text(desc).font(.caption).foregroundStyle(.secondary)
        }
    }
}
.buttonStyle(.glass)  // Optional: glass button style
```

Low priority — the menu bar popover will look good automatically.

---

## 5. Availability Checks and Fallback Patterns

### 5.1 Recommended Pattern

The existing `GlassEffectModifier` pattern is correct. Here is the generalized version:

```swift
extension View {
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
                .clipShape(shape)
        }
    }
}
```

### 5.2 Fallback with Faux-Glass Aesthetic

For a closer approximation of glass on pre-macOS 26:

```swift
extension Shape {
    @ViewBuilder
    func fauxGlass() -> some View {
        self.fill(.ultraThinMaterial)
            .overlay(
                self.fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.08),
                            .white.opacity(0.05),
                            .white.opacity(0.01),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                self.stroke(.white.opacity(0.2), lineWidth: 0.7)
            )
    }
}
```

### 5.3 Conditional Button Styles

```swift
extension View {
    @ViewBuilder
    func adaptiveGlassButton() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.plain)
        }
    }
}
```

### 5.4 Deployment Target Considerations

If Pastel raises its minimum deployment target to macOS 26, all `#available` checks become
unnecessary. Until then, maintain dual paths. The current approach of keeping the check in
a `ViewModifier` is clean and maintainable.

---

## 6. Pitfalls and Gotchas

### 6.1 Glass Cannot Sample Glass

**Rule:** Never stack glass on glass. If a glass element is placed over another glass element,
the inner one cannot properly sample the outer one's content. This results in visual artifacts.

**Impact on Pastel:** The panel has one glass background (the `GlassEffectModifier` on the
entire `VStack`). Do NOT add individual glass effects to cards, search field, or chip bar
unless they are in the same `GlassEffectContainer` and the outer glass is removed.

### 6.2 Non-Activating Panel Degradation

As documented in section 2.2, this is the biggest concern for Pastel. The glass effect
in the sliding panel will render as basic blur rather than full liquid glass because
`NSPanel` with `.nonactivatingPanel` means the app is never frontmost.

### 6.3 Forced Dark Mode Interaction

Pastel forces `.preferredColorScheme(.dark)`. Glass adapts to this correctly, but:
- If a user has "Reduce Transparency" enabled in System Settings, glass becomes opaque/frosty
- If "Increase Contrast" is enabled, glass gets stark borders
- These accessibility adaptations happen automatically — no code needed

### 6.4 Glass in ScrollView

Content scrolling behind glass looks intentional in toolbars/navigation but can look like
a layout error in other contexts. Since Pastel's card list scrolls within the glass panel,
test that the visual result is acceptable. The glass panel is the container, and content
scrolls inside it — this should be fine since the glass is on the outer container, not
floating over scrolling content.

### 6.5 `.interactive()` is iOS Only

`Glass.regular.interactive()` (which adds scale, bounce, shimmer on touch) is iOS/iPadOS
only. Do not use on macOS — it will compile but has no effect or may cause issues.

### 6.6 UnevenRoundedRectangle Compatibility

The current `UnevenRoundedRectangle` shape used for edge-aware corners works with
`.glassEffect(in:)` since it conforms to `Shape`. No changes needed.

### 6.7 Color Scheme and Glass Tinting

Setting `.tint(.blue)` on glass behaves differently in dark vs. light mode. Since Pastel
forces dark mode, test any tints in dark mode specifically. Avoid over-tinting — Apple
recommends tinting only for semantic meaning.

### 6.8 Performance

Glass effects involve real-time compositing. On older Macs (without Apple Silicon), the
rendering may be heavier. The effect degrades gracefully on constrained hardware, but
consider this if targeting Intel Macs.

### 6.9 glassEffect Always Re-renders

There are reports on Apple Developer Forums that `.glassEffect()` in certain configurations
triggers unnecessary re-renders. Monitor for performance issues in the card list if glass
is applied broadly.

### 6.10 Menu Popover Interaction

When a native `Menu` is opened from within a glass view, the glass effect can temporarily
flatten or disappear because the menu is managed by AppKit/UIKit rather than SwiftUI.
This affects the gear menu button in the panel header. The effect restores when the menu
dismisses.

---

## 7. Summary of Recommended Changes

### Priority 1 — Low Risk, High Impact
| Component | Change | Effort |
|-----------|--------|--------|
| Panel (`PanelContentView`) | Already done — `GlassEffectModifier` is correct | None |
| Settings window chrome | Automatic with Xcode 26 recompile | None |
| Menu bar popover | Automatic with Xcode 26 recompile | None |

### Priority 2 — Medium Risk, Visual Polish
| Component | Change | Effort |
|-----------|--------|--------|
| Settings tab bar | Migrate to SwiftUI `TabView` for native glass tabs | Medium |
| Settings tab bar (alt) | Add `.buttonStyle(.glass)` to custom tabs | Low |
| Settings `.ultraThinMaterial` | May need removal/update under glass window chrome | Low |
| History browser `.ultraThinMaterial` | Test and possibly remove | Low |

### Priority 3 — Investigate / Defer
| Component | Change | Effort |
|-----------|--------|--------|
| Panel glass degradation | Test actual rendering; decide if blur-only is acceptable | Low |
| NSVisualEffectView hybrid | Add `.active` state background for consistent blur | Medium |
| Glass buttons in panel header | Add `.buttonStyle(.glass)` to gear button | Low |
| GlassEffectContainer for header | Wrap header controls if multiple get glass | Low |

---

## 8. Sources

- [Apple: glassEffect(_:in:) Documentation](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [Apple: Glass Struct Documentation](https://developer.apple.com/documentation/swiftui/glass)
- [Apple: Applying Liquid Glass to Custom Views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Apple: GlassEffectContainer Documentation](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [Apple: glassEffectID(_:in:) Documentation](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:))
- [Apple: GlassEffectTransition Documentation](https://developer.apple.com/documentation/swiftui/glasseffecttransition)
- [Apple: GlassButtonStyle Documentation](https://developer.apple.com/documentation/swiftui/glassbuttonstyle)
- [Apple: glassProminent Documentation](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent)
- [Apple: sharedBackgroundVisibility Documentation](https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:))
- [WWDC25 Session 323: Build a SwiftUI App with the New Design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Apple: Landmarks — Refining Glass Effect in Toolbars](https://developer.apple.com/documentation/SwiftUI/Landmarks-Refining-the-system-provided-glass-effect-in-toolbars)
- [Apple: Landmarks — Background Extension Effect](https://developer.apple.com/documentation/SwiftUI/Landmarks-Applying-a-background-extension-effect)
- [Liquid Glass Reference (GitHub)](https://github.com/conorluddy/LiquidGlassReference)
- [Liquid Glass Best Practices (DEV Community)](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)
- [GlassEffectContainer Guide (DEV Community)](https://dev.to/arshtechpro/understanding-glasseffectcontainer-in-ios-26-2n8p)
- [glassEffect in Floating Window/Panel (HWS Forums)](https://www.hackingwithswift.com/forums/swiftui/glasseffect-in-floating-window-panel/30067)
- [Adopting Liquid Glass: Experiences and Pitfalls](https://juniperphoton.substack.com/p/adopting-liquid-glass-experiences)
- [Glassifying Toolbars in SwiftUI (Swift with Majid)](https://swiftwithmajid.com/2025/07/01/glassifying-toolbars-in-swiftui/)
- [SwiftUI for Mac 2025 (TrozWare)](https://troz.net/post/2025/swiftui-mac-2025/)
- [Implementing glassEffect in SwiftUI (Livsy Code)](https://livsycode.com/swiftui/implementing-the-glasseffect-in-swiftui/)
- [glassEffectID Tutorial (SerialCoder.dev)](https://serialcoder.dev/text-tutorials/swiftui/transforming-glass-views-with-the-glasseffectid-modifier-in-swiftui/)
- [BackgroundExtensionEffect in SwiftUI (Nil Coalescing)](https://nilcoalescing.com/blog/BackgroundExtensionEffectInSwiftUI/)
- [Glass Button Styles Explained (tanaschita.com)](https://tanaschita.com/swiftui-glass-button-style/)
