import SwiftUI

/// Card content for `.code` clipboard items.
///
/// Placeholder stub -- Plan 07-02 will replace this with syntax-highlighted rendering.
/// This minimal implementation ensures the project builds while 07-02 completes.
struct CodeCardView: View {

    let item: ClipboardItem
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    var body: some View {
        Text(item.textContent ?? "")
            .font(.system(.callout, design: .monospaced))
            .lineLimit(isHorizontal ? 8 : 4)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
