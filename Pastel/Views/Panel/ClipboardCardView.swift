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

    /// A label chip is hovering over this card, waiting to be dropped.
    @State private var isLabelDropTargeted = false
    /// A label was dropped that this card already carries. Briefly scales the chip it
    /// already has, so the refusal names its own reason instead of just failing.
    @State private var pulsingLabelID: PersistentIdentifier?

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

    /// Whether the Shift key is currently held (for dynamic badge display).
    var isShiftHeld: Bool

    /// When true, the built-in context menu is suppressed (caller provides its own).
    var hideContextMenu: Bool

    /// Which items a dropped label should be applied to. Defaults to this card alone.
    ///
    /// The History browser hands back its whole multi-selection when this card is part
    /// of it, so one drop labels everything selected. That is the surface where people
    /// go to organize in bulk, and doing it one card at a time there was busywork.
    var labelDropTargets: (() -> [ClipboardItem])?

    init(item: ClipboardItem, isSelected: Bool = false, allLabels: [Label] = [], badgePosition: Int? = nil, isShiftHeld: Bool = false, hideContextMenu: Bool = false, labelDropTargets: (() -> [ClipboardItem])? = nil, onPaste: (() -> Void)? = nil) {
        self.item = item
        self.isSelected = isSelected
        self.allLabels = allLabels
        self.badgePosition = badgePosition
        self.isShiftHeld = isShiftHeld
        self.hideContextMenu = hideContextMenu
        self.labelDropTargets = labelDropTargets
        self.onPaste = onPaste
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row: source app icon + label chips (max 3) + overflow + timestamp
            HStack(spacing: 4) {
                sourceAppIcon

                ForEach(headerLabels) { label in
                    LabelChipView(label: label, size: .compact, tintOverride: isColorCard ? colorCardTextColor : nil)
                        // A freshly dropped label grows into place rather than popping
                        // in. In the History browser, where a drop can hit an entire
                        // selection, this is what makes twelve cards acknowledge at once.
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .scaleEffect(pulsingLabelID == label.persistentModelID ? 1.18 : 1)
                }
                if item.safeLabels.count > 3 {
                    Text("+\(item.safeLabels.count - 3)")
                        .font(PanelStyle.Text.meta)
                        .foregroundStyle(metaForeground)
                        .chipChrome(tintOverride: isColorCard ? colorCardTextColor : nil, isCompact: true)
                }

                Spacer()

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(PanelStyle.Icon.meta)
                        .foregroundStyle(metaForeground)
                }

                // Abbreviated relative time
                Text(relativeTimeString(for: item.timestamp))
                    .font(PanelStyle.Text.meta)
                    .foregroundStyle(metaForeground)
                    .monospacedDigit()
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
                            .font(PanelStyle.Text.title)
                            .lineLimit(1)
                            .foregroundStyle(isColorCard ? colorCardTextColor : .primary)
                    }

                    Spacer()

                    if let badgePosition {
                        KeycapBadge(
                            number: badgePosition,
                            isShiftHeld: isShiftHeld,
                            tint: isColorCard ? colorCardTextColor : nil
                        )
                    }
                }
            }
        }
        .padding(.horizontal, PanelLayout.cardHorizontalPadding)
        .padding(.vertical, PanelLayout.cardVerticalPadding)
        // In horizontal mode the list hands every card an identical slot sized to the
        // space under the header, so the card must not also impose its own ceiling —
        // the two caps fought and the shorter one won, leaving the dead band.
        .frame(
            maxWidth: .infinity,
            minHeight: cardMinHeight,
            maxHeight: isHorizontal ? .infinity : PanelLayout.cardMaxHeight,
            alignment: .topLeading
        )
        .foregroundStyle(isColorCard ? colorCardTextColor : .primary)
        .background {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: PanelLayout.cardCornerRadius)
                    .fill(cardBackground)
                if !isColorCard, let dominantColor {
                    // Confined to the header row and capped low. This is an app tint,
                    // not a highlight — at its old 0.5 opacity across the top half of
                    // the card it outranked the actual selection state.
                    LinearGradient(
                        colors: [dominantColor.opacity(0.12), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: PanelLayout.cardAppWashHeight)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: PanelLayout.cardCornerRadius)
                .strokeBorder(cardBorderColor, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: PanelLayout.cardCornerRadius))
        // Selection ring, drawn OUTSIDE the card in the layout gutter. Content cannot
        // paint outside its own frame, so a `.color` clip that happens to be the accent
        // colour can never counterfeit this — which it could, and did, when selection
        // was just an accent fill.
        .overlay {
            RoundedRectangle(
                cornerRadius: PanelLayout.cardCornerRadius + PanelLayout.selectionRingInset,
                style: .continuous
            )
            .strokeBorder(PanelStyle.selectionRing, lineWidth: PanelLayout.selectionRingWidth)
            .padding(-PanelLayout.selectionRingInset)
            .opacity(isSelected ? 1 : 0)
        }
        .task {
            // Load dominant color for header gradient (deferred to avoid blocking panel open)
            if !isColorCard {
                dominantColor = AppIconColorService.shared.dominantColor(forBundleID: item.sourceAppBundleID)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        // Label drops are handled here rather than by the list that owns the card.
        // The panel's list used to own it, which is why the History browser could not
        // accept a label at all despite showing the same chip bar directly above the
        // same cards.
        .dropDestination(for: String.self) { strings, _ in
            handleLabelDrop(strings)
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                isLabelDropTargeted = targeted
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .contextMenu(hideContextMenu ? nil : ContextMenu {
            if item.type == .image {
                Button("View Image") {
                    ImageViewerWindow.show(for: item)
                }
                Divider()
            }

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

            if let text = item.textContent, !text.isEmpty, isTransformable {
                Divider()
                Menu("Transform") {
                    ForEach(TextTransform.Group.allCases, id: \.self) { group in
                        Section(group.rawValue) {
                            ForEach(TextTransformService.transforms(in: group)) { transform in
                                Button(transform.name) {
                                    applyTransform(transform, to: text)
                                }
                                // Disabled rather than hidden: a stable menu is easier to
                                // learn than one whose contents shift per clip.
                                .disabled(!transform.canApply(text))
                            }
                        }
                    }
                }
            }

            Divider()

            Button(item.isPinned ? "Unpin" : "Pin to Top") {
                appState.togglePin(item, in: modelContext)
            }

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
                        item.refreshLabelKey()
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
                        item.refreshLabelKey()
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

    // MARK: - Label Drops

    /// The label chips that actually render in the header row.
    private var headerLabels: [Label] {
        Array(item.safeLabels.prefix(3))
    }

    /// Assign a dropped label, either to this card or to the caller's whole selection.
    ///
    /// Returns `false` when every target already carries the label, which lets the
    /// system play its own snap-back. That is the platform's vocabulary for "not
    /// accepted", and it is a great deal clearer than what this did before: report
    /// success, change nothing, and leave the user unsure whether the drop registered.
    private func handleLabelDrop(_ strings: [String]) -> Bool {
        guard let encodedID = strings.first,
              let labelID = PersistentIdentifier.fromTransferString(encodedID),
              let label = try? modelContext.model(for: labelID) as? Label else {
            return false
        }

        let targets = labelDropTargets?() ?? [item]
        let needsLabel = targets.filter { target in
            !target.safeLabels.contains { $0.persistentModelID == label.persistentModelID }
        }

        guard !needsLabel.isEmpty else {
            pulseExistingChip(for: label)
            return false
        }

        withAnimation(.easeOut(duration: 0.24)) {
            for target in needsLabel {
                target.safeLabels.append(label)
                target.refreshLabelKey()
            }
        }
        saveWithLogging(modelContext, operation: "label drop assignment")
        return true
    }

    /// Briefly grow the chip the card already has, so a refused drop points at its
    /// own reason. Skipped when that chip is folded into the "+N" overflow, where
    /// there is nothing to point at and the snap-back has to carry the message alone.
    private func pulseExistingChip(for label: Label) {
        let id = label.persistentModelID
        guard headerLabels.contains(where: { $0.persistentModelID == id }) else { return }

        withAnimation(.easeOut(duration: 0.12)) { pulsingLabelID = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.easeOut(duration: 0.24)) { pulsingLabelID = nil }
        }
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

    /// Images and files carry no editable text, so the Transform submenu is hidden
    /// for them entirely rather than shown full of disabled items.
    private var isTransformable: Bool {
        item.type != .image && item.type != .file
    }

    /// Rewrite the clip's content with the transform's output.
    ///
    /// Transforms replace in place (plan decision Q3.2), so this routes through the
    /// same `commitEditedText` the edit window uses — that keeps `contentHash`,
    /// highlight-cache eviction, and URL-metadata refresh consistent between the two.
    private func applyTransform(_ transform: TextTransform, to text: String) {
        // `canApply` only screens cheaply; a transform can still fail on the real input.
        guard let transformed = transform.apply(text), transformed != text else { return }
        commitEditedText(transformed, to: item, in: modelContext)
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
        if item.isUserCreated {
            // Authored clips have no source app. A distinct glyph reads as "you wrote
            // this" instead of looking like a failed icon lookup, and `sourceAppName`
            // stays nil so no sentinel string leaks into search results.
            Image(systemName: "square.and.pencil")
                .font(PanelStyle.Icon.content)
                .foregroundStyle(metaForeground)
                .frame(width: 24, height: 24)
        } else if let bundleID = item.sourceAppBundleID,
           let icon = AppIconCache.shared.icon(forBundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
                .clipShape(Circle())
        } else {
            Image(systemName: "app")
                .font(PanelStyle.Icon.content)
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

    /// Card background: the detected colour for `.color` items, the surface ramp otherwise.
    ///
    /// Note what is *absent*: selection no longer changes a colour card's fill. The
    /// swatch stays true to its value and the outset ring carries the state instead.
    private var cardBackground: AnyShapeStyle {
        if isColorCard {
            return AnyShapeStyle(colorFromHex(item.detectedColorHex))
        } else if isLabelDropTargeted {
            return AnyShapeStyle(PanelStyle.dropTargetFill)
        } else if isSelected {
            return AnyShapeStyle(PanelStyle.selectionFill)
        } else if isHovered {
            return AnyShapeStyle(PanelStyle.surfaceHover)
        } else {
            return AnyShapeStyle(PanelStyle.surface)
        }
    }

    /// Inset border. Drop targets get it (interior geometry); selection deliberately
    /// does not, so the two states stay visually separable when a card is both.
    private var cardBorderColor: Color {
        if isLabelDropTargeted {
            return PanelStyle.dropTargetStroke
        } else if isColorCard {
            return PanelStyle.strokeStrong
        }
        return .clear
    }

    /// Foreground for header metadata, resolved against whichever surface it lands on.
    private var metaForeground: AnyShapeStyle {
        isColorCard
            ? AnyShapeStyle(PanelStyle.onColor(colorCardTextColor, secondary: true))
            : AnyShapeStyle(HierarchicalShapeStyle.secondary)
    }

    private var cardMinHeight: CGFloat {
        if item.type == .image { return PanelLayout.cardMinHeightImage }
        else if item.type == .url && item.urlPreviewImagePath != nil { return PanelLayout.cardMinHeightURL }
        else { return PanelLayout.cardMinHeightDefault }
    }

}

// MARK: - KeycapBadge

/// Badge showing a quick paste shortcut (e.g., "\u{2318}1" or "\u{2318}\u{21E7}1").
/// Dynamically shows the Shift symbol when the Shift key is held.
///
/// Rendered as an actual keycap (raised surface, capsule) rather than loose text.
/// It previously sat at `white.opacity(0.5)` on a `white.opacity(0.06)` card, which
/// is well under 4.5:1 — a legibility problem on the one affordance in the panel
/// whose entire job is to teach a shortcut.
struct KeycapBadge: View {
    let number: Int  // 1-9
    var isShiftHeld: Bool = false
    /// Contrast colour when the badge sits on an arbitrary user colour (colour cards).
    var tint: Color?

    var body: some View {
        HStack(spacing: 1) {
            Text("\u{2318}")
            if isShiftHeld {
                Text("\u{21E7}")
            }
            Text("\(number)")
        }
        .font(PanelStyle.Text.meta.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(tint.map { PanelStyle.onColor($0) } ?? .secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
            tint.map { PanelStyle.surfaceOnColor($0) } ?? PanelStyle.surfaceRaised,
            in: Capsule()
        )
    }
}
