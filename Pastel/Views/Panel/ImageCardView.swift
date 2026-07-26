import SwiftUI

/// Card content for `.image` clipboard items.
///
/// Displays the image via `AsyncThumbnailView` when a path is available, or falls back
/// to a photo system image placeholder.
///
/// Prefers the full image as the decode *source* (the stored 200px `_thumb.png` is too
/// low-res for a crisp card) but `AsyncThumbnailView` decodes it down to a card-sized
/// preview off the main thread — good resolution without decoding the whole 4K bitmap.
struct ImageCardView: View {

    let item: ClipboardItem

    var body: some View {
        Group {
            if let imagePath = item.imagePath ?? item.thumbnailPath {
                AsyncThumbnailView(filename: imagePath)
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
