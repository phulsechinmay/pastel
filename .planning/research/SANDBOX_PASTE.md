# App Sandbox vs Paste-Back: Deep Research

**Project:** Pastel — macOS Clipboard Manager
**Researched:** 2026-02-07
**Confidence:** HIGH (verified against Maccy open-source implementation, Apple DTS statements, and App Store evidence)

---

## Executive Summary

**The current CGEvent.post(tap: .cgSessionEventTap) approach IS compatible with App Sandbox.** This is the most important finding of this research. The conflict described in the original problem statement is based on outdated information from a 2016 Apple Developer Forums thread. Apple has since introduced a granular TCC (Transparency, Consent, and Control) service called **PostEvent** (`kTCCServicePostEvent`) that is separate from full Accessibility and is explicitly compatible with the App Sandbox.

**Proof:** Maccy, an open-source clipboard manager (MIT license, GitHub: p0deje/Maccy), uses the exact same approach as Pastel — `CGEvent.post(tap: .cgSessionEventTap)` with `CGEventSource(stateID: .combinedSessionState)` — and has been on the Mac App Store (app ID 1527619437) since 2020 with App Sandbox enabled. As of November 2025, it is at version 2.6.1, requires macOS 14+, and is priced at $9.99.

**Recommendation:** Keep the current CGEvent.post implementation. Enable App Sandbox. Replace `AXIsProcessTrusted()` with `CGPreflightPostEventAccess()` / `CGRequestPostEventAccess()` for more precise permission checking. Submit to Mac App Store and TestFlight with confidence.

---

## The Problem (Restated)

Pastel uses `CGEvent.post(tap: .cgSessionEventTap)` to simulate Cmd+V for paste-back. The concern was that this API does not work inside App Sandbox. However, research reveals this concern is based on outdated information.

### Current Implementation

**File:** `/Users/phulsechinmay/Desktop/Projects/pastel/Pastel/Services/PasteService.swift`

```swift
private static func simulatePaste() {
    let source = CGEventSource(stateID: .combinedSessionState)
    source?.setLocalEventsFilterDuringSuppressionState(
        [.permitLocalMouseEvents, .permitSystemDefinedEvents],
        state: .eventSuppressionStateSuppressionInterval
    )
    let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
    keyDown?.flags = .maskCommand
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cgSessionEventTap)
    keyUp?.post(tap: .cgSessionEventTap)
}
```

**File:** `/Users/phulsechinmay/Desktop/Projects/pastel/Pastel/Resources/Pastel.entitlements`

```xml
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
```

App Sandbox is already enabled. The current entitlements file already has `com.apple.security.app-sandbox` set to `true`.

**File:** `/Users/phulsechinmay/Desktop/Projects/pastel/Pastel/Services/AccessibilityService.swift`

Currently uses `AXIsProcessTrusted()` which checks the full Accessibility TCC service. This should be updated to use the more precise `CGPreflightPostEventAccess()` API.

---

## The Key Discovery: PostEvent TCC Service

Quinn "The Eskimo!" from Apple Developer Technical Support confirmed in Apple Developer Forums thread 789896:

> "You can post events using `CGEvent.post(...)`, which uses its own privilege that's compatible with App Sandbox. While this privilege shows up in the UI as System Settings > Privacy & Security > Accessibility, it doesn't give you complete accessibility access — it's just limited to posting events."

> "In `tccutil`, there are separate services for Accessibility, ListenEvent, and PostEvent."

> "If you try to post a CGEvent, the system will present the TCC alert for you. Alternatively, you can call `CGPreflightPostEventAccess` and `CGRequestPostEventAccess`."

### Three Separate TCC Services

| TCC Service | Purpose | Sandbox Compatible | UI Location |
|---|---|---|---|
| `kTCCServiceAccessibility` | Full AX API access (AXUIElement, etc.) | **NO** | Privacy > Accessibility |
| `kTCCServiceListenEvent` | CGEventTap (monitoring/listening) | **YES** | Privacy > Input Monitoring |
| `kTCCServicePostEvent` | CGEvent.post (sending events) | **YES** | Privacy > Accessibility* |

*PostEvent shows up under the Accessibility heading in System Settings, but it is a separate, more limited privilege.

### Contradiction Resolution

The 2016 thread (thread 61387) that said "CGEventPost is not allowed from a sandboxed app" predates the introduction of the PostEvent TCC service. Apple has since refined the TCC system to separate event posting from full accessibility access. The newer information from Quinn "The Eskimo!" (thread 789896) supersedes the older guidance.

---

## Approach-by-Approach Analysis

### Approach 1: Keep Current CGEvent.post (RECOMMENDED)

