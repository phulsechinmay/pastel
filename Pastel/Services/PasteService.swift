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
/// 3. Write item content to NSPasteboard.general via `writeSuppressed`
///    (drains any pending capture, then suppresses our own changeCount)
/// 4. Hide the panel
/// 5. After a delay, simulate Cmd+V via CGEvent
///
/// **Copy mode:**
/// 1. Write item content to NSPasteboard.general via `writeSuppressed`
/// 2. Hide the panel
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
    // MARK: - Paste Choreography

    /// Which Pastel surface a paste is coming from.
    ///
    /// This determines what has to get out of the way before ⌘V can be posted, and
    /// it is the only thing that genuinely differs between the paste entry points.
    enum PasteOrigin {
        /// The sliding panel. Non-activating, so the user's app never lost focus —
        /// but the panel is the *key* window while visible and will eat its own ⌘V,
        /// so it still has to be hidden first.
        case panel(PanelController)

        /// The Settings history browser. A normal activating window: while it is up,
        /// a posted ⌘V lands in Settings itself. It must be ordered out before posting.
        case settings
    }

    /// How `performPaste` treats the user's paste-behavior preference.
    private enum PasteMode {
        /// Honour `PasteBehavior`: post ⌘V unless the user chose copy-only.
        case respectPreference
        /// Never post ⌘V, whatever the preference says — the explicit Copy actions.
        ///
        /// This is a parameter rather than a comment because the difference is one
        /// early return in the middle of a shared sequence, and getting it wrong
        /// makes the Copy button paste.
        case copyOnly
    }

    /// What a paste attempt did. Returned so the branches are named rather than
    /// implied by control flow; `.posted` means the post was *scheduled* after
    /// dismissal, not that it has already happened.
    private enum PasteOutcome {
        case posted
        case copiedOnly
        case blockedSecureInput
        case deniedPermission
        case nothingToWrite
    }

    /// How to get Pastel's own UI out of the way, which differs by origin in a way
    /// that a single "hide" closure cannot express.
    private struct Dismissal {
        /// Ends the interaction without posting: copy-only, blocked, or nothing to
        /// write. The panel closes here; Settings deliberately stays open, because
        /// clicking Copy in a browser you are working in should not close it.
        let finishWithoutPosting: () -> Void

        /// Hands control back once no Pastel window holds keyboard focus, so ⌘V can
        /// be posted safely.
        let beforePosting: (@escaping () -> Void) -> Void
    }

    private func dismissal(for origin: PasteOrigin) -> Dismissal {
        switch origin {
        case .panel(let panelController):
            return Dismissal(
                finishWithoutPosting: { panelController.hide() },
                beforePosting: { post in
                    panelController.hide()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { post() }
                }
            )
        case .settings:
            return Dismissal(
                finishWithoutPosting: {},
                beforePosting: { post in
                    SettingsWindowController.shared.hide()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { post() }
                }
            )
        }
    }

    /// The one paste sequence. Every entry point below is this, with a different
    /// `write` and a different `origin`.
    ///
    /// The steps are ordered so that nothing irreversible happens before the checks
    /// that can cancel it, and so that the pasteboard is never left in a state the
    /// user did not ask for:
    ///
    /// 1. Drain, write, suppress (`writeSuppressed`). A write that resolves to
    ///    nothing leaves the user's clipboard untouched and stops here — posting
    ///    would paste their own stale content.
    /// 2. Explicit copy actions stop here regardless of preference.
    /// 3. The user's `PasteBehavior` preference.
    /// 4. PostEvent permission — probed live every time, never cached.
    /// 5. Secure input — kernel-enforced; nothing can post through it.
    /// 6. Dismiss, then post.
    ///
    /// - Returns: what actually happened. Callers may ignore it.
    @discardableResult
    private func performPaste(
        source: String,
        mode: PasteMode,
        clipboardMonitor: ClipboardMonitor,
        origin: PasteOrigin,
        write: () -> Bool
    ) -> PasteOutcome {
        let dismissal = dismissal(for: origin)

        guard writeSuppressed(clipboardMonitor, write) else {
            pasteLog("[PASTE] nothing to write (source=\(source)) — clipboard left as-is, not posting")
            dismissal.finishWithoutPosting()
            return .nothingToWrite
        }

        if mode == .copyOnly {
            pasteLog("[PASTE] copy-only action (source=\(source)) — no CGEvent")
            dismissal.finishWithoutPosting()
            return .copiedOnly
        }

        if Self.pasteBehavior == .copy {
            pasteLog("[PASTE] behavior=copy (source=\(source)) — write-only, no CGEvent")
            dismissal.finishWithoutPosting()
            return .copiedOnly
        }

        guard AccessibilityService.isGranted else {
            pasteLog("[PASTE] PERMISSION DENIED (source=\(source)) — content is on the clipboard, prompting")
            logger.info("PostEvent not granted -- copied to clipboard, showing permission prompt")
            AccessibilityService.notePasteDeniedDueToPermission()
            dismissal.finishWithoutPosting()
            onAccessibilityRequired?()
            return .deniedPermission
        }

        if IsSecureEventInputEnabled() {
            pasteLog("[PASTE] BLOCKED by secure event input (source=\(source)) — user must ⌘V manually")
            logger.warning("Secure input is active -- wrote to pasteboard only")
            dismissal.finishWithoutPosting()
            Self.showFailureAlert(
                title: "Paste Blocked by Secure Input",
                message: "A password field or banking app has secure input enabled, which prevents Pastel from simulating ⌘V.\n\nThe content is on your clipboard — paste it manually with ⌘V."
            )
            return .blockedSecureInput
        }

        pasteLog("[PASTE] dismissing, will post ⌘V when clear (source=\(source))")
        dismissal.beforePosting {
            let frontmost = NSWorkspace.shared.frontmostApplication
            pasteLog("[PASTE] posting now. frontmostApp=\(frontmost?.localizedName ?? "nil") bundle=\(frontmost?.bundleIdentifier ?? "nil") pid=\(frontmost?.processIdentifier ?? -1)")
            guard Self.simulatePaste() else {
                pasteLog("[PASTE] CGEvent post FAILED (source=\(source)) — event source or events were nil")
                Self.showFailureAlert(
                    title: "Paste Simulation Failed",
                    message: "Pastel could not post the ⌘V keystroke. The event source returned nil — this usually means PostEvent / Accessibility permission was revoked.\n\nThe content is on your clipboard — paste it manually with ⌘V."
                )
                return
            }
            pasteLog("[PASTE] CGEvent posted successfully (source=\(source))")
        }
        return .posted
    }

    // MARK: - Entry Points

    /// Paste a clipboard item into the frontmost app, with full fidelity.
    ///
    /// - Parameters:
    ///   - item: The clipboard item to paste.
    ///   - clipboardMonitor: The monitor to drain before, and suppress after, the write.
    ///   - origin: Which Pastel surface this came from; decides what gets dismissed.
    ///   - source: Free-form tag identifying which UI path triggered the paste (for logging).
    func paste(
        item: ClipboardItem,
        clipboardMonitor: ClipboardMonitor,
        from origin: PasteOrigin,
        source: String = "unknown"
    ) {
        Self.logEntry(method: "paste", source: source, item: item)
        performPaste(
            source: source,
            mode: .respectPreference,
            clipboardMonitor: clipboardMonitor,
            origin: origin
        ) { writeToPasteboard(item: item) }
    }

    /// Paste a clipboard item as plain text (RTF and HTML stripped).
    ///
    /// Receiving apps fall back to their own default styling. For non-text content
    /// types the write is identical to `paste(item:)` — there is no RTF to strip.
    func pastePlainText(
        item: ClipboardItem,
        clipboardMonitor: ClipboardMonitor,
        from origin: PasteOrigin,
        source: String = "unknown"
    ) {
        Self.logEntry(method: "pastePlainText", source: source, item: item)
        performPaste(
            source: source,
            mode: .respectPreference,
            clipboardMonitor: clipboardMonitor,
            origin: origin
        ) { writeToPasteboardPlainText(item: item) }
    }

    /// Paste one or more selected items.
    ///
    /// A single item goes through the full-fidelity path. Multiple items are
    /// newline-joined plain text, with non-text items skipped.
    func paste(
        items: [ClipboardItem],
        clipboardMonitor: ClipboardMonitor,
        from origin: PasteOrigin,
        source: String = "unknown"
    ) {
        guard !items.isEmpty else { return }
        if items.count == 1 {
            paste(item: items[0], clipboardMonitor: clipboardMonitor, from: origin, source: source)
            return
        }
        pasteLog("[PASTE] paste(items) ENTRY count=\(items.count) source=\(source)")
        performPaste(
            source: source,
            mode: .respectPreference,
            clipboardMonitor: clipboardMonitor,
            origin: origin
        ) { writeConcatenatedText(items: items) }
    }

    /// Copy a clipboard item to the pasteboard without simulating ⌘V.
    ///
    /// Ignores the user's paste-behavior preference entirely: this is the explicit
    /// Copy action, and it copies.
    func copyOnly(
        item: ClipboardItem,
        clipboardMonitor: ClipboardMonitor,
        from origin: PasteOrigin
    ) {
        pasteLog("[PASTE] copyOnly() ENTRY itemType=\(item.type.rawValue)")
        performPaste(
            source: "copyOnly",
            mode: .copyOnly,
            clipboardMonitor: clipboardMonitor,
            origin: origin
        ) { writeToPasteboard(item: item) }
    }

    /// Copy one or more selected items to the pasteboard without simulating ⌘V.
    func copyOnly(
        items: [ClipboardItem],
        clipboardMonitor: ClipboardMonitor,
        from origin: PasteOrigin
    ) {
        guard !items.isEmpty else { return }
        if items.count == 1 {
            copyOnly(item: items[0], clipboardMonitor: clipboardMonitor, from: origin)
            return
        }
        pasteLog("[PASTE] copyOnly(items) ENTRY count=\(items.count)")
        performPaste(
            source: "copyOnly(items)",
            mode: .copyOnly,
            clipboardMonitor: clipboardMonitor,
            origin: origin
        ) { writeConcatenatedText(items: items) }
    }

    /// The user's configured paste behavior, read fresh on every paste.
    private static var pasteBehavior: PasteBehavior {
        let raw = UserDefaults.standard.string(forKey: "pasteBehavior") ?? PasteBehavior.paste.rawValue
        return PasteBehavior(rawValue: raw) ?? .paste
    }

    // MARK: - Pasteboard Writing

    /// Drain, write, suppress — in that order, synchronously on the main actor.
    ///
    /// All three steps are load-bearing and the order is not negotiable:
    ///
    /// - **Drain first.** The capture poll runs every 0.5s with 0.1s tolerance, so a
    ///   copy the user made moments ago may not have been recorded yet. Writing over
    ///   it without draining loses it permanently.
    /// - **Suppress by exact changeCount, after the write.** The old `skipNextChange`
    ///   flag meant "skip whatever change I see next", which is a different event from
    ///   "skip the change I just made" the moment the user copies something in between.
    ///
    /// - Returns: whatever `write` returned; on `false` nothing is suppressed because
    ///   nothing was written.
    @discardableResult
    private func writeSuppressed(
        _ clipboardMonitor: ClipboardMonitor,
        _ write: () -> Bool
    ) -> Bool {
        clipboardMonitor.drainPendingChange()
        guard write() else { return false }
        clipboardMonitor.suppressChange(count: NSPasteboard.general.changeCount)
        return true
    }

    /// One resolved pasteboard representation, held so the whole set can be built
    /// *before* anything is cleared. See `commit(_:describing:)`.
    private enum PasteboardWrite {
        case string(String, NSPasteboard.PasteboardType)
        case data(Data, NSPasteboard.PasteboardType)
        /// `writeObjects` appends a new pasteboard item rather than writing into the
        /// first one, which is why URL items carry both a `.string` and this.
        case objects([NSPasteboardWriting])
    }

    /// Resolve everything we intend to put on the pasteboard for this item.
    ///
    /// Every branch here can legitimately produce nothing: an `.image` whose backing
    /// file never synced from CloudKit, or a `.text` snippet the user created but has
    /// not typed into yet (`AppState.createSnippet` inserts one with no `textContent`).
    /// Empty strings count as nothing — the only way to hold one is an edited-to-blank
    /// snippet, since capture rejects empty content.
    private func representations(for item: ClipboardItem) -> [PasteboardWrite] {
        var writes: [PasteboardWrite] = []

        func addString(_ value: String?, _ type: NSPasteboard.PasteboardType) {
            guard let value, !value.isEmpty else { return }
            writes.append(.string(value, type))
        }
        func addData(_ value: Data?, _ type: NSPasteboard.PasteboardType) {
            guard let value, !value.isEmpty else { return }
            writes.append(.data(value, type))
        }

        switch item.type {
        case .text:
            addString(item.textContent, .string)
            addData(item.rtfData, .rtf)
            addString(item.htmlContent, .html)

        case .richText:
            // Write richest format first for maximum fidelity
            addData(item.rtfData, .rtf)
            addString(item.htmlContent, .html)
            addString(item.textContent, .string)

        case .url:
            if let urlString = item.textContent, !urlString.isEmpty {
                writes.append(.string(urlString, .string))
                // Also set as proper URL type for apps that support it
                if let url = URL(string: urlString) {
                    writes.append(.objects([url as NSURL]))
                }
            }

        case .image:
            if let imagePath = item.imagePath {
                let imageURL = ImageStorageService.shared.resolveImageURL(imagePath)
                if let imageData = try? Data(contentsOf: imageURL), !imageData.isEmpty {
                    writes.append(.data(imageData, .png))
                    // Also write TIFF for broader app compatibility
                    if let nsImage = NSImage(data: imageData),
                       let tiffData = nsImage.tiffRepresentation {
                        writes.append(.data(tiffData, .tiff))
                    }
                }
            }

        case .file:
            if let filePath = item.textContent, !filePath.isEmpty {
                writes.append(.objects([URL(fileURLWithPath: filePath) as NSURL]))
            }

        case .code, .color:
            // Code snippets and color values are stored as text
            addString(item.textContent, .string)
        }

        return writes
    }

    /// Clear the pasteboard and write, or do neither.
    ///
    /// `clearContents()` used to run unconditionally before a run of `if let` writes,
    /// so an item that resolved to nothing destroyed whatever the user had copied.
    /// Nothing to write now means the pasteboard is left exactly as it was.
    ///
    /// - Returns: `true` if the pasteboard now holds this item's content.
    private func commit(_ writes: [PasteboardWrite], describing label: String) -> Bool {
        guard !writes.isEmpty else {
            pasteLog("[PASTE] nothing to write for \(label) — pasteboard left untouched")
            logger.warning("Refusing to clear pasteboard: \(label) resolved to no content")
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for write in writes {
            switch write {
            case .string(let value, let type): pasteboard.setString(value, forType: type)
            case .data(let value, let type): pasteboard.setData(value, forType: type)
            case .objects(let objects): pasteboard.writeObjects(objects)
            }
        }

        pasteLog("[PASTE] wrote \(label) to pasteboard (changeCount=\(pasteboard.changeCount))")
        logger.info("Wrote \(label) content to pasteboard")
        return true
    }

    /// Write the clipboard item's content to NSPasteboard.general, preserving all representations.
    /// Returns `false` — leaving the pasteboard untouched — when the item resolves to nothing.
    @discardableResult
    private func writeToPasteboard(item: ClipboardItem) -> Bool {
        commit(representations(for: item), describing: item.type.rawValue)
    }

    /// Write the clipboard item's content to NSPasteboard.general WITHOUT RTF data.
    ///
    /// For text-based types (.text, .richText, .code, .color), omits `.rtf` so receiving
    /// apps fall back to plain text styling. For non-text types (.url, .image, .file),
    /// delegates to `writeToPasteboard(item:)` since these have no RTF to strip.
    /// Returns `false` — leaving the pasteboard untouched — when the item resolves to nothing.
    @discardableResult
    private func writeToPasteboardPlainText(item: ClipboardItem) -> Bool {
        // Non-text types have no RTF -- use normal pasteboard write
        switch item.type {
        case .url, .image, .file:
            return writeToPasteboard(item: item)
        case .text, .richText, .code, .color:
            break
        }

        // Write ONLY plain string -- no .rtf, no .html
        let writes = representations(for: item).filter { write in
            if case .string(_, let type) = write { return type == .string }
            return false
        }
        return commit(writes, describing: "\(item.type.rawValue) (plain text)")
    }

    /// Concatenate the text content of multiple items (newline-joined, non-text items
    /// skipped) and write it to the general pasteboard as plain text.
    /// Returns `false` — leaving the pasteboard untouched — when nothing is copyable.
    @discardableResult
    private func writeConcatenatedText(items: [ClipboardItem]) -> Bool {
        let parts = items.compactMap { item -> String? in
            switch item.type {
            case .text, .richText, .url, .code, .color:
                // Empty is nothing to write, same as a non-text type — see `commit`.
                guard let text = item.textContent, !text.isEmpty else { return nil }
                return text
            case .image, .file:
                return nil
            }
        }
        guard !parts.isEmpty else {
            return commit([], describing: "\(items.count) items (none copyable)")
        }
        return commit(
            [.string(parts.joined(separator: "\n"), .string)],
            describing: "\(parts.count) items as text"
        )
    }

    // MARK: - CGEvent Paste Simulation

    /// Simulate Cmd+V keystroke via CGEvent.
    ///
    /// Uses virtual key code 0x09 (kVK_ANSI_V) which is layout-independent.
    /// Posts to `.cgSessionEventTap` to reach the frontmost app.
    /// Returns `true` when both keyDown and keyUp events were created and posted,
    /// `false` when the event source or events could not be created (permission issue).
    /// Private now that the Settings bulk-paste path no longer hand-rolls its own
    /// sequence around it. Every paste goes through `performPaste`, which is the only
    /// place that knows a post is safe to make.
    @discardableResult
    private static func simulatePaste() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            pasteLog("[PASTE] simulatePaste: CGEventSource(stateID:) returned nil")
            return false
        }

        // Permit *all* local events during the suppression interval that follows a post.
        //
        // This used to omit `.permitLocalKeyboardEvents`, which meant every paste
        // installed a short window where the user's own keystrokes were dropped —
        // type immediately after pasting and lose the first characters. There is no
        // interference to suppress: the ⌘V we post is self-contained.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
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

    private static func logEntry(method: String, source: String, item: ClipboardItem) {
        let preview = (item.textContent ?? "").prefix(40).replacingOccurrences(of: "\n", with: "⏎")
        pasteLog("[PASTE] \(method)() ENTRY source=\(source) type=\(item.type.rawValue) behavior=\(pasteBehavior.rawValue) preview=\"\(preview)\"")
    }

    /// Display an NSAlert so paste failures are user-visible.
    ///
    /// Does *not* call `NSApp.activate(ignoringOtherApps:)`. It used to, which is the
    /// pattern commit d5d1e40 removed everywhere else — and here it was actively
    /// counterproductive: the secure-input alert tells the user to press ⌘V in the app
    /// they were pasting into, while stealing focus from exactly that app.
    private static func showFailureAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
