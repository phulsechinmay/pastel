import SwiftUI

/// Card content for `.url` clipboard items.
///
/// Displays a globe icon and the URL text in blue accent color,
/// making URL cards visually distinct from plain text cards.
struct URLCardView: View {

    let item: ClipboardItem

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(Color.blue)

            Text(item.textContent ?? "")
                .font(.system(.body, design: .default))
                .lineLimit(2)
                .foregroundStyle(Color.blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
