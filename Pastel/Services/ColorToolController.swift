import AppKit

/// Manages the macOS system color panel for standalone color picking.
///
/// When the user picks a color in the system color wheel, the hex value
/// is automatically copied to the clipboard. The ``ClipboardMonitor``
/// picks up the change and creates a color-swatch history item via
/// ``ColorDetectionService``.
@MainActor
final class ColorToolController: NSObject {

    static let shared = ColorToolController()

    private var closeObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    /// Opens the system color panel configured for standalone picking.
    func showColorPicker() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.isContinuous = true
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        panel.level = NSWindow.Level(rawValue: dockLevel + 3)  // 23 -- match SlidingPanel

        // Pastel is an LSUIElement (menu-bar) app, so it is never the active app on its
        // own. NSColorPanel only comes forward and becomes interactive when its owning
        // app is active, so activate explicitly before ordering it front. Without this,
        // the picker opens behind everything and the eyedropper appears to do nothing.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Clean up target/action when the color panel closes to avoid
        // conflicts with SwiftUI ColorPicker in the edit modal.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupTarget()
            }
        }
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        guard let rgb = sender.color.usingColorSpace(.sRGB) else { return }
        let hex = String(
            format: "#%02X%02X%02X",
            Int(rgb.redComponent * 255),
            Int(rgb.greenComponent * 255),
            Int(rgb.blueComponent * 255)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
    }

    private func cleanupTarget() {
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
    }
}
