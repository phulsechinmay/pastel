/// Defines what happens when the user activates a clipboard item (double-click or Enter).
///
/// Persisted via `@AppStorage("pasteBehavior")`.
enum PasteBehavior: String, CaseIterable {
    static var allCases: [PasteBehavior] { [.paste, .copy] }

    static func resolved(_ raw: String?) -> PasteBehavior {
        switch raw {
        case PasteBehavior.copy.rawValue: return .copy
        case PasteBehavior.paste.rawValue, PasteBehavior.copyAndPaste.rawValue: return .paste
        default: return .copy // matches the fresh-install UI default
        }
    }
    /// Write to pasteboard and simulate Cmd+V to paste into frontmost app.
    case paste = "paste"
    /// Write to pasteboard only. User must manually Cmd+V.
    case copy = "copy"
    /// Write to pasteboard and simulate Cmd+V (same as .paste).
    case copyAndPaste = "copyAndPaste"

    /// Human-readable label for display in settings UI.
    var displayName: String {
        switch self {
        case .paste: return "Paste into active app"
        case .copy: return "Copy to Clipboard"
        case .copyAndPaste: return "Paste into active app"
        }
    }
}
