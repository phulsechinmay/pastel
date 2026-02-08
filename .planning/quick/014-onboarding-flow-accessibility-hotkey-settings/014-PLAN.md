---
phase: quick
plan: 014
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Onboarding/OnboardingView.swift
  - Pastel/Views/Onboarding/OnboardingWindowController.swift
  - Pastel/App/AppState.swift
  - Pastel/PastelApp.swift
autonomous: true

must_haves:
  truths:
    - "On first launch (no hasCompletedOnboarding key), the onboarding window appears centered with dark theme"
    - "Onboarding shows PastelLogo image, accessibility section with grant/open buttons and green/red status indicator, hotkey recorder, Try It button, and quick settings"
    - "Accessibility permission status indicator polls every 1s and updates green (granted) vs red (not granted)"
    - "User can change hotkey, toggle launch at login, pick retention, and pick panel edge within onboarding"
    - "Clicking Get Started sets hasCompletedOnboarding = true and closes the window"
    - "On subsequent launches without accessibility, the existing AccessibilityPromptView appears (not the full onboarding)"
    - "On subsequent launches with accessibility granted, no window appears"
  artifacts:
    - path: "Pastel/Views/Onboarding/OnboardingView.swift"
      provides: "SwiftUI onboarding view with 3 sections"
      min_lines: 80
    - path: "Pastel/Views/Onboarding/OnboardingWindowController.swift"
      provides: "NSWindow manager for onboarding, mirrors SettingsWindowController pattern"
      min_lines: 25
  key_links:
    - from: "Pastel/PastelApp.swift"
      to: "AppState.handleFirstLaunch()"
      via: "called in PastelApp.init"
      pattern: "handleFirstLaunch|showOnboarding"
    - from: "Pastel/App/AppState.swift"
      to: "OnboardingWindowController"
      via: "first-launch check using UserDefaults hasCompletedOnboarding"
      pattern: "hasCompletedOnboarding"
    - from: "Pastel/Views/Onboarding/OnboardingView.swift"
      to: "AccessibilityService"
      via: "requestPermission + polling isGranted"
      pattern: "AccessibilityService\\.(isGranted|requestPermission|openAccessibilitySettings)"
---

<objective>
Create a first-launch onboarding flow for Pastel with three sections: accessibility permissions, hotkey setup, and quick settings. The onboarding appears once on first install, then subsequent launches fall back to the existing AccessibilityPromptView if needed.

Purpose: Give new users a guided setup experience that covers the essential configuration (accessibility, hotkey, preferences) in one welcoming window instead of a bare permission prompt.
Output: OnboardingView.swift, OnboardingWindowController.swift, updated AppState.swift and PastelApp.swift
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/App/AppState.swift
@Pastel/PastelApp.swift
@Pastel/Views/Onboarding/AccessibilityPromptView.swift
@Pastel/Views/Settings/SettingsWindowController.swift
@Pastel/Views/Settings/GeneralSettingsView.swift
@Pastel/Views/Settings/ScreenEdgePicker.swift
@Pastel/Services/AccessibilityService.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create OnboardingView and OnboardingWindowController</name>
  <files>
    Pastel/Views/Onboarding/OnboardingView.swift
    Pastel/Views/Onboarding/OnboardingWindowController.swift
  </files>
  <action>
**OnboardingWindowController.swift** -- Follow the exact same pattern as `SettingsWindowController.swift`:
- `@MainActor final class OnboardingWindowController` with a singleton `static let shared`
- Private `var window: NSWindow?`
- Method `func showOnboarding(appState: AppState)` that:
  - If window already visible, bring to front and return
  - Creates `OnboardingView(onDismiss: { ... })` wrapped in `.preferredColorScheme(.dark).environment(appState)`
  - Creates NSWindow with `contentRect: NSRect(x: 0, y: 0, width: 480, height: 640)`, styleMask `[.titled, .closable]`, buffered, defer true
  - Sets window.title = "Welcome to Pastel", centers, `isReleasedWhenClosed = false`
  - Sets `window.appearance = NSAppearance(named: .darkAqua)`
  - `makeKeyAndOrderFront(nil)`, `NSApp.activate(ignoringOtherApps: true)`
  - The `onDismiss` closure closes the window and nils it out
