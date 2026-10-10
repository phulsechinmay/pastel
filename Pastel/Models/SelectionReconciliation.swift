/// Restores panel selection after a page refresh using clip identity rather than
/// the previous array position. Kept independent of SwiftUI and SwiftData so the
/// transition rules can be checked without launching a clipboard monitor.
enum SelectionReconciliation {
    static func index<ID: Hashable>(priorID: ID?, priorIndex: Int, displayedIDs: [ID]) -> Int? {
        guard !displayedIDs.isEmpty else { return nil }
        if let priorID, let retained = displayedIDs.firstIndex(of: priorID) { return retained }
        return min(max(0, priorIndex), displayedIDs.count - 1)
    }

    static func identities<ID: Hashable>(previous: Set<ID>,
                                           selectedID: ID?,
                                           displayedIDs: [ID],
                                           reset: Bool) -> Set<ID> {
        var result = reset ? Set<ID>() : previous.intersection(displayedIDs)
        if let selectedID { result.insert(selectedID) }
        return result
    }

    static func pageSize(reset: Bool, scanAll: Bool, lastSelectedIndex: Int,
                         initial: Int, maximum: Int) -> Int {
        if reset { return initial }
        if scanAll { return maximum }
        return min(maximum, max(initial, lastSelectedIndex + 2))
    }
}
