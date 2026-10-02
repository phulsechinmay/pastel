import Foundation

/// Small copies of clipboard text for UI and classification work.
/// The original content remains on ClipboardItem for paste and full-history search.
enum TextWorkBudget {
    static let cardPreviewBytes = 4 * 1024
    static let cardPreviewLines = 10
    static let codeSampleBytes = 8 * 1024
    static let codeSampleLines = 160

    static func cardPreview(_ text: String?) -> String {
        guard let text else { return "" }
        return prefix(text, maxUTF8Bytes: cardPreviewBytes, maxLines: cardPreviewLines)
    }

    static func codeSample(_ text: String) -> String {
        prefix(text, maxUTF8Bytes: codeSampleBytes, maxLines: codeSampleLines)
    }

    /// Stops reading once either budget is reached, including for one huge line.
    /// Copy scalars into owned storage so a short preview cannot retain a large source buffer.
    static func prefix(_ text: String, maxUTF8Bytes: Int, maxLines: Int) -> String {
        guard maxUTF8Bytes > 0, maxLines > 0 else { return "" }
        var result = String()
        result.reserveCapacity(min(maxUTF8Bytes, 4096))
        var bytes = 0
        var lines = 1

        for scalar in text.unicodeScalars {
            if scalar == "\n" && lines >= maxLines { break }
            let scalarBytes = scalar.utf8.count
            if bytes + scalarBytes > maxUTF8Bytes { break }
            result.unicodeScalars.append(scalar)
            bytes += scalarBytes
            if scalar == "\n" { lines += 1 }
        }
        return result
    }
}
