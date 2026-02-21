# Phase 25: OTA Updates with Sparkle - Research

**Researched:** 2026-02-20
**Domain:** macOS OTA updates, Sparkle 2.x framework, conditional compilation, DMG notarization
**Confidence:** HIGH

## Summary

Sparkle 2.x is the de facto standard for OTA updates in macOS apps distributed outside the Mac App Store. The framework supports sandboxed apps via XPC services, uses EdDSA (Ed25519) signing for update verification, and integrates via Swift Package Manager. The current stable version is 2.8.1 with macOS Tahoe compatibility.

The primary challenge for Pastel is that XcodeGen does not support per-configuration conditional SPM dependencies. The recommended approach is to always link Sparkle but use `#if SPARKLE` conditional compilation to strip all Sparkle code paths from App Store builds, combined with a build phase script that removes the embedded Sparkle.framework from non-Sparkle configurations. An alternative (and cleaner) approach is to use separate xcodegen build configurations (`Debug-Sparkle`/`Release-Sparkle` and `Debug-AppStore`/`Release-AppStore`) with the `SPARKLE` Active Compilation Condition set only on the Sparkle variants.

**Primary recommendation:** Add Sparkle 2.8.x via SPM with `configVariants` in xcodegen to create separate Sparkle vs AppStore schemes and configurations, using `SWIFT_ACTIVE_COMPILATION_CONDITIONS: SPARKLE` only on Sparkle configs, and a Run Script phase to strip the framework from AppStore builds.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Sparkle | 2.8.1 | OTA update framework | 8.5k+ GitHub stars, 18 years of development, MIT license, sandbox support |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `generate_keys` | Generate EdDSA keypair for update signing | Once during initial setup |
| `generate_appcast` | Generate appcast.xml from update archives | Every release |
| `xcrun notarytool` | Notarize DMG for Gatekeeper | Every DMG release |
| `xcrun stapler` | Staple notarization ticket to DMG | After notarization |
| `hdiutil` | Create DMG disk image | Every release |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Sparkle | Custom update checker | Sparkle handles delta updates, UI, rollback, signing -- never hand-roll |
| GitHub Pages appcast | Raw GitHub URL appcast | Pages is more reliable but raw URLs work fine for small projects |
| DMG distribution | ZIP distribution | DMG provides better UX with drag-to-Applications, Sparkle supports both |

**Installation (project.yml):**
```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.8.0"
```

## Architecture Patterns

### Recommended Project Structure

```
Pastel/
├── App/
│   └── PastelApp.swift          # #if SPARKLE for updater init
├── Services/
│   └── UpdaterService.swift     # Sparkle wrapper, entirely #if SPARKLE guarded
├── Views/
│   └── CheckForUpdatesView.swift # Menu item, #if SPARKLE guarded
└── Resources/
    ├── Info.plist               # SUFeedURL, SUPublicEDKey, SUEnableInstallerLauncherService
    ├── Pastel.entitlements      # Base entitlements (App Store)
    └── Pastel-Sparkle.entitlements # Extended entitlements with XPC mach-lookup
```

### Pattern 1: Conditional Compilation with `#if SPARKLE`

**What:** Use Swift Active Compilation Conditions to gate all Sparkle code
**When to use:** Every file that touches Sparkle APIs
**Example:**
```swift
// Source: https://www.avanderlee.com/xcode/sparkle-distribution-apps-in-and-out-of-the-mac-app-store/
#if SPARKLE
import Sparkle
#endif

@main
struct PastelApp: App {
    #if SPARKLE
    private let updaterController: SPUStandardUpdaterController

    init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // ... existing init code
    }
    #endif

    var body: some Scene {
        MenuBarExtra { /* ... */ } label: { /* ... */ }
        .menuBarExtraStyle(.window)
        #if SPARKLE
        Settings {
            // Update settings view
        }
        #endif
    }
}
```

### Pattern 2: CheckForUpdatesViewModel (SwiftUI Integration)

