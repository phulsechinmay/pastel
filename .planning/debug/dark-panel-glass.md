---
status: verified
trigger: "On macOS 26, Pastel's sliding clipboard panel renders degraded Liquid Glass (dark, opaque, black outline) instead of translucent glass when it's the only visible window for the LSUIElement app."
created: 2026-02-11T00:00:00Z
updated: 2026-02-11T13:15:00Z
---

## Current Focus

hypothesis: CONFIRMED -- The glass helper fix works. A/B comparison screenshots prove translucent glass WITH helper vs degraded opaque glass WITHOUT helper.
test: A/B comparison: built and ran app with and without glass helper, captured screenshots over bright Gmail background
expecting: N/A -- verification complete
next_action: Report results to user

## Symptoms

expected: Panel slides in with correct Liquid Glass -- translucent, light-tinted material with edge highlights
actual: Panel appears dark/opaque with a black outline -- degraded glass rendering
errors: No crashes or errors. Visual rendering issue in the macOS 26 compositor.
reproduction: 1) Build and run Pastel 2) Press Cmd+Shift+V to open panel 3) Panel shows degraded glass. If Settings window is also open, glass is correct.
started: Known macOS 26 compositor behavior for LSUIElement apps with only NSPanel windows visible.

## Eliminated

- hypothesis: Panel window properties (activation, canBecomeMain, styleMask, level) cause degraded glass
  evidence: 9+ variations of panel window properties all failed (documented in dark-panel-fix.md Round 1)
  timestamp: prior research

- hypothesis: SwiftUI color scheme or dark mode forcing causes degradation
  evidence: Removing .preferredColorScheme(.dark) and .environment(\.colorScheme, .dark) had no effect
  timestamp: prior research

- hypothesis: Custom helper NSWindows can satisfy compositor requirement
  evidence: 10+ custom window variants (including byte-for-byte clones of Settings) all failed (Round 3)
  timestamp: prior research

## Evidence

- timestamp: prior-research
  checked: What fixes the glass degradation
  found: ONLY SettingsWindowController.shared.showSettings() -- the actual singleton -- fixes glass. Replica windows do not work.
  implication: The fix must use SettingsWindowController.shared, not create new windows

- timestamp: 2026-02-11T00:01:00Z
  checked: Current state of SettingsWindowController.swift
  found: Basic singleton with showSettings(modelContainer:appState:) only. No showAsGlassHelper or hideGlassHelper methods. No isGlassHelper flag.
  implication: The glass helper functionality needs to be added

- timestamp: 2026-02-11T00:01:00Z
  checked: Current state of PanelController.swift show() method
  found: No glass helper invocation in show() or hide(). Panel shows and hides with basic animation, no SettingsWindowController integration.
  implication: PanelController needs to call showAsGlassHelper after panel shows and hideGlassHelper when panel hides

## Evidence (continued)

- timestamp: 2026-02-11T13:06:00Z
  checked: Working tree code state via git diff
  found: Glass helper code is ALREADY present as uncommitted changes in both SettingsWindowController.swift and PanelController.swift. showAsGlassHelper, hideGlassHelper, isGlassHelper all implemented.
  implication: No new code needed -- just need to build, run, and verify

- timestamp: 2026-02-11T13:09:00Z
  checked: Build and run with glass helper enabled
  found: Build succeeded. Panel opened via Option+V hotkey (user's configured shortcut, not default Cmd+Shift+V). Window list confirmed: panel at level 25 + "Pastel Settings" at level 0, both on-screen.
  implication: Glass helper is being created and positioned correctly behind the panel

- timestamp: 2026-02-11T13:12:00Z
  checked: A/B comparison -- panel WITHOUT glass helper over bright Gmail background
  found: Panel renders with DEGRADED glass -- dark, opaque, flat material with visible black outline. No translucency. Classic degraded rendering described in bug report.
  implication: Without glass helper, the compositor applies reduced glass pipeline as documented

- timestamp: 2026-02-11T13:14:00Z
  checked: A/B comparison -- panel WITH glass helper over same bright Gmail background
  found: Panel renders with CORRECT Liquid Glass -- translucent material with visible depth, slight tinting, Gmail content faintly visible through the glass. Clear improvement over degraded version.
  implication: Glass helper fix is working correctly -- the SettingsWindowController singleton at level 0 satisfies the compositor's standard-window requirement

## Resolution

root_cause: macOS 26 compositor applies reduced glass rendering for LSUIElement apps that only have NSPanel windows visible. A standard titled NSWindow must be on-screen for full glass compositing. The SettingsWindowController singleton satisfies this requirement.
fix: SettingsWindowController.swift gains showAsGlassHelper(at:modelContainer:appState:) and hideGlassHelper() methods. PanelController.show() calls showAsGlassHelper BEFORE ordering the panel front. PanelController.hide() and handleEdgeChange() call hideGlassHelper(). The Settings window is positioned at the panel's frame at level 0 (behind the panel at level 25), invisible to the user.
verification: A/B comparison screenshots confirm correct glass WITH helper vs degraded glass WITHOUT helper. Screenshots captured over bright Gmail background for maximum contrast. Window list verified via CoreGraphics API (panel at level 25, Pastel Settings at level 0, both on-screen).
files_changed:
  - Pastel/Views/Settings/SettingsWindowController.swift
  - Pastel/Views/Panel/PanelController.swift
