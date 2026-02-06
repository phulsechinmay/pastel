import SwiftUI
import SwiftData

/// Root SwiftUI view hosted inside the sliding panel.
///
/// Uses `@Query` to reactively display clipboard items sorted by most recent.
/// Shows `EmptyStateView` when no items exist, otherwise a scrollable list
/// of `ClipboardCardView` rows with type-specific content rendering.
///
/// Supports keyboard navigation (up/down arrows), Enter to paste,
/// double-click to paste, and single-click to select.
struct PanelContentView: View {

    @Query(sort: \ClipboardItem.timestamp, order: .reverse)
    private var items: [ClipboardItem]

    @Environment(PanelActions.self) private var panelActions

    @State private var selectedIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Minimal header
            HStack {
                Text("Pastel")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Content area
            if items.isEmpty {
                EmptyStateView()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                ClipboardCardView(
                                    item: item,
                                    isSelected: selectedIndex == index
                                )
                                .id(index)
                                .onTapGesture(count: 2) {
                                    pasteItem(item)
                                }
                                .onTapGesture(count: 1) {
                                    selectedIndex = index
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: selectedIndex) { _, newValue in
                        if let newValue {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            if let index = selectedIndex, index < items.count {
                pasteItem(items[index])
            }
            return .handled
        }
        .onAppear {
            selectedIndex = nil
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Private Helpers

    private func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        if let current = selectedIndex {
            selectedIndex = max(0, min(items.count - 1, current + offset))
        } else {
            selectedIndex = 0
        }
    }

    private func pasteItem(_ item: ClipboardItem) {
        panelActions.pasteItem?(item)
    }
}
