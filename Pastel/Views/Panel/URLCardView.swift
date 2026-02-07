import AppKit
import SwiftUI

/// Card content for `.url` clipboard items with rich metadata preview.
///
/// Displays three possible states based on `urlMetadataFetched`:
/// - **Loading** (nil): Plain URL card with globe icon + blue text and a subtle spinner
/// - **Enriched** (true): og:image banner + favicon + page title row (raw URL hidden)
/// - **Failed** (false): Plain URL fallback (globe icon + blue text, no spinner)
///
/// Images (favicon, og:image) are loaded from disk via ImageStorageService.
/// The shared header row (source app icon + timestamp) is rendered by ClipboardCardView
/// above this view, consistent with all other card types.
struct URLCardView: View {

    let item: ClipboardItem
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

    @State private var bannerImage: NSImage?
    @State private var faviconImage: NSImage?

    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

    var body: some View {
        Group {
            switch item.urlMetadataFetched {
            case nil:
                // State 1: Loading -- plain card with spinner
                loadingState
            case true:
                // State 2: Enriched -- og:image banner + favicon + title
                enrichedState
            case false:
                // State 3: Failed -- plain URL fallback
                plainURLRow
            default:
                plainURLRow
            }
        }
        .animation(.easeInOut(duration: 0.3), value: item.urlMetadataFetched)
        .task(id: item.urlPreviewImagePath) {
            guard let path = item.urlPreviewImagePath else {
                bannerImage = nil
                return
            }
            let url = ImageStorageService.shared.resolveImageURL(path)
            bannerImage = await loadImageFromDisk(url: url)
        }
        .task(id: item.urlFaviconPath) {
            guard let path = item.urlFaviconPath else {
                faviconImage = nil
                return
            }
            let url = ImageStorageService.shared.resolveImageURL(path)
            faviconImage = await loadImageFromDisk(url: url)
        }
    }

    // MARK: - State Views

    /// Loading state: plain URL row with a trailing spinner
    private var loadingState: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 16))
                .foregroundStyle(Color.blue)

            Text(item.textContent ?? "")
                .font(.system(.callout, design: .default))
                .lineLimit(isHorizontal ? 4 : 2)
                .foregroundStyle(Color.blue)

            Spacer()

            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whether the banner image is large enough to display as a full-width banner.
    /// Small images (e.g. favicons returned as og:image) look bad when scaled up.
    private var hasBannerSizedImage: Bool {
        guard let img = bannerImage else { return false }
        return img.size.width >= 200 && img.size.height >= 100
    }

    /// Enriched state: og:image banner (if available) + favicon + title row
    private var enrichedState: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasBannerSizedImage, let bannerImage {
                // Full-width banner for large og:images
                Image(nsImage: bannerImage)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(2 / 1, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .transition(.opacity)
            } else if bannerImage != nil || faviconImage != nil {
                // Small og:image or favicon only — show centered at natural size
                let displayImage = faviconImage ?? bannerImage
                if let displayImage {
                    HStack {
                        Spacer()
                        Image(nsImage: displayImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 64, maxHeight: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                }
            }

            // Favicon + title row (always shown when enriched)
            HStack(spacing: 6) {
                if hasBannerSizedImage, let faviconImage {
                    // Show favicon only when we have a proper banner above
                    Image(nsImage: faviconImage)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else if !hasBannerSizedImage {
                    // No banner — use globe as prefix icon
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }

                Text(item.urlTitle ?? item.textContent ?? "")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    /// Plain URL row: globe icon + URL text in blue (no spinner)
    private var plainURLRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 16))
                .foregroundStyle(Color.blue)

            Text(item.textContent ?? "")
                .font(.system(.callout, design: .default))
                .lineLimit(isHorizontal ? 4 : 2)
                .foregroundStyle(Color.blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    /// Load an NSImage from a file URL on a background thread.
    private func loadImageFromDisk(url: URL) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = NSImage(contentsOf: url)
                continuation.resume(returning: loaded)
            }
        }
    }
}
