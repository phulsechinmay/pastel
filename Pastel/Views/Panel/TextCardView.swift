import SwiftUI

/// Card content for `.text` and `.richText` clipboard items.
///
/// Displays up to 4 lines outside the compact strip. Strip previews reserve a
/// stable bottom metadata/shortcut baseline and use fewer lines when titled.
struct TextCardView: View {

    let item: ClipboardItem
    var isCompactStrip = false

    var body: some View {
        Text(TextWorkBudget.cardPreview(item.textContent))
            .font(PanelStyle.Text.body)
            .lineLimit(isCompactStrip ? ((item.title?.isEmpty == false) ? 5 : 6) : 4)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
