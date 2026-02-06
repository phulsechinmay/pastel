import ApplicationServices
import AppKit

/// Accessibility permission check and request for CGEvent paste simulation.
///
/// CGEvent posting requires Accessibility permission. This service provides:
/// - `isGranted`: cheap check, call before every paste (permission can be revoked at any time)
/// - `requestPermission()`: triggers the macOS system dialog
/// - `openAccessibilitySettings()`: opens System Settings directly to the Accessibility pane
@MainActor
enum AccessibilityService {

    /// Whether Accessibility permission is currently granted.
    ///
    /// This is a cheap call -- do NOT cache the result.
    /// Users can revoke permission at any time via System Settings.
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Request Accessibility permission, showing the macOS system dialog.
    ///
    /// - Returns: `true` if permission is already granted, `false` if the user
    ///   needs to grant it via System Settings.
    @discardableResult
    static func requestPermission() -> Bool {
        // Use the string key directly to avoid Swift 6 concurrency warning
        // on kAXTrustedCheckOptionPrompt (shared mutable state)
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings directly to the Accessibility privacy pane.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
