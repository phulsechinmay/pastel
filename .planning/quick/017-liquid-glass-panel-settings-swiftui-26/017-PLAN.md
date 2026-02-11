---
phase: quick-017
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Settings/SettingsView.swift
  - Pastel/Views/Panel/PanelContentView.swift
  - Pastel/Views/Panel/PanelController.swift
autonomous: true

must_haves:
  truths:
    - "On macOS 26+ the settings tab bar uses glass button styles with glassProminent for selected and glass for unselected"
    - "On macOS 26+ the settings tab bar has no ultraThinMaterial background (glass cannot sample glass)"
    - "On pre-macOS 26 the settings tab bar looks identical to current (plain buttons, accent highlight, ultraThinMaterial)"
    - "On macOS 26+ the gear button in the panel header uses .buttonStyle(.glass)"
    - "On pre-macOS 26 the gear button uses .buttonStyle(.plain) as before"
    - "On pre-macOS 26 the panel has an NSVisualEffectView with state=.active providing consistent blur"
    - "On macOS 26+ the panel has NO NSVisualEffectView (SwiftUI .glassEffect handles visuals)"
  artifacts:
    - path: "Pastel/Views/Settings/SettingsView.swift"
      provides: "Glass-aware tab bar with availability gate"
      contains: "#available(macOS 26"
    - path: "Pastel/Views/Panel/PanelContentView.swift"
      provides: "Glass-aware gear button style"
      contains: "buttonStyle(.glass)"
    - path: "Pastel/Views/Panel/PanelController.swift"
      provides: "NSVisualEffectView background for pre-macOS 26"
      contains: "NSVisualEffectView"
  key_links:
    - from: "Pastel/Views/Settings/SettingsView.swift"
      to: "GlassEffectContainer"
      via: "wraps tab buttons on macOS 26+"
      pattern: "GlassEffectContainer"
    - from: "Pastel/Views/Panel/PanelController.swift"
      to: "NSVisualEffectView"
      via: "background blur layer in createPanel()"
      pattern: "NSVisualEffectView"
---

<objective>
Adopt liquid glass styling across the panel and settings on macOS 26+ with proper fallbacks to the current look on older macOS versions.

Purpose: Bring Pastel's visual identity in line with the macOS 26 Liquid Glass design language while preserving the existing aesthetic on macOS 14-15.
Output: Updated SettingsView.swift (glass tab bar), PanelContentView.swift (glass gear button), PanelController.swift (NSVisualEffectView fallback).
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Settings/SettingsView.swift
@Pastel/Views/Panel/PanelContentView.swift
@Pastel/Views/Panel/PanelController.swift
@Pastel/Views/Panel/SlidingPanel.swift
@.planning/quick/017-liquid-glass-panel-settings-swiftui-26/RESEARCH.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Glass tab bar in Settings and glass gear button in Panel</name>
  <files>
    Pastel/Views/Settings/SettingsView.swift
    Pastel/Views/Panel/PanelContentView.swift
  </files>
  <action>
**SettingsView.swift — Glass tab bar on macOS 26+:**

In the `body` property, wrap the entire tab bar `HStack` in an `#available(macOS 26, *)` availability gate that provides two paths:

macOS 26+ path:
- Wrap the `HStack(spacing: 16)` in a `GlassEffectContainer` (no spacing parameter needed since the default works for adjacent buttons).
- For each tab `Button`, use a conditional button style: `.buttonStyle(.glassProminent)` when `selectedTab == tab`, `.buttonStyle(.glass)` when not selected. Because `.buttonStyle()` is a method that takes a concrete type and `.glass` / `.glassProminent` are different types, you CANNOT use a ternary. Instead, use two separate `Button` declarations inside an `if selectedTab == tab { ... } else { ... }` block within the `ForEach`. Both buttons share the same action and label (the VStack with icon+text), but differ only in `.buttonStyle(...)`.
- In the macOS 26+ label VStack, keep the same icon (16pt) and text (12pt) layout and frame (width: 80, height: 52). Remove the manual `.foregroundStyle(...)` conditional coloring (glass buttons manage their own visual states). Remove the `.background(RoundedRectangle...)` and `.overlay(RoundedRectangle...)` — the glass button style provides its own shape and highlight.
- The outer tab bar area: keep `.padding(.vertical, 12)` and `.frame(maxWidth: .infinity)`. Do NOT apply `.background(.ultraThinMaterial)` on macOS 26+ because glass cannot sample glass. The `GlassEffectContainer` and glass buttons provide sufficient visual weight.

