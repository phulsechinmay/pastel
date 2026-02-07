---
phase: quick
plan: 007
type: fix
wave: 1
autonomous: true
---

<objective>
Fix Cmd+1-9 quick paste hotkeys not working until the user clicks on the panel. The panel opens visually but isn't made the key window, so SwiftUI .onKeyPress handlers don't receive keyboard events.
</objective>

<tasks>

<task type="auto">
  <name>Task 1: Add panel.makeKey() after orderFrontRegardless() in PanelController.show()</name>
  <files>Pastel/Views/Panel/PanelController.swift</files>
  <action>
Add `panel.makeKey()` after `panel.orderFrontRegardless()` in the `show()` method. This makes the NSPanel the key window so that SwiftUI .onKeyPress handlers receive keyboard events immediately when the panel opens, without requiring the user to click on it first.
  </action>
</task>

</tasks>
