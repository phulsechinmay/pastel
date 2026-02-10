import AppKit
import Carbon
import CoreGraphics
import OSLog

/// Writes clipboard item content to NSPasteboard and optionally simulates Cmd+V via CGEvent.
///
/// This is the core paste-back service. Behavior depends on the user's paste preference:
///
/// **Paste / Copy + Paste mode:**
/// 1. Check Accessibility permission (required for CGEvent)
/// 2. Check secure input (fall back to copy-only if active)
/// 3. Write item content to NSPasteboard.general
/// 4. Set skipNextChange on ClipboardMonitor (self-paste loop prevention)
/// 5. Hide the panel
/// 6. After 50ms delay, simulate Cmd+V via CGEvent
///
/// **Copy mode:**
/// 1. Write item content to NSPasteboard.general
/// 2. Set skipNextChange on ClipboardMonitor (self-paste loop prevention)
/// 3. Hide the panel
///
/// Handles all 5 content types: text, richText, url, image, file.
@MainActor
final class PasteService {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "PasteService"
    )

    /// Paste a clipboard item into the frontmost app.
    ///
    /// - Parameters:
    ///   - item: The clipboard item to paste.
    ///   - clipboardMonitor: The monitor whose skipNextChange flag will be set.
    ///   - panelController: The panel to hide before simulating paste.
    func paste(
        item: ClipboardItem,
        clipboardMonitor: ClipboardMonitor,
        panelController: PanelController
    ) {
        // Read user's paste behavior preference
        let behaviorRaw = UserDefaults.standard.string(forKey: "pasteBehavior") ?? PasteBehavior.paste.rawValue
        let behavior = PasteBehavior(rawValue: behaviorRaw) ?? .paste

        // Copy-only mode: write to pasteboard and hide panel (no accessibility or CGEvent needed)
        if behavior == .copy {
            writeToPasteboard(item: item)
            clipboardMonitor.skipNextChange = true
            panelController.hide()
            logger.info("Copy-only mode -- wrote to pasteboard, skipping Cmd+V simulation")
            return
        }

        // Paste / Copy+Paste mode: full flow with Cmd+V simulation

        // 1. Check Accessibility permission (never cache -- can be revoked at any time)
        guard AccessibilityService.isGranted else {
            logger.warning("Accessibility permission not granted -- paste blocked")
            return
        }

        // 2. Check secure input (password fields, banking apps)
        if IsSecureEventInputEnabled() {
            logger.warning("Secure input is active -- writing to pasteboard only (user must Cmd+V manually)")
            writeToPasteboard(item: item)
            clipboardMonitor.skipNextChange = true
            return
        }

        // 3. Write item content to pasteboard
        writeToPasteboard(item: item)

        // 4. Signal monitor to skip the next change (self-paste loop prevention)
        clipboardMonitor.skipNextChange = true

        // 5. Hide panel
        panelController.hide()

        // 6. Simulate Cmd+V after 250ms delay (must exceed panel hide animation + previous app re-activation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Self.simulatePaste()
        }
    }

    /// Copy a clipboard item to the pasteboard without simulating Cmd+V.
    ///
    /// Always writes to pasteboard and hides the panel, regardless of the user's
    /// paste behavior preference. Used by the context menu "Copy" action.
    func copyOnly(
        item: ClipboardItem,
        clipboardMonitor: ClipboardMonitor,
        panelController: PanelController
    ) {
        writeToPasteboard(item: item)
        clipboardMonitor.skipNextChange = true
        panelController.hide()
        logger.info("Copy-only (explicit) -- wrote \(item.type.rawValue) to pasteboard")
    }

    /// Paste a clipboard item as plain text (RTF stripped) into the frontmost app.
    ///
    /// Follows the same flow as `paste()` but uses `writeToPasteboardPlainText(item:)` which
    /// omits the `.rtf` data type, causing receiving apps to fall back to plain text styling.
    /// For non-text content types (url, image, file), delegates to normal `writeToPasteboard(item:)`.
    func pastePlainText(
        item: ClipboardItem,
        clipboardMonitor: ClipboardMonitor,
        panelController: PanelController
    ) {
        let behaviorRaw = UserDefaults.standard.string(forKey: "pasteBehavior") ?? PasteBehavior.paste.rawValue
        let behavior = PasteBehavior(rawValue: behaviorRaw) ?? .paste

        if behavior == .copy {
            writeToPasteboardPlainText(item: item)
            clipboardMonitor.skipNextChange = true
            panelController.hide()
            logger.info("Copy-only mode (plain text) -- wrote to pasteboard, skipping Cmd+V simulation")
            return
        }

        guard AccessibilityService.isGranted else {
            logger.warning("Accessibility permission not granted -- plain text paste blocked")
            return
        }

        if IsSecureEventInputEnabled() {
            logger.warning("Secure input is active -- writing plain text to pasteboard only (user must Cmd+V manually)")
            writeToPasteboardPlainText(item: item)
            clipboardMonitor.skipNextChange = true
            return
        }

        writeToPasteboardPlainText(item: item)
        clipboardMonitor.skipNextChange = true
        panelController.hide()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Self.simulatePaste()
        }
    }

    // MARK: - Pasteboard Writing

    /// Write the clipboard item's content to NSPasteboard.general, preserving all representations.
    private func writeToPasteboard(item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.type {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
            if let rtfData = item.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            if let html = item.htmlContent {
                pasteboard.setString(html, forType: .html)
            }

        case .richText:
            // Write richest format first for maximum fidelity
            if let rtfData = item.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            if let html = item.htmlContent {
                pasteboard.setString(html, forType: .html)
            }
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .url:
            if let urlString = item.textContent {
                pasteboard.setString(urlString, forType: .string)
                // Also set as proper URL type for apps that support it
                if let url = URL(string: urlString) {
                    pasteboard.writeObjects([url as NSURL])
                }
            }

        case .image:
            if let imagePath = item.imagePath {
                let imageURL = ImageStorageService.shared.resolveImageURL(imagePath)
                if let imageData = try? Data(contentsOf: imageURL) {
                    pasteboard.setData(imageData, forType: .png)
                    // Also write TIFF for broader app compatibility
                    if let nsImage = NSImage(data: imageData),
                       let tiffData = nsImage.tiffRepresentation {
                        pasteboard.setData(tiffData, forType: .tiff)
                    }
                }
            }

        case .file:
            if let filePath = item.textContent {
                let fileURL = URL(fileURLWithPath: filePath)
                pasteboard.writeObjects([fileURL as NSURL])
            }

        case .code, .color:
            // Code snippets and color values are stored as text
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        }

        logger.info("Wrote \(item.type.rawValue) content to pasteboard")
    }

    /// Write the clipboard item's content to NSPasteboard.general WITHOUT RTF data.
    ///
    /// For text-based types (.text, .richText, .code, .color), omits `.rtf` so receiving
    /// apps fall back to plain text styling. For non-text types (.url, .image, .file),
    /// delegates to `writeToPasteboard(item:)` since these have no RTF to strip.
    private func writeToPasteboardPlainText(item: ClipboardItem) {
        // Non-text types have no RTF -- use normal pasteboard write
        switch item.type {
        case .url, .image, .file:
            writeToPasteboard(item: item)
            return
        case .text, .richText, .code, .color:
            break
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Write ONLY plain string -- no .rtf, no .html
        if let text = item.textContent {
            pasteboard.setString(text, forType: .string)
        }

        logger.info("Wrote \(item.type.rawValue) content to pasteboard (plain text, RTF and HTML stripped)")
    }

    // MARK: - CGEvent Paste Simulation

    /// Simulate Cmd+V keystroke via CGEvent.
    ///
    /// Uses virtual key code 0x09 (kVK_ANSI_V) which is layout-independent.
    /// Posts to `.cgSessionEventTap` to reach the frontmost app.
    private static func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Suppress local keyboard events during paste to avoid interference
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
}
