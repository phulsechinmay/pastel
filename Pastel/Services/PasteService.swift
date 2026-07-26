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
/// Static helper logger so call sites in other files (and the static methods here)
/// can write [PASTE]-tagged messages that are visible in `log stream --process Pastel`.
let pasteDebugLogger = Logger(subsystem: "app.pastel.Pastel", category: "Paste")

func pasteLog(_ message: String) {
    pasteDebugLogger.notice("\(message, privacy: .public)")
}

@MainActor
final class PasteService {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "PasteService"
    )

    /// Callback invoked when a paste action requires accessibility but it is not granted.
    /// The item has already been copied to the clipboard before this fires.
    var onAccessibilityRequired: (() -> Void)?

    /// Paste a clipboard item into the frontmost app.
    ///
    /// - Parameters:
    ///   - item: The clipboard item to paste.
    ///   - clipboardMonitor: The monitor whose skipNextChange flag will be set.
    ///   - panelController: The panel to hide before simulating paste.
    ///   - source: Free-form tag identifying which UI path triggered the paste (for logging).
    func paste(
        item: ClipboardItem,
        clipboardMonitor: ClipboardMonitor,
        panelController: PanelController,
        source: String = "unknown"
    ) {
        let behaviorRaw = UserDefaults.standard.string(forKey: "pasteBehavior") ?? PasteBehavior.paste.rawValue
        let behavior = PasteBehavior(rawValue: behaviorRaw) ?? .paste

        Self.logEntry(method: "paste", source: source, item: item, behavior: behavior)

        // Copy-only mode: write to pasteboard and hide panel (no accessibility or CGEvent needed)
        if behavior == .copy {
            pasteLog("[PASTE] behavior=copy -> write-only, no CGEvent")
            writeToPasteboard(item: item)
            clipboardMonitor.skipNextChange = true
            panelController.hide()
            logger.info("Copy-only mode -- wrote to pasteboard, skipping Cmd+V simulation")
            return
        }

        // Paste / Copy+Paste mode: full flow with Cmd+V simulation

        // 1. Check Accessibility permission (never cache -- can be revoked at any time)
        let axTrusted = AXIsProcessTrusted()
        let cgPreflight = CGPreflightPostEventAccess()
        let granted = AccessibilityService.isGranted
        pasteLog("[PASTE] permission probe: isGranted=\(granted) AXIsProcessTrusted=\(axTrusted) CGPreflightPostEventAccess=\(cgPreflight) sandboxed=\(Self.isSandboxed)")
        guard granted else {
            pasteLog("[PASTE] PERMISSION DENIED — copying to clipboard and showing permission prompt (source=\(source))")
            AccessibilityService.notePasteDeniedDueToPermission()
            writeToPasteboard(item: item)
            clipboardMonitor.skipNextChange = true
            panelController.hide()
            logger.info("Accessibility not granted -- copied to clipboard, showing permission prompt")
            onAccessibilityRequired?()
            return
        }

        // 2. Check secure input (password fields, banking apps)
        if IsSecureEventInputEnabled() {
            pasteLog("[PASTE] BLOCKED: secure event input is active — copying only, user must Cmd+V manually")
            logger.warning("Secure input is active -- writing to pasteboard only (user must Cmd+V manually)")
            writeToPasteboard(item: item)
            clipboardMonitor.skipNextChange = true
            panelController.hide()
            Self.showFailureAlert(
                title: "Paste Blocked by Secure Input",
                message: "A password field or banking app has secure input enabled, which prevents Pastel from simulating ⌘V.\n\nThe item is on your clipboard — paste it manually with ⌘V."
            )
            return
        }

        // 3. Write item content to pasteboard
        writeToPasteboard(item: item)

        // 4. Signal monitor to skip the next change (self-paste loop prevention)
        clipboardMonitor.skipNextChange = true

        // 5. Hide panel
        panelController.hide()
        pasteLog("[PASTE] panel.hide() called, scheduling CGEvent Cmd+V in 250ms (source=\(source))")

        // 6. Simulate Cmd+V after 250ms delay (must exceed panel hide animation + previous app re-activation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let frontmost = NSWorkspace.shared.frontmostApplication
            pasteLog("[PASTE] CGEvent firing now. frontmostApp=\(frontmost?.localizedName ?? "nil") bundle=\(frontmost?.bundleIdentifier ?? "nil") pid=\(frontmost?.processIdentifier ?? -1)")
            let posted = Self.simulatePaste()
            if !posted {
                pasteLog("[PASTE] CGEvent post FAILED — keyboard event source or events were nil (likely permission revoked between probe and post)")
                Self.showFailureAlert(
                    title: "Paste Simulation Failed",
                    message: "Pastel could not post the ⌘V keystroke. The event source returned nil — this usually means PostEvent / Accessibility permission was revoked.\n\nThe item is on your clipboard — paste it manually with ⌘V."
                )
            } else {
                pasteLog("[PASTE] CGEvent posted successfully (source=\(source))")
            }
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
        pasteLog("[PASTE] copyOnly() entry itemType=\(item.type.rawValue)")
        writeToPasteboard(item: item)
        clipboardMonitor.skipNextChange = true
        panelController.hide()
        logger.info("Copy-only (explicit) -- wrote \(item.type.rawValue) to pasteboard")
    }

    /// Copy one or more selected items to the pasteboard without simulating Cmd+V.
    ///
    /// A single item is written with full fidelity (rtf/html/image/file) via the
    /// single-item path. Multiple items are concatenated as newline-joined plain
    /// text (non-text items skipped), matching the Settings history bulk-copy.
    /// Always hides the panel afterward, mirroring the single-item copyOnly.
    func copyOnly(
        items: [ClipboardItem],
        clipboardMonitor: ClipboardMonitor,
        panelController: PanelController
    ) {
        guard !items.isEmpty else { return }
        if items.count == 1 {
            copyOnly(item: items[0], clipboardMonitor: clipboardMonitor, panelController: panelController)
            return
        }
        pasteLog("[PASTE] copyOnly(items) entry count=\(items.count)")
        let wrote = writeConcatenatedText(items: items)
        clipboardMonitor.skipNextChange = true
        panelController.hide()
        logger.info("Copy-only (multi) -- wrote \(items.count) items (\(wrote ? "text" : "nothing copyable"))")
    }

    /// Paste one or more selected items into the frontmost app.
    ///
    /// A single item delegates to the full-fidelity `paste(item:)`. Multiple items
    /// are written as newline-joined plain text and pasted via the same permission /
    /// secure-input / CGEvent flow used by `paste(item:)`.
    func paste(
        items: [ClipboardItem],
        clipboardMonitor: ClipboardMonitor,
        panelController: PanelController,
        source: String = "unknown"
    ) {
        guard !items.isEmpty else { return }
        if items.count == 1 {
            paste(item: items[0], clipboardMonitor: clipboardMonitor, panelController: panelController, source: source)
            return
        }

        let behaviorRaw = UserDefaults.standard.string(forKey: "pasteBehavior") ?? PasteBehavior.paste.rawValue
        let behavior = PasteBehavior(rawValue: behaviorRaw) ?? .paste
        pasteLog("[PASTE] paste(items) entry count=\(items.count) behavior=\(behavior.rawValue) source=\(source)")

        // Nothing copyable (e.g. only images/files selected): hide and bail.
        guard writeConcatenatedText(items: items) else {
            panelController.hide()
            return
        }
        clipboardMonitor.skipNextChange = true

        if behavior == .copy {
            pasteLog("[PASTE] (items) behavior=copy -> write-only, no CGEvent")
            panelController.hide()
            return
        }

        guard AccessibilityService.isGranted else {
            pasteLog("[PASTE] (items) PERMISSION DENIED — copied to clipboard, showing prompt")
            AccessibilityService.notePasteDeniedDueToPermission()
            panelController.hide()
            onAccessibilityRequired?()
            return
        }

        if IsSecureEventInputEnabled() {
            pasteLog("[PASTE] (items) BLOCKED: secure event input is active")
            panelController.hide()
            Self.showFailureAlert(
                title: "Paste Blocked by Secure Input",
                message: "A password field or banking app has secure input enabled, which prevents Pastel from simulating ⌘V.\n\nThe items are on your clipboard — paste them manually with ⌘V."
            )
            return
        }

        panelController.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let posted = Self.simulatePaste()
            pasteLog("[PASTE] (items) CGEvent posted=\(posted) (source=\(source))")
        }
    }

    /// Concatenate the text content of multiple items (newline-joined, non-text
    /// items skipped) and write it to the general pasteboard as plain text.
    /// Returns false when nothing was written (all items were non-text).
    @discardableResult
    private func writeConcatenatedText(items: [ClipboardItem]) -> Bool {
        let parts = items.compactMap { item -> String? in
            switch item.type {
            case .text, .richText, .url, .code, .color:
                return item.textContent
            case .image, .file:
                return nil
            }
        }
        guard !parts.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(parts.joined(separator: "\n"), forType: .string)
        return true
    }

    /// Paste a clipboard item as plain text (RTF stripped) into the frontmost app.
    ///
    /// Follows the same flow as `paste()` but uses `writeToPasteboardPlainText(item:)` which
    /// omits the `.rtf` data type, causing receiving apps to fall back to plain text styling.
    /// For non-text content types (url, image, file), delegates to normal `writeToPasteboard(item:)`.
    func pastePlainText(
        item: ClipboardItem,
        clipboardMonitor: ClipboardMonitor,
        panelController: PanelController,
        source: String = "unknown"
    ) {
        let behaviorRaw = UserDefaults.standard.string(forKey: "pasteBehavior") ?? PasteBehavior.paste.rawValue
        let behavior = PasteBehavior(rawValue: behaviorRaw) ?? .paste

        Self.logEntry(method: "pastePlainText", source: source, item: item, behavior: behavior)

        if behavior == .copy {
            pasteLog("[PASTE] behavior=copy (plain) -> write-only, no CGEvent")
            writeToPasteboardPlainText(item: item)
            clipboardMonitor.skipNextChange = true
            panelController.hide()
            logger.info("Copy-only mode (plain text) -- wrote to pasteboard, skipping Cmd+V simulation")
            return
        }

        let axTrustedPT = AXIsProcessTrusted()
        let cgPreflightPT = CGPreflightPostEventAccess()
        let grantedPT = AccessibilityService.isGranted
        pasteLog("[PASTE] (plain) permission probe: isGranted=\(grantedPT) AXIsProcessTrusted=\(axTrustedPT) CGPreflightPostEventAccess=\(cgPreflightPT)")
        guard grantedPT else {
            pasteLog("[PASTE] (plain) PERMISSION DENIED — copying plain text to clipboard and showing permission prompt (source=\(source))")
            AccessibilityService.notePasteDeniedDueToPermission()
            writeToPasteboardPlainText(item: item)
            clipboardMonitor.skipNextChange = true
            panelController.hide()
            logger.info("Accessibility not granted -- copied plain text to clipboard, showing permission prompt")
            onAccessibilityRequired?()
            return
        }

        if IsSecureEventInputEnabled() {
            pasteLog("[PASTE] (plain) BLOCKED: secure event input is active")
            logger.warning("Secure input is active -- writing plain text to pasteboard only (user must Cmd+V manually)")
            writeToPasteboardPlainText(item: item)
            clipboardMonitor.skipNextChange = true
            panelController.hide()
            Self.showFailureAlert(
                title: "Paste Blocked by Secure Input",
                message: "A password field or banking app has secure input enabled, which prevents Pastel from simulating ⌘V.\n\nThe item is on your clipboard — paste it manually with ⌘V."
            )
            return
        }

        writeToPasteboardPlainText(item: item)
        clipboardMonitor.skipNextChange = true
        panelController.hide()
        pasteLog("[PASTE] (plain) panel.hide() called, scheduling CGEvent Cmd+V in 250ms (source=\(source))")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let frontmost = NSWorkspace.shared.frontmostApplication
            pasteLog("[PASTE] (plain) CGEvent firing now. frontmostApp=\(frontmost?.localizedName ?? "nil") bundle=\(frontmost?.bundleIdentifier ?? "nil")")
            let posted = Self.simulatePaste()
            if !posted {
                pasteLog("[PASTE] (plain) CGEvent post FAILED")
                Self.showFailureAlert(
                    title: "Paste Simulation Failed",
                    message: "Pastel could not post the ⌘V keystroke. The event source returned nil — this usually means PostEvent / Accessibility permission was revoked.\n\nThe item is on your clipboard — paste it manually with ⌘V."
                )
            } else {
                pasteLog("[PASTE] (plain) CGEvent posted successfully (source=\(source))")
            }
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

        pasteLog("[PASTE] wrote \(item.type.rawValue) to pasteboard (changeCount=\(pasteboard.changeCount))")
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

        pasteLog("[PASTE] wrote \(item.type.rawValue) to pasteboard (plain text, changeCount=\(pasteboard.changeCount))")
        logger.info("Wrote \(item.type.rawValue) content to pasteboard (plain text, RTF and HTML stripped)")
    }

    // MARK: - CGEvent Paste Simulation

    /// Simulate Cmd+V keystroke via CGEvent.
    ///
    /// Uses virtual key code 0x09 (kVK_ANSI_V) which is layout-independent.
    /// Posts to `.cgSessionEventTap` to reach the frontmost app.
    /// Returns `true` when both keyDown and keyUp events were created and posted,
    /// `false` when the event source or events could not be created (permission issue).
    @discardableResult
    static func simulatePaste() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            pasteLog("[PASTE] simulatePaste: CGEventSource(stateID:) returned nil")
            return false
        }

        // Suppress local keyboard events during paste to avoid interference
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            pasteLog("[PASTE] simulatePaste: CGEvent(keyboardEventSource:) returned nil")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return true
    }

    // MARK: - Logging & Alert helpers

    private static let isSandboxed: Bool = {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }()

    private static func logEntry(method: String, source: String, item: ClipboardItem, behavior: PasteBehavior) {
        let preview = (item.textContent ?? "").prefix(40).replacingOccurrences(of: "\n", with: "⏎")
        pasteLog("[PASTE] \(method)() ENTRY source=\(source) type=\(item.type.rawValue) behavior=\(behavior.rawValue) preview=\"\(preview)\"")
    }

    /// Display a non-blocking NSAlert so paste failures are user-visible.
    /// Activates the app (so the panel hide doesn't leave the alert hidden behind
    /// the previous frontmost app) and uses .informational style.
    private static func showFailureAlert(title: String, message: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
