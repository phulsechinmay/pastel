import SwiftUI

/// Shared label chip used across chip bar, card footer, and edit modal.
///
/// Two sizes: `.regular` for chip bar and edit modal, `.compact` for card footers.
/// Background is always neutral (no colored background). A small color dot circle
/// precedes the emoji/name text. Active state adds an accent stroke border.
struct LabelChipView: View {
    let label: Label
    var size: ChipSize = .regular
    var isActive: Bool = false
    /// Override background for special contexts (e.g. color cards).
    var tintOverride: Color?

    enum ChipSize {
        case regular  // chip bar, edit modal
        case compact  // card footer
    }

    var body: some View {
        HStack(spacing: size == .compact ? 2 : 4) {
            // Color dot -- only shown if label has no emoji
            if label.emoji?.isEmpty ?? true {
                Circle()
                    .fill(dotColor)
                    .frame(width: size == .compact ? 5 : 7, height: size == .compact ? 5 : 7)
            }

            if let emoji = label.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(PanelStyle.Text.meta)
            }
            Text(label.name)
                // Compact chips used to drop to 8/9pt, below the platform's legibility
                // floor. Both sizes now sit on the shared ladder.
                .font(size == .compact ? PanelStyle.Text.meta : PanelStyle.Text.control)
                .lineLimit(1)
        }
        .chipChrome(isActive: isActive, tintOverride: tintOverride, isCompact: size == .compact)
    }

    /// Color for the leading dot circle.
    private var dotColor: Color {
        if let tint = tintOverride {
            return tint
        }
        return LabelColor(rawValue: label.colorName)?.color ?? .gray
    }
}
