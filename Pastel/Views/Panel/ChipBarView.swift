import SwiftUI
import SwiftData

/// Wrapping chip bar for label filtering and inline label creation.
///
/// Displays one chip per label plus a trailing "+" chip for creating new labels.
/// Tapping a chip toggles filtering; tapping the active chip deselects it.
///
/// Chips wrap to leading-aligned rows, capped at `PanelLayout.chipMaxRows`. Anything
/// past the cap folds behind a "+N" chip that expands the bar on demand. Both the
/// alignment and the cap are deliberate: centred rows shared no left edge with the
/// search field above or the cards below, and an uncapped bar grew until the panel
/// was mostly chrome.
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
    /// Hover state for the create chip's left color/emoji section (lightens on hover).
    @State private var isHoveringStyle = false

    // MARK: - Overflow State

    /// How many chips of any kind the layout managed to place inside the row cap.
    @State private var placedChipCount: Int = .max
    /// Whether the user has tapped "+N" to see every label.
    @State private var isExpanded = false

    /// The label budget: whatever the layout placed, minus the two slots that
    /// "All History" and the trailing create chip always occupy.
    private var visibleLabelCount: Int {
        placedChipCount == .max ? .max : max(0, placedChipCount - reservedChipCount)
    }

    private var canCreate: Bool {
        !newLabelName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Labels past the row cap, folded behind the overflow chip.
    private var hiddenLabels: [Label] {
        isExpanded ? [] : Array(labels.dropFirst(visibleLabelCount))
    }

    private var shownLabels: [Label] {
        isExpanded ? labels : Array(labels.prefix(visibleLabelCount))
    }

    var body: some View {
        WrappingFlowLayout(
            horizontalSpacing: PanelLayout.chipSpacing,
            verticalSpacing: PanelLayout.chipRowSpacing,
            maxRows: isExpanded ? nil : PanelLayout.chipMaxRows,
            // Monotone decreasing. The count feeds back into `shownLabels`, which
            // changes the subview list, which re-runs layout: left free to move in
            // both directions that settles into a two-value oscillation at widths
            // where hiding a label frees exactly enough room to show it again.
            // Shrink-only converges, and the resets below let it recover.
            visibleCount: Binding(
                get: { placedChipCount },
                set: { placedChipCount = min(placedChipCount, $0) }
            )
        ) {
            allHistoryChip
            ForEach(shownLabels) { label in
                labelChip(for: label)
            }
            if !hiddenLabels.isEmpty {
                overflowChip
            } else if isExpanded {
                collapseChip
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
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isExpanded)
        .padding(.vertical, 4)
        // Release the shrink-only ratchet whenever the thing being measured changes,
        // so the bar can grow back after a label is deleted or the panel widens.
        .onChange(of: labels.count) { _, _ in placedChipCount = .max }
        .onChange(of: isExpanded) { _, _ in placedChipCount = .max }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in
            placedChipCount = .max
        }
        .sheet(item: $editingLabel) { label in
            LabelEditPalette(label: label, onDismiss: { editingLabel = nil })
        }
    }

    /// "All History" plus the trailing create chip always hold a slot, so the label
    /// budget is whatever the layout reported minus those two.
    private var reservedChipCount: Int { 2 }

    // MARK: - Overflow Chip

    /// Folds the labels that did not fit into a single "+N" chip.
    ///
    /// The cap exists because the bar had no ceiling: seven labels already wrapped to
    /// four centred rows in the 320pt panel, roughly 200pt of chrome before the first
    /// clip. Every label a user created made their own history harder to see.
    private var overflowChip: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                isExpanded = true
            }
        } label: {
            Text("+\(hiddenLabels.count)")
                .font(PanelStyle.Text.control)
                .lineLimit(1)
                .chipChrome()
        }
        .buttonStyle(.plain)
        .help("Show \(hiddenLabels.count) more label\(hiddenLabels.count == 1 ? "" : "s")")
    }

    /// The way back down to the row cap once the bar has been expanded.
    private var collapseChip: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                isExpanded = false
            }
        } label: {
            Image(systemName: "chevron.up")
                .font(PanelStyle.Text.control.weight(.semibold))
                .chipChrome()
        }
        .buttonStyle(.plain)
        .help("Show fewer labels")
    }

    // MARK: - All History Chip

    private var allHistoryChip: some View {
        Button {
            onSelectAllHistory?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(PanelStyle.Text.control)
                Text("All History")
                    .font(PanelStyle.Text.control)
                    .lineLimit(1)
            }
            .chipChrome(isActive: isAllHistoryActive)
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
                .font(PanelStyle.Text.control.weight(.semibold))
                .chipChrome()
        }
        .buttonStyle(.plain)
        .help("New Label")
    }

    // MARK: - Inline Create Chip

    /// Compact editable chip that replaces the "+": a color/emoji dot (tap for the
    /// style dropdown), a name field, and a trailing cancel. Enter creates, Esc cancels.
    /// The label starts with a randomly assigned color so no picking is required.
    private var inlineCreateChip: some View {
        HStack(spacing: 0) {
            // The whole left region (leading inset + dot + gap) opens the picker and
            // lightens on hover to signal it's interactive.
            Button {
                showStylePicker.toggle()
            } label: {
                styleDot
                    .padding(.leading, PanelLayout.chipHorizontalPadding)
                    .padding(.trailing, 6)
                    .frame(maxHeight: .infinity)
                    .background(
                        isHoveringStyle ? PanelStyle.surfaceHover : Color.clear,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: PanelLayout.chipHeight / 2,
                            bottomLeadingRadius: PanelLayout.chipHeight / 2
                        )
                    )
                    .contentShape(Rectangle())
                    .animation(.easeInOut(duration: 0.12), value: isHoveringStyle)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringStyle = $0 }
            .popover(isPresented: $showStylePicker, arrowEdge: .bottom) {
                LabelStyleSelector(colorName: $newLabelColorName, emoji: $newLabelEmoji)
                    .padding(12)
                    .frame(width: 220)
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
            // Un-highlighted margin so the hover fill doesn't reach the cursor.
            .padding(.leading, 4)

            Button {
                closeCreate()
            } label: {
                Image(systemName: "xmark")
                    .font(PanelStyle.Icon.meta.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                    .padding(.trailing, PanelLayout.chipHorizontalPadding)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: PanelLayout.chipHeight)
        .background(PanelStyle.surfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(PanelStyle.chipActiveStroke, lineWidth: 1))
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    /// The chip's leading indicator: the chosen emoji, or a color dot when none.
    private var styleDot: some View {
        Group {
            if let emoji = newLabelEmoji, !emoji.isEmpty {
                Text(emoji).font(PanelStyle.Text.control)
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
                        .overlay {
                            Circle()
                                .strokeBorder(PanelStyle.swatchSelectionRing, lineWidth: 2)
                                .padding(-3)
                                .opacity(selected ? 1 : 0)
                        }
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
                        .font(PanelStyle.Icon.content)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selected ? PanelStyle.surfaceActive : Color.clear)
                        )
                        // Same ring as the colour swatches above, so "selected" is one
                        // thing in this control rather than a fill here and a ring there.
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(PanelStyle.swatchSelectionRing, lineWidth: 2)
                                .padding(-3)
                                .opacity(selected ? 1 : 0)
                        }
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

// MARK: - Wrapping Flow Layout

/// Arranges subviews in leading-aligned rows, wrapping to new lines, with an optional
/// hard ceiling on row count.
///
/// Replaces the previous centred variant. Centring each row was the single thing that
/// made a bar of eight or nine pills read as chaotic: no two rows shared a left edge,
/// so nothing lined up with the search field above it or the cards below it. Leading
/// alignment costs nothing and gives the whole panel one vertical rhythm.
///
/// `maxRows` clips overflow rather than growing without bound. The caller learns how
/// many subviews actually fit via `onVisibleCountChange` and folds the rest behind a
/// "+N" chip. The last slot on the final row is always reserved for the trailing
/// control (the create chip), so it never gets clipped away.
struct WrappingFlowLayout: Layout {

    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat
    /// `nil` means unlimited.
    var maxRows: Int?
    /// Receives how many subviews were placed within the row cap.
    ///
    /// A `Binding` rather than a closure on purpose. Swift matches a trailing closure
    /// by scanning parameters backward for the first function-typed one, wherever it
    /// sits in the list, so a `((Int) -> Void)?` member would swallow the layout's
    /// content closure at every call site that omitted it. The compiler's diagnostic
    /// for that ("requires conformance to View") points nowhere near the cause.
    var visibleCount: Binding<Int>?

    /// One resolved wrapping pass: which subview indices land on which row.
    private struct Plan {
        var rows: [[Int]]
        var size: CGSize
        var placedCount: Int
    }

    private func plan(sizes: [CGSize], containerWidth: CGFloat) -> Plan {
        var rows: [[Int]] = [[]]
        var rowHeights: [CGFloat] = [0]
        var currentX: CGFloat = 0
        var maxWidth: CGFloat = 0
        var placed = 0

        for (index, size) in sizes.enumerated() {
            let needsWrap = currentX + size.width > containerWidth && currentX > 0
            if needsWrap {
                if let maxRows, rows.count >= maxRows {
                    // Out of rows. Everything from here on is overflow.
                    break
                }
                maxWidth = max(maxWidth, currentX - horizontalSpacing)
                rows.append([])
                rowHeights.append(0)
                currentX = 0
            }
            rows[rows.count - 1].append(index)
            rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], size.height)
            currentX += size.width + horizontalSpacing
            placed += 1
        }
        maxWidth = max(maxWidth, currentX - horizontalSpacing)

        let totalHeight = rowHeights.reduce(0, +)
            + CGFloat(max(0, rowHeights.count - 1)) * verticalSpacing

        return Plan(
            rows: rows,
            size: CGSize(width: max(0, maxWidth), height: totalHeight),
            placedCount: placed
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let singleLineWidth = sizes.reduce(0) { $0 + $1.width }
            + CGFloat(max(0, sizes.count - 1)) * horizontalSpacing
        let containerWidth = proposal.width ?? singleLineWidth
        return plan(sizes: sizes, containerWidth: containerWidth).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let resolved = plan(sizes: sizes, containerWidth: bounds.width)

        // Writing during layout would mutate state mid-pass; defer a tick.
        if let visibleCount {
            let count = resolved.placedCount
            if visibleCount.wrappedValue != count {
                DispatchQueue.main.async { visibleCount.wrappedValue = count }
            }
        }

        var y = bounds.minY
        for row in resolved.rows {
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            var x = bounds.minX
            for index in row {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2),
                    proposal: .unspecified
                )
                x += size.width + horizontalSpacing
            }
            y += rowHeight + verticalSpacing
        }

        // Anything past the cap is parked off-screen rather than left at the origin,
        // where it would stack on top of the first chip.
        if resolved.placedCount < subviews.count {
            for index in resolved.placedCount..<subviews.count {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX, y: bounds.minY - 10_000),
                    proposal: .unspecified
                )
            }
        }
    }
}
