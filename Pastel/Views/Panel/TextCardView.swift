import SwiftUI

/// Card content for `.text` and `.richText` clipboard items.
///
/// Displays up to 3 lines of the item's text content with standard body font.
struct TextCardView: View {

    let item: ClipboardItem

    var body: some View {
        Text(item.textContent ?? "")
            .font(.system(.callout, design: .default))
            .lineLimit(4)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
