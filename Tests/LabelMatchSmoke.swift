import Foundation
import SwiftData

// Compile this smoke test with the production model and LabelMatchPlan files.
enum DeviceIdentifier {
    static let current = "label-smoke-device"
}

@main
struct LabelMatchSmoke {
    @MainActor
    static func main() throws {
        let container = try ModelContainer(
            for: ClipboardItem.self, Label.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let red = Label(name: "Red", colorName: "red", sortOrder: 0)
        let blue = Label(name: "Blue", colorName: "blue", sortOrder: 1)
        let missing = Label(name: "Missing", colorName: "gray", sortOrder: 2)
        context.insert(red)
        context.insert(blue)

        let item = ClipboardItem(textContent: "clip", contentHash: "test-hash")
        item.safeLabels = [red]
        item.labelKey = "|\(red.stableID)|"
        context.insert(item)
        try context.save()

        let redPlan = LabelMatchPlan(selectedLabelIDs: [red.persistentModelID], allLabels: [red, blue])
        let bluePlan = LabelMatchPlan(selectedLabelIDs: [blue.persistentModelID], allLabels: [red, blue])
        precondition(redPlan.matches(item))
        precondition(!bluePlan.matches(item))

        item.labelKey = "|stale-other-device-id|"
        precondition(redPlan.matches(item)) // relationship fallback
        precondition(!bluePlan.matches(item))

        item.labelKey = "|"
        precondition(!bluePlan.matches(item))
        let unresolved = LabelMatchPlan(selectedLabelIDs: [missing.persistentModelID], allLabels: [red, blue])
        precondition(!unresolved.matches(item))
        print("Label match positive, negative, stale and unresolved cases passed")
    }
}
