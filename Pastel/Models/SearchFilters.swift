import Foundation

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
/// Applied in memory rather than in `#Predicate`, even though `contentType`,
/// `sourceAppBundleID`, and `timestamp` are all predicate-safe scalars. Changing the
/// `@Query` predicate re-runs the fetch and recreates the view through `.id()`, which
/// is exactly the cost the Phase 26 perf work removed — and filters change on every
/// click. The fetch already returns the full set for label post-filtering, so
/// filtering here adds a pass over an array that was being walked anyway.
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
