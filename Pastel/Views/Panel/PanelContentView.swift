import SwiftUI
import SwiftData

/// Root SwiftUI view hosted inside the sliding panel.
///
/// Uses `@Query` to reactively display clipboard items sorted by most recent.
/// Shows `EmptyStateView` when no items exist, otherwise a scrollable list
/// of `ClipboardCardView` rows with type-specific content rendering.
struct PanelContentView: View {

    @Query(sort: \ClipboardItem.timestamp, order: .reverse)
    private var items: [ClipboardItem]

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
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { item in
                            ClipboardCardView(item: item)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }
}
