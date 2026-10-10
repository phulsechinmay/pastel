import Foundation

@main
struct UXActionPolicySmoke {
    static func main() {
        let preferences: [(String?, PasteBehavior)] = [
            (nil, .copy),
            (PasteBehavior.copy.rawValue, .copy),
            (PasteBehavior.paste.rawValue, .paste),
            (PasteBehavior.copyAndPaste.rawValue, .paste),
            ("unknown", .copy),
        ]
        for (stored, expected) in preferences {
            precondition(PasteBehavior.resolved(stored) == expected)
        }

        for behavior in PasteBehavior.allCases {
            precondition(!behavior.postsPaste(for: .explicitCopy))
            precondition(behavior.postsPaste(for: .explicitPaste))
            precondition(behavior.postsPaste(for: .activation) == (behavior == .paste))
        }
        precondition(PasteBehavior.allCases == [.paste, .copy])
        print("UX action policy: all intent and migration cases passed")
    }
}