- Method `func close()` to close window and nil it

**OnboardingView.swift** -- A single scrollable page with all 3 sections:

```swift
import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts

struct OnboardingView: View {
    var onDismiss: () -> Void = {}
    @Environment(AppState.self) private var appState

    // Accessibility polling
    @State private var accessibilityGranted = AccessibilityService.isGranted
    let pollTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    // Settings bindings (same @AppStorage keys as GeneralSettingsView)
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue
    @AppStorage("historyRetention") private var retentionDays: Int = 90

    var body: some View { ... }
}
```

Layout (single VStack inside ScrollView, .padding(32)):

1. **Header** -- `Image("PastelLogo").resizable().scaledToFit().frame(height: 64)` centered, then `Text("Welcome to Pastel")` as `.font(.title).fontWeight(.bold)`, then a subtitle `Text("Let's get you set up in under a minute.").foregroundStyle(.secondary)`

2. **Section 1: Accessibility** -- Section header "Accessibility Permission" with `.font(.headline)`. Explanation text similar to current AccessibilityPromptView: "Pastel needs Accessibility permission to paste items into other apps." Below that, an HStack with a status indicator: `Circle().fill(accessibilityGranted ? .green : .red).frame(width: 10, height: 10)` and text "Permission granted" or "Permission required". Then two buttons in a VStack:
   - "Grant Permission" button (`.buttonStyle(.borderedProminent).controlSize(.regular)`) calling `AccessibilityService.requestPermission()`
   - "Open System Settings" button (`.buttonStyle(.bordered).controlSize(.regular)`) calling `AccessibilityService.openAccessibilitySettings()`
   - When `accessibilityGranted` is true, hide/disable the buttons and show a checkmark message instead.

3. **Section 2: Panel Hotkey** -- Section header "Panel Hotkey" with `.font(.headline)`. `KeyboardShortcuts.Recorder("Toggle panel:", name: .togglePanel)`. Below that, a "Try It!" button (`.buttonStyle(.bordered)`) that calls `appState.togglePanel()`. Help text: `Text("Press the hotkey anytime to open your clipboard panel.").font(.caption).foregroundStyle(.secondary)`

4. **Section 3: Quick Settings** -- Section header "Quick Settings" with `.font(.headline)`. Three items:
   - `LaunchAtLogin.Toggle("Launch at login").toggleStyle(.switch)`
   - `Picker("Keep history for:", selection: $retentionDays)` with the same tags: 7 (1 Week), 30 (1 Month), 90 (3 Months), 365 (1 Year), 0 (Forever). `.pickerStyle(.menu).frame(maxWidth: 200)`
   - `HStack { Text("Panel position"); ScreenEdgePicker(selectedEdge: $panelEdgeRaw) }`

5. **Footer** -- A prominent "Get Started" button at the bottom, full-width, `.buttonStyle(.borderedProminent).controlSize(.large)`. On tap: set `UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")` and call `onDismiss()`.

Use `Divider()` between sections for visual separation. All sections are separated by `spacing: 24` in the VStack.

The `.onReceive(pollTimer)` modifier updates `accessibilityGranted = AccessibilityService.isGranted` every tick (no guard on isChecking -- always poll in onboarding).

The `.onChange(of: panelEdgeRaw)` modifier should call `appState.panelController.handleEdgeChange()` (same as GeneralSettingsView does).

IMPORTANT: Do NOT use `@Observable` tracking for accessibilityGranted -- it's a local `@State` updated by timer. The `appState` environment is used only for `togglePanel()` and `panelController.handleEdgeChange()`.
  </action>
  <verify>
    Both files compile with no errors: `xcodebuild build -scheme Pastel -destination 'platform=macOS' 2>&1 | tail -5`
  </verify>
  <done>
    OnboardingView.swift exists with PastelLogo header, 3 sections (accessibility with green/red indicator + polling, hotkey recorder + Try It, quick settings), and a Get Started button that writes UserDefaults. OnboardingWindowController.swift exists following SettingsWindowController pattern.
  </done>
