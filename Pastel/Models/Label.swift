import Foundation
import SwiftData

@Model
final class Label {
    var name: String = ""
    var colorName: String = "blue"
    var sortOrder: Int = 0

    /// Optional emoji that replaces the color dot when set.
    /// Single emoji character (one grapheme cluster) or nil.
    var emoji: String?

    /// Inverse relationship: many labels <-> many clipboard items.
    /// Delete rule: .nullify -- deleting a label removes it from item.labels arrays.
    /// No @Relationship attribute needed -- SwiftData infers the inverse from ClipboardItem.labels.
    /// Optional for CloudKit compatibility (Phase 19).
    var items: [ClipboardItem]?

    /// Nil-safe access to items array.
    var safeItems: [ClipboardItem] {
        get { items ?? [] }
        set { items = newValue }
    }

    init(name: String, colorName: String, sortOrder: Int, emoji: String? = nil) {
        self.name = name
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.emoji = emoji
        self.items = []
    }
}
