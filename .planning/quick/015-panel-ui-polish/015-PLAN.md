---
phase: quick
plan: "015"
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/PanelContentView.swift
  - Pastel/Views/Panel/FilteredCardListView.swift
  - Pastel/Views/Panel/PanelController.swift
  - Pastel/Views/Panel/SlidingPanel.swift
  - Pastel/Models/PanelEdge.swift
autonomous: true

must_haves:
  truths:
    - "In top/bottom mode, minimal gap between header bar and clipboard cards"
    - "Panel background has frosted glass appearance (ultra-thin material)"
    - "Panel has rounded corners on the edges facing inward (away from screen edge)"
    - "Panel extends behind the dock, covering it when visible"
    - "Panel does NOT cover the macOS menu bar"
  artifacts:
    - path: "Pastel/Views/Panel/PanelController.swift"
      provides: "Glass material, rounded corners on NSVisualEffectView"
      contains: "ultraThinMaterial"
    - path: "Pastel/Models/PanelEdge.swift"
      provides: "Frame calculations using screen.frame for dock coverage"
      contains: "menuBarHeight"
    - path: "Pastel/Views/Panel/SlidingPanel.swift"
      provides: "Panel level high enough to overlay dock"
    - path: "Pastel/Views/Panel/PanelContentView.swift"
      provides: "Reduced spacing in horizontal mode"
  key_links:
    - from: "PanelController.swift"
      to: "PanelEdge.swift"
      via: "Frame calculation uses full screen frame with menu bar offset"
    - from: "SlidingPanel.swift"
      to: "dock overlay"
      via: "Window level set above dock"
---

<objective>
Polish the sliding panel UI with four visual improvements: tighten spacing in horizontal mode, apply frosted glass background, add rounded corners, and extend the panel to overlay the dock.

