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
    @Environment(AppState.self) private var appState

    // MARK: - Label Edit State

    @State private var editingLabel: Label?

    // MARK: - Label Creation State

    /// Whether the "+" has morphed into the inline creation chip.
    @State private var isCreating = false
    @State private var newLabelName = ""
    @State private var newLabelColorName: String = LabelColor.blue.rawValue
    @State private var newLabelEmoji: String?
    /// Bumped after the chip appears to pull keyboard focus into the name field.
    @State private var createFocusRequestID = 0
    /// Whether the color/emoji picker dropdown is open (anchored to the chip's dot).
    @State private var showStylePicker = false

    private var canCreate: Bool {
        !newLabelName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        CenteredFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            allHistoryChip
            ForEach(labels) { label in
                labelChip(for: label)
            }
            // The "+" morphs into a compact editable chip in place.
            if isCreating {
                inlineCreateChip
            } else {
                createChip
            }
        }
        // Springy reflow as chips are added/removed and as the "+" morphs.
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: labels.count)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isCreating)
        .padding(.vertical, 4)
        .sheet(item: $editingLabel) { label in
            LabelEditPalette(label: label, onDismiss: { editingLabel = nil })
        }
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
            .frame(height: PanelLayout.chipHeight)
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
            .contextMenu {
                Button {
                    editingLabel = label
                } label: {
                    SwiftUI.Label("Edit", systemImage: "pencil")
                }

                Button {
                    SettingsWindowController.shared.showSettings(
                        modelContainer: modelContext.container,
                        appState: appState,
                        initialTab: .labels
                    )
                } label: {
                    SwiftUI.Label("Reorder", systemImage: "arrow.up.arrow.down")
                }

                Divider()

                Button(role: .destructive) {
                    deleteLabel(label)
                } label: {
                    SwiftUI.Label("Delete", systemImage: "trash")
                }
            }
    }

    // MARK: - Create Chip

    /// The idle "+" chip. Tapping it morphs into the inline creation chip.
    private var createChip: some View {
        Button {
            openCreate()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: PanelLayout.chipHeight)
                .background(Color.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline Create Chip

    /// Compact editable chip that replaces the "+": a color/emoji dot (tap for the
    /// style dropdown), a name field, and a trailing cancel. Enter creates, Esc cancels.
    /// The label starts with a randomly assigned color so no picking is required.
    private var inlineCreateChip: some View {
        HStack(spacing: 6) {
            Button {
                showStylePicker.toggle()
            } label: {
                HStack(spacing: 2) {
                    styleDot
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showStylePicker, arrowEdge: .bottom) {
                LabelStyleSelector(colorName: $newLabelColorName, emoji: $newLabelEmoji)
                    .padding(12)
                    .frame(width: 220)
                    .preferredColorScheme(.dark)
            }

            FocusableTextField(
                text: $newLabelName,
                placeholder: "Label name",
                fontSize: 11,
                focusRequestID: createFocusRequestID,
                onSubmit: { createLabel() },
                onCancel: { closeCreate() }
            )
            .frame(width: 104)

            Button {
                closeCreate()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: PanelLayout.chipHeight)
        .background(Color.white.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    /// The chip's leading indicator: the chosen emoji, or a color dot when none.
    private var styleDot: some View {
        Group {
            if let emoji = newLabelEmoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: 11))
            } else {
                Circle()
                    .fill(LabelColor(rawValue: newLabelColorName)?.color ?? .gray)
                    .frame(width: 7, height: 7)
            }
        }
        .animation(.snappy, value: newLabelEmoji)
        .animation(.snappy, value: newLabelColorName)
    }

    // MARK: - Actions

    private func openCreate() {
        newLabelName = ""
        // Assign a random color up front so the user can just type and hit Enter.
        newLabelColorName = (LabelColor.allCases.randomElement() ?? .blue).rawValue
        newLabelEmoji = nil
        showStylePicker = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            isCreating = true
        }
        // Pull focus into the name field once the chip is in the hierarchy.
        DispatchQueue.main.async { createFocusRequestID &+= 1 }
    }

    private func closeCreate() {
        showStylePicker = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            isCreating = false
        }
    }

    private func createLabel() {
        let trimmedName = newLabelName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // Determine next sort order
        let maxOrder = labels.map(\.sortOrder).max() ?? -1
        let newLabel = Label(
            name: trimmedName,
            colorName: newLabelColorName,
            sortOrder: maxOrder + 1,
            emoji: newLabelEmoji
        )

        modelContext.insert(newLabel)
        saveWithLogging(modelContext, operation: "create label")
        closeCreate()
    }

    private func deleteLabel(_ label: Label) {
        selectedLabelIDs.remove(label.persistentModelID)
        deleteLabelWithCleanup(label, from: modelContext)
        saveWithLogging(modelContext, operation: "delete label from chip bar")
    }
}

// MARK: - Label Style Selector

/// Shared color + emoji picker used by both inline label creation and the edit palette.
///
/// Selecting a color clears the emoji (color dot mode); selecting an emoji keeps the
/// stored color but hides the dot — matching `LabelChipView`'s rendering. Selection
/// changes animate so the highlight glides between swatches.
struct LabelStyleSelector: View {

    /// Bound to the label's `colorName` (a `LabelColor` raw value).
    @Binding var colorName: String
    /// Bound to the label's optional emoji.
    @Binding var emoji: String?

    /// Curated label-friendly emojis for quick selection.
    static let curatedEmojis: [String] = [
        "📌", "📎", "📝", "📋", "📂", "💡",
        "⭐", "❤️", "🔥", "🎯", "🏷️", "🔖",
        "✅", "❌", "⚡", "🎨", "🔧", "🐛",
        "💬", "📧", "🔒", "🌟", "💎", "🚀"
    ]

    private var isColorSelected: Bool { emoji?.isEmpty ?? true }

    private let columns = Array(repeating: GridItem(.fixed(22), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(LabelColor.allCases, id: \.self) { labelColor in
                    let selected = isColorSelected && colorName == labelColor.rawValue
                    Circle()
                        .fill(labelColor.color)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().strokeBorder(selected ? Color.white : Color.clear, lineWidth: 2)
                        )
                        .scaleEffect(selected ? 1.12 : 1.0)
                        .contentShape(Circle())
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) {
                                colorName = labelColor.rawValue
                                emoji = nil
                            }
                        }
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Self.curatedEmojis, id: \.self) { curatedEmoji in
                    let selected = emoji == curatedEmoji
                    Text(curatedEmoji)
                        .font(.system(size: 16))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selected ? Color.white.opacity(0.22) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) {
                                emoji = curatedEmoji
                            }
                        }
                }
            }
        }
    }
}

// MARK: - Label Edit Palette

/// Inline edit palette for modifying a label's name, color, and emoji.
private struct LabelEditPalette: View {
    @Bindable var label: Label
    @Environment(\.modelContext) private var modelContext
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Label")
                .font(.headline)

            TextField("Label name", text: $label.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit {
                    saveWithLogging(modelContext, operation: "update label name")
                }

            LabelStyleSelector(colorName: $label.colorName, emoji: $label.emoji)
                .onChange(of: label.colorName) { _, _ in
                    saveWithLogging(modelContext, operation: "update label color")
                }
                .onChange(of: label.emoji) { _, _ in
                    saveWithLogging(modelContext, operation: "update label emoji")
                }

            HStack {
                Spacer()
                Button("Done") {
                    saveWithLogging(modelContext, operation: "update label")
                    onDismiss()
                }
            }
        }
        .padding(12)
        .frame(width: 220)
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
