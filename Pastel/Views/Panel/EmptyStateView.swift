import SwiftUI

/// Friendly empty state displayed when no clipboard items exist yet.
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Copy something to get started")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Your clipboard history will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