Pre-macOS 26 path (else branch):
- Keep the current implementation exactly as-is: `HStack` with `ForEach`, `.buttonStyle(.plain)`, manual accent color `.foregroundStyle(...)`, `.background(RoundedRectangle...)`, `.overlay(RoundedRectangle...)`, and `.background(.ultraThinMaterial)` on the outer container.

Structure:
```swift
var body: some View {
    VStack(spacing: 0) {
        // Tab bar
        if #available(macOS 26, *) {
            GlassEffectContainer {
                HStack(spacing: 16) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        if selectedTab == tab {
                            Button { selectedTab = tab } label: { tabLabel(tab) }
                                .buttonStyle(.glassProminent)
                        } else {
                            Button { selectedTab = tab } label: { tabLabel(tab) }
                                .buttonStyle(.glass)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        } else {
            // existing tab bar code unchanged
            HStack(spacing: 16) { ... }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }

        Divider()
        // Content area unchanged ...
    }
}
```

Extract a `tabLabel(_ tab: SettingsTab)` helper function (private, returns `some View`) to avoid duplicating the VStack(icon + text) layout between the two branches. The label should have:
- `Image(systemName: tab.iconName).font(.system(size: 16))`
- `Text(tab.displayName).font(.system(size: 12))`
- `.frame(width: 80, height: 52)`
- No foregroundStyle / background / overlay (those are only in the pre-26 path).

In the pre-macOS 26 branch, the ForEach body uses the existing approach with `.foregroundStyle(...)`, `.background(...)`, `.overlay(...)` applied to the label directly (NOT using the helper, since it needs those extra modifiers). OR: use the helper and apply the modifiers after calling it. Either approach is fine as long as the pre-26 path is visually identical to current.

**PanelContentView.swift — Glass gear button:**

There are two gear buttons in `PanelContentView`: one in the `isHorizontal` branch (line ~71-83) and one in the `!isHorizontal` (vertical) branch (line ~95-107). Update BOTH.

For each gear button, replace the static `.buttonStyle(.plain)` with an availability-gated style. The cleanest approach: create a private `ViewModifier` or use `@ViewBuilder` in a helper. However, since `.buttonStyle()` takes concrete types, the simplest pattern is:

```swift
// Replace this:
.buttonStyle(.plain)

// With this approach — wrap the Button in a @ViewBuilder helper or use Group:
// Option: apply after the Button using a custom modifier
```

Actually the simplest approach: create a small private extension or ViewModifier in PanelContentView.swift (below the existing `GlassEffectModifier`):

```swift
private struct AdaptiveGlassButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.plain)
        }
    }
}
```

Then on each gear button, replace `.buttonStyle(.plain)` with `.modifier(AdaptiveGlassButtonStyle())`.

Keep the `.foregroundStyle(.secondary)` on the gear icon label in both cases — on macOS 26+ the glass button will provide its own background treatment but the icon color hint is still useful.
  </action>
  <verify>
