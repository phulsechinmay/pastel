import SwiftUI
import AppKit

/// Card content for `.url` clipboard items with rich metadata preview.
///
/// Displays three possible states based on `urlMetadataFetched`:
/// - **Loading** (nil): the URL, plus a spinner for the metadata still in flight
/// - **Enriched** (true): og:image banner + favicon + page title + the URL beneath it
/// - **Failed** (false): the URL alone
///
/// All three render the URL through `DisplayURL` at the same size and weights, so the
/// card gains a picture and a title when metadata lands rather than restyling its
/// text. The enriched state used to hide the raw URL entirely, which meant two links
/// to the same site were indistinguishable: same favicon, same og:image, and titles
/// that differ by an issue number the tail-truncation then cut off.
///
/// Images (favicon, og:image) are loaded from disk via ImageStorageService.
/// The shared header row (source app icon + timestamp) is rendered by ClipboardCardView
/// above this view, consistent with all other card types.
struct URLCardView: View {

    let item: ClipboardItem

    @State private var bannerImage: NSImage?
    @State private var faviconImage: NSImage?

    // The panel edge is no longer read here. It used to switch the raw URL between a
    // 2-line and a 4-line wrap, which only mattered while the card was printing an
    // unstripped URL that needed four lines to say anything.

    var body: some View {
        Group {
            switch item.urlMetadataFetched {
            case nil:
                // State 1: Loading -- URL with a spinner
                loadingState
            case true:
                // State 2: Enriched -- og:image banner + favicon + title + URL
                enrichedState
            case false:
                // State 3: Failed -- URL alone
                plainURLRow
            default:
                plainURLRow
            }
        }
        .animation(.easeInOut(duration: 0.3), value: item.urlMetadataFetched)
        .task(id: item.urlPreviewImagePath) {
            guard let path = item.urlPreviewImagePath else { bannerImage = nil; return }
            bannerImage = await loadPreview(path: path, maxPixelSize: ThumbnailLoader.cardPreviewMaxPixelSize)
        }
        .task(id: item.urlFaviconPath) {
            guard let path = item.urlFaviconPath else { faviconImage = nil; return }
            faviconImage = await loadPreview(path: path, maxPixelSize: ThumbnailLoader.faviconMaxPixelSize)
        }
    }

    // MARK: - Parsed Content

    /// The copied URL split into its site half and its page half, or nil when the
    /// string will not parse and the raw text has to stand in.
    private var displayURL: DisplayURL? {
        DisplayURL(item.textContent ?? "")
    }

