---
phase: quick-018
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/PanelController.swift
  - Pastel/Views/Panel/PanelContentView.swift
  - Pastel/Views/Panel/SlidingPanel.swift
  - Pastel/Views/Settings/SettingsView.swift
  - Pastel/Views/Settings/SettingsWindowController.swift
autonomous: true

must_haves:
  truths:
    - "On macOS 26+ the panel uses NSGlassEffectView at the AppKit layer (not SwiftUI .glassEffect)"
    - "On macOS 26+ the NSHostingView is set as NSGlassEffectView.contentView (not addSubview)"
    - "On macOS 26+ the PanelContentView GlassEffectModifier passes content through without glass"
    - "On macOS 26+ the gear button uses .borderless (not .glass — avoids glass-on-glass)"
    - "On pre-macOS 26 the panel uses NSVisualEffectView(state: .active, material: .hudWindow)"
    - "On pre-macOS 26 PanelContentView clips to UnevenRoundedRectangle shape"
    - "SlidingPanel sets appearance = .darkAqua"
    - "SettingsWindowController sets titlebarSeparatorStyle = .none"
    - "No print() debug statements in any view modifier"
  artifacts:
    - path: "Pastel/Views/Panel/PanelController.swift"
      provides: "NSGlassEffectView wrapping NSHostingView on macOS 26"
      contains: "NSGlassEffectView"
    - path: "Pastel/Views/Panel/PanelContentView.swift"
      provides: "No SwiftUI glass on macOS 26, borderless gear button"
      contains: "buttonStyle(.borderless)"
    - path: "Pastel/Views/Panel/SlidingPanel.swift"
      provides: "Dark appearance for consistent glass rendering"
      contains: ".darkAqua"
---

<objective>
Replace SwiftUI .glassEffect() with native AppKit NSGlassEffectView for the panel on macOS 26+.

Problem: SwiftUI's .glassEffect() degrades to basic blur on non-activating panels because the app is never frontmost.
Solution: NSGlassEffectView renders glass at the AppKit/compositor level, handling non-activating panels correctly.
</objective>

<tasks>
<task type="auto">
  <name>Task 1: NSGlassEffectView panel + cleanup</name>
  <files>
    Pastel/Views/Panel/PanelController.swift
    Pastel/Views/Panel/PanelContentView.swift
    Pastel/Views/Panel/SlidingPanel.swift
    Pastel/Views/Settings/SettingsView.swift
    Pastel/Views/Settings/SettingsWindowController.swift
  </files>
  <action>
1. PanelController: Replace SwiftUI glass with NSGlassEffectView on macOS 26
2. PanelContentView: Remove SwiftUI .glassEffect() on 26, change gear button to .borderless, remove prints
3. SlidingPanel: Add .darkAqua appearance
4. SettingsView: Remove debug prints
5. SettingsWindowController: Add titlebarSeparatorStyle = .none
  </action>
</task>
</tasks>
