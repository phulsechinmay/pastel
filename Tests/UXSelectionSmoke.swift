import Foundation

@main
struct UXSelectionSmoke {
    static func main() {
        let clips = ["a", "b", "c", "d"]
        precondition(SelectionReconciliation.index(priorID: nil as String?,
            priorIndex: 0, displayedIDs: clips) == 0)
        precondition(SelectionReconciliation.index(priorID: "c",
            priorIndex: 2, displayedIDs: ["new"] + clips) == 3)
        precondition(SelectionReconciliation.index(priorID: "c",
            priorIndex: 2, displayedIDs: ["a", "b", "d"]) == 2)
        precondition(SelectionReconciliation.index(priorID: "c",
            priorIndex: 2, displayedIDs: []) == nil)
        precondition(SelectionReconciliation.identities(previous: ["b", "c", "d"],
            selectedID: "c", displayedIDs: ["new", "d", "b", "c"], reset: false)
            == ["b", "c", "d"])
        precondition(SelectionReconciliation.identities(previous: ["b", "c", "d"],
            selectedID: "a", displayedIDs: clips, reset: true) == ["a"])
        precondition(SelectionReconciliation.pageSize(reset: false, scanAll: false,
            lastSelectedIndex: 11, initial: 12, maximum: 150) == 13)
        precondition(SelectionReconciliation.pageSize(reset: false, scanAll: true,
            lastSelectedIndex: 11, initial: 12, maximum: 150) == 150)
        print("UX selection: initial, insert, remove, range, reset, and paging passed")
    }
}
