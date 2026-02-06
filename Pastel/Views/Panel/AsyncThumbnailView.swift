import SwiftUI
import AppKit

/// Asynchronously loads a thumbnail image from disk using `ImageStorageService`.
///
/// Uses `.task(id:)` to trigger loading when the filename changes.
/// Shows a progress indicator placeholder while loading.
struct AsyncThumbnailView: View {

    let filename: String

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
            image = await loadThumbnail()
        }
    }

    // MARK: - Private

    private func loadThumbnail() async -> NSImage? {
        let url = ImageStorageService.shared.resolveImageURL(filename)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = NSImage(contentsOf: url)
                continuation.resume(returning: loaded)
            }
        }
    }
}
