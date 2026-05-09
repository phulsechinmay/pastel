---
phase: quick-34
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Services/AccessibilityService.swift
  - Pastel/Services/PasteService.swift
  - Pastel/PastelApp.swift
  - Pastel/Views/Onboarding/AccessibilityRequiredView.swift
  - Pastel/Views/Onboarding/OnboardingView.swift
  - Pastel/Views/Settings/GeneralSettingsView.swift
autonomous: true
requirements: [QUICK-34]

must_haves:
  truths:
    - "Clicking an item in the panel pastes it into the previous app without showing a permission prompt (when accessibility IS granted)"
    - "Cmd+Shift+1-9 hotkeys paste items without showing a permission prompt (when accessibility IS granted)"
    - "When accessibility is NOT granted, clicking items copies to clipboard and shows the prompt exactly once"
    - "After granting accessibility in System Settings, the app detects it within 1-2 seconds without a restart"
  artifacts:
    - path: "Pastel/Services/AccessibilityService.swift"
      provides: "Non-caching permission check using CGEventTapCreate probe"
      contains: "CGEventTapCreate"
    - path: "Pastel/Services/PasteService.swift"
      provides: "Paste flow that passes when accessibility is granted"
  key_links:
    - from: "AccessibilityService.isGranted"
      to: "CGEventTapCreate"
      via: "live kernel-level probe (not AXIsProcessTrusted/CGPreflightPostEventAccess)"
      pattern: "CGEventTapCreate"
    - from: "PasteService.paste"
      to: "AccessibilityService.isGranted"
      via: "guard check before CGEvent simulation"
      pattern: "AccessibilityService.isGranted"
---

<objective>
Fix paste-via-hotkeys and paste-via-click being broken despite accessibility permission being granted.

Purpose: The root cause is that both `AXIsProcessTrusted()` and `CGPreflightPostEventAccess()` cache their return value per-process on macOS 26. Once either returns `false` at startup (before the user grants permission), they continue returning `false` for the entire app lifetime — even after the user grants permission in System Settings. The permission check in `PasteService.paste()` therefore always blocks paste, regardless of what the user has done in System Settings.

Additionally: the stash `stash@{0}` (labeled "accessibility perms iteration") contains a partially-correct fix that was started but never committed. It replaces `isGranted`/`refreshPermissionState()` at call sites but does NOT fix the underlying `isGranted` implementation (still uses the caching APIs). The stash's `AccessibilityService.swift` is the right direction but needs `CGEventTapCreate` replacing the caching API calls. This task applies the correct complete fix.

Output: Rebuilt `AccessibilityService.swift` using `CGEventTapCreate` as a live permission probe + `DistributedNotificationCenter("com.apple.accessibility.api")` for instant detection. Paste works immediately after permission is granted, without restart.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/debug/accessibility-permission-not-detected.md
@.planning/debug/accessibility-permission-inverted.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix AccessibilityService with non-caching CGEventTapCreate probe</name>
  <files>Pastel/Services/AccessibilityService.swift</files>
  <action>
Completely rewrite `AccessibilityService` to replace the two caching API calls (`AXIsProcessTrusted()` and `CGPreflightPostEventAccess()`) with a `CGEventTapCreate` probe. The `CGEventTapCreate` approach is the only documented non-caching permission check for sandboxed macOS apps (confirmed in `.planning/debug/accessibility-permission-not-detected.md`).

The new implementation:

1. `isGranted` computed property: Creates a temporary passive event tap using `CGEventTapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: 0, callback: ..., userInfo: nil)`. If it returns non-nil, permission is granted; if nil, not granted. Immediately call `CGEventTapEnable(tap, false)` and CFRelease equivalent (the tap goes out of scope so ARC handles it). This is a live kernel check — NOT cached per-process.

   ```swift
   static var isGranted: Bool {
       guard let tap = CGEventTapCreate(
           tap: .cgSessionEventTap,
           place: .headInsertEventTap,
           options: .listenOnly,
           eventsOfInterest: CGEventMask(0),
           callback: { _, _, event, _ in return Unmanaged.passRetained(event) },
           userInfo: nil
       ) else {
           return false
       }
       // Immediately disable and release — we only needed the creation to succeed
       CGEventTapEnable(tap, false)
       return true
   }
   ```

2. `refreshPermissionState()` method: Delegates to `isGranted` (no separate cache needed since CGEventTapCreate is the probe itself). Keep this method so all the existing call sites that already use it (in the stash) continue to work.

3. `requestPermission()`: Keep as-is using `CGRequestPostEventAccess()`.

4. `openAccessibilitySettings()`: Keep as-is.

5. `startListeningForPermissionChanges()`: Add a `DistributedNotificationCenter.default().addObserver` for `"com.apple.accessibility.api"` that logs when TCC accessibility changes. This is purely a supplementary signal — the `isGranted` probe already works without it, but it provides a hook for future optimization. Keep the app reactivation observer too (already in the stash).

   Important: Use `nonisolated(unsafe)` for the static observer variables since `@MainActor` enum members cannot store `NSObjectProtocol?` directly across isolation domains.

Keep the `@MainActor` attribute on the enum — it's correct and all callers are already on the main actor.

