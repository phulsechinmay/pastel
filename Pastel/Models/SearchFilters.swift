import Foundation

/// A source app present in clipboard history, for the app filter menu.
struct SourceAppOption: Identifiable, Equatable, Sendable {
    let bundleID: String
    let name: String

    var id: String { bundleID }

    /// Distinct source apps in a recent, bounded history sample.
    static func derive(from items: [ClipboardItem], limit: Int = 12) -> [SourceAppOption] {
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        for item in items {
            guard let bundleID = item.sourceAppBundleID, !bundleID.isEmpty else { continue }
            counts[bundleID, default: 0] += 1
            if names[bundleID] == nil { names[bundleID] = item.sourceAppName ?? bundleID }
        }
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value
                ? (names[lhs.key] ?? lhs.key) < (names[rhs.key] ?? rhs.key)
                : lhs.value > rhs.value
        }
        .prefix(limit)
        .map { SourceAppOption(bundleID: $0.key, name: names[$0.key] ?? $0.key) }
    }
}

/// Preset time windows for the date filter.
///
/// Presets only, deliberately — a full date picker costs more panel space than the
/// query it answers is worth ("the thing I copied yesterday" is the real use case).
enum DateRangeFilter: String, CaseIterable, Identifiable, Sendable {
    case today = "Today"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"

    var id: String { rawValue }

    /// Earliest timestamp included by this range.
    func cutoff(from now: Date = .now) -> Date {
        let calendar = Calendar.current
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .last7Days:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30Days:
            return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        }
    }
}

/// Non-text search filters applied alongside the text query and label chips.
///
/// Composition rule (plan decision Q4.5): **OR within a group, AND across groups**.
/// Picking Text + Image widens; adding Today narrows. This matches how the label
/// chips already behave, so the two selections read consistently.
///
/// Applied in the SQLite metadata query once the local index is ready. During
/// backfill, the background page worker applies the same rules to bounded batches.
struct SearchFilters: Equatable, Sendable {

    /// Empty means "any type".
    var types: Set<ContentType> = []

    /// Empty means "any app". Matched against `sourceAppBundleID`.
    var appBundleIDs: Set<String> = []

    /// Nil means "any time".
    var dateRange: DateRangeFilter?

    /// Whether anything is actually being filtered.
    var isEmpty: Bool {
        types.isEmpty && appBundleIDs.isEmpty && dateRange == nil
    }

    /// Number of active filter groups, for the toolbar badge.
    var activeGroupCount: Int {
        var count = 0
        if !types.isEmpty { count += 1 }
        if !appBundleIDs.isEmpty { count += 1 }
        if dateRange != nil { count += 1 }
        return count
    }

    mutating func removeAll() {
        types.removeAll()
        appBundleIDs.removeAll()
        dateRange = nil
    }

    /// Whether `item` passes every active group.
    ///
    /// - Parameter cutoff: Precomputed date cutoff, so a list-wide filter pass doesn't
    ///   recompute the same calendar math per item.
    func matches(_ item: ClipboardItem, cutoff: Date?) -> Bool {
        if !types.isEmpty, !types.contains(item.type) { return false }

        if !appBundleIDs.isEmpty {
            guard let bundleID = item.sourceAppBundleID, appBundleIDs.contains(bundleID) else {
                return false
            }
        }

        if let cutoff, item.timestamp < cutoff { return false }

        return true
    }
}

// MARK: - Display Helpers

extension ContentType {
    /// Menu label for the type filter.
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .url: return "Link"
        case .image: return "Image"
        case .file: return "File"
        case .code: return "Code"
        case .color: return "Color"
        }
    }

    /// SF Symbol shown beside the type in the filter menu.
    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .url: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        }
    }
}
