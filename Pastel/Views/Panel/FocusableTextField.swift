import SwiftUI
import AppKit

/// NSViewRepresentable wrapper around NSTextField for reliable programmatic focus.
///
/// SwiftUI's `@FocusState` doesn't reliably call `makeFirstResponder()` on TextFields
/// hosted inside NSPanel via NSHostingView when the binding crosses view boundaries.
/// This wrapper gives direct access to AppKit's first-responder chain.
struct FocusableTextField: NSViewRepresentable {

    @Binding var text: String
    var placeholder: String = ""
    /// Monotonically-increasing focus request token. Each time the caller wants
    /// the field focused they increment this value; we observe the change in
    /// `updateNSView` and call `makeFirstResponder`. A counter is used instead
    /// of a `Bool` because once the caller's "please focus" Bool flips to true
    /// it can't fire another `false → true` edge without an intervening reset,
    /// which makes a second focus request invisible if focus was lost in the
    /// meantime (e.g. SwiftUI moved first responder elsewhere).
    var focusRequestID: Int = 0

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.placeholderString = placeholder
        tf.font = .systemFont(ofSize: 13)
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.textColor = .white
        tf.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 13)
            ]
        )
        tf.delegate = context.coordinator
        // Initialize so the first updateNSView (with focusRequestID == 0)
        // does not steal focus on appear.
        context.coordinator.lastSeenFocusRequestID = focusRequestID
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        if tf.stringValue != text {
            tf.stringValue = text
        }

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
        var lastSeenFocusRequestID: Int = 0

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            text = tf.stringValue
        }
    }
}
