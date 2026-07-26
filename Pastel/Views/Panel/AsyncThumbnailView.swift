import SwiftUI
import AppKit

/// Asynchronously loads a decoded, size-capped thumbnail from disk via `ThumbnailLoader`.
///
/// Uses `.task(id:)` to trigger loading when the filename changes. The loader decodes
/// off the main thread and caches the result, so drawing stays cheap and re-appearing
/// cards (e.g. after a label-filter change) are cache hits. A warm image is applied
/// synchronously to avoid a placeholder flash; otherwise a spinner shows while loading.
struct AsyncThumbnailView: View {

    let filename: String

    /// Target max pixel dimension to decode to. Defaults to the card preview size.
    var maxPixelSize: Int = ThumbnailLoader.cardPreviewMaxPixelSize

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }
            }
        }
        .task(id: filename) {
            if let warm = ThumbnailLoader.shared.cached(filename: filename, maxPixelSize: maxPixelSize) {
                image = warm
            } else {
                image = await ThumbnailLoader.shared.load(filename: filename, maxPixelSize: maxPixelSize)
            }
        }
    }
}
