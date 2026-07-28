import SwiftUI

/// Persistent search text field displayed below the panel header.
///
/// Shows a magnifying glass icon on the left, a clear button when text is non-empty,
/// and a filter toggle at the trailing edge. Styled to match the panel's dark theme.
struct SearchFieldView: View {

    @Binding var searchText: String
    /// Monotonic focus request token. See `FocusableTextField.focusRequestID`.
    var focusRequestID: Int = 0

    /// Whether the Type/App/Date filter row is currently revealed.
    var isFilterExpanded: Bool = false
    /// Whether any filter is actually narrowing results.
    var isFilterActive: Bool = false
    /// Toggles the filter row. When nil, the filter button is not shown at all.
    var onToggleFilters: (() -> Void)?

    /// Lit whenever filters are doing something or the row is open, so the control
    /// never looks inert while it is affecting what the user sees.
    private var isFilterHighlighted: Bool {
        isFilterActive || isFilterExpanded
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            FocusableTextField(
                text: $searchText,
                placeholder: "Search...",
                focusRequestID: focusRequestID
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

            if let onToggleFilters {
                // Filtering narrows the same result set the query does, so the control
                // belongs with the query rather than with the window-level toolbar.
                Divider()
                    .frame(height: 14)

                Button(action: onToggleFilters) {
                    Image(systemName: isFilterActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(isFilterHighlighted ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Filter by Type, App, or Date")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            Color.white.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