**What:** Observable object wrapping Sparkle's `canCheckForUpdates` for SwiftUI
**When to use:** For the "Check for Updates" menu item
**Example:**
```swift
// Source: https://sparkle-project.org/documentation/programmatic-setup/
#if SPARKLE
import Sparkle

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var viewModel: CheckForUpdatesViewModel

    var body: some View {
        Button("Check for Updates...") {
            viewModel.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
#endif
```

### Pattern 3: XcodeGen configVariants for Dual Distribution

**What:** Separate build configurations and schemes for Sparkle vs App Store
**When to use:** In `project.yml` to manage both distribution channels
**Example:**
```yaml
# Source: https://yonaskolb.github.io/XcodeGen/Docs/ProjectSpec.html
configs:
  Debug: debug
  Release: release
  Debug-Sparkle: debug
  Release-Sparkle: release

targets:
  Pastel:
    type: application
    platform: macOS
    scheme:
      configVariants:
        - ""           # generates "Pastel" scheme (App Store)
        - Sparkle      # generates "Pastel Sparkle" scheme
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: app.pastel.Pastel
        # ... existing settings
      configs:
        Debug-Sparkle:
          SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) SPARKLE"
          CODE_SIGN_ENTITLEMENTS: Pastel/Resources/Pastel-Sparkle.entitlements
        Release-Sparkle:
          SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) SPARKLE"
          CODE_SIGN_ENTITLEMENTS: Pastel/Resources/Pastel-Sparkle.entitlements
    dependencies:
      - package: Sparkle
      # ... other dependencies
```

### Pattern 4: Strip Sparkle from Non-Sparkle Builds (Build Phase Script)

**What:** Run script that removes embedded Sparkle.framework from App Store builds
**When to use:** As a build phase in xcodegen
**Example:**
```yaml
# In project.yml target
postBuildScripts:
  - script: |
      if [[ "$CONFIGURATION" == *"Sparkle"* ]]; then
        echo "Sparkle build — keeping Sparkle.framework"
      else
        echo "App Store build — removing Sparkle.framework"
        rm -rf "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/Sparkle.framework"
        rm -rf "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/Sparkle_XPCServices.framework" 2>/dev/null || true
      fi
    name: "Strip Sparkle from App Store Builds"
```

### Anti-Patterns to Avoid
- **Linking Sparkle unconditionally without stripping:** App Store review will reject apps that contain Sparkle (Guideline 2.5.2)
- **Using `codesign --deep`:** Breaks Sparkle XPC service signatures; sign components individually
- **Storing EdDSA private key in repo:** The private key belongs in macOS Keychain only
- **Skipping DMG notarization:** Gatekeeper will block un-notarized Sparkle updates on user machines

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Update checking | Custom HTTP polling | Sparkle's `SPUUpdater` | Handles version comparison, schedule, user preferences |
| Update UI | Custom alert/window | Sparkle's `SPUStandardUserDriver` | Localized, accessible, handles release notes |
| Delta updates | Binary diff system | Sparkle's `generate_appcast` (creates `.delta` files) | BinaryDelta is battle-tested, saves bandwidth |
| Update signing | Custom signing scheme | Sparkle EdDSA (Ed25519) | Cryptographically secure, integrated with toolchain |
| Appcast generation | Manual XML editing | `generate_appcast` tool | Handles signing, delta generation, version ordering |
| DMG creation | Manual Finder | `hdiutil create` | Scriptable, reproducible |

**Key insight:** Sparkle is a complete update solution. The only custom code needed is the thin SwiftUI integration layer (~50 lines) and build system configuration.

## Common Pitfalls

### Pitfall 1: Missing SUEnableInstallerLauncherService
**What goes wrong:** Sparkle silently fails to install updates in sandboxed apps
**Why it happens:** The XPC installer service is opt-in via Info.plist
**How to avoid:** Add `SUEnableInstallerLauncherService: YES` to Info.plist
**Warning signs:** Update downloads but install step fails or hangs

### Pitfall 2: Missing Mach-Lookup Entitlements
**What goes wrong:** "Sandbox: deny mach-lookup" errors in Console.app
**Why it happens:** Sandboxed apps need explicit permission to communicate with Sparkle's XPC services
**How to avoid:** Add `com.apple.security.temporary-exception.mach-lookup.global-name` with both `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`
**Warning signs:** Update check works but install fails with sandbox denial

