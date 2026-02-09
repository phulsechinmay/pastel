import SwiftUI

/// Shared label chip used across chip bar, card footer, and edit modal.
///
/// Two sizes: `.regular` for chip bar and edit modal, `.compact` for card footers.
/// Background uses the label's assigned color (no color dot). Emoji labels use
/// a neutral background. Active state adds an accent stroke border.
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
            if let emoji = label.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: size == .compact ? 8 : 10))
            }
            Text(label.name)
                .font(size == .compact ? .system(size: 9) : .caption)
                .lineLimit(1)
        }
        .padding(.horizontal, size == .compact ? 5 : 8)
        .padding(.vertical, size == .compact ? 2 : 4)
        .background(background, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                isActive ? Color.accentColor.opacity(0.6) : Color.clear,
                lineWidth: 1
            )
        )
    }

    private var background: Color {
        if let tint = tintOverride {
            return tint.opacity(0.15)
        }

        let hasEmoji = label.emoji?.isEmpty == false
        let labelColor = LabelColor(rawValue: label.colorName)?.color ?? .gray

        if hasEmoji {
            return isActive ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.1)
        } else {
            return isActive ? labelColor.opacity(0.7) : labelColor.opacity(0.45)
        }
    }
}
