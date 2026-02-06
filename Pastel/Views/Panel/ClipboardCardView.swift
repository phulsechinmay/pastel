import SwiftUI
import AppKit

/// Dispatcher card view that wraps each clipboard item in shared chrome
/// (source app icon, content preview, relative timestamp) and routes to
/// the appropriate type-specific subview.
///
/// Card height varies by content type: 90pt for images, 72pt for all others.
/// Cards have rounded corners, subtle background, and a hover highlight.
struct ClipboardCardView: View {

    let item: ClipboardItem

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Source app icon (left)
            sourceAppIcon

            // Content preview (center, fills space)
            contentPreview

            // Relative timestamp (right)
            Text(item.timestamp, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: cardHeight)
        .frame(maxWidth: .infinity)
        .background(
            isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // MARK: - Private Views

    @ViewBuilder
    private var sourceAppIcon: some View {
        if let bundleID = item.sourceAppBundleID,
           let icon = NSWorkspace.shared.appIcon(forBundleIdentifier: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .clipShape(Circle())
        } else {
            Image(systemName: "app")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .text, .richText:
            TextCardView(item: item)
        case .url:
            URLCardView(item: item)
        case .image:
            ImageCardView(item: item)
        case .file:
            FileCardView(item: item)
        }
    }

    private var cardHeight: CGFloat {
        item.type == .image ? 90 : 72
    }
}