Purpose: Improve visual polish and consistency of the clipboard panel.
Output: Modified panel files with all four visual fixes applied.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Panel/PanelController.swift
@Pastel/Views/Panel/SlidingPanel.swift
@Pastel/Views/Panel/PanelContentView.swift
@Pastel/Views/Panel/FilteredCardListView.swift
@Pastel/Models/PanelEdge.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Glass background, rounded corners, and tighten horizontal spacing</name>
  <files>
    Pastel/Views/Panel/PanelController.swift
    Pastel/Views/Panel/SlidingPanel.swift
    Pastel/Views/Panel/PanelContentView.swift
    Pastel/Views/Panel/FilteredCardListView.swift
  </files>
  <action>
    Three changes in this task:

    **1. Glass material (PanelController.swift, createPanel())**

    In `createPanel()`, change the NSVisualEffectView material from `.sidebar` to `.hudWindow`. The `.hudWindow` material gives a more translucent, frosted-glass look compared to the opaque `.sidebar` material. Keep `.behindWindow` blending mode and `.active` state. Keep the dark appearance.

    Note: Do NOT use SwiftUI `.ultraThinMaterial` -- this is AppKit NSVisualEffectView code. The `.hudWindow` material is the AppKit equivalent of a glass-like frosted effect. If `.hudWindow` looks too dark, `.underPageBackground` is another option, but start with `.hudWindow`.

    **2. Rounded corners (SlidingPanel.swift and PanelController.swift)**

    In `SlidingPanel.init()`, after the existing configuration, add corner masking. The panel's contentView needs rounded corners only on the edges facing INWARD (away from the screen edge):
    - Right edge panel: round top-left and bottom-left corners
    - Left edge panel: round top-right and bottom-right corners
    - Top edge panel: round bottom-left and bottom-right corners
    - Bottom edge panel: round top-left and top-right corners

    However, since SlidingPanel doesn't know which edge it's on at init time, the rounding approach should be applied in PanelController.createPanel() AFTER the panel is created, since the edge is known there.

    Implementation in PanelController.createPanel():
    - After setting `slidingPanel.contentView = visualEffectView`, configure the visual effect view's layer for corner rounding:
      ```swift
      visualEffectView.wantsLayer = true
      visualEffectView.layer?.cornerRadius = 12
      // Determine which corners to mask based on current edge
      let edge = currentEdge
      switch edge {
      case .right:
          visualEffectView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
      case .left:
          visualEffectView.layer?.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
      case .top:
          visualEffectView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
      case .bottom:
          visualEffectView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
      }
      visualEffectView.layer?.masksToBounds = true
      ```

    Note on macOS CALayer corner naming: In macOS Core Animation (flipped vs unflipped coordinates can be confusing). The CACornerMask values are:
    - `.layerMinXMinYCorner` = bottom-left in default (unflipped) CA coordinates
    - `.layerMinXMaxYCorner` = top-left
    - `.layerMaxXMinYCorner` = bottom-right
    - `.layerMaxXMaxYCorner` = top-right

    So the correct mappings are:
    - Right edge (round left side): `.layerMinXMinYCorner` (bottom-left) + `.layerMinXMaxYCorner` (top-left)
    - Left edge (round right side): `.layerMaxXMinYCorner` (bottom-right) + `.layerMaxXMaxYCorner` (top-right)
    - Top edge (round bottom): `.layerMinXMinYCorner` (bottom-left) + `.layerMaxXMinYCorner` (bottom-right)
    - Bottom edge (round top): `.layerMinXMaxYCorner` (top-left) + `.layerMaxXMaxYCorner` (top-right)

    **3. Tighten horizontal spacing (PanelContentView.swift and FilteredCardListView.swift)**

    In PanelContentView.swift: The horizontal mode header HStack has `.padding(.vertical, 10)`. Reduce this to `.padding(.vertical, 6)`.

    In FilteredCardListView.swift: In the horizontal branch (`if isHorizontal`), the LazyHStack content has `.padding(.vertical, 8)`. Reduce to `.padding(.vertical, 2)`. This tightens the gap between the header row and the card row in top/bottom mode. Keep the vertical mode `.padding(.vertical, 8)` unchanged.
  </action>
  <verify>
    Build: `cd /Users/phulsechinmay/Desktop/Projects/pastel && xcodebuild -scheme Pastel -configuration Debug build 2>&1 | tail -5`
    Expect: BUILD SUCCEEDED with no errors.
  </verify>
  <done>
    - NSVisualEffectView uses `.hudWindow` material for glass effect
    - Panel corners are rounded (12pt radius) on inward-facing edges only
    - Horizontal mode vertical padding reduced from 10+8 to 6+2
  </done>
</task>

