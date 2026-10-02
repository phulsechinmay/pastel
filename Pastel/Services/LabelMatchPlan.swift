import SwiftData

/// Precomputed label membership check backed by ClipboardItem.labelKey.
/// A nonempty, current labelKey avoids relationship faults; legacy or stale keys
/// still use the authoritative relationship.
struct LabelMatchPlan {
    private let selectedLabelIDs: Set<PersistentIdentifier>
    private let stableNeedles: [String]
    private let selectedLabelsAllIndexed: Bool
    private let knownStableIDs: Set<String>
    private let hasSelectedLabels: Bool

    init(selectedLabelIDs: Set<PersistentIdentifier>, allLabels: [Label]) {
        self.selectedLabelIDs = selectedLabelIDs
        let selectedLabels = allLabels.filter { selectedLabelIDs.contains($0.persistentModelID) }
        hasSelectedLabels = !selectedLabels.isEmpty
        stableNeedles = selectedLabels
            .map(\.stableID)
            .filter { !$0.isEmpty }
            .map { "|\($0)|" }
        selectedLabelsAllIndexed = !selectedLabels.contains { $0.stableID.isEmpty }
        knownStableIDs = Set(allLabels.map(\.stableID).filter { !$0.isEmpty })
    }

    func matches(_ item: ClipboardItem) -> Bool {
        guard hasSelectedLabels else { return false }

        let key = item.labelKey
        if !key.isEmpty,
           stableNeedles.contains(where: { key.contains($0) }) {
            return true
        }

        let keyTokensAllKnown = !key.isEmpty
            && key.split(separator: "|").allSatisfy { knownStableIDs.contains(String($0)) }
        if selectedLabelsAllIndexed && keyTokensAllKnown {
            return false
        }

        return item.safeLabels.contains { label in
            selectedLabelIDs.contains(label.persistentModelID)
        }
    }
}

