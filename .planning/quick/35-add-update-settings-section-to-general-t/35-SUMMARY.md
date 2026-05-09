---
phase: 35-add-update-settings-section-to-general-t
plan: 01
subsystem: settings-ui
tags: [sparkle, updates, settings-ui]
requires:
  - Phase 25 (Sparkle integration: SPUStandardUpdaterController, SUFeedURL, entitlements)
provides:
  - UpdateCheckMode enum (manual / checkAndNotify / autoInstall)
  - UpdaterService.updateMode published property
  - UpdaterService.applyUpdateMode(_:) writer
  - Updates section in General Settings (Sparkle build only)
affects:
  - SettingsWindowController (now accepts and injects optional UpdaterService)
  - StatusPopoverView (wires shared.updaterService on first appear)
tech-stack:
  added: []
  patterns:
    - Custom Binding(get:set:) on Picker to call applyUpdateMode side-effect
    - Singleton property hand-off (StatusPopoverView -> SettingsWindowController.shared.updaterService)
    - Conditional .environmentObject injection via AnyView under #if SPARKLE
key-files:
  created: []
  modified:
    - Pastel/Services/UpdaterService.swift
    - Pastel/Views/Settings/GeneralSettingsView.swift
    - Pastel/Views/Settings/SettingsWindowController.swift
    - Pastel/Views/MenuBar/StatusPopoverView.swift
decisions:
  - Mode persistence delegated entirely to Sparkle's own UserDefaults keys (SUEnableAutomaticChecks, SUAutomaticallyUpdate); no parallel @AppStorage to avoid drift
  - No didSet on updateMode — mode writes happen from Picker's Binding.set to prevent setter loop with the binding
  - SettingsWindowController.updaterService set from StatusPopoverView.onAppear (singleton hand-off) instead of PastelApp.init, since @StateObject cannot be safely accessed during struct init
  - Updates section gated by #if SPARKLE at the SwiftUI level (including the Divider above it) so AppStore builds show no extra spacing or empty section
metrics:
  duration: 3m
  tasks: 2 of 2 implementation tasks (Task 3 is human-verify checkpoint, awaiting user)
  files_modified: 4
  completed_date: 2026-05-09
---

# Quick Task 35: Add Updates Section to General Settings Summary

User-controllable Sparkle update behavior (manual / auto-check + notify / auto-download + install) plus an on-demand "Check for Updates Now" button, surfaced in the General Settings tab and gated to Sparkle builds only.

## What Changed

Four files modified:

1. **`Pastel/Services/UpdaterService.swift`** — Added `UpdateCheckMode` enum (3 cases, `Identifiable`, `displayName`), added `@Published var updateMode: UpdateCheckMode` initialized from current `SPUUpdater` state at construction, added `applyUpdateMode(_:)` that writes through to `automaticallyChecksForUpdates` / `automaticallyDownloadsUpdates` and updates the published value. All inside the existing `#if SPARKLE` block.

2. **`Pastel/Views/Settings/GeneralSettingsView.swift`** — Added `@EnvironmentObject private var updaterService: UpdaterService` (gated `#if SPARKLE`). Added a new "Updates" section between "URL Previews" and "Data" with a 3-option `Picker` and a `Check for Updates Now` button. Picker uses a custom `Binding(get:set:)` so selection changes call `applyUpdateMode` directly. The button is `.disabled(!canCheckForUpdates)` so it stays consistent with the menu bar `CheckForUpdatesView`. Whole section (including its leading `Divider`) is `#if SPARKLE`.

3. **`Pastel/Views/Settings/SettingsWindowController.swift`** — Added optional `var updaterService: UpdaterService?` property under `#if SPARKLE`. In `showSettings`, the SwiftUI environment chain now conditionally `.environmentObject(updaterService)` when set. Uses `AnyView` once at window creation — fine for a one-time path, no hot-loop overhead.

4. **`Pastel/Views/MenuBar/StatusPopoverView.swift`** — Added a single line in `.onAppear` (under `#if SPARKLE`) to hand the existing `@EnvironmentObject` `updaterService` to `SettingsWindowController.shared.updaterService`. This is the clean injection site since `StatusPopoverView` is the first view to receive the `@StateObject` from `PastelApp` and `MenuBarExtra` shows it before any Settings interaction.

## Mode Mapping

| `UpdateCheckMode`   | Display name                            | `automaticallyChecksForUpdates` | `automaticallyDownloadsUpdates` |
| ------------------- | --------------------------------------- | ------------------------------- | ------------------------------- |
| `.manual`           | Manual checks only                      | `false`                         | `false`                         |
| `.checkAndNotify`   | Automatically check and notify          | `true`                          | `false`                         |
| `.autoInstall`      | Automatically download and install      | `true`                          | `true`                          |

Persistence is handled entirely by Sparkle, which writes these to `UserDefaults` under `SUEnableAutomaticChecks` and `SUAutomaticallyUpdate` keys.

## Build Verification

| Scheme            | Configuration       | Result                |
| ----------------- | ------------------- | --------------------- |
| Pastel Sparkle    | Debug-Sparkle       | `** BUILD SUCCEEDED **` |
| Pastel AppStore   | Debug-AppStore      | `** BUILD SUCCEEDED **` |

(Both schemes built clean after each task.)

## Commits

| Task | Description                                                           | Commit    |
| ---- | --------------------------------------------------------------------- | --------- |
| 1    | feat(quick-35): add UpdateCheckMode enum and updateMode property      | `57d35b2` |
| 2    | feat(quick-35): add Updates section to General Settings tab           | `14df420` |

No final/aggregate commit was made per user request — they will review the per-task commits before deciding to push.

## Deviations from Plan

None of substance. Two minor implementation choices worth noting:

1. **Plan suggested `Group { #if SPARKLE ... #else ... #endif }` OR `AnyView` for SettingsWindowController.** Used `AnyView` (one-time on window open, not a hot path) — the only place that needs to compose differently is the optional `.environmentObject` modifier, which doesn't exist symmetrically in the `else` branch. `AnyView` keeps both branches type-aligned with minimal ceremony.

2. **Placed the Sparkle-only `Divider()` inside the `#if SPARKLE` block** instead of relying on the existing `Divider()` between URL Previews and Data. This avoids the AppStore build showing two adjacent dividers (one above the now-missing Updates section, one below). Net result: AppStore build sees the original divider rhythm exactly as before.

## Manual Verification (Task 3 — Pending User)

The plan's Task 3 is a `checkpoint:human-verify` gate. Implementation is complete and both build configurations pass. The user must:

1. Run `Pastel Sparkle` scheme from Xcode and open Settings → General.
2. Confirm the new "Updates" section appears between "URL Previews" and "Data".
3. Pick each of the three modes; quit and relaunch; verify the dropdown reflects the chosen mode (Sparkle persistence).
4. Click "Check for Updates Now"; confirm the Sparkle UI appears.
5. Switch to `Pastel AppStore` scheme, build, run, open Settings → General; confirm the "Updates" section is absent and the rest of the tab is unchanged.

## Reminder

User explicitly requested: **DO NOT push to remote** and **do NOT do a final/aggregate commit**. The two per-task commits above are local-only pending user review.

## Self-Check: PASSED

- `57d35b2` exists in `git log`
- `14df420` exists in `git log`
- `Pastel/Services/UpdaterService.swift` modified
- `Pastel/Views/Settings/GeneralSettingsView.swift` modified
- `Pastel/Views/Settings/SettingsWindowController.swift` modified
- `Pastel/Views/MenuBar/StatusPopoverView.swift` modified
- Both build configurations passed `xcodebuild ... build` after each task
