import SwiftUI

/// Card content for `.text` and `.richText` clipboard items.
///
/// Displays up to 4 lines of the item's text content with standard body font.
/// In horizontal panel mode (top/bottom edges), increases to 8 lines to fill
/// the taller fixed-height cards.
struct TextCardView: View {

    let item: ClipboardItem
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    var body: some View {
        Text(item.textContent ?? "")
            .font(.system(.callout, design: .default))
            .lineLimit(isHorizontal ? 8 : 4)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
