import Foundation
import SwiftData

@Model
final class Label {
    var name: String
    var colorName: String
    var sortOrder: Int

    /// Optional emoji that replaces the color dot when set.
    /// Single emoji character (one grapheme cluster) or nil.
    var emoji: String?

    /// Inverse relationship: many labels <-> many clipboard items.
    /// Delete rule: .nullify -- deleting a label removes it from item.labels arrays.
    /// No @Relationship attribute needed -- SwiftData infers the inverse from ClipboardItem.labels.
    var items: [ClipboardItem]

    init(name: String, colorName: String, sortOrder: Int, emoji: String? = nil) {
        self.name = name
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.emoji = emoji
        self.items = []
    }
}
