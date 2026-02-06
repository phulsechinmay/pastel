import SwiftUI

/// Card content for `.image` clipboard items.
///
/// Displays the thumbnail via `AsyncThumbnailView` when a thumbnail path is available,
/// or falls back to a photo system image placeholder.
struct ImageCardView: View {

    let item: ClipboardItem

    var body: some View {
        Group {
            if let thumbnailPath = item.thumbnailPath {
                AsyncThumbnailView(filename: thumbnailPath)
                    .frame(maxWidth: .infinity, maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }
}
