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

    /// Whether this card is a color item (entire card uses the detected color).
    private var isColorCard: Bool { item.type == .color }

    /// The contrasting text color for color cards (white or black based on luminance).
    private var colorCardTextColor: Color {
        contrastingColor(forHex: item.detectedColorHex)
    }

    /// 1-based position badge number (1-9), or nil to hide badge.
    var badgePosition: Int?

    /// Whether a label chip is currently being dragged over this card.
    var isDropTarget: Bool

    /// Whether the Shift key is currently held (for dynamic badge display).
    var isShiftHeld: Bool

    init(item: ClipboardItem, isSelected: Bool = false, badgePosition: Int? = nil, isDropTarget: Bool = false, isShiftHeld: Bool = false, onPaste: (() -> Void)? = nil) {
        self.item = item
        self.isSelected = isSelected
        self.badgePosition = badgePosition
        self.isDropTarget = isDropTarget
        self.isShiftHeld = isShiftHeld
        self.onPaste = onPaste
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row: source app icon + label chip + timestamp
            HStack {
                sourceAppIcon

                // Label chip (inline, only shown when assigned)
                if let label = item.label {
                    HStack(spacing: 3) {
                        if let emoji = label.emoji, !emoji.isEmpty {
                            Text(emoji)
                                .font(.system(size: 9))
                        } else {
                            Circle()
                                .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
                                .frame(width: 6, height: 6)
                        }
                        Text(label.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(isColorCard ? colorCardTextColor.opacity(0.7) : .secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        isColorCard
                            ? colorCardTextColor.opacity(0.15)
                            : Color.white.opacity(0.1),
                        in: Capsule()
                    )
                }

                Spacer()

                Text(item.timestamp, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(isColorCard ? colorCardTextColor.opacity(0.7) : .secondary)
            }

            // Content preview (full-width)
            contentPreview
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, maxHeight: 195, alignment: .topLeading)
        .foregroundStyle(isColorCard ? colorCardTextColor : .primary)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardBorderColor, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottomTrailing) {
            if let badgePosition {
                KeycapBadge(number: badgePosition)
                    .padding(6)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isDropTarget)
        .contextMenu {
            // Label assignment submenu
            Menu("Label") {
                ForEach(labels) { label in
                    Button {
                        item.label = label
                        try? modelContext.save()
                    } label: {
                        HStack {
                            Text(labelDisplayText(label))
                            if item.label?.persistentModelID == label.persistentModelID {
                                Spacer()
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
        // Clean up URL metadata cached images
        ImageStorageService.shared.deleteImage(
            imagePath: item.urlFaviconPath,
            thumbnailPath: item.urlPreviewImagePath
        )
        modelContext.delete(item)
        try? modelContext.save()
    }

    /// Returns a display string for the label in context menus.
    /// Emoji labels show "emoji name"; color-dot labels show just the name.
    private func labelDisplayText(_ label: Label) -> String {
        if let emoji = label.emoji, !emoji.isEmpty {
            return "\(emoji) \(label.name)"
        } else {
            return label.name
        }
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
            CodeCardView(item: item)
        case .color:
            ColorCardView(item: item)
        }
    }

    /// Card background: detected color for `.color` items, standard dark chrome otherwise.
    private var cardBackground: AnyShapeStyle {
        if isColorCard {
            return AnyShapeStyle(colorFromHex(item.detectedColorHex))
        } else if isDropTarget {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))   // Subtle accent highlight
        } else if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.3))
        } else if isHovered {
            return AnyShapeStyle(Color.white.opacity(0.12))
        } else {
            return AnyShapeStyle(Color.white.opacity(0.06))
        }
    }

    /// Card border: accent when drop target or selected, subtle white for color cards, clear otherwise.
    private var cardBorderColor: Color {
        if isDropTarget {
            return Color.accentColor          // Bright accent border during drag hover
        } else if isSelected {
            return Color.accentColor.opacity(0.5)
        } else if isColorCard {
            return Color.white.opacity(0.15)
        }
        return Color.clear
    }

    private var cardMinHeight: CGFloat {
        if item.type == .image {
            return 120
        } else if item.type == .url && item.urlPreviewImagePath != nil {
            return 140
        } else {
            return 80
        }
    }
}

// MARK: - KeycapBadge

/// Keyboard key-style badge showing a quick paste shortcut (e.g., "\u{2318} 1").
/// Mimics a physical keycap with rounded rect background and subtle border.
struct KeycapBadge: View {
    let number: Int  // 1-9

    var body: some View {
        HStack(spacing: 2) {
            Text("\u{2318}")  // ⌘ symbol
                .font(.system(size: 9, weight: .medium))
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.white.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}
