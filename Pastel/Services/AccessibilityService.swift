import ApplicationServices
import AppKit
import CoreGraphics

/// PostEvent permission check and request for CGEvent paste simulation.
///
/// CGEvent.post requires the PostEvent TCC permission (kTCCServicePostEvent),
/// which is separate from full Accessibility (kTCCServiceAccessibility).
/// PostEvent IS compatible with App Sandbox — full Accessibility is NOT.
///
/// We check both `AXIsProcessTrusted()` and `CGPreflightPostEventAccess()` because
/// the System Settings UI grants all three TCC services together, and
/// `AXIsProcessTrusted()` reflects changes immediately while
/// `CGPreflightPostEventAccess()` caches per-process and may need a restart.
///
/// - `isGranted`: cheap check, call before every paste (permission can be revoked at any time)
/// - `requestPermission()`: triggers the macOS system dialog for PostEvent access
/// - `openAccessibilitySettings()`: opens System Settings directly to the Accessibility pane
@MainActor
enum AccessibilityService {

    /// Whether PostEvent permission is currently granted.
    ///
    /// Checks both AX (instant TCC refresh) and PostEvent (correct entitlement).
    /// System Settings grants both together, so either returning true is sufficient.
    static var isGranted: Bool {
        AXIsProcessTrusted() || CGPreflightPostEventAccess()
    }

    /// Request PostEvent permission, showing the macOS system dialog.
    ///
    /// - Returns: `true` if permission is already granted, `false` if the user
    ///   needs to grant it via System Settings.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestPostEventAccess()
    }

    /// Open System Settings directly to the Accessibility privacy pane.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
