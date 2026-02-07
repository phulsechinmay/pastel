import SwiftUI

/// Card content for `.url` clipboard items.
///
/// Displays a globe icon and the URL text in blue accent color,
/// making URL cards visually distinct from plain text cards.
/// In horizontal panel mode (top/bottom edges), increases line limit to 4.
struct URLCardView: View {

    let item: ClipboardItem
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 16))
                .foregroundStyle(Color.blue)

            Text(item.textContent ?? "")
                .font(.system(.callout, design: .default))
                .lineLimit(isHorizontal ? 4 : 2)
                .foregroundStyle(Color.blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
