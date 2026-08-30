import Carbon
import CoreGraphics
import Foundation
import OSLog

/// Resolves the virtual key code that produces a given character on the *active*
/// keyboard layout.
///
/// Virtual key codes name physical key positions, not characters. `0x09` is where V
/// sits on ANSI; on Dvorak that same key produces "K", so posting `0x09` with Command
/// sends ⌘K — "add link" in Slack and Notion, "clear scrollback" in Terminal. The
/// long-standing comment in `PasteService` calling `0x09` layout-independent had it
/// exactly backwards.
///
/// The blast radius is narrower than it sounds, because macOS ships
/// "Dvorak - QWERTY ⌘" and many Dvorak users run it — but plain Dvorak, Colemak and
/// friends get a wrong and occasionally destructive action.
@MainActor
enum KeyboardLayoutService {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "KeyboardLayout"
    )

    /// ANSI V. The fallback whenever the active source has no resolvable layout —
    /// which is the right answer for the overwhelming majority of users.
    static let ansiV: CGKeyCode = 0x09

    private static var cachedPasteKeyCode: CGKeyCode?
    private static var isObserving = false

    /// The key code to post, with Command, to mean Paste on the active layout.
    static var pasteKeyCode: CGKeyCode {
        startObservingIfNeeded()
        if let cachedPasteKeyCode { return cachedPasteKeyCode }

        let resolved = resolveKeyCode(producing: "v") ?? ansiV
        if resolved != ansiV {
            logger.info("Active layout produces 'v' at key code \(resolved), not \(ansiV)")
        }
        cachedPasteKeyCode = resolved
        return resolved
    }

    /// Drop the cache when the user switches input source.
    ///
    /// `kTISNotifySelectedKeyboardInputSourceChanged` is broadcast on the
    /// **distributed** notification center; it never arrives on `NotificationCenter.default`.
    private static func startObservingIfNeeded() {
        guard !isObserving else { return }
        isObserving = true
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                cachedPasteKeyCode = nil
                logger.info("Input source changed — key code cache invalidated")
            }
        }
    }

    /// Scan every key code for the one that produces `character` on the active layout.
    ///
    /// - Returns: the lowest matching key code, or `nil` if the active source exposes
    ///   no Unicode layout data.
    private static func resolveKeyCode(producing character: Character) -> CGKeyCode? {
        // `TISCopyCurrentKeyboardLayoutInputSource`, not `TISCopyCurrentKeyboardInputSource`:
        // the latter returns the *input method* for CJK sources, which carries no
        // `kTISPropertyUnicodeKeyLayoutData` at all.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())
        let target = String(character).lowercased()

        return layoutData.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let base = buffer.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)

            for keyCode in 0..<CGKeyCode(128) {
                // Translate *with Command held*. "Dvorak - QWERTY ⌘" carries a separate
                // command-state table that reverts to QWERTY, so translating without
                // Command yields the wrong key code for precisely the layout that was
                // trying to help. UCKeyTranslate wants the modifiers in the high byte
                // of the Carbon modifier word.
                let modifierState = UInt32(cmdKey >> 8) & 0xFF
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)

                let status = UCKeyTranslate(
                    layout,
                    keyCode,
                    UInt16(kUCKeyActionDown),
                    modifierState,
                    keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    characters.count,
                    &length,
                    &characters
                )

                guard status == noErr, length > 0 else { continue }
                let produced = String(utf16CodeUnits: characters, count: length).lowercased()
                if produced == target { return keyCode }
            }
            return nil
        }
    }
}