**Verdict: WORKS IN SANDBOX. This is the recommended approach.**

| Aspect | Detail |
|---|---|
| Implementation | Already done — no code changes needed for paste-back |
| Sandbox | Compatible via PostEvent TCC service |
| Permission | User grants via Accessibility in System Settings (PostEvent subset) |
| App Store | Proven — Maccy uses this exact approach on the Mac App Store |
| TestFlight | Works — App Sandbox is mandatory for TestFlight, which is already enabled |
| User experience | System presents TCC alert automatically, or use `CGRequestPostEventAccess()` |

**Recommended code change:** Replace `AXIsProcessTrusted()` with `CGPreflightPostEventAccess()` in `AccessibilityService.swift`. The former checks full Accessibility permission; the latter checks specifically for PostEvent permission, which is what Pastel actually needs.

**One caveat:** Sandboxed apps do NOT automatically appear in the Accessibility list when requesting permission (confirmed by Maccy issue #159). Users must manually add the app via the "+" button. This is a UX friction point but not a blocker.

**Maccy's entitlements for reference:**
```xml
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
    </array>
</dict>
```

Note: No special entitlements are needed for CGEvent.post — no accessibility entitlement, no temporary exception. Just the basic sandbox entitlement.

### Approach 2: AppleScript / NSAppleScript

**Verdict: NOT VIABLE for Mac App Store.**

| Aspect | Detail |
|---|---|
| Concept | `tell application "System Events" to keystroke "v" using command down` |
| Sandbox | Requires `com.apple.security.temporary-exception.apple-events` targeting `com.apple.systemevents` |
| App Review | **REJECTED** — Apple Review does not approve this temporary exception entitlement. Multiple developers have reported rejections. The Apple Core Security team does not grant this exception. |
| Alternative | `NSUserAppleScriptTask` runs scripts from `~/Library/Application Scripts/[bundle-id]/` but requires users to manually install a script, which is unacceptable UX |
| Reliability | AppleScript keystroke simulation is slower and less reliable than CGEvent |

**Sources:** Apple Developer Forums threads confirm that `com.apple.security.temporary-exception.apple-events` is systematically rejected by App Review. The objc.io article on Sandbox Scripting confirms `NSUserAppleScriptTask` requires user-installed scripts.

### Approach 3: Accessibility API (AXUIElement)

**Verdict: NOT VIABLE in sandbox.**

| Aspect | Detail |
|---|---|
| Concept | Use AXUIElement to find the target app's Edit menu and trigger Paste |
| Sandbox | Full Accessibility (`kTCCServiceAccessibility`) is NOT available to sandboxed apps |
| Limitation | Even if it worked, this approach is fragile — not all apps have Edit > Paste menus, and menu structures vary |
| Permission | AXIsProcessTrusted() may always return false in sandboxed apps (reported in Apple Developer Forums thread 707680) |

**Key quote from research:** "The Accessibility API is not available in sandboxed apps." This means AXUIElement-based approaches are fundamentally incompatible with Mac App Store distribution.

### Approach 4: NSWorkspace / Services

**Verdict: NOT VIABLE for paste-back.**

| Aspect | Detail |
|---|---|
| Concept | Use macOS Services menu programmatically to trigger paste |
| Reality | There is no API to programmatically invoke the Services menu Paste action in another app |
| NSWorkspace | Does not provide paste functionality — it handles launching apps, opening files/URLs, and querying running apps |
| Services | The Services architecture is designed for the target app to register services, not for external apps to trigger them |

This approach has no viable implementation path.

### Approach 5: XPC Helper Tool (SMAppService)

**Verdict: NOT VIABLE for this purpose.**

| Aspect | Detail |
|---|---|
| Concept | Non-sandboxed XPC helper performs CGEvent.post while main app stays sandboxed |
| SMAppService | Introduced in macOS 13 (Ventura) — replacement for SMJobBless and SMLoginItemSetEnabled |
| Critical blocker | **If the main app is sandboxed, the helper tool must also be sandboxed.** Apple changed requirements to prevent sandbox escapes via helper tools |
| App Review | Would be considered a sandbox escape attempt — very likely to be rejected |

**Key quote:** "Requirements for agents and daemons registered with SMAppService have changed to prevent sandbox escapes. The target executable must be sandboxed if the main app is sandboxed."

This approach is explicitly designed to be blocked by Apple's security architecture.

### Approach 6: Hybrid Distribution

**Verdict: UNNECESSARY given Approach 1 works, but viable as fallback.**

| Aspect | Detail |
|---|---|
| Concept | App Store version with degraded paste (copy-only) + Direct download version with full paste-back |
| Complexity | Two build configurations, two distribution channels, two update mechanisms |
| Direct download | Use Developer ID signing + Sparkle framework for auto-updates |
| Copy-only mode | Pastel already supports this via `PasteBehavior.copy` setting |

This approach is common in the macOS ecosystem. CopyLess 2, for example, removed "Direct Paste" from its App Store version due to sandbox limitations and offers a separate "CopyLess Helper" plugin for the direct download version. However, since CGEvent.post is compatible with sandbox, this complexity is unnecessary for Pastel.

### Approach 7: Disable App Sandbox

**Verdict: BLOCKS TestFlight and Mac App Store.**

| Aspect | Detail |
|---|---|
| TestFlight | **MANDATORY** — macOS TestFlight requires `com.apple.security.app-sandbox` set to `true`. Upload validation error ITMS-90296 explicitly rejects apps without it |
| Mac App Store | **MANDATORY** — All Mac App Store executables must be sandboxed |
| Direct download | Works fine — Developer ID signed apps do not require sandbox |
| Apple's stance | No exceptions or relaxation of this requirement as of 2025 |

This approach is only viable for direct-download distribution, which sacrifices both TestFlight beta testing and Mac App Store discoverability.

---

## Comparison Matrix

| Approach | Works in Sandbox | App Store Viable | TestFlight | Implementation Effort | Reliability |
|---|---|---|---|---|---|
| **1. CGEvent.post (current)** | **YES** | **YES** (proven by Maccy) | **YES** | **None** (already done) | **HIGH** |
| 2. AppleScript | No (rejected) | **NO** | No | Medium | Low |
| 3. AXUIElement | No | **NO** | No | High | Low |
| 4. NSWorkspace/Services | N/A | N/A | N/A | N/A | N/A |
| 5. XPC Helper | No (blocked) | **NO** | No | Very High | Medium |
| 6. Hybrid distribution | Partial | Partial | Partial | High | High |
| 7. Disable Sandbox | N/A | **NO** | **NO** | None | High |

---

## What Popular Clipboard Managers Do

### On the Mac App Store (Sandboxed)

| App | App Store | Auto-Paste | Approach |
|---|---|---|---|
| **Maccy** | Yes ($9.99) | Yes | CGEvent.post + Accessibility/PostEvent permission |
| **Paste** (by Dmitry Obukhov) | Yes (subscription) | Yes | Likely CGEvent.post (closed-source, same UX pattern) |
| **PasteNow** | Yes | Yes | Likely CGEvent.post (requires Accessibility) |
| **PastePal** | Yes | Yes | Requires Accessibility permission |
| **Pasty** | Yes | Unknown | Unknown |
| **Flycut** | Yes (free) | Manual only | Copies to clipboard; user pastes manually |
| **CopyLess 2** | Yes | Removed | Removed Direct Paste from App Store version; offers separate helper plugin |
| **CopyClip 2** | Yes | Unknown | Unknown |

### Not on App Store (Direct Download)

| App | Distribution | Auto-Paste | Approach |
|---|---|---|---|
| **Alfred** (clipboard feature) | Direct download | Yes | CGEvent.post, not sandboxed |
| **Keyboard Maestro** | Direct download | Yes | Not sandboxed |

### Key Insight

The majority of Mac App Store clipboard managers that offer auto-paste appear to use CGEvent.post with the PostEvent privilege. This is the industry-standard approach. CopyLess 2 is the notable exception that removed the feature, suggesting they may have been using a different (now-blocked) mechanism, or they chose not to require the accessibility permission.

---

## Upcoming Risk: macOS 16 (Tahoe) Pasteboard Privacy

**Important future consideration:** macOS 16 introduces pasteboard privacy alerts (previewed in macOS 15.4 behind a developer flag). When an app programmatically reads NSPasteboard.general without user interaction (e.g., polling), the system will show a privacy alert.

| Aspect | Detail |
|---|---|
| Feature | System alert when app reads clipboard without user interaction |
| Impact on Pastel | Pastel's 0.5s polling of NSPasteboard would trigger this alert |
| User control | Users can allow always, block entirely, or prompt each time per app |
| New APIs | `NSPasteboard.detect()` methods let apps check data types without reading content |
| Native competition | macOS Tahoe includes a built-in Spotlight clipboard history (8-hour retention) |
| Timeline | Beta now, release expected Fall 2026 |

This is a separate concern from the sandbox/paste-back issue, but it will affect ALL clipboard managers. It is not specific to Pastel's architecture and does not change the recommendation for the paste-back approach.

---

## Recommended Action Plan

### Immediate (No Code Changes Needed for Paste-Back)

1. **Confirm sandbox is enabled** -- Already done. `Pastel.entitlements` has `com.apple.security.app-sandbox` = `true`.

2. **Update AccessibilityService** to use the more precise PostEvent APIs:
   - Replace `AXIsProcessTrusted()` with `CGPreflightPostEventAccess()`
   - Replace `AXIsProcessTrustedWithOptions()` prompt with `CGRequestPostEventAccess()`
   - These APIs specifically check/request the PostEvent privilege instead of full Accessibility

3. **Update onboarding UX** for the sandbox limitation:
   - Sandboxed apps do NOT auto-appear in the Accessibility list
   - Users must manually add via "+" button in System Settings > Privacy & Security > Accessibility
   - Update `AccessibilityPromptView` to guide users through this process with clear instructions

4. **Submit to TestFlight** for beta testing with the current implementation.

### API Migration Reference

**Current (broad — asks for more than needed):**
```swift
static var isGranted: Bool {
    AXIsProcessTrusted()
}

static func requestPermission() -> Bool {
    let promptKey = "AXTrustedCheckOptionPrompt" as CFString
    let options = [promptKey: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}
```

**Recommended (precise — asks only for PostEvent):**
```swift
static var isGranted: Bool {
    CGPreflightPostEventAccess()
}

static func requestPermission() -> Bool {
    return CGRequestPostEventAccess()
}
```

Note: `CGPreflightPostEventAccess()` and `CGRequestPostEventAccess()` are available since macOS 10.15 (Catalina). Pastel targets macOS 14+, so these are safe to use.

### Future (macOS 16 Pasteboard Privacy)

- Investigate `NSPasteboard.detect()` methods for non-intrusive clipboard type checking
- Consider transitioning from polling to a detect-then-read pattern
- Monitor Apple's guidance for clipboard manager apps during WWDC 2026

---

## Sources

- [Maccy GitHub Repository](https://github.com/p0deje/Maccy) — Open-source clipboard manager, MIT license, App Store + direct download
- [Maccy on Mac App Store](https://apps.apple.com/us/app/maccy/id1527619437) — Version 2.6.1, macOS 14+, $9.99, sandboxed
- [Maccy Entitlements](https://raw.githubusercontent.com/p0deje/Maccy/refs/heads/master/Maccy/Maccy.entitlements) — App Sandbox enabled, no accessibility entitlements
- [Maccy Clipboard.swift](https://github.com/p0deje/Maccy/blob/master/Maccy/Clipboard.swift) — CGEvent.post(tap: .cgSessionEventTap) implementation
- [Maccy Issue #161](https://github.com/p0deje/Maccy/issues/161) — Pasting fails on High Sierra (sandbox + CGEvent bug specific to 10.13, fixed by dropping High Sierra support)
- [Maccy Issue #159](https://github.com/p0deje/Maccy/issues/159) — Accessibility permissions not auto-appearing for sandboxed apps
- [Apple Developer Forums Thread 789896](https://developer.apple.com/forums/thread/789896) — Quinn "The Eskimo!" confirms PostEvent is compatible with App Sandbox
- [Apple Developer Forums Thread 61387](https://developer.apple.com/forums/thread/61387) — Older (2016) thread saying CGEventPost not allowed in sandbox (SUPERSEDED)
- [Apple Developer Forums Thread 707680](https://developer.apple.com/forums/thread/707680) — Accessibility permission in sandboxed apps
- [AeroSpace Issue #1012](https://github.com/nikitabobko/AeroSpace/issues/1012) — CGEventTap sandbox compatibility confirmed by Apple DTS
- [CGRequestPostEventAccess Documentation](https://developer.apple.com/documentation/coregraphics/cgrequestposteventaccess()) — Apple API reference
- [objc.io: Scripting from a Sandbox](https://www.objc.io/issues/14-mac/sandbox-scripting/) — NSUserAppleScriptTask limitations
- [ClipBook Blog: Paste to Other Applications](https://clipbook.app/blog/paste-to-other-applications/) — How clipboard managers implement paste-back
- [CopyLess 2](https://copyless.net/) — Removed Direct Paste from App Store version
- [Apple Developer Forums Thread 733942](https://developer.apple.com/forums/thread/733942) — TestFlight requires App Sandbox
- [Sparkle Framework](https://sparkle-project.org/) — Auto-update framework for direct download distribution
- [macOS Tahoe Clipboard Privacy](https://9to5mac.com/2025/05/12/macos-16-clipboard-privacy-protection/) — Upcoming pasteboard privacy alerts
- [Pasteboard Privacy Preview](https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4/) — macOS 15.4 developer preview flag
