import Foundation
import SwiftData

@Model
final class Label {
    var name: String
    var colorName: String
    var sortOrder: Int

    /// Inverse relationship: one label -> many clipboard items.
    /// Delete rule: .nullify -- deleting a label sets item.label = nil, does NOT delete items.
    @Relationship(deleteRule: .nullify, inverse: \ClipboardItem.label)
    var items: [ClipboardItem]

    init(name: String, colorName: String, sortOrder: Int) {
        self.name = name
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.items = []
    }
}
