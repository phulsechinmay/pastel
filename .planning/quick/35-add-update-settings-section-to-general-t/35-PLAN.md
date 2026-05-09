---
phase: 35-add-update-settings-section-to-general-t
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Services/UpdaterService.swift
  - Pastel/Views/Settings/GeneralSettingsView.swift
  - Pastel/Views/Settings/SettingsWindowController.swift
autonomous: false
requirements:
  - QUICK-35
must_haves:
  truths:
    - "General Settings tab shows an 'Updates' section (Sparkle build only)"
    - "Section contains a dropdown with three modes: Manual / Auto-check + notify / Auto-update"
    - "Selecting a mode updates SPUUpdater.automaticallyChecksForUpdates and .automaticallyDownloadsUpdates accordingly"
    - "Selection persists across app launches"
    - "Dropdown reflects current SPUUpdater state when Settings opens"
    - "Section also exposes a 'Check for Updates Now' button that triggers an immediate check"
    - "App Store builds (no SPARKLE flag) compile cleanly and do NOT show the Updates section"
  artifacts:
    - path: "Pastel/Services/UpdaterService.swift"
      provides: "UpdateCheckMode enum + computed mode property bound to SPUUpdater"
      contains: "enum UpdateCheckMode"
    - path: "Pastel/Views/Settings/GeneralSettingsView.swift"
      provides: "Updates section UI (dropdown + check now button), gated by #if SPARKLE"
      contains: "Updates"
    - path: "Pastel/Views/Settings/SettingsWindowController.swift"
      provides: "Inject updaterService into SettingsView for SPARKLE builds"
      contains: "updaterService"
  key_links:
    - from: "GeneralSettingsView updateMode binding"
      to: "UpdaterService.updateMode setter"
      via: "@EnvironmentObject UpdaterService (SPARKLE only)"
      pattern: "updaterService\\.updateMode"
    - from: "UpdaterService.updateMode"
      to: "SPUUpdater.automaticallyChecksForUpdates / automaticallyDownloadsUpdates"
      via: "controller.updater property writes"
      pattern: "automaticallyChecksForUpdates|automaticallyDownloadsUpdates"
    - from: "SettingsWindowController.showSettings"
      to: "SettingsView environment"
      via: ".environmentObject(updaterService) under #if SPARKLE"
      pattern: "environmentObject.*updaterService"
---

<objective>
Add an "Updates" section to the General Settings tab that lets the user pick one of three Sparkle update modes (manual / auto-check + notify / auto-download + install) and trigger an immediate update check. Wire up to the already-integrated `UpdaterService` so user-visible state stays in sync with `SPUUpdater` runtime properties.

Purpose: Give users control over update behavior without leaving Pastel — currently the only update UI is "Check for Updates" in the menu bar popover.
Output: A new collapsible-free, plain section in the existing General Settings tab. Sparkle-build-only (`#if SPARKLE`). App Store builds remain unaffected.

Notes for executor:
- Sparkle is already integrated. Do NOT add SPM packages, entitlements, or Info.plist keys — they are already in place (`SUFeedURL`, `SUPublicEDKey`, `SUEnableInstallerLauncherService`, mach-lookup exceptions in `Pastel-Sparkle.entitlements`).
- The user said "DO NOT COMMIT THIS UNTIL I REVIEW". The executor will still create per-task commits per GSD norm; user will review before pushing. Make commit messages clear so they're easy to amend/squash if needed.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md

# Existing Sparkle integration (read these before editing)
@Pastel/Services/UpdaterService.swift
@Pastel/PastelApp.swift
@Pastel/Views/MenuBar/CheckForUpdatesView.swift
@Pastel/Views/MenuBar/StatusPopoverView.swift

# Settings UI to extend
@Pastel/Views/Settings/GeneralSettingsView.swift
@Pastel/Views/Settings/SettingsView.swift
@Pastel/Views/Settings/SettingsWindowController.swift

# Build configuration (SPARKLE flag, entitlements)
@project.yml
@Pastel/Resources/Info.plist
@Pastel/Resources/Pastel-Sparkle.entitlements

