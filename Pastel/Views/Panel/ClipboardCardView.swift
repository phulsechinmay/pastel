import SwiftUI
import SwiftData
import AppKit

/// Dispatcher card view that wraps each clipboard item in shared chrome
/// (source app icon, content preview, relative timestamp) and routes to
/// the appropriate type-specific subview.
///
/// Card height varies by content type: 90pt for images, 72pt for all others.
/// Cards have rounded corners, subtle background, and a hover highlight.
/// When selected (via keyboard navigation or single-click), the card shows
/// an accent-colored background and border distinct from the hover state.
///
/// Provides a right-click context menu with label assignment submenu and delete action.
struct ClipboardCardView: View {

    let item: ClipboardItem
    var isSelected: Bool
    var onPaste: (() -> Void)?

    @Query(sort: \Label.sortOrder) private var labels: [Label]
    @Environment(\.modelContext) private var modelContext

    @State private var isHovered = false

    init(item: ClipboardItem, isSelected: Bool = false, onPaste: (() -> Void)? = nil) {
        self.item = item
        self.isSelected = isSelected
        self.onPaste = onPaste
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row: source app icon + timestamp
            HStack {
                sourceAppIcon
                Spacer()
                Text(item.timestamp, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Content preview (full-width)
            contentPreview
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, maxHeight: 195, alignment: .topLeading)
        .background(
            isSelected ? Color.accentColor.opacity(0.3)
                : isHovered ? Color.white.opacity(0.12)
                : Color.white.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .contextMenu {
            // Label assignment submenu
            Menu("Label") {
                ForEach(labels) { label in
                    Button {
                        item.label = label
                        try? modelContext.save()
                    } label: {
                        HStack {
                            Circle()
                                .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
                                .frame(width: 8, height: 8)
                            Text(label.name)
                            if item.label?.persistentModelID == label.persistentModelID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if item.label != nil {
                    Divider()
                    Button("Remove Label") {
                        item.label = nil
                        try? modelContext.save()
                    }
                }
            }

            Divider()

            Button("Delete", role: .destructive) {
                deleteItem()
            }
        }
    }

    // MARK: - Actions

    /// Delete the clipboard item with full cleanup:
    /// 1. Remove image and thumbnail files from disk (if any)
    /// 2. Delete the SwiftData model
    ///
    /// Pending expiration timers for concealed items are handled gracefully --
    /// ExpirationService.performExpiration checks if the item still exists
    /// via `modelContext.model(for:)` and no-ops if already deleted.
    private func deleteItem() {
        // Clean up disk images before removing the model
        ImageStorageService.shared.deleteImage(
            imagePath: item.imagePath,
            thumbnailPath: item.thumbnailPath
        )
        modelContext.delete(item)
        try? modelContext.save()
    }

    // MARK: - Private Views

    @ViewBuilder
    private var sourceAppIcon: some View {
        if let bundleID = item.sourceAppBundleID,
           let icon = NSWorkspace.shared.appIcon(forBundleIdentifier: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
                .clipShape(Circle())
        } else {
            Image(systemName: "app")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
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
        case .code:
            TextCardView(item: item)
        case .color:
            TextCardView(item: item)
        }
    }

    private var cardMinHeight: CGFloat {
        item.type == .image ? 120 : 80
    }
}
