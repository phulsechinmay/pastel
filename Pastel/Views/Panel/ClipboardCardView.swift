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

    let allLabels: [Label]
    @Environment(\.modelContext) private var modelContext
    @Environment(PanelActions.self) private var panelActions
    @Environment(AppState.self) private var appState

    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue

    @State private var isHovered = false
    @State private var dominantColor: Color?

    private var isHorizontal: Bool {
        let edge = PanelEdge(rawValue: panelEdgeRaw) ?? .right
        return !edge.isVertical
    }

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

    init(item: ClipboardItem, isSelected: Bool = false, allLabels: [Label] = [], badgePosition: Int? = nil, isDropTarget: Bool = false, isShiftHeld: Bool = false, hideContextMenu: Bool = false, onPaste: (() -> Void)? = nil) {
        self.item = item
        self.isSelected = isSelected
        self.allLabels = allLabels
        self.badgePosition = badgePosition
        self.isDropTarget = isDropTarget
        self.isShiftHeld = isShiftHeld
        self.hideContextMenu = hideContextMenu
        self.onPaste = onPaste
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row: source app icon + label chips (max 3) + overflow + timestamp
            HStack(spacing: 4) {
                sourceAppIcon

                let visibleLabels = Array(item.safeLabels.prefix(3))
                ForEach(visibleLabels) { label in
                    LabelChipView(label: label, size: .compact, tintOverride: isColorCard ? colorCardTextColor : nil)
                }
                if item.safeLabels.count > 3 {
                    Text("+\(item.safeLabels.count - 3)")
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

                // Abbreviated relative time
                Text(relativeTimeString(for: item.timestamp))
                    .font(.caption2)
                    .foregroundStyle(isColorCard ? colorCardTextColor.opacity(0.7) : .secondary)
            }

            // Content preview (full-width)
            contentPreview

            // In horizontal mode, push footer to card bottom for uniform alignment
            if isHorizontal {
                Spacer(minLength: 0)
            }

            // Footer row: title (bold) + keycap badge
            if (item.title != nil && !(item.title?.isEmpty ?? true)) || badgePosition != nil {
                HStack(spacing: 4) {
                    if let title = item.title, !title.isEmpty {
                        Text(title)
                            .font(.caption.bold())
                            .lineLimit(1)
                            .foregroundStyle(isColorCard ? colorCardTextColor : .primary)
                    }

                    Spacer()

                    if let badgePosition {
                        KeycapBadge(number: badgePosition, isShiftHeld: isShiftHeld)
                    }
                }
            }
        }
        .padding(.horizontal, PanelLayout.cardHorizontalPadding)
        .padding(.vertical, PanelLayout.cardVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, maxHeight: PanelLayout.cardMaxHeight, alignment: .topLeading)
        .foregroundStyle(isColorCard ? colorCardTextColor : .primary)
        .background {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: PanelLayout.cardCornerRadius)
                    .fill(cardBackground)
                if !isColorCard, let dominantColor {
                    LinearGradient(
                        stops: [
                            .init(color: dominantColor.opacity(0.5), location: 0.0),
                            .init(color: .clear, location: 0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PanelLayout.cardCornerRadius))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: PanelLayout.cardCornerRadius)
                .strokeBorder(cardBorderColor, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: PanelLayout.cardCornerRadius))
        .task {
            // Load dominant color for header gradient (deferred to avoid blocking panel open)
            if !isColorCard {
                dominantColor = AppIconColorService.shared.dominantColor(forBundleID: item.sourceAppBundleID)
            }
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
            Button("Paste as Plain Text") {
                panelActions.pastePlainTextItem?(item)
            }

            if let colorHex = item.detectedColorHex {
                Divider()
                Menu("Copy Color As") {
                    Button("Hex — \(ColorFormatService.toHex(colorHex))") {
                        copyToClipboard(ColorFormatService.toHex(colorHex))
                    }
                    Button("RGB — \(ColorFormatService.toRGB(colorHex))") {
                        copyToClipboard(ColorFormatService.toRGB(colorHex))
                    }
                    Button("HSL — \(ColorFormatService.toHSL(colorHex))") {
                        copyToClipboard(ColorFormatService.toHSL(colorHex))
                    }
                    Button("CMYK — \(ColorFormatService.toCMYK(colorHex))") {
                        copyToClipboard(ColorFormatService.toCMYK(colorHex))
                    }

                    if let text = item.textContent,
                       !isHexVariant(text.trimmingCharacters(in: .whitespacesAndNewlines), of: colorHex) {
                        Divider()
                        Button("Copy Original — \(text)") {
                            copyToClipboard(text)
                        }
                    }
                }
            }

            Divider()

            Button("Edit...") {
                EditItemWindow.show(for: item, modelContainer: modelContext.container)
            }

            Divider()

            // Label assignment submenu with toggle checkmarks
            Menu("Label") {
                ForEach(allLabels) { label in
                    let isAssigned = item.safeLabels.contains {
                        $0.persistentModelID == label.persistentModelID
                    }
                    Button {
                        if isAssigned {
                            item.safeLabels.removeAll {
                                $0.persistentModelID == label.persistentModelID
                            }
                        } else {
                            item.safeLabels.append(label)
                        }
                        saveWithLogging(modelContext, operation: "label toggle")
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

                if !item.safeLabels.isEmpty {
                    Divider()
                    Button("Remove All Labels") {
                        item.safeLabels.removeAll()
                        saveWithLogging(modelContext, operation: "remove all labels")
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

    /// Copy a formatted string directly to the system clipboard.
    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Check whether the given text is a variant of the hex color (with/without #, upper/lower).
    private func isHexVariant(_ text: String, of hex: String) -> Bool {
        let variants = ["#" + hex, hex, "#" + hex.lowercased(), hex.lowercased()]
        return variants.contains(text)
    }

    /// Soft-delete the clipboard item: hide from display immediately with animation,
    /// play trash sound, and schedule deferred image cleanup.
    ///
    /// The item remains in SwiftData until the panel hides (commitPendingDeletion)
    /// or a new deletion replaces it. Undo via Cmd+Z restores the item.
    ///
    /// Pending expiration timers for concealed items are handled gracefully --
    /// ExpirationService.performExpiration checks if the item still exists
    /// via `modelContext.model(for:)` and no-ops if already deleted.
    private func deleteItem() {
        withAnimation(.easeOut(duration: 0.2)) {
            appState.deletionManager.softDelete(item, in: modelContext)
        }
        appState.itemCount -= 1
    }

    /// Pre-rendered menu icon for context menu labels.
    /// Both emoji and color labels render as NSImage so NSMenu aligns them in the same image column.
    private func menuIcon(for label: Label) -> NSImage {
        let size: CGFloat = 16
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
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
            return true
        }
        image.isTemplate = false
        return image
    }


    // MARK: - Helpers

    /// Localized relative time using Apple's RelativeDateTimeFormatter.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relativeTimeString(for date: Date) -> String {
        let interval = Date.now.timeIntervalSince(date)
        if interval < 2 { return "now" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    // MARK: - Private Views

    @ViewBuilder
    private var sourceAppIcon: some View {
        if let bundleID = item.sourceAppBundleID,
           let icon = AppIconCache.shared.icon(forBundleID: bundleID) {
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
        if item.type == .image { return PanelLayout.cardMinHeightImage }
        else if item.type == .url && item.urlPreviewImagePath != nil { return PanelLayout.cardMinHeightURL }
        else { return PanelLayout.cardMinHeightDefault }
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