</task>

<task type="auto">
  <name>Task 2: Wire onboarding into AppState and PastelApp launch flow</name>
  <files>
    Pastel/App/AppState.swift
    Pastel/PastelApp.swift
  </files>
  <action>
**AppState.swift** -- Replace `checkAccessibilityOnLaunch()` with a new method `handleFirstLaunch()`:

1. Add a private property: `private var onboardingController = OnboardingWindowController.shared`
2. Keep the existing `private var accessibilityWindow: NSWindow?` and `checkAccessibilityOnLaunch()` method -- do NOT delete them. The accessibility-only prompt is still used for subsequent launches.
3. Add a new method:

```swift
/// Handle first-launch onboarding or subsequent accessibility check.
///
/// On first launch (hasCompletedOnboarding is false): show full onboarding.
/// On subsequent launches: if accessibility not granted, show the simple AccessibilityPromptView.
/// If accessibility is already granted on subsequent launches: no-op.
func handleFirstLaunch() {
    let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    if !hasCompleted {
        // First launch: show full onboarding
        onboardingController.showOnboarding(appState: self)
    } else {
        // Subsequent launch: just check accessibility
        checkAccessibilityOnLaunch()
    }
}
```

Do NOT modify or delete `checkAccessibilityOnLaunch()` -- it remains for the subsequent-launch accessibility-only prompt path.

**PastelApp.swift** -- In `init()`, replace the line:
```swift
state.checkAccessibilityOnLaunch()
```
with:
```swift
state.handleFirstLaunch()
```

This is a single line change. Everything else in PastelApp.swift stays the same.
  </action>
  <verify>
    Full build succeeds: `xcodebuild build -scheme Pastel -destination 'platform=macOS' 2>&1 | tail -5`
    Verify the logic: grep for `handleFirstLaunch` in AppState.swift and PastelApp.swift to confirm wiring.
  </verify>
  <done>
    - First launch (no hasCompletedOnboarding key): full onboarding window appears
    - After completing onboarding (hasCompletedOnboarding = true): onboarding never appears again
    - Subsequent launch without accessibility: existing AccessibilityPromptView appears
    - Subsequent launch with accessibility: no window appears (clean start)
    - Existing AccessibilityPromptView.swift is untouched and still functional
  </done>
</task>

</tasks>

<verification>
1. `xcodebuild build -scheme Pastel -destination 'platform=macOS'` completes with 0 errors
2. `grep -r "hasCompletedOnboarding" Pastel/` shows usage in OnboardingView.swift (setting true) and AppState.swift (reading)
3. `grep -r "handleFirstLaunch" Pastel/` shows definition in AppState.swift and call in PastelApp.swift
4. `grep -r "checkAccessibilityOnLaunch" Pastel/` still shows the method in AppState.swift (preserved for subsequent launches)
5. OnboardingView.swift imports and uses: KeyboardShortcuts.Recorder, LaunchAtLogin.Toggle, ScreenEdgePicker, AccessibilityService
</verification>

<success_criteria>
- OnboardingView renders with PastelLogo, accessibility section (green/red indicator, grant buttons, 1s polling), hotkey section (recorder + Try It), quick settings (launch at login, retention, panel edge)
- OnboardingWindowController follows SettingsWindowController pattern (NSWindow, dark theme, centered)
- First launch shows onboarding; subsequent launches show accessibility-only prompt when needed
- Get Started button sets hasCompletedOnboarding = true and dismisses
- Existing AccessibilityPromptView is preserved and still used for post-onboarding accessibility prompts
- Project builds with zero errors
</success_criteria>

<output>
After completion, create `.planning/quick/014-onboarding-flow-accessibility-hotkey-settings/014-SUMMARY.md`
</output>
