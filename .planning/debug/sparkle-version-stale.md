---
status: verifying
trigger: "Sparkle shows 1.0.12 is newest when 1.0.14 exists"
created: 2026-02-25T00:00:00Z
updated: 2026-02-25T00:03:00Z
---

## Current Focus

hypothesis: CONFIRMED ROOT CAUSE - fixed
test: User needs to click "Check for Updates" to verify update detection
expecting: Sparkle should now detect v1.0.14 and offer update
next_action: Present resolution to user and ask them to verify

## Symptoms

expected: Sparkle should detect version 1.0.14 as available and offer to update
actual: Sparkle says 1.0.12 is the newest version available (user is running 1.0.12)
errors: No error messages — Sparkle simply reports current version is newest
reproduction: Click "Check for Updates" menu item — always says 1.0.12 is newest
started: Always shows 1.0.12, has never successfully found 1.0.13 or 1.0.14

## Eliminated

- hypothesis: SUFeedURL points to wrong location
  evidence: URL resolves correctly to appcast.xml with valid content
  timestamp: 2026-02-25T00:00:30Z

- hypothesis: Appcast XML is missing 1.0.14 entry
  evidence: Live appcast has sparkle:version=4, sparkle:shortVersionString=1.0.14
  timestamp: 2026-02-25T00:00:30Z

- hypothesis: Sparkle EdDSA signature mismatch blocking update
  evidence: SURequireSignedFeed is not set, so feed signing is not validated
  timestamp: 2026-02-25T00:01:00Z

- hypothesis: Network/sandbox blocking appcast fetch
  evidence: com.apple.security.network.client entitlement present, URL reachable with 200 OK
  timestamp: 2026-02-25T00:01:00Z

- hypothesis: SUSkippedVersion blocking update
  evidence: No SUSkippedVersion in UserDefaults
  timestamp: 2026-02-25T00:01:00Z

- hypothesis: Sparkle version comparison logic is wrong
  evidence: Tested SUStandardVersionComparator: "1" vs "4" = ASCENDING (update available)
  timestamp: 2026-02-25T00:01:30Z

## Evidence

- timestamp: 2026-02-25T00:00:20Z
  checked: Info.plist SUFeedURL
  found: Points to https://raw.githubusercontent.com/phulsechinmay/pastel/appcast/appcast.xml
  implication: Feed URL is correct

- timestamp: 2026-02-25T00:00:25Z
  checked: Live appcast XML (curl)
  found: Single item - sparkle:version=4, sparkle:shortVersionString=1.0.14
  implication: Appcast has correct latest version NOW

- timestamp: 2026-02-25T00:00:30Z
  checked: project.yml version at each release tag
  found: v1.0.10/11/12 all had CURRENT_PROJECT_VERSION=1. v1.0.13 had BUILD=3 in project.yml but pbxproj still had 1
  implication: project.yml was bumped manually but pbxproj was never regenerated

- timestamp: 2026-02-25T00:00:35Z
  checked: pbxproj at each tag
  found: CURRENT_PROJECT_VERSION=1 at ALL tags (v1.0.10-v1.0.14). Never updated.
  implication: Xcode always built with CFBundleVersion=1 unless overridden via xcodebuild CLI

- timestamp: 2026-02-25T00:00:40Z
  checked: v1.0.12 DMG Info.plist (mounted from GitHub release)
  found: CFBundleVersion=1, CFBundleShortVersionString=1.0.12
  implication: Running app has build number 1

- timestamp: 2026-02-25T00:00:45Z
  checked: v1.0.13 DMG Info.plist (mounted from GitHub release)
  found: CFBundleVersion=1, CFBundleShortVersionString=1.0.13
  implication: v1.0.13 ALSO had build number 1 - old script had no override

- timestamp: 2026-02-25T00:00:50Z
  checked: v1.0.14 DMG Info.plist (mounted from GitHub release)
  found: CFBundleVersion=4, CFBundleShortVersionString=1.0.14
  implication: v1.0.14 correctly has build 4 (new script with override was used)

- timestamp: 2026-02-25T00:00:55Z
  checked: build-release.sh git status
  found: Working copy has 29 added lines vs committed version. Adds auto-increment, CURRENT_PROJECT_VERSION override, and appcast branch deployment.
  implication: Critical build improvements exist only locally, not committed

- timestamp: 2026-02-25T00:01:00Z
  checked: Appcast branch history
  found: v1.0.11/12/13 appcasts all had sparkle:version=1. v1.0.14 appcast has sparkle:version=4.
  implication: All prior appcasts matched running app's build number = no update detected

- timestamp: 2026-02-25T00:01:10Z
  checked: Timeline analysis
  found: v1.0.14 appcast pushed at 06:30:03 UTC. SULastCheckTime is 06:31:26 UTC (83s later). CDN cache is 300s.
  implication: Last check hit CDN-cached v1.0.13 appcast (sparkle:version=1, same as running app)

- timestamp: 2026-02-25T00:02:00Z
  checked: Committed Info.plist vs working copy
  found: Committed SUFeedURL has typo "pulsechinmay" instead of "phulsechinmay" pointing to wrong repo entirely
  implication: If app were built from committed source without the local fix, Sparkle would fetch from wrong URL

## Resolution

root_cause: |
  Multi-factor failure preventing Sparkle update detection:

  1. PRIMARY: CURRENT_PROJECT_VERSION stuck at 1 in pbxproj for ALL releases (v1.0.5 through v1.0.14).
     project.yml was manually bumped but pbxproj was never synced. The committed build-release.sh
     did not pass CURRENT_PROJECT_VERSION override to xcodebuild. All DMGs through v1.0.13 had
     CFBundleVersion=1. The running v1.0.12 also has CFBundleVersion=1. All appcast entries
     through v1.0.13 had sparkle:version=1. Sparkle compared 1==1 = "up to date".

  2. SECONDARY: CDN caching. v1.0.14 was correctly built (CFBundleVersion=4) using the locally
     modified build script, but the user's last check (83 seconds after appcast push) hit the
     CDN-cached v1.0.13 appcast (sparkle:version=1).

  3. TERTIARY: Uncommitted improvements to build-release.sh (auto-increment build number,
     CURRENT_PROJECT_VERSION xcodebuild override, appcast branch auto-deployment).

  4. BONUS: Committed Info.plist has wrong SUFeedURL (typo in username). Only works because
     builds used the locally-modified Info.plist.

fix: |
  1. Updated pbxproj CURRENT_PROJECT_VERSION from 1 to 4 (synced with project.yml)
  2. build-release.sh improvements already in working tree (need commit)
  3. Info.plist SUFeedURL fix already in working tree (need commit)
  4. CDN cache has long expired - next check should detect v1.0.14

verification: |
  - Confirmed live appcast has sparkle:version=4 via curl
  - Confirmed installed app has CFBundleVersion=1 and correct SUFeedURL
  - Tested version comparison: "1" vs "4" = ASCENDING (update available)
  - CDN cache (max-age=300) expired hours ago, serving fresh content
  - User should verify by clicking "Check for Updates" in Pastel menu bar

files_changed:
  - Pastel.xcodeproj/project.pbxproj (CURRENT_PROJECT_VERSION 1 -> 4)
