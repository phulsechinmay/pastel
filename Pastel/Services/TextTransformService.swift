import Foundation

/// A single named text transformation.
///
/// Transforms are pure `String -> String?` functions with no knowledge of SwiftData
/// or the clipboard. `nil` means "this input can't be transformed" (invalid JSON,
/// malformed Base64), which the menu surfaces as a disabled item rather than a
/// silent no-op.
struct TextTransform: Identifiable, Sendable {

    /// Menu grouping. Order of the cases is the order sections appear in the submenu.
    enum Group: String, CaseIterable, Sendable {
        case caseConversion = "Case"
        case whitespace = "Whitespace"
        case lines = "Lines"
        case encoding = "Encoding"
        case structured = "JSON & URL"
    }

    let id: String
    let name: String
    let group: Group

    /// Produces the transformed text, or nil when the input isn't valid for it.
    let apply: @Sendable (String) -> String?

    /// Cheap pre-check used to disable the menu item without running `apply` on
    /// potentially large content. Defaults to always-enabled; only the fallible
    /// transforms override it.
    let canApply: @Sendable (String) -> Bool

    init(
        id: String,
        name: String,
        group: Group,
        canApply: @escaping @Sendable (String) -> Bool = { _ in true },
        apply: @escaping @Sendable (String) -> String?
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.canApply = canApply
        self.apply = apply
    }
}

/// Declarative registry of built-in text transforms.
///
/// Single source of truth, the way `LabelColor` drives every label picker: the card
/// context menu reads this list, and any future Settings UI reads the same one.
///
/// Deliberately excluded for now (see the plan's Q3.3/Q3.5): automatic-on-capture
/// transforms, which would mutate content before `contentHash` is computed, and
/// user-authored JavaScript transforms, which carry App Review risk in the sandboxed
/// App Store build.
enum TextTransformService {

    /// Query parameters stripped by `stripTracking`. Covers the common ad-network and
    /// analytics families; deliberately not exhaustive, since over-stripping can break
    /// legitimate links.
    private static let trackingParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_name", "utm_reader", "utm_social", "utm_brand",
        "gclid", "gclsrc", "dclid", "fbclid", "msclkid", "twclid", "igshid",
        "mc_cid", "mc_eid", "_hsenc", "_hsmi", "hsCtaTracking",
        "yclid", "vero_id", "wickedid", "s_kwcid", "ef_id",
        "ref", "referrer", "source",
    ]

    static let all: [TextTransform] = [
        // MARK: Case

        TextTransform(id: "uppercase", name: "UPPERCASE", group: .caseConversion) {
            $0.uppercased()
        },
        TextTransform(id: "lowercase", name: "lowercase", group: .caseConversion) {
            $0.lowercased()
        },
        TextTransform(id: "capitalize", name: "Capitalize Words", group: .caseConversion) {
            $0.capitalized
        },

        // MARK: Whitespace

        TextTransform(id: "trim", name: "Trim Whitespace", group: .whitespace) {
            // Trims the ends of every line as well as the whole string, which is what
            // "trim" means for pasted code and copied table cells.
            $0.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        },
        TextTransform(id: "collapseSpaces", name: "Collapse Repeated Spaces", group: .whitespace) {
            $0.replacingOccurrences(
                of: "[ \\t]+",
                with: " ",
                options: .regularExpression
            )
        },
        TextTransform(id: "collapseBlankLines", name: "Remove Blank Lines", group: .whitespace) {
            $0.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
        },

        // MARK: Lines

        TextTransform(id: "sortLines", name: "Sort Lines", group: .lines) {
            $0.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .joined(separator: "\n")
        },
        TextTransform(id: "dedupeLines", name: "Remove Duplicate Lines", group: .lines) {
            var seen = Set<String>()
            return $0.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { seen.insert($0).inserted }
                .joined(separator: "\n")
        },
        TextTransform(id: "reverseLines", name: "Reverse Line Order", group: .lines) {
            $0.split(separator: "\n", omittingEmptySubsequences: false)
                .reversed()
                .joined(separator: "\n")
        },

        // MARK: Encoding

        TextTransform(id: "base64Encode", name: "Base64 Encode", group: .encoding) {
            Data($0.utf8).base64EncodedString()
        },
        TextTransform(
            id: "base64Decode",
            name: "Base64 Decode",
            group: .encoding,
            canApply: { isProbablyBase64($0) }
        ) {
            guard let data = Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let decoded = String(data: data, encoding: .utf8) else { return nil }
            return decoded
        },
        TextTransform(id: "urlEncode", name: "URL Encode", group: .encoding) {
            $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~")))
        },
        TextTransform(
            id: "urlDecode",
            name: "URL Decode",
            group: .encoding,
            canApply: { $0.contains("%") }
        ) {
            $0.removingPercentEncoding
        },

        // MARK: JSON & URL

        TextTransform(
            id: "jsonPretty",
            name: "Pretty-Print JSON",
            group: .structured,
            canApply: { looksLikeJSON($0) }
        ) {
            reformatJSON($0, pretty: true)
        },
        TextTransform(
            id: "jsonMinify",
            name: "Minify JSON",
            group: .structured,
            canApply: { looksLikeJSON($0) }
        ) {
            reformatJSON($0, pretty: false)
        },
        TextTransform(
            id: "stripTracking",
            name: "Strip Tracking Parameters",
            group: .structured,
            canApply: { hasQueryParameters($0) }
        ) {
            stripTrackingParameters(from: $0)
        },
    ]

    /// Transforms in `group`, in registry order.
    static func transforms(in group: TextTransform.Group) -> [TextTransform] {
        all.filter { $0.group == group }
    }

    // MARK: - Applicability Heuristics

    /// Cheap structural check — avoids running `JSONSerialization` over a large clip
    /// just to decide whether to enable a menu item.
    private static func looksLikeJSON(_ text: String) -> Bool {
        guard let first = text.first(where: { !$0.isWhitespace }) else { return false }
        return first == "{" || first == "["
    }

    private static func isProbablyBase64(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.count % 4 == 0 else { return false }
        let base64Characters = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        return trimmed.unicodeScalars.allSatisfy { base64Characters.contains($0) }
    }

    private static func hasQueryParameters(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else { return false }
        return components.scheme != nil && !(components.queryItems ?? []).isEmpty
    }

    // MARK: - Transform Implementations

    private static func reformatJSON(_ text: String, pretty: Bool) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }

        // .sortedKeys keeps pretty-printing deterministic — without it, re-running the
        // transform can reorder keys and produce a different hash each time.
        var options: JSONSerialization.WritingOptions = [.withoutEscapingSlashes, .fragmentsAllowed]
        if pretty {
            options.insert(.prettyPrinted)
            options.insert(.sortedKeys)
        }

        guard let output = try? JSONSerialization.data(withJSONObject: object, options: options),
              let string = String(data: output, encoding: .utf8)
        else { return nil }
        return string
    }

    private static func stripTrackingParameters(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let queryItems = components.queryItems
        else { return nil }

        let kept = queryItems.filter { !trackingParameters.contains($0.name.lowercased()) }
        guard kept.count != queryItems.count else { return trimmed }

        // An empty array would still render a trailing "?" — nil drops it entirely.
        components.queryItems = kept.isEmpty ? nil : kept
        return components.string
    }
}
