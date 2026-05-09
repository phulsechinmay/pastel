import ApplicationServices
import AppKit
import CoreGraphics
import IOKit.hid
import OSLog
import SwiftUI

/// PostEvent permission check and request for CGEvent paste simulation.
///
/// CGEvent.post requires the PostEvent TCC permission (kTCCServicePostEvent),
/// which is separate from full Accessibility (kTCCServiceAccessibility).
/// PostEvent IS compatible with App Sandbox — full Accessibility is NOT.
///
/// Implementation note (macOS 26): `AXIsProcessTrusted()` and
/// `CGPreflightPostEventAccess()` cache their return value per-process.
/// Once they return `false` at process startup (typical when permission was not
/// granted before launch), they keep returning `false` for the entire app
/// lifetime, even after the user grants permission in System Settings.
///
/// We use `IOHIDCheckAccess(kIOHIDRequestTypePostEvent)` as the live probe — it
/// queries the kernel directly for the PostEvent TCC service without going
/// through the cached CG wrappers, and (unlike `CGEvent.tapCreate`) it is a pure
/// query that does NOT register the process for Input Monitoring.
///
/// - `isGranted`: live kernel probe via `IOHIDCheckAccess` — safe to call on every paste
/// - `requestPermission()`: triggers the macOS system dialog for PostEvent access
/// - `openAccessibilitySettings()`: opens System Settings directly to the Accessibility pane
/// - `startListeningForPermissionChanges()`: subscribes to TCC change notifications and
///   posts an internal `permissionChangedNotification` observers can react to
@MainActor
enum AccessibilityService {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "AccessibilityService"
    )

    /// Whether PostEvent permission is currently granted, queried live every call.
    ///
    /// `IOHIDCheckAccess(kIOHIDRequestTypePostEvent)` asks the kernel for the
    /// current state of the PostEvent TCC service for this process. Unlike the
    /// CG-level wrappers it does not cache per-process, and unlike a tap-create
    /// probe it does not register the process for Input Monitoring.
    static var isGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypePostEvent) == kIOHIDAccessTypeGranted
    }

    /// Backwards-compatible alias for callers that explicitly want a "force re-probe"
    /// semantic. Internally identical to `isGranted` because the probe is already live.
    @discardableResult
    static func refreshPermissionState() -> Bool {
        isGranted
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

    // MARK: - Permission change notifications

    /// Posted when TCC reports an accessibility-related permission change, or when
    /// the app is reactivated and a re-probe shows the granted state has flipped.
    /// SwiftUI views that display permission state can subscribe with `onReceive`.
    static let permissionChangedNotification = Notification.Name("PastelAccessibilityPermissionChanged")

    /// `nonisolated(unsafe)` because @MainActor enums cannot store `NSObjectProtocol?`
    /// directly across isolation domains, and we hand these tokens back to AppKit
    /// observer registration.
    nonisolated(unsafe) private static var tccObserver: NSObjectProtocol?
    nonisolated(unsafe) private static var activationObserver: NSObjectProtocol?
    nonisolated(unsafe) private static var lastKnownGranted: Bool = false

    /// Timestamp of the most recent paste attempt that was blocked by missing
    /// permission. When a TCC broadcast arrives within `relaunchWindow` of this
    /// timestamp and the cached probe is still `false`, we treat that as
    /// "user just granted via System Settings" and silently relaunch to flush
    /// the per-process TCC cache.
    nonisolated(unsafe) private static var pasteDeniedAt: Date?
    nonisolated(unsafe) private static var hasAttemptedRelaunch: Bool = false

    private static let relaunchWindow: TimeInterval = 600 // 10 minutes

    /// Called by `PasteService` when a paste attempt is blocked because
    /// `isGranted` is `false`. Records the timestamp so a subsequent TCC
    /// broadcast can confirm "the user just granted" and trigger a relaunch.
    static func notePasteDeniedDueToPermission() {
        pasteDeniedAt = Date()
        logger.info("notePasteDeniedDueToPermission recorded — awaiting TCC broadcast")
    }

    /// Subscribe to TCC permission-change broadcasts and app reactivation, and
    /// re-broadcast a unified `permissionChangedNotification` when state flips.
    /// Idempotent — calling it twice is a no-op.
    static func startListeningForPermissionChanges() {
        guard tccObserver == nil else { return }
        lastKnownGranted = isGranted
        logger.info("startListeningForPermissionChanges: initial isGranted=\(lastKnownGranted)")

        // 1. macOS broadcasts this when an app's accessibility/TCC settings change.
        tccObserver = DistributedNotificationCenter.default()
            .addObserver(
                forName: Notification.Name("com.apple.accessibility.api"),
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in checkAndPostIfChanged(reason: "tcc-broadcast") }
            }

        // 2. Re-probe when our app reactivates (covers cases where the broadcast is
        //    missed or filtered, e.g. user switched to System Settings then back).
        activationObserver = NotificationCenter.default
            .addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in checkAndPostIfChanged(reason: "app-active") }
            }
    }

    private static func checkAndPostIfChanged(reason: String) {
        let now = isGranted
        if now != lastKnownGranted {
            logger.info("permission flip detected (\(reason)): \(lastKnownGranted) -> \(now)")
            lastKnownGranted = now
            pasteDeniedAt = nil
            NotificationCenter.default.post(name: permissionChangedNotification, object: nil)
            return
        }
        // Cache didn't flip. If user attempted paste recently and was denied,
        // assume they just granted via System Settings and relaunch to flush
        // the per-process TCC cache. macOS 26 has no public way to flush it
        // in-place for a sandboxed app.
        guard reason == "tcc-broadcast",
              let deniedAt = pasteDeniedAt,
              Date().timeIntervalSince(deniedAt) < relaunchWindow,
              !hasAttemptedRelaunch
        else { return }
        hasAttemptedRelaunch = true
        logger.info("TCC broadcast after recent paste denial — assuming permission granted; relaunching to flush cache")
        relaunchToApplyPermission()
    }

    // MARK: - Relaunch flow

    /// Display a brief toast and relaunch the app to flush the per-process TCC
    /// cache. The new process starts fresh and reads the just-granted permission
    /// as `true` immediately, so paste works on the next attempt.
    static func relaunchToApplyPermission() {
        showRelaunchToast()
        // Long enough that the user sees the message; short enough not to feel sluggish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            performRelaunch()
        }
    }

    private static func performRelaunch() {
        let url = Bundle.main.bundleURL
        let cfg = NSWorkspace.OpenConfiguration()
        // MUST be true. With `false`, LaunchServices sees this process is still
        // running, "activates" it, and returns — no new instance is spawned, so
        // when we terminate ourselves moments later the user is left with no
        // app at all. With `true`, LaunchServices starts a new process; we
        // overlap for ~200 ms, then the old one exits.
        cfg.createsNewApplicationInstance = true
        cfg.activates = true
        logger.info("performRelaunch: requesting new instance at \(url.path, privacy: .public)")
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { app, error in
            if let error {
                logger.error("Relaunch openApplication failed: \(error.localizedDescription, privacy: .public)")
            } else if let app {
                logger.info("Relaunch new instance pid=\(app.processIdentifier)")
            }
            // Give LaunchServices a beat to actually start the new process
            // before we exit. Without this, a fast terminate can race the spawn.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
        }
    }

    nonisolated(unsafe) private static var relaunchToastWindow: NSWindow?

    private static func showRelaunchToast() {
        // If already showing, don't re-create.
        guard relaunchToastWindow == nil else { return }

        let hosting = NSHostingView(rootView: RelaunchToastView())
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 64)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: visible.maxX - 340,
                y: visible.maxY - 84
            ))
        }
        window.orderFront(nil)
        relaunchToastWindow = window
    }
}

/// Toast contents shown to the user just before we relaunch to apply a
/// newly-granted Accessibility / PostEvent permission.
private struct RelaunchToastView: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pastel is restarting")
                    .font(.callout.weight(.semibold))
                Text("Applying Accessibility permission…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .preferredColorScheme(.dark)
    }
}
