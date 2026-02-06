/// Defines what happens when the user activates a clipboard item (double-click or Enter).
///
/// Persisted via `@AppStorage("pasteBehavior")`.
enum PasteBehavior: String, CaseIterable {
    /// Write to pasteboard and simulate Cmd+V to paste into frontmost app.
    case paste = "paste"
    /// Write to pasteboard only. User must manually Cmd+V.
    case copy = "copy"
    /// Write to pasteboard and simulate Cmd+V (same as .paste).
    case copyAndPaste = "copyAndPaste"

    /// Human-readable label for display in settings UI.
    var displayName: String {
        switch self {
        case .paste: return "Paste"
        case .copy: return "Copy to Clipboard"
        case .copyAndPaste: return "Copy + Paste"
        }
    }
}
