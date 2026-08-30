import SwiftUI

/// Friendly empty state displayed when no clipboard items exist yet.
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clipboard")
                .font(PanelStyle.Icon.empty)
                .foregroundStyle(.secondary)

            Text("Copy something to get started")
                .font(PanelStyle.Text.title)
                .foregroundStyle(.secondary)

            Text("Your clipboard history will appear here")
                .font(PanelStyle.Text.meta)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
