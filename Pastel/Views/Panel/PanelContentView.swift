import SwiftUI
import SwiftData

/// Root SwiftUI view hosted inside the sliding panel.
///
/// Uses `@Query` to reactively display clipboard items sorted by most recent.
/// Shows `EmptyStateView` when no items exist, otherwise a scrollable list
/// with temporary placeholder rows (real card UI ships in Plan 02-02).
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
                            Text(item.textContent ?? item.contentType)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
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
