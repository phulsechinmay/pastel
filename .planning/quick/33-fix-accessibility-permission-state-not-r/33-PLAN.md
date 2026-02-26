---
phase: quick-33
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Onboarding/AccessibilityRequiredView.swift
  - Pastel/Views/Settings/GeneralSettingsView.swift
autonomous: true
requirements: [QUICK-33]

must_haves:
  truths:
    - "AccessibilityRequiredView auto-dismisses when permission is granted, regardless of which buttons the user clicked"
    - "AccessibilityRequiredView shows live permission status (green/red indicator) updating every second"
    - "GeneralSettingsView permission warning disappears within 2 seconds of granting accessibility"
    - "PasteService allows paste-back on the very next attempt after permission is granted (already works, no change needed)"
  artifacts:
    - path: "Pastel/Views/Onboarding/AccessibilityRequiredView.swift"
      provides: "Contextual permission prompt with always-active polling and live status"
      contains: "AccessibilityService.isGranted"
    - path: "Pastel/Views/Settings/GeneralSettingsView.swift"
      provides: "Settings view with polling timer for accessibility status"
      contains: "accessibilityPollTimer"
  key_links:
    - from: "Pastel/Views/Onboarding/AccessibilityRequiredView.swift"
      to: "AccessibilityService.isGranted"
      via: "Timer polling every 1 second"
      pattern: "onReceive.*pollTimer"
    - from: "Pastel/Views/Settings/GeneralSettingsView.swift"
      to: "AccessibilityService.isGranted"
      via: "Timer polling every 2 seconds"
      pattern: "onReceive.*accessibilityPollTimer"
---

<objective>
Fix accessibility permission state not refreshing in real-time after the user grants permission.

Purpose: When a user grants accessibility permission via System Settings, the app currently shows "not granted" indefinitely in the AccessibilityRequiredView prompt because polling is gated behind an `isChecking` flag that only activates after clicking specific buttons. The user perceives the app as broken and thinks a restart is required.

Output: AccessibilityRequiredView always polls for permission state and shows a live status indicator, auto-dismissing immediately when granted. GeneralSettingsView continues to work as-is (already polls correctly).
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Services/AccessibilityService.swift
@Pastel/Views/Onboarding/AccessibilityRequiredView.swift
@Pastel/Views/Settings/GeneralSettingsView.swift
@Pastel/Services/PasteService.swift
@Pastel/App/AppState.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix AccessibilityRequiredView to always poll and show live status</name>
  <files>Pastel/Views/Onboarding/AccessibilityRequiredView.swift</files>
  <action>
The root bug: `AccessibilityRequiredView` has a `guard isChecking else { return }` in its `onReceive(pollTimer)` handler. The `isChecking` flag is only set to `true` when the user clicks "Grant Permission" or "Open System Settings". If the user grants permission any other way (manually navigating to System Settings, or granting via a different macOS dialog), the view never detects the change and appears stuck on "not granted".

Fix this by:

1. Remove the `@State private var isChecking = false` property entirely.

2. Add a `@State private var accessibilityGranted = false` property to track live state.

3. Update the `onReceive(pollTimer)` handler to ALWAYS check `AccessibilityService.isGranted` (remove the `guard isChecking` gate). When granted becomes true, auto-dismiss via `onDismiss()`.

4. Add a live status indicator between the description text and the buttons — use the same pattern as OnboardingView:
   ```swift
   HStack(spacing: 8) {
       Circle()
           .fill(accessibilityGranted ? .green : .red)
           .frame(width: 10, height: 10)
       Text(accessibilityGranted ? "Permission granted" : "Not granted")
           .font(.body)
   }
   ```

5. Keep the "Grant Permission" and "Open System Settings" buttons but remove the `isChecking = true` lines from their actions (no longer needed since polling is always active).

6. Add an `onAppear` to set the initial state: `accessibilityGranted = AccessibilityService.isGranted`.

