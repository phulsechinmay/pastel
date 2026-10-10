import SwiftUI
import AppKit

@MainActor
enum PanelSearchFieldFocus {
    static weak var field: NSTextField?

    static func focusForIncomingKey() {
        guard let field, let window = field.window else { return }
        window.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: editor.string.utf16.count, length: 0)
        }
    }
}

/// NSViewRepresentable wrapper around NSTextField for reliable programmatic focus.
///
/// SwiftUI's `@FocusState` doesn't reliably call `makeFirstResponder()` on TextFields
/// hosted inside NSPanel via NSHostingView when the binding crosses view boundaries.
/// This wrapper gives direct access to AppKit's first-responder chain.
struct FocusableTextField: NSViewRepresentable {

    @Binding var text: String
    var placeholder: String = ""
    /// Point size for the field's text and placeholder. Defaults to 13 (search field);
    /// the inline label-create chip passes 11 to match normal chip text height.
    var fontSize: CGFloat = 13
    /// Monotonically-increasing focus request token. Each time the caller wants
    /// the field focused they increment this value; we observe the change in
    /// `updateNSView` and call `makeFirstResponder`. A counter is used instead
    /// of a `Bool` because once the caller's "please focus" Bool flips to true
    /// it can't fire another `false → true` edge without an intervening reset,
    /// which makes a second focus request invisible if focus was lost in the
    /// meantime (e.g. SwiftUI moved first responder elsewhere).
    var focusRequestID: Int = 0
    var isPanelSearch = false

    /// Invoked when the user presses Return while the field is focused.
    var onSubmit: (() -> Void)?
    var onTab: (() -> Void)?
    /// Invoked when the user presses Escape while the field is focused.
    var onCancel: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.placeholderString = placeholder
        tf.font = .systemFont(ofSize: fontSize)
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.textColor = .labelColor
        tf.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: fontSize)
            ]
        )
        tf.delegate = context.coordinator
        if isPanelSearch { PanelSearchFieldFocus.field = tf }
        context.coordinator.lastPublishedText = text
        // Initialize so the first updateNSView (with focusRequestID == 0)
        // does not steal focus on appear.
        context.coordinator.lastSeenFocusRequestID = focusRequestID
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        if isPanelSearch { PanelSearchFieldFocus.field = tf }
        // AppKit owns the live edit buffer. A parent SwiftUI refresh can arrive
        // while the field editor is still handling a keystroke or IME composition;
        // only push text back into it for an actual external change (e.g. Clear).
        if text != context.coordinator.lastPublishedText, tf.stringValue != text {
            tf.stringValue = text
        }
        context.coordinator.lastPublishedText = text

        // Refresh callbacks each update so the coordinator invokes the latest closures.
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onTab = onTab
        context.coordinator.onCancel = onCancel

        if focusRequestID != context.coordinator.lastSeenFocusRequestID {
            context.coordinator.lastSeenFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                tf.window?.makeFirstResponder(tf)
                // Place cursor at end instead of selecting all text
                if let editor = tf.currentEditor() {
                    editor.selectedRange = NSRange(location: editor.string.count, length: 0)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var lastPublishedText = ""
        var lastSeenFocusRequestID: Int = 0
        var onSubmit: (() -> Void)?
        var onTab: (() -> Void)?
        var onCancel: (() -> Void)?

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            let newText = tf.stringValue
            lastPublishedText = newText
            text = newText
        }

        /// Intercept Return / Escape from the field editor so callers can commit or
        /// cancel. Returning true marks the command handled and suppresses the beep.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                if textView.hasMarkedText() { return false }
                if let onSubmit {
                    onSubmit()
                    return true
                }
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                if let onTab {
                    onTab()
                    return true
                }
            case #selector(NSResponder.cancelOperation(_:)):
                if let onCancel {
                    onCancel()
                    return true
                }
            default:
                break
            }
            return false
        }
    }
}