# Sparkle SPUUpdater API reference (for property names):
# - automaticallyChecksForUpdates: Bool   — SUEnableAutomaticChecks at runtime
# - automaticallyDownloadsUpdates: Bool   — SUAutomaticallyUpdate at runtime
# - canCheckForUpdates: Bool              — already exposed via UpdaterService
# - checkForUpdates()                     — already exposed via UpdaterService
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add UpdateCheckMode + mode property to UpdaterService</name>
  <files>Pastel/Services/UpdaterService.swift</files>
  <action>
Inside the existing `#if SPARKLE` block in `Pastel/Services/UpdaterService.swift`, add:

1. A top-level enum `UpdateCheckMode: String, CaseIterable, Identifiable` with three cases:
   - `.manual` — display name "Manual checks only"
   - `.checkAndNotify` — display name "Automatically check and notify"
   - `.autoInstall` — display name "Automatically download and install"
   Add `var id: String { rawValue }` and `var displayName: String { ... }` (switch on self).

2. Make `UpdaterService` conform to `ObservableObject` (already does) and add a `@Published var updateMode: UpdateCheckMode` stored property. Initialize it from the current `SPUUpdater` properties inside `init()` AFTER `self.controller` is created:
   ```swift
   let updater = self.controller.updater
   if !updater.automaticallyChecksForUpdates {
       self.updateMode = .manual
   } else if updater.automaticallyDownloadsUpdates {
       self.updateMode = .autoInstall
   } else {
       self.updateMode = .checkAndNotify
   }
   ```
   (Use a temp `let` so you don't write to `self` before `super.init` semantics — `UpdaterService` has no superclass other than `NSObject`/none, so direct assignment is fine in Swift class init.)

3. Add a method `func applyUpdateMode(_ mode: UpdateCheckMode)` that writes through to Sparkle:
   ```swift
   switch mode {
   case .manual:
       controller.updater.automaticallyChecksForUpdates = false
       controller.updater.automaticallyDownloadsUpdates = false
   case .checkAndNotify:
       controller.updater.automaticallyChecksForUpdates = true
       controller.updater.automaticallyDownloadsUpdates = false
   case .autoInstall:
       controller.updater.automaticallyChecksForUpdates = true
       controller.updater.automaticallyDownloadsUpdates = true
   }
   self.updateMode = mode
   ```

4. Use a `didSet` on `updateMode` is tempting but creates a setter loop with the SwiftUI binding — DO NOT use didSet. Instead, the View calls `applyUpdateMode` from an `onChange` handler.

Why: Sparkle persists `automaticallyChecksForUpdates` and `automaticallyDownloadsUpdates` to UserDefaults under its own keys (`SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`) automatically — no separate `@AppStorage` needed. We only mirror it into `@Published` so SwiftUI can bind.

Keep all existing code (controller init, KVO publisher for `canCheckForUpdates`, `startUpdater`, `checkForUpdates`) intact. Whole file remains inside the existing `#if SPARKLE` / `#endif`.
  </action>
  <verify>
Build the Sparkle scheme:
```
xcodebuild -project Pastel.xcodeproj -scheme "Pastel Sparkle" -configuration Debug-Sparkle build 2>&1 | tail -30
```
Must compile with no errors. Also build the AppStore scheme to confirm conditional compilation still excludes the file cleanly:
```
xcodebuild -project Pastel.xcodeproj -scheme "Pastel AppStore" -configuration Debug build 2>&1 | tail -30
```
  </verify>
  <done>
- `UpdateCheckMode` enum exists with three cases and displayNames
- `UpdaterService.updateMode` is `@Published` and initialized from current SPUUpdater state
- `applyUpdateMode(_:)` writes both `automaticallyChecksForUpdates` and `automaticallyDownloadsUpdates`
- Both build configurations compile cleanly
- Entire change is inside `#if SPARKLE`
  </done>
</task>

<task type="auto">
  <name>Task 2: Add Updates section to GeneralSettingsView + inject UpdaterService into Settings window</name>
  <files>
Pastel/Views/Settings/GeneralSettingsView.swift
Pastel/Views/Settings/SettingsWindowController.swift
  </files>
  <action>
**Part A — `SettingsWindowController.swift`:**

The settings window currently does NOT receive `updaterService` (only the menu bar popover does). Inject it.

1. At the top of the file, add `#if SPARKLE` import for the type, but the property itself can use `Any?`-style erasure to avoid type leaks. Simpler: gate just the property and the injection.

2. Add a property:
   ```swift
   #if SPARKLE
   var updaterService: UpdaterService?
   #endif
   ```

3. In `showSettings(modelContainer:appState:initialTab:)`, modify the `settingsView` chain so that under `#if SPARKLE`, the view also gets `.environmentObject(updaterService)` when non-nil. Pattern:
   ```swift
   var rootView: some View {
       let base = SettingsView(initialTab: initialTab)
           .preferredColorScheme(.dark)
           .modelContainer(modelContainer)
           .environment(appState)
           .environment(syncMonitor)
       #if SPARKLE
       if let updaterService {
           return AnyView(base.environmentObject(updaterService))
       }
       #endif
       return AnyView(base)
   }
   ```
   Use this computed result in `NSHostingView(rootView:)`. (If `AnyView` feels heavy, an alternative is to use `Group { #if SPARKLE ... #else ... #endif }` — pick whichever compiles cleanest. Goal: no AnyView in hot paths is fine, this is one-time on window open.)

4. In `PastelApp.swift` `init()`, after the `#if SPARKLE` block that creates `updaterService`, you'll wire `SettingsWindowController.shared.updaterService = updaterService`. BUT — `updaterService` is a `@StateObject` declared at struct scope, and `_updaterService` cannot be safely accessed in `init()`. Solution: assign after first read inside `body` is too late. Best path: inject from a `.task` or `.onAppear` on `MenuBarExtra` content. Actually, since `SettingsWindowController.shared` is a singleton and the assignment must happen before user opens Settings, do this in `StatusPopoverView` (which already has `@EnvironmentObject var updaterService`) inside an `.onAppear { SettingsWindowController.shared.updaterService = updaterService }`. Add that single-line `.onAppear` in `StatusPopoverView` under `#if SPARKLE`.

   Note for executor: Read `Pastel/Views/MenuBar/StatusPopoverView.swift` first to find the right place for `.onAppear`. If `StatusPopoverView` is the root of `MenuBarExtra` body, attach to its top-level container.

**Part B — `GeneralSettingsView.swift`:**

Add a new section between the existing "URL Previews" section (item #6) and the "Data" section (item #7). Match the existing visual pattern: heading via `Text(...).font(.headline)`, descriptive `Text(...).font(.caption).foregroundStyle(.secondary)`, `Picker` with `.pickerStyle(.menu)` and `.frame(maxWidth:)`.

Wrap the entire new section in `#if SPARKLE`. Inside it:

1. Add `@EnvironmentObject private var updaterService: UpdaterService` near the other property wrappers (also gated by `#if SPARKLE`).

2. Add the section block:
   ```swift
   #if SPARKLE
   Divider()

   VStack(alignment: .leading, spacing: 6) {
       Text("Updates")
           .font(.headline)
       Picker("Update behavior:", selection: Binding(
           get: { updaterService.updateMode },
           set: { updaterService.applyUpdateMode($0) }
       )) {
           ForEach(UpdateCheckMode.allCases) { mode in
               Text(mode.displayName).tag(mode)
           }
       }
       .pickerStyle(.menu)
       .frame(maxWidth: 320)

       Text("Pastel uses Sparkle to deliver updates outside the App Store.")
           .font(.caption)
           .foregroundStyle(.secondary)

       HStack {
           Button("Check for Updates Now") {
               updaterService.checkForUpdates()
           }
           .disabled(!updaterService.canCheckForUpdates)
           .buttonStyle(.bordered)
           .controlSize(.small)
       }
       .padding(.top, 4)
   }
   #endif
   ```

3. Place this BEFORE the existing `Divider()` that precedes the Data section, so the order becomes: ... URL Previews → Divider → Updates → Divider → Data.

DO NOT touch any other section. DO NOT add SUEnableDownloaderService to Info.plist (downloader service is only required if you bundle a custom downloader; default in-process downloader works for sandboxed apps that have `SUEnableInstallerLauncherService` true — which is already set).

DO NOT add `@AppStorage` for the mode — Sparkle's own UserDefaults keys handle persistence. Adding a parallel `@AppStorage` would create drift.
  </action>
  <verify>
1. Sparkle build:
```
xcodebuild -project Pastel.xcodeproj -scheme "Pastel Sparkle" -configuration Debug-Sparkle build 2>&1 | tail -30
```
2. App Store build (must compile without UpdaterService):
```
xcodebuild -project Pastel.xcodeproj -scheme "Pastel AppStore" -configuration Debug build 2>&1 | tail -30
```
3. Both must succeed with zero errors. Warnings about unused imports under one config are acceptable but try to keep clean.
  </verify>
  <done>
- New "Updates" section exists in General tab between "URL Previews" and "Data"
- Section is gated by `#if SPARKLE` and invisible in App Store builds
- Picker has 3 modes, bound through `updaterService.updateMode` ↔ `applyUpdateMode`
- "Check for Updates Now" button calls `updaterService.checkForUpdates()` and disables when `!canCheckForUpdates`
- `SettingsWindowController` injects `updaterService` into the Settings window
- `StatusPopoverView` (or equivalent early site) sets `SettingsWindowController.shared.updaterService` once
- Both Sparkle and AppStore configurations build cleanly
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: Manual verification of update mode UI</name>
  <what-built>
Updates section in General Settings (Sparkle build only) with a 3-option dropdown bound to Sparkle's runtime settings, plus a "Check for Updates Now" button.
  </what-built>
  <how-to-verify>
1. Run the Pastel Sparkle scheme from Xcode (Cmd+R with the "Pastel Sparkle" scheme selected).
2. Open the menu bar icon → click the gear/Settings button (or use the keyboard shortcut for Settings) to open Pastel Settings.
3. Confirm you land on the General tab.
4. Scroll to verify a new "Updates" section appears between "URL Previews" and "Data".
5. Open the dropdown — confirm three options:
   - Manual checks only
   - Automatically check and notify
   - Automatically download and install
6. Pick each option in turn. After each selection, fully quit Pastel (menu bar icon → Quit) and relaunch the same scheme. Reopen Settings. The dropdown must reflect the previously chosen mode (Sparkle persists this in UserDefaults automatically).
7. Click "Check for Updates Now". A Sparkle window should appear (it may say "You're up to date" or show an error if appcast.xml is unreachable — both prove the call is wired). Button must be disabled while a check is already in progress.
8. Switch to the "Pastel AppStore" scheme, build and run. Open Settings → General. Confirm the "Updates" section is NOT present (no Picker, no button, no extra divider). The other sections (Startup, Hotkey, Panel Position, History Retention, Paste Behavior, URL Previews, Data) must still render correctly.
9. Visual: spacing, font sizes, and divider rhythm should match neighboring sections (compare to "URL Previews" above and "Data" below).

If anything looks off (extra padding, wrong font, AppStore build shows the section, dropdown does not persist), report it before approving.

User reminder: do NOT push to remote until explicit approval. Per-task commits are fine and expected.
  </how-to-verify>
  <resume-signal>Type "approved" to mark complete, or describe issues to address.</resume-signal>
</task>

</tasks>

<verification>
- Both build configurations (`Debug-Sparkle`, `Debug` for AppStore) compile.
- Manual verification of all three modes persists across relaunch.
- "Check for Updates Now" triggers a real Sparkle check.
- AppStore build does not show the Updates section and does not reference Sparkle types.
</verification>

<success_criteria>
- User can choose one of three update behaviors in General Settings (Sparkle build).
- Choice is honored by Sparkle on next scheduled check.
- Choice survives app restart.
- Manual "Check for Updates Now" works on demand.
- App Store builds remain entirely unaffected.
</success_criteria>

<output>
After completion, create `.planning/quick/35-add-update-settings-section-to-general-t/35-SUMMARY.md` with:
- What changed (3 files modified, list each)
- Mapping table (mode → SPUUpdater properties)
- Build verification output (both schemes)
- Manual verification notes from human
- Reminder: user has not yet approved push to remote.
</output>
