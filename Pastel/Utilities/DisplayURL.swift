import Foundation

/// A URL split into the part that identifies the *site* and the part that identifies
/// the *page*, so one line of a card can weight the two halves differently.
///
/// Safari's address bar is the precedent: emphasise the host, dim the rest. Both
/// halves matter on a clipboard card, and which one matters more depends entirely on
/// what the neighbouring cards happen to be:
///
/// - Two links to *different* sites are told apart by the domain. Their og:images are
///   often both a generic default banner, so the picture answers nothing.
/// - Two links to *the same* site (two pull requests, two Linear issues, two Notion
///   pages) share a domain, a favicon, and usually an og:image, and frequently have
///   near-identical titles. Only the path tail separates them.
///
/// One treatment covers both cases without a mode switch: when the domain repeats
/// down the list it goes quiet through repetition and the eye lands on the differing
/// tail; when it does not repeat, the emphasised head is the first thing read.
struct DisplayURL {

    /// Host with `www.` removed, lowercased. Never empty.
    let domain: String

    /// Everything after the host: the path, plus the query when the query is what
    /// actually identifies the page. Empty string for a bare domain.
    let remainder: String

    /// Untruncated single-line form. Used where the halves cannot be weighted
    /// separately, such as the hover tooltip that backs the truncated line.
    var combined: String { domain + remainder }

    /// Parse a copied URL string into its display halves.
    ///
    /// Returns nil when the string has no host to lead with, which is the signal for
    /// callers to fall back to printing the raw text. `.url` items are classified on
    /// `url.host != nil` (see `NSPasteboard+Reading`), so in practice this only fails
    /// for malformed history rows.
    init?(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              !host.isEmpty
        else { return nil }

        domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

        // `URLComponents.path` and `.query` hand back percent-decoded values, which is
        // what turns "/Design%20Notes" back into "/Design Notes" for free.
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }

        // The query survives only when the path is too shallow to identify the page on
        // its own. `youtube.com/watch?v=...` and `google.com/search?q=...` *are* their
        // query and read as nothing without it. A four-segment
        // `github.com/owner/repo/pull/4821?tab=files` is already identified by its
        // path, and its query is tracking noise that would eat the width the
        // discriminating tail needs.
        let isPathIdentifying = path.split(separator: "/").count >= 2
        let query = components.query.map { "?" + $0 } ?? ""

        // Fragments are dropped in both cases. They are anchors far more often than
        // identity, and an SPA fragment is long enough to push the real path out of
        // the visible line.
        remainder = path + (isPathIdentifying ? "" : query)
    }
}