    /// The fetched page title, treating whitespace-only as absent. Sites do return
    /// `<title> </title>`, and an empty title slot with a URL line beneath it looks
    /// like a rendering bug rather than a site with nothing to say.
    private var pageTitle: String? {
        guard let title = item.urlTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }
        return title
    }

    // MARK: - State Views

    /// Loading state: the URL with a trailing spinner.
    private var loadingState: some View {
        HStack(spacing: PanelLayout.urlGlyphSpacing) {
            globeGlyph

            urlHeadline(lineLimit: 2)

            Spacer(minLength: PanelLayout.urlGlyphSpacing)

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

    /// Enriched state: og:image banner (if available) + the metadata block.
    private var enrichedState: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasBannerSizedImage, let bannerImage {
                Image(nsImage: bannerImage)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        maxWidth: .infinity,
                        minHeight: PanelLayout.cardURLBannerHeight,
                        maxHeight: PanelLayout.cardURLBannerHeight
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PanelLayout.cardURLBannerCornerRadius))
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
                            .frame(
                                maxWidth: PanelLayout.cardURLSmallImageSize,
                                maxHeight: PanelLayout.cardURLSmallImageSize
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .transition(.opacity)
                }
            }

            metadataBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    /// Favicon/globe + page title, with the URL on a second line beneath it.
    ///
    /// The URL sits *below* the title rather than above it because that is where every
    /// native link preview on this platform puts it (Messages, Notes, Safari's own
    /// bookmark rows), so it reads as a subtitle rather than an eyebrow.
    ///
    /// When there is no page title the URL is promoted into the title slot and the
    /// second line is dropped. One piece of information, one row.
    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: PanelLayout.urlMetadataLineSpacing) {
            HStack(spacing: PanelLayout.urlGlyphSpacing) {
                if hasBannerSizedImage, let faviconImage {
                    // Show favicon only when we have a proper banner above
                    Image(nsImage: faviconImage)
                        .resizable()
                        .frame(width: PanelLayout.urlGlyphSize, height: PanelLayout.urlGlyphSize)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else if !hasBannerSizedImage {
                    // No banner — use globe as prefix icon
                    globeGlyph
                }

                if let pageTitle {
                    Text(pageTitle)
                        .font(PanelStyle.Text.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                } else {
                    urlHeadline(lineLimit: 1)
                }
            }

            if pageTitle != nil, let displayURL {
                urlSubtitle(displayURL)
                    // Inset to the title's text edge, not the card's, so the two rows
                    // read as one block instead of a list of two things.
                    .padding(.leading, PanelLayout.urlGlyphSize + PanelLayout.urlGlyphSpacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Failed state: the URL alone, no spinner.
    private var plainURLRow: some View {
        HStack(spacing: PanelLayout.urlGlyphSpacing) {
            globeGlyph

            urlHeadline(lineLimit: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - URL Rendering

    private var globeGlyph: some View {
        Image(systemName: "globe")
            .font(PanelStyle.Icon.control)
            .foregroundStyle(.secondary)
            .frame(width: PanelLayout.urlGlyphSize, height: PanelLayout.urlGlyphSize)
    }

    /// The URL acting as the card's headline, when there is no page title to be one.
    ///
    /// Deliberately not blue. Blue link-coloured text is a browser idiom, and rendering
    /// it inside a native panel was the card admitting it had nothing but a raw string
    /// to show. The domain carries the emphasis instead.
    @ViewBuilder
    private func urlHeadline(lineLimit: Int) -> some View {
        if let displayURL {
            (
                Text(displayURL.domain)
                    .font(PanelStyle.Text.body.weight(.medium))
                    .foregroundStyle(.primary)
                + Text(displayURL.remainder)
                    .font(PanelStyle.Text.body)
                    .foregroundStyle(.secondary)
            )
            .lineLimit(lineLimit)
            .truncationMode(.middle)
            .help(displayURL.combined)
        } else {
            Text(item.textContent ?? "")
                .font(PanelStyle.Text.body)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
        }
    }

    /// The URL acting as a subtitle under a page title.
    ///
    /// `.truncationMode(.middle)` is the whole point of this row. The default `.tail`
    /// renders `github.com/pastel-app/pastel/pu…` and cuts off precisely the `/4821`
    /// that tells this card apart from the one below it; `.head` eats the domain.
    /// Middle truncation keeps both ends and drops the run in between, which is the
    /// only part neither question needs.
    ///
    /// `Text.control` rather than `Text.meta`: a path you cannot read is chrome, and
    /// this row exists to be read.
    private func urlSubtitle(_ displayURL: DisplayURL) -> some View {
        (
            Text(displayURL.domain)
                .font(PanelStyle.Text.control.weight(.medium))
                .foregroundStyle(.secondary)
            + Text(displayURL.remainder)
                .font(PanelStyle.Text.control)
                .foregroundStyle(.tertiary)
        )
        .lineLimit(1)
        .truncationMode(.middle)
        .help(displayURL.combined)
    }

    // MARK: - Helpers

    /// Load a decoded, size-capped preview image via `ThumbnailLoader`, using a warm
    /// cache hit synchronously when available to avoid a flash.
    private func loadPreview(path: String, maxPixelSize: Int) async -> NSImage? {
        if let warm = ThumbnailLoader.shared.cached(filename: path, maxPixelSize: maxPixelSize) {
            return warm
        }
        return await ThumbnailLoader.shared.load(filename: path, maxPixelSize: maxPixelSize)
    }
}
