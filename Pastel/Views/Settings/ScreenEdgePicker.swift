import SwiftUI

/// Visual screen diagram with four clickable edge bars for selecting panel position.
///
/// The picker renders a stylized screen rectangle with edge bars on all four sides.
/// The selected edge is highlighted in accent color. Tapping an edge updates the binding.
struct ScreenEdgePicker: View {

    @Binding var selectedEdge: String

    // Screen diagram dimensions
    private let screenWidth: CGFloat = 160
    private let screenHeight: CGFloat = 100
    private let barThickness: CGFloat = 12
    private let horizontalBarLength: CGFloat = 120
    private let verticalBarLength: CGFloat = 70

    var body: some View {
        ZStack {
            // Screen body
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .frame(width: screenWidth, height: screenHeight)

            // Top edge bar
            edgeBar(edge: .top)
                .frame(width: horizontalBarLength, height: barThickness)
                .offset(y: -(screenHeight / 2 - barThickness / 2 - 4))

            // Bottom edge bar
            edgeBar(edge: .bottom)
                .frame(width: horizontalBarLength, height: barThickness)
                .offset(y: screenHeight / 2 - barThickness / 2 - 4)

            // Left edge bar
            edgeBar(edge: .left)
                .frame(width: barThickness, height: verticalBarLength)
                .offset(x: -(screenWidth / 2 - barThickness / 2 - 4))

            // Right edge bar
            edgeBar(edge: .right)
                .frame(width: barThickness, height: verticalBarLength)
                .offset(x: screenWidth / 2 - barThickness / 2 - 4)
        }
        .frame(width: screenWidth + 20, height: screenHeight + 20)
    }

    // MARK: - Private Helpers

    private func edgeBar(edge: PanelEdge) -> some View {
        let isSelected = selectedEdge == edge.rawValue
        return RoundedRectangle(cornerRadius: 3)
            .fill(isSelected ? Color.accentColor : Color.white.opacity(0.15))
            .onTapGesture {
                selectedEdge = edge.rawValue
            }
    }
}
