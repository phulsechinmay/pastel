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
    var requestFocus: Bool = false

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
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        if tf.stringValue != text {
            tf.stringValue = text
        }

        // Focus on false→true transition
        if requestFocus, !context.coordinator.wasFocused {
            DispatchQueue.main.async {
                tf.window?.makeFirstResponder(tf)
                // Place cursor at end instead of selecting all text
                if let editor = tf.currentEditor() {
                    editor.selectedRange = NSRange(location: editor.string.count, length: 0)
                }
            }
        }
        context.coordinator.wasFocused = requestFocus
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var wasFocused = false

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            text = tf.stringValue
        }
    }
}
