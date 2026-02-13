import SwiftUI
import SwiftData

/// Wrapping chip bar for label filtering and inline label creation.
///
/// Displays one chip per label plus a trailing "+" chip for creating new labels.
/// Tapping a chip toggles filtering; tapping the active chip deselects it.
/// Chips wrap to multiple centered lines when they don't fit in a single row.
struct ChipBarView: View {

    let labels: [Label]
    @Binding var selectedLabelIDs: Set<PersistentIdentifier>
    var isAllHistoryActive: Bool = true
    var onSelectAllHistory: (() -> Void)?

    @Environment(\.modelContext) private var modelContext

    // MARK: - Label Creation State

    @State private var showingCreateLabel = false
    @State private var newLabelName = ""
    @State private var newLabelColor: LabelColor = .blue
    @State private var newLabelEmoji: String?

    /// Curated label-friendly emojis for quick selection.
    private static let curatedEmojis: [String] = [
        "📌", "📎", "📝", "📋", "📂", "💡",
        "⭐", "❤️", "🔥", "🎯", "🏷️", "🔖",
        "✅", "❌", "⚡", "🎨", "🔧", "🐛",
        "💬", "📧", "🔒", "🌟", "💎", "🚀"
    ]

    var body: some View {
        CenteredFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            allHistoryChip
            ForEach(labels) { label in
                labelChip(for: label)
            }
            createChip
        }
        .padding(.vertical, 4)
    }

    // MARK: - All History Chip

    private var allHistoryChip: some View {
        Button {
            onSelectAllHistory?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 11))
                Text("All History")
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isAllHistoryActive ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.1),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    isAllHistoryActive ? Color.accentColor.opacity(0.6) : Color.clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Label Chip

    @ViewBuilder
    private func labelChip(for label: Label) -> some View {
        let isActive = selectedLabelIDs.contains(label.persistentModelID)

        LabelChipView(label: label, isActive: isActive)
            .contentShape(Capsule())
            .onTapGesture {
                if isActive {
                    selectedLabelIDs.removeAll()
                } else {
                    selectedLabelIDs = [label.persistentModelID]
                }
            }
            .draggable(label.persistentModelID.asTransferString ?? "") {
                LabelChipView(label: label)
            }
    }

    // MARK: - Create Chip

    private var createChip: some View {
        Button {
            newLabelName = ""
            newLabelColor = .blue
            newLabelEmoji = nil
            showingCreateLabel = true
        } label: {
            Text("+")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingCreateLabel) {
            createLabelPopover
        }
    }

    // MARK: - Create Label Popover

    private var createLabelPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Label")
                .font(.headline)

            TextField("Label name", text: $newLabelName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            // Color palette (6x2 grid)
            let columns = Array(repeating: GridItem(.fixed(20), spacing: 6), count: 6)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(LabelColor.allCases, id: \.self) { labelColor in
                    Circle()
                        .fill(labelColor.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    newLabelEmoji == nil && newLabelColor == labelColor
                                        ? Color.white : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .onTapGesture {
                            newLabelColor = labelColor
                            newLabelEmoji = nil
                        }
                }
            }

            Divider()

            // Emoji header
            Text("Emoji")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Curated emoji grid (same 6-column layout)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.curatedEmojis, id: \.self) { emoji in
                    Text(emoji)
                        .font(.system(size: 16))
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(newLabelEmoji == emoji ? Color.white.opacity(0.2) : Color.clear)
                        )
                        .onTapGesture {
                            newLabelEmoji = emoji
                        }
                }

            }

            HStack {
                Button("Cancel") {
                    showingCreateLabel = false
                }

                Spacer()

                Button("Create") {
                    createLabel()
                }
                .disabled(newLabelName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    // MARK: - Actions

    private func createLabel() {
        let trimmedName = newLabelName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // Determine next sort order
        let maxOrder = labels.map(\.sortOrder).max() ?? -1
        let newLabel = Label(
            name: trimmedName,
            colorName: newLabelColor.rawValue,
            sortOrder: maxOrder + 1,
            emoji: newLabelEmoji
        )

        modelContext.insert(newLabel)
        saveWithLogging(modelContext, operation: "label reorder")
        showingCreateLabel = false
    }
}

// MARK: - Centered Flow Layout

/// A layout that arranges subviews in rows, wrapping to new lines and centering each row.
struct CenteredFlowLayout: Layout {

    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // When no width proposed, calculate single-line width as ideal
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let singleLineWidth = sizes.reduce(0) { $0 + $1.width }
            + CGFloat(max(0, sizes.count - 1)) * horizontalSpacing

        let containerWidth = proposal.width ?? singleLineWidth

        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if currentX + size.width > containerWidth && currentX > 0 {
                maxWidth = max(maxWidth, currentX - horizontalSpacing)
                currentY += lineHeight + verticalSpacing
                currentX = 0
                lineHeight = 0
            }
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
        maxWidth = max(maxWidth, currentX - horizontalSpacing)

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // First pass: group subviews into lines
        var lines: [(subviews: [LayoutSubviews.Element], sizes: [CGSize])] = [([], [])]

        var currentX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.width && currentX > 0 {
                lines.append(([], []))
                currentX = 0
            }
            lines[lines.count - 1].subviews.append(subview)
            lines[lines.count - 1].sizes.append(size)
            currentX += size.width + horizontalSpacing
        }

        // Second pass: place each line centered
        var y = bounds.minY
        for line in lines {
            let lineWidth = line.sizes.reduce(0) { $0 + $1.width }
                + CGFloat(max(0, line.sizes.count - 1)) * horizontalSpacing
            let lineHeight = line.sizes.map(\.height).max() ?? 0
            var x = bounds.minX + (bounds.width - lineWidth) / 2

            for (i, subview) in line.subviews.enumerated() {
                let size = line.sizes[i]
                subview.place(
                    at: CGPoint(x: x, y: y + (lineHeight - size.height) / 2),
                    proposal: .unspecified
                )
                x += size.width + horizontalSpacing
            }
            y += lineHeight + verticalSpacing
        }
    }
}