### Pitfall 3: Sparkle Framework Leaking into App Store Build
**What goes wrong:** App Store rejection under Guideline 2.5.2
**Why it happens:** SPM always links the dependency; conditional compilation only hides code paths, not the binary
**How to avoid:** Must have a build phase script that physically removes Sparkle.framework from the build output for non-Sparkle configurations
**Warning signs:** `otool -L` on the App Store build binary shows Sparkle linkage

### Pitfall 4: Un-notarized DMG Updates
**What goes wrong:** Users see "cannot be opened because it is from an unidentified developer"
**Why it happens:** macOS Gatekeeper requires notarization for all distributed software
**How to avoid:** Notarize every DMG with `xcrun notarytool submit` and staple with `xcrun stapler staple`
**Warning signs:** Works on dev machine but fails on user machines

### Pitfall 5: CFBundleVersion Not Incrementing
**What goes wrong:** Sparkle thinks current version is already latest
**Why it happens:** Sparkle uses `CFBundleVersion` (build number) for comparison, not `CFBundleShortVersionString`
**How to avoid:** Ensure `CURRENT_PROJECT_VERSION` increments with every release
**Warning signs:** "You're up to date" when a newer version exists

### Pitfall 6: Entitlements File Mismatch Between Configurations
**What goes wrong:** App Store build includes XPC mach-lookup entitlements (unnecessary) or Sparkle build lacks them (broken)
**Why it happens:** Single entitlements file for both configs
**How to avoid:** Use separate entitlements files: `Pastel.entitlements` (App Store) and `Pastel-Sparkle.entitlements` (direct distribution). Set `CODE_SIGN_ENTITLEMENTS` per configuration in xcodegen.
**Warning signs:** Entitlement warnings during App Store upload

## Code Examples

### Sparkle Entitlements File (Pastel-Sparkle.entitlements)
```xml
<!-- Source: https://sparkle-project.org/documentation/sandboxing/ -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Existing entitlements -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.app.pastel.Pastel</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.aps-environment</key>
    <string>development</string>

    <!-- Sparkle XPC entitlements -->
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
    </array>
</dict>
</plist>
```

### Info.plist Additions for Sparkle
```xml
<!-- Source: https://sparkle-project.org/documentation/ -->
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/user/pastel-updates/main/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>BASE64_PUBLIC_KEY_HERE</string>
<key>SUEnableInstallerLauncherService</key>
<true/>
```

### Full UpdaterService Implementation
```swift
// Source: https://sparkle-project.org/documentation/programmatic-setup/
#if SPARKLE
import Sparkle
import Combine

/// Wraps SPUStandardUpdaterController for SwiftUI integration
@MainActor
final class UpdaterService: ObservableObject {
    let controller: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false
    private var cancellable: AnyCancellable?

    init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    func startUpdater() {
        do {
            try controller.updater.start()
        } catch {
            print("Failed to start Sparkle updater: \(error)")
        }
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
#endif
```