7. In the pollTimer handler, update `accessibilityGranted` before the dismiss check, and add a brief delay (0.5s) before auto-dismiss so the user sees the green "Permission granted" status flash before the window closes:
   ```swift
   .onReceive(pollTimer) { _ in
       accessibilityGranted = AccessibilityService.isGranted
       if accessibilityGranted {
           DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
               onDismiss()
           }
       }
   }
   ```

The view should still be a simple standalone SwiftUI view with `var onDismiss: () -> Void = {}`. Keep the existing window structure (shown via AppState.showAccessibilityRequired). Keep `.fontDesign(.rounded)` and `.preferredColorScheme(.dark)`.
  </action>
  <verify>Build with `xcodebuild -project Pastel.xcodeproj -scheme "Pastel Sparkle" -configuration Debug build 2>&1 | tail -20` — no errors in AccessibilityRequiredView.swift. Verify by grepping that `isChecking` no longer appears in the file and that `accessibilityGranted` and the unconditional `onReceive` handler are present.</verify>
  <done>AccessibilityRequiredView always polls permission state every second without any gate flag, shows a live green/red status indicator, and auto-dismisses with a brief visual confirmation when permission is granted.</done>
</task>

<task type="auto">
  <name>Task 2: Verify GeneralSettingsView polling is correct and confirm end-to-end flow</name>
  <files>Pastel/Views/Settings/GeneralSettingsView.swift</files>
  <action>
GeneralSettingsView already polls correctly with `onReceive(accessibilityPollTimer)` updating `accessibilityGranted` every 2 seconds — no gate flag, always active. Verify this is working as-is by reading the file.

One minor improvement: the poll timer is 2 seconds which is fine for settings, but ensure consistency. No changes needed if already working.

Verify the end-to-end flow by checking:
1. PasteService.paste() checks `AccessibilityService.isGranted` on every call (line 63) — confirmed, no caching
2. PasteService fires `onAccessibilityRequired` callback when not granted — confirmed
3. AppState.showAccessibilityRequired() creates the prompt window — confirmed
4. After permission grant, next paste attempt will succeed because PasteService re-checks each time — confirmed

No code changes needed to GeneralSettingsView or PasteService. The fix is entirely in AccessibilityRequiredView (Task 1). Mark this file as verified with no modifications.
  </action>
  <verify>Grep for `guard isChecking` across the entire Pastel directory to confirm no other views have the same gating bug: `grep -r "isChecking" Pastel/`. Only result should be zero matches (after Task 1 removes it from AccessibilityRequiredView).</verify>
  <done>Confirmed that GeneralSettingsView already polls correctly, PasteService re-checks permission on every paste call, and the only fix needed was in AccessibilityRequiredView (Task 1). No `isChecking` guards remain in any accessibility-related views.</done>
</task>

</tasks>

<verification>
1. Build succeeds with no errors: `xcodebuild -project Pastel.xcodeproj -scheme "Pastel Sparkle" -configuration Debug build`
2. `isChecking` does not appear anywhere in the codebase: `grep -r "isChecking" Pastel/` returns no results
3. AccessibilityRequiredView contains unconditional polling: `grep "onReceive" Pastel/Views/Onboarding/AccessibilityRequiredView.swift` shows the handler
4. AccessibilityRequiredView contains live status indicator: `grep "accessibilityGranted" Pastel/Views/Onboarding/AccessibilityRequiredView.swift` shows the state variable and UI binding
</verification>

<success_criteria>
- AccessibilityRequiredView always polls for permission changes (no isChecking gate)
- Live green/red status indicator visible in the permission prompt
- Auto-dismiss with brief visual confirmation when permission is granted
- Build succeeds with zero warnings in modified files
- Next paste attempt works immediately after granting permission (already worked, confirmed unchanged)
</success_criteria>

<output>
After completion, create `.planning/quick/33-fix-accessibility-permission-state-not-r/33-SUMMARY.md`
</output>
