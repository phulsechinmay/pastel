---
phase: 25-ota-updates-with-sparkle
plan: 01
subsystem: infra
tags: [sparkle, xcodegen, dual-distribution, entitlements, build-configs]

requires:
  - phase: none
    provides: existing project.yml and entitlements
provides:
  - Dual-distribution build system (App Store vs Sparkle/DMG)
  - Sparkle SPM dependency integrated
  - SPARKLE compilation condition for conditional compilation
  - Sparkle-specific entitlements with XPC mach-lookup
  - Post-build script to strip Sparkle from App Store builds
affects: [25-02, sparkle-integration, conditional-compilation]

tech-stack:
  added: [Sparkle 2.8.0+]
  patterns: [configVariants dual-scheme, per-config entitlements, post-build framework stripping]

key-files:
  created:
    - Pastel/Resources/Pastel-Sparkle.entitlements
  modified:
    - project.yml
    - Pastel/Resources/Info.plist

key-decisions:
  - "configVariants generates Pastel AppStore and Pastel Sparkle schemes (replaces single Pastel scheme)"
  - "SUPublicEDKey placeholder in Info.plist -- user replaces after running generate_keys"
  - "SUFeedURL points to GitHub raw appcast.xml (placeholder repo URL)"

patterns-established:
  - "SPARKLE compilation condition: wrap all Sparkle-dependent code in #if SPARKLE"
  - "Dual entitlements: Pastel.entitlements (App Store) vs Pastel-Sparkle.entitlements (DMG)"

duration: 2min
completed: 2026-02-20
---

# Phase 25 Plan 01: Build System Configuration Summary

**Dual-distribution xcodegen setup with 4 build configs, Sparkle SPM dependency, conditional compilation flag, and separate entitlements for App Store vs DMG builds**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-21T03:47:42Z
- **Completed:** 2026-02-21T03:49:45Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Four build configurations (Debug/Release x AppStore/Sparkle) with two xcodegen-generated schemes
- SPARKLE active compilation condition set exclusively on Sparkle configs
- Sparkle entitlements file with XPC mach-lookup for sandboxed installer service
- Post-build script strips Sparkle.framework from App Store builds (Guideline 2.5.2 compliance)
- Info.plist configured with SUFeedURL, SUPublicEDKey placeholder, and SUEnableInstallerLauncherService

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Sparkle SPM dependency and xcodegen configVariants** - `491770c` (feat)
2. **Task 2: Create Sparkle entitlements and add Info.plist keys** - `159875a` (feat)

## Files Created/Modified
- `project.yml` - Added 4 configs, Sparkle package, configVariants, per-config settings, post-build strip script
- `Pastel/Resources/Pastel-Sparkle.entitlements` - Base entitlements plus XPC mach-lookup for Sparkle installer
- `Pastel/Resources/Info.plist` - Added SUFeedURL, SUPublicEDKey, SUEnableInstallerLauncherService

## Decisions Made
- configVariants replaces the single "Pastel" scheme with "Pastel AppStore" and "Pastel Sparkle" schemes
- SUPublicEDKey uses placeholder string -- user must run Sparkle generate_keys and replace
- SUFeedURL uses GitHub raw URL (placeholder repo pulsechinmay/pastel-updates)
- Sparkle keys in Info.plist are harmless in App Store builds since no Sparkle code references them

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Cleared SPM cache conflict for Sparkle binary artifact**
- **Found during:** Task 1 verification (xcodebuild -list)
- **Issue:** Stale SPM cache entries for Sparkle binary target caused resolution failure
- **Fix:** Removed cached Sparkle artifacts from DerivedData and SwiftPM cache directories
- **Files modified:** None (cache cleanup only)
- **Verification:** xcodebuild -list succeeded, resolved Sparkle 2.8.1
- **Committed in:** N/A (not a code change)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Cache cleanup necessary for SPM resolution. No scope creep.

## Issues Encountered
None beyond the SPM cache conflict documented above.

## User Setup Required
EdDSA keypair generation required before Sparkle can sign updates. User must:
1. Run generate_keys from Sparkle tools to create EdDSA keypair (stored in Keychain)
2. Copy the public key and replace REPLACE_WITH_EDDSA_PUBLIC_KEY in Info.plist

## Next Phase Readiness
- Build system fully configured for dual distribution
- Ready for Plan 02: Sparkle integration code with conditional compilation (#if SPARKLE)
- SPARKLE compilation condition available for wrapping all Sparkle-dependent code

---
*Phase: 25-ota-updates-with-sparkle*
*Completed: 2026-02-20*
