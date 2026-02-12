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
            // Color dot -- always shown as first element
            Circle()
                .fill(dotColor)
                .frame(width: size == .compact ? 5 : 6, height: size == .compact ? 5 : 6)

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

    /// Color for the leading dot circle.
    private var dotColor: Color {
        if let tint = tintOverride {
            return tint
        }
        return LabelColor(rawValue: label.colorName)?.color ?? .gray
    }

    /// Always-neutral background regardless of label color or emoji.
    private var background: Color {
        if let tint = tintOverride {
            return tint.opacity(0.15)
        }

        if isActive {
            return Color.accentColor.opacity(0.3)
        } else {
            return Color.white.opacity(0.1)
        }
    }
}