<task type="auto">
  <name>Task 2: Extend panel to overlay the dock</name>
  <files>
    Pastel/Models/PanelEdge.swift
    Pastel/Views/Panel/PanelController.swift
    Pastel/Views/Panel/SlidingPanel.swift
  </files>
  <action>
    The panel currently uses `screen.visibleFrame` for all frame calculations, which excludes the dock and menu bar area. The panel should cover the dock but NOT the menu bar.

    **1. PanelEdge.swift -- new frame calculation methods**

    Add a new method `fullFrame(screenFrame:visibleFrame:)` that returns the usable area: full screen minus the menu bar. This gives us "screen.frame but respecting menu bar".

    The menu bar is at the TOP of the screen in macOS coordinate system (where y=0 is bottom). The `screen.visibleFrame` already excludes both dock and menu bar. The `screen.frame` includes everything. By comparing the two, we can derive the menu bar height.

    However, the approach should be simpler: modify `panelSize`, `onScreenFrame`, and `offScreenFrame` to accept a `fullFrame` parameter (the expanded frame covering the dock).

    Actually, the cleanest approach: change PanelController to compute an "expanded frame" that covers the dock but not the menu bar, and pass THAT as the screenFrame to the existing PanelEdge methods.

    In PanelController.swift, modify the `show()` method:

    Replace:
    ```swift
    let screenFrame = screen.visibleFrame
    ```

    With a computed frame that extends to cover the dock area but preserves the menu bar exclusion:
    ```swift
    let fullFrame = screen.frame
    let visibleFrame = screen.visibleFrame

    // Build a frame that covers the dock but not the menu bar.
    // Menu bar is at the top of the screen (in Cocoa coordinates, top = maxY).
    // visibleFrame.maxY < fullFrame.maxY means menu bar is eating space at top.
    // visibleFrame.minY > fullFrame.minY means dock is at the bottom.
    // visibleFrame.minX > fullFrame.minX means dock is on the left.
    // visibleFrame.maxX < fullFrame.maxX means dock is on the right.
    //
    // We want: start from fullFrame, but clip the menu bar portion (top).
    let menuBarHeight = fullFrame.maxY - visibleFrame.maxY
    let screenFrame = NSRect(
        x: fullFrame.origin.x,
        y: fullFrame.origin.y,
        width: fullFrame.width,
        height: fullFrame.height - menuBarHeight
    )
    ```

    This creates a rect that spans the full screen width and height minus the menu bar. The dock area is now included.

    Also update the `hide()` method similarly. Currently it reads:
    ```swift
    let screenFrame = panel.screen?.visibleFrame
        ?? NSScreen.main?.visibleFrame
        ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    ```

    Change to compute the expanded frame the same way:
    ```swift
    let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
    let fullFrame = screen.frame
    let menuBarHeight = fullFrame.maxY - screen.visibleFrame.maxY
    let screenFrame = NSRect(
        x: fullFrame.origin.x,
        y: fullFrame.origin.y,
        width: fullFrame.width,
        height: fullFrame.height - menuBarHeight
    )
    ```

    **2. SlidingPanel.swift -- raise window level**

    The dock sits at a specific window level. The panel's current `level = .floating` may not be enough to overlay the dock in all cases. Change the level to:
    ```swift
    level = .init(Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
    ```

    This places the panel just below the main menu bar level but above the dock. The dock typically renders at `kCGDockWindowLevel` (level 20), and `.floating` is level 3. Using a level just below the menu bar window ensures we're above the dock.

    Actually, a simpler approach: `.statusBar` level (25) is above the dock (20) and below the menu bar. Change:
    ```swift
    level = .statusBar
    ```

    This ensures the panel renders above the dock.

    **3. No changes needed to PanelEdge.swift** -- the existing methods will work correctly with the expanded screenFrame passed from PanelController.
  </action>
  <verify>
    Build: `cd /Users/phulsechinmay/Desktop/Projects/pastel && xcodebuild -scheme Pastel -configuration Debug build 2>&1 | tail -5`
    Expect: BUILD SUCCEEDED. Run the app, toggle the panel in bottom edge mode -- it should extend behind/over the dock. In top edge mode, it should NOT cover the menu bar.
  </verify>
  <done>
    - Panel frame calculation uses full screen minus menu bar (covers dock area)
    - Panel window level raised to .statusBar to render above the dock
    - Menu bar remains uncovered in all edge modes
    - Left/right edge panels now extend full screen height (covering dock if dock is on bottom)
  </done>
</task>

</tasks>

<verification>
1. Build succeeds with no errors or warnings related to changed files
2. Panel in right/left mode: glass background visible, rounded corners on inner edge, extends full height (over dock if dock is at bottom/sides)
3. Panel in top mode: glass background, rounded bottom corners, does NOT cover menu bar
4. Panel in bottom mode: glass background, rounded top corners, extends over dock
5. In top/bottom mode: minimal gap between header bar and clipboard cards
</verification>

<success_criteria>
- All four visual improvements applied: tighter spacing, glass material, rounded corners, dock overlay
- Build compiles successfully
- Panel does not cover the macOS menu bar in any edge mode
- Panel covers the dock in all edge modes where relevant
</success_criteria>

<output>
After completion, create `.planning/quick/015-panel-ui-polish/015-SUMMARY.md`
</output>