NOTE: The existing stash (`stash@{0}: "accessibility perms iteration"`) replaces `.isGranted` with `.refreshPermissionState()` at call sites in PasteService, AccessibilityRequiredView, OnboardingView, GeneralSettingsView, and PastelApp. Pop the stash after fixing `AccessibilityService.swift` so those call-site changes apply. The stash does NOT fix `AccessibilityService.swift` itself — that's what this task does.
  </action>
  <verify>Build succeeds with `xcodebuild -scheme "Pastel Sparkle" -configuration Debug-Sparkle build 2>&1 | tail -5`. No compile errors.</verify>
  <done>Build passes. `AccessibilityService.isGranted` uses `CGEventTapCreate` instead of `AXIsProcessTrusted`/`CGPreflightPostEventAccess`.</done>
</task>

<task type="auto">
  <name>Task 2: Apply stash and wire startListeningForPermissionChanges at startup</name>
  <files>
    Pastel/Services/PasteService.swift
    Pastel/PastelApp.swift
    Pastel/Views/Onboarding/AccessibilityRequiredView.swift
    Pastel/Views/Onboarding/OnboardingView.swift
    Pastel/Views/Settings/GeneralSettingsView.swift
  </files>
  <action>
Pop the stash `stash@{0}` to apply the call-site changes that replace `.isGranted` with `.refreshPermissionState()` at all timer-poll and paste-action sites:

```bash
git stash pop
```

This applies:
- `PasteService.swift`: `paste()` and `pastePlainText()` guard uses `refreshPermissionState()` — ensures a live probe at every paste attempt.
- `AccessibilityRequiredView.swift`: `onAppear` and `onReceive` use `refreshPermissionState()`.
- `OnboardingView.swift`: `onReceive` uses `refreshPermissionState()`.
- `GeneralSettingsView.swift`: `onReceive` uses `refreshPermissionState()`.
- `PastelApp.swift`: Adds `AccessibilityService.startListeningForPermissionChanges()` call after `state.setupPanel()`.

If the stash pop has conflicts (unlikely since only `AccessibilityService.swift` was changed in Task 1 and the stash only touches that file plus call sites), resolve by keeping Task 1's version of `AccessibilityService.swift` and accepting the stash changes for the other files.

After popping, verify no compile errors remain.

ALSO verify the `PasteBehavior` default alignment: `PasteService.swift` defaults to `.paste` when UserDefaults key is missing (`?? PasteBehavior.paste.rawValue`), while UI views default to `.copy`. This means a user who never visited Settings has `.paste` behavior in practice. This is fine and intentional (the stash doesn't change it), but note it in the summary.
  </action>
  <verify>Build succeeds: `xcodebuild -scheme "Pastel Sparkle" -configuration Debug-Sparkle build 2>&1 | tail -5`. Check that `PastelApp.swift` contains `AccessibilityService.startListeningForPermissionChanges()` and `PasteService.swift` uses `refreshPermissionState()` in both guard blocks.</verify>
  <done>Build passes. All six files updated. `startListeningForPermissionChanges()` called at app startup. Paste guard uses `refreshPermissionState()` (which calls `CGEventTapCreate` live probe) at every paste attempt.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <what-built>Fixed accessibility permission detection. `isGranted` now uses `CGEventTapCreate` as a live kernel probe instead of the caching `AXIsProcessTrusted`/`CGPreflightPostEventAccess` APIs. Paste flow re-probes permission on every click/hotkey activation.</what-built>
  <how-to-verify>
1. Build and run the Pastel Sparkle scheme in Xcode.
2. Open System Settings > Privacy & Security > Accessibility. If Pastel is listed, REMOVE it (to start from a denied state). Quit Pastel and relaunch.
3. Open the panel (Cmd+Shift+V). Click any item. Confirm: item is copied to clipboard and the "Accessibility Permission Needed" prompt appears. Do NOT grant it yet.
4. In System Settings > Privacy & Security > Accessibility, add/enable Pastel. Switch back to Pastel within 2 seconds. Confirm: the permission indicator in the prompt turns green and the prompt auto-dismisses. No restart needed.
5. Open the panel again. Click any item. Confirm: the item is pasted directly into the previous app (no permission prompt this time).
6. With the panel open, press Cmd+Shift+1. Confirm: the first item is pasted directly (no prompt).
7. Type "approved" if all steps worked, or describe which step failed.
  </how-to-verify>
  <resume-signal>Type "approved" or describe the failure step</resume-signal>
</task>

</tasks>

<verification>
- `AccessibilityService.isGranted` uses `CGEventTapCreate` (grep confirms: `grep -n "CGEventTapCreate" Pastel/Services/AccessibilityService.swift`)
- `AXIsProcessTrusted` and `CGPreflightPostEventAccess` do NOT appear in `AccessibilityService.swift` (grep returns nothing)
- `PasteService.paste()` calls `refreshPermissionState()` not `.isGranted` directly
- Build succeeds for Pastel Sparkle Debug-Sparkle scheme
- Human confirms paste works without restart after granting permission
</verification>

<success_criteria>
- Clicking items in panel pastes correctly when accessibility is granted (no spurious prompt)
- Cmd+Shift+1-9 hotkeys paste correctly when accessibility is granted
- Granting permission in System Settings is detected within ~1-2 seconds without restart
- When accessibility is NOT granted, copy-to-clipboard fallback still works and prompt appears
</success_criteria>

<output>
After completion, create `.planning/quick/34-research-why-pastel-paste-via-hotkeys-an/34-SUMMARY.md`
</output>
