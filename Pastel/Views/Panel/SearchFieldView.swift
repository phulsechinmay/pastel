import SwiftUI

/// Persistent search text field displayed below the panel header.
///
/// Shows a magnifying glass icon on the left and a clear button on the right
/// when text is non-empty. Styled to match the panel's dark theme.
struct SearchFieldView: View {

    @Binding var searchText: String
    var requestFocus: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            FocusableTextField(
                text: $searchText,
                placeholder: "Search...",
                requestFocus: requestFocus
            )

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color.white.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
