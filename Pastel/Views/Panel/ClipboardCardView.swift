import SwiftUI
import SwiftData
import AppKit
import ImageIO

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
    @Environment(PanelActions.self) private var panelActions
    @Environment(AppState.self) private var appState

    @State private var isHovered = false
    @State private var imageDimensions: String?
    @State private var dominantColor: Color?

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

    /// When true, the built-in context menu is suppressed (caller provides its own).
    var hideContextMenu: Bool

    init(item: ClipboardItem, isSelected: Bool = false, badgePosition: Int? = nil, isDropTarget: Bool = false, isShiftHeld: Bool = false, hideContextMenu: Bool = false, onPaste: (() -> Void)? = nil) {
        self.item = item
        self.isSelected = isSelected
        self.badgePosition = badgePosition
        self.isDropTarget = isDropTarget
        self.isShiftHeld = isShiftHeld
        self.hideContextMenu = hideContextMenu
        self.onPaste = onPaste
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row: source app icon + title + timestamp
            HStack {
                sourceAppIcon

                // Title (when set) -- bold caption2, visually distinct
                if let title = item.title, !title.isEmpty {
                    Text(title)
                        .font(.caption2.bold())
                        .lineLimit(1)
                        .foregroundStyle(isColorCard ? colorCardTextColor : .primary)
                }

                Spacer()

                // Abbreviated relative time
                Text(relativeTimeString(for: item.timestamp))
                    .font(.caption2)
                    .foregroundStyle(isColorCard ? colorCardTextColor.opacity(0.7) : .secondary)
            }

            // Content preview (full-width)
            contentPreview

            // Footer row: metadata + label chips (max 3) + overflow badge + keycap badge
            if footerMetadataText != nil || !item.labels.isEmpty || badgePosition != nil {
                HStack(spacing: 4) {
                    if let metadata = footerMetadataText {
                        Text(metadata)
                            .font(.caption2)
                            .foregroundStyle(isColorCard ? colorCardTextColor.opacity(0.5) : .secondary.opacity(0.7))
                            .lineLimit(1)
                    }

                    let visibleLabels = Array(item.labels.prefix(3))
                    ForEach(visibleLabels) { label in
                        LabelChipView(label: label, size: .compact, tintOverride: isColorCard ? colorCardTextColor : nil)
                    }
                    if item.labels.count > 3 {
                        Text("+\(item.labels.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(isColorCard ? colorCardTextColor.opacity(0.7) : .secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                isColorCard ? colorCardTextColor.opacity(0.15) : Color.white.opacity(0.1),
                                in: Capsule()
                            )
                    }

                    Spacer()

                    if let badgePosition {
                        KeycapBadge(number: badgePosition, isShiftHeld: isShiftHeld)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, maxHeight: 195, alignment: .topLeading)
        .foregroundStyle(isColorCard ? colorCardTextColor : .primary)
        .background {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardBackground)
                if !isColorCard, let dominantColor {
                    LinearGradient(
                        colors: [dominantColor.opacity(0.5), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardBorderColor, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            // Load dominant color for header gradient (deferred to avoid blocking panel open)
            if !isColorCard {
                dominantColor = AppIconColorService.shared.dominantColor(forBundleID: item.sourceAppBundleID)
            }

            guard item.type == .image, let path = item.imagePath else { return }
            let fileURL = ImageStorageService.shared.resolveImageURL(path)
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else { return }
            imageDimensions = "\(width) \u{00D7} \(height)"
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isDropTarget)
        .contextMenu(hideContextMenu ? nil : ContextMenu {
            Button("Copy") {
                panelActions.copyOnlyItem?(item)
            }
            Button("Paste") {
                panelActions.pasteItem?(item)
            }
            Button("Copy + Paste") {
                panelActions.pasteItem?(item)
            }
            Button("Paste as Plain Text") {
                panelActions.pastePlainTextItem?(item)
            }

            Divider()

            Button("Edit...") {
                EditItemWindow.show(for: item, modelContainer: modelContext.container)
            }

            Divider()

            // Label assignment submenu with toggle checkmarks
            Menu("Label") {
                ForEach(labels) { label in
                    let isAssigned = item.labels.contains {
                        $0.persistentModelID == label.persistentModelID
                    }
                    Button {
                        if isAssigned {
                            item.labels.removeAll {
                                $0.persistentModelID == label.persistentModelID
                            }
                        } else {
                            item.labels.append(label)
                        }
                        try? modelContext.save()
                    } label: {
                        HStack {
                            Image(nsImage: menuIcon(for: label))
                            Text(label.name)
                            if isAssigned {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if !item.labels.isEmpty {
                    Divider()
                    Button("Remove All Labels") {
                        item.labels.removeAll()
                        try? modelContext.save()
                    }
                }
            }

            Divider()

            Button("Delete", role: .destructive) {
                deleteItem()
            }
        })
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
        appState.itemCount -= 1
    }

    /// Pre-rendered menu icon for context menu labels.
    /// Both emoji and color labels render as NSImage so NSMenu aligns them in the same image column.
    private func menuIcon(for label: Label) -> NSImage {
        let size: CGFloat = 16
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        if let emoji = label.emoji, !emoji.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12)
            ]
            let str = NSAttributedString(string: emoji, attributes: attributes)
            let strSize = str.size()
            str.draw(at: NSPoint(
                x: (size - strSize.width) / 2,
                y: (size - strSize.height) / 2
            ))
        } else {
            let nsColor = NSColor(LabelColor(rawValue: label.colorName)?.color ?? .gray)
            nsColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12)).fill()
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }


    // MARK: - Helpers

    /// Abbreviated relative time: "now", "X secs ago", "X mins ago", "X hours ago", "X days ago".
    private func relativeTimeString(for date: Date) -> String {
        let interval = Date.now.timeIntervalSince(date)
        switch interval {
        case ..<2:
            return "now"
        case ..<60:
            let secs = Int(interval)
            return secs == 1 ? "1 sec ago" : "\(secs) secs ago"
        case ..<3600:
            let mins = Int(interval / 60)
            return mins == 1 ? "1 min ago" : "\(mins) mins ago"
        case ..<86400:
            let hours = Int(interval / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        default:
            let days = Int(interval / 86400)
            return days == 1 ? "1 day ago" : "\(days) days ago"
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

    /// Type-appropriate metadata text for the card footer.
    private var footerMetadataText: String? {
        switch item.type {
        case .text, .richText:
            let count = item.characterCount > 0 ? item.characterCount : (item.textContent?.count ?? 0)
            return count > 0 ? "\(count) chars" : nil
        case .url:
            guard let text = item.textContent,
                  let url = URL(string: text),
                  var host = url.host else { return nil }
            if host.hasPrefix("www.") {
                host = String(host.dropFirst(4))
            }
            return host
        case .image:
            return imageDimensions
        case .code:
            let count = item.characterCount > 0 ? item.characterCount : (item.textContent?.count ?? 0)
            guard count > 0 else { return nil }
            var result = "\(count) chars"
            if let lang = item.detectedLanguage, !lang.isEmpty {
                result += " \u{00B7} \(lang.capitalized)"
            }
            return result
        case .color, .file:
            return nil
        }
    }
}

// MARK: - KeycapBadge

/// Text-only badge showing a quick paste shortcut (e.g., "\u{2318}1" or "\u{2318}\u{21E7}1").
/// Dynamically shows the Shift symbol when the Shift key is held.
struct KeycapBadge: View {
    let number: Int  // 1-9
    var isShiftHeld: Bool = false

    var body: some View {
        HStack(spacing: 1) {
            Text("\u{2318}")
            if isShiftHeld {
                Text("\u{21E7}")
            }
            Text("\(number)")
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.5))
    }
}