Build the project with `xcodebuild build -scheme Pastel -destination 'platform=macOS'` (or the project's standard build command). Verify no compiler errors. Check that `#available(macOS 26, *)` gates compile correctly. On current macOS (pre-26), verify the settings and panel look identical to before (the else branches execute).
  </verify>
  <done>
Settings tab bar uses GlassEffectContainer with .glass/.glassProminent button styles on macOS 26+ and preserves current look on older macOS. Gear button in panel header uses .glass on macOS 26+ and .plain on older. No visual regression on current macOS.
  </done>
</task>

<task type="auto">
  <name>Task 2: NSVisualEffectView blur layer for pre-macOS 26 panel</name>
  <files>
    Pastel/Views/Panel/PanelController.swift
  </files>
  <action>
In `PanelController.createPanel()`, after creating the `containerView` (line ~301: `let containerView = NSView()`) and before adding the `hostingView` as a subview, add an `NSVisualEffectView` as a background layer for pre-macOS 26 systems.

The NSVisualEffectView provides a consistent always-active blur behind the SwiftUI content. On macOS 26+, the SwiftUI `.glassEffect` handles the visual treatment, so no AppKit blur layer is needed.

Implementation:

```swift
let containerView = NSView()
slidingPanel.contentView = containerView

// Add always-active blur background for pre-macOS 26
// (On macOS 26+, SwiftUI .glassEffect handles the panel's visual treatment)
if #unavailable(macOS 26) {
    let visualEffect = NSVisualEffectView()
    visualEffect.blendingMode = .behindWindow
    visualEffect.state = .active          // Forces active appearance even when app is not frontmost
    visualEffect.material = .hudWindow    // Dark translucent material matching panel aesthetic
    visualEffect.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(visualEffect)
    NSLayoutConstraint.activate([
        visualEffect.topAnchor.constraint(equalTo: containerView.topAnchor),
        visualEffect.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        visualEffect.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
        visualEffect.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
    ])
}
```

This must go BEFORE the `hostingView` is added as a subview, so the visual effect view sits behind the SwiftUI content in the view hierarchy. The existing `hostingView` subview addition (line ~336: `containerView.addSubview(hostingView)`) stays after this block.

Also update the `GlassEffectModifier` in `PanelContentView.swift` to account for the NSVisualEffectView now providing the blur on pre-26. The current fallback is `.background(shape.fill(.ultraThinMaterial)).clipShape(shape)`. Since the NSVisualEffectView already provides the behind-window blur, the SwiftUI `.ultraThinMaterial` layer creates a double-blur effect. Change the pre-26 fallback to just clip the shape without adding another material:

```swift
private struct GlassEffectModifier: ViewModifier {
    let shape: UnevenRoundedRectangle

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            // NSVisualEffectView in PanelController provides the behind-window blur;
            // just clip to the edge-aware shape here.
            content.clipShape(shape)
        }
    }
}
```

Wait — actually the `.ultraThinMaterial` in the SwiftUI layer and the `NSVisualEffectView` serve slightly different purposes. The NSVisualEffectView blurs behind the window, while `.ultraThinMaterial` adds an in-window translucent fill. Having both could make the panel overly opaque. However, removing the material entirely makes the SwiftUI content area fully transparent (showing only the AppKit blur underneath), which is actually the desired behavior — the NSVisualEffectView IS the panel's background material.

So yes: change the pre-26 fallback to just `.clipShape(shape)` with no `.background(...)`. The NSVisualEffectView handles the material. This keeps the edge-aware rounded corners working.

Update the comment on `SlidingPanel.swift` line 24 from "NSVisualEffectView provides the material" to "SwiftUI .glassEffect (macOS 26+) or NSVisualEffectView (pre-26) provides the material" since that comment was stale (no NSVisualEffectView existed before this change).
  </action>
  <verify>
Build the project. Verify no compiler errors. On current macOS (pre-26), confirm the panel still shows a translucent blur behind content (now via NSVisualEffectView with `.active` state instead of SwiftUI `.ultraThinMaterial`). Verify the edge-aware rounded corners still clip correctly.
  </verify>
  <done>
Pre-macOS 26 panel has an NSVisualEffectView with state=.active and material=.hudWindow providing consistent always-active blur. macOS 26+ panel has no NSVisualEffectView (SwiftUI .glassEffect handles it). The GlassEffectModifier pre-26 fallback clips to shape without redundant material. SlidingPanel comment updated.
  </done>
</task>

</tasks>

<verification>
1. `xcodebuild build -scheme Pastel -destination 'platform=macOS'` completes with zero errors
2. On current macOS (pre-26): panel appearance unchanged (translucent blur with edge-aware corners)
3. On current macOS (pre-26): settings tab bar appearance unchanged (accent highlight, ultraThinMaterial)
4. On current macOS (pre-26): gear button appearance unchanged (plain style)
5. All `#available(macOS 26, *)` / `#unavailable(macOS 26)` gates compile cleanly
6. No glass-on-glass stacking (settings tab bar removes .ultraThinMaterial on macOS 26+)
</verification>

<success_criteria>
- Settings tab bar uses GlassEffectContainer + .glass/.glassProminent on macOS 26+ with no .ultraThinMaterial
- Settings tab bar unchanged on pre-macOS 26
- Panel gear button uses .glass on macOS 26+, .plain on pre-26
- Panel has NSVisualEffectView(state: .active, material: .hudWindow) on pre-26 only
- Panel GlassEffectModifier pre-26 fallback uses clipShape only (no redundant material)
- Zero build errors, zero visual regressions on current macOS
</success_criteria>

<output>
After completion, create `.planning/quick/017-liquid-glass-panel-settings-swiftui-26/017-SUMMARY.md`
</output>