### DMG Creation and Notarization Script
```bash
#!/bin/bash
# Source: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
set -euo pipefail

APP_NAME="Pastel"
APP_PATH="build/${APP_NAME}.app"
DMG_PATH="build/${APP_NAME}.dmg"
KEYCHAIN_PROFILE="pastel-notarize"

# 1. Create DMG
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" \
  -ov -format UDZO "$DMG_PATH"

# 2. Sign DMG
codesign --force --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --options runtime "$DMG_PATH"

# 3. Notarize
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" --wait

# 4. Staple
xcrun stapler staple "$DMG_PATH"

# 5. Verify
xcrun stapler validate "$DMG_PATH"
echo "DMG notarized and stapled successfully"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Sparkle 1.x (DSA signing) | Sparkle 2.x (EdDSA/Ed25519) | Sparkle 2.0 (2022) | Stronger crypto, sandbox support |
| `altool` for notarization | `notarytool` for notarization | Xcode 13 (2021) | Faster, more reliable, `altool` deprecated |
| Manual appcast XML | `generate_appcast` tool | Sparkle 2.x | Automated signing and delta generation |
| Sparkle XPC as bundled services | XPC services inside framework bundle | Sparkle 2.2 | Simplified setup, no manual XPC bundling |
| CocoaPods for Sparkle | SPM for Sparkle | Sparkle 2.9 deprecates CocoaPods | SPM is the future-proof path |

**Deprecated/outdated:**
- **Sparkle 1.x:** No sandbox support, uses legacy DSA signing
- **CocoaPods distribution:** Deprecated as of Sparkle 2.9 beta
- **`altool` notarization:** Replaced by `notarytool`
- **Interactive GUI package updates (`.sparkle_interactive.pkg`):** Removed in Sparkle 2.8

## Open Questions

1. **Appcast hosting location**
   - What we know: Can use GitHub Pages, raw GitHub URLs, or a custom server
   - What's unclear: Whether the project already has a GitHub Pages setup or preferred hosting
   - Recommendation: Use raw GitHub URL in a dedicated updates repo for simplicity; migrate to GitHub Pages later if needed

2. **EdDSA key management in CI/CD**
   - What we know: `generate_keys` stores private key in macOS Keychain; can pipe via stdin in CI
   - What's unclear: Whether CI/CD is set up, and how to securely manage the Sparkle signing key
   - Recommendation: For now, handle signing locally. Document the key backup/CI approach as a future task

3. **XcodeGen configVariants with empty string**
   - What we know: `configVariants` expects named variants that match config name patterns
   - What's unclear: Whether using `""` as a variant name works for the default (non-Sparkle) scheme
   - Recommendation: Use explicit variant names like `AppStore` and `Sparkle` for clarity; creates `Debug-AppStore`/`Release-AppStore`/`Debug-Sparkle`/`Release-Sparkle` configs

4. **Sparkle framework binary stripping effectiveness**
   - What we know: Build script can `rm -rf` the framework from the build output
   - What's unclear: Whether Xcode/SPM will cause linker errors when the framework is removed post-build
   - Recommendation: The `#if SPARKLE` guards ensure no runtime references exist, so removing the binary post-link should be safe. Verify with `otool -L` on the final binary

## Sources

### Primary (HIGH confidence)
- [Sparkle Official Documentation](https://sparkle-project.org/documentation/) - SPM setup, appcast, EdDSA signing, Info.plist keys
- [Sparkle Sandboxing Guide](https://sparkle-project.org/documentation/sandboxing/) - XPC services, entitlements, Info.plist keys
- [Sparkle Programmatic Setup](https://sparkle-project.org/documentation/programmatic-setup/) - SwiftUI integration, SPUStandardUpdaterController
- [Sparkle GitHub Releases](https://github.com/sparkle-project/Sparkle/releases) - Version 2.8.1 confirmed as latest stable
- [Apple Notarization Docs](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) - notarytool workflow

### Secondary (MEDIUM confidence)
- [SwiftLee: Sparkle Distribution Guide](https://www.avanderlee.com/xcode/sparkle-distribution-apps-in-and-out-of-the-mac-app-store/) - Conditional compilation pattern with build configs
- [XcodeGen ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) - configVariants, configs, build settings
- [Sparkle Discussion #2290](https://github.com/sparkle-project/Sparkle/discussions/2290) - Sandbox mach-lookup troubleshooting

### Tertiary (LOW confidence)
- XcodeGen conditional SPM dependency exclusion: No official support found. Build script stripping is a community workaround that needs validation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Sparkle 2.x is the undisputed standard for macOS OTA updates, well-documented
- Architecture: HIGH - Programmatic SwiftUI setup and sandbox configuration are officially documented
- Conditional compilation: MEDIUM - The dual-config approach is well-established but XcodeGen's handling of configVariants with SPM framework stripping needs validation
- Pitfalls: HIGH - Common issues are well-documented in Sparkle's GitHub discussions
- Notarization: HIGH - Apple's `notarytool` workflow is officially documented

**Research date:** 2026-02-20
**Valid until:** 2026-04-20 (Sparkle is stable; 2.9 may release but 2.8.x approach remains valid)
