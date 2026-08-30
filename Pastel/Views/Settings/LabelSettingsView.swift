import SwiftUI
import SwiftData

/// Label management view for the Settings Labels tab.
///
/// Native `List` with `.inset` style, an always-editable name `TextField` per row,
/// a swatch button that opens a color + emoji popover, and a trailing trash button
/// that requires confirmation. Reorder is supported via `.onMove` (drag any row).
/// The `+` button lives in the window toolbar via `ToolbarItem`.
struct LabelSettingsView: View {

    @Query(sort: \Label.sortOrder) private var labels: [Label]
    @Environment(\.modelContext) private var modelContext

    @State private var labelPendingDeletion: Label?

    var body: some View {
        Group {
            if labels.isEmpty {
                ContentUnavailableView {
                    SwiftUI.Label("No labels yet", systemImage: "tag")
                } description: {
                    Text("Use the + button above to create your first label.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(labels) { label in
                        LabelRow(label: label) { labelPendingDeletion = label }
                    }
                    .onMove(perform: moveLabels)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createLabel) {
                    SwiftUI.Label("Add Label", systemImage: "plus")
                }
                .help("Add a new label")
            }
        }
        .alert(
            "Delete Label?",
            isPresented: Binding(
                get: { labelPendingDeletion != nil },
                set: { if !$0 { labelPendingDeletion = nil } }
            ),
            presenting: labelPendingDeletion
        ) { label in
            Button("Delete", role: .destructive) {
                deleteLabel(label)
                labelPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                labelPendingDeletion = nil
            }
        } message: { label in
            // States the actual number. "any clipboard items it's attached to" asked the
            // user to authorise a consequence whose size only the database knew.
            Text(deletionWarning(for: label))
        }
    }

    // MARK: - Actions

    /// Delete confirmation copy, sized to what the label is actually holding.
    private func deletionWarning(for label: Label) -> String {
        let count = label.safeItems.count
        let name = "\u{201C}\(label.name)\u{201D}"
        switch count {
        case 0:
            return "\(name) isn't attached to anything. The clips themselves are not affected."
        case 1:
            return "\(name) will be removed from 1 clip. The clip itself is kept."
        default:
            return "\(name) will be removed from \(count) clips. The clips themselves are kept."
        }
    }

    private func createLabel() {
        let maxOrder = labels.map(\.sortOrder).max() ?? -1
        let newLabel = Label(name: "New Label", colorName: "blue", sortOrder: maxOrder + 1)
        modelContext.insert(newLabel)
        saveWithLogging(modelContext, operation: "create label")
    }

    private func deleteLabel(_ label: Label) {
        deleteLabelWithCleanup(label, from: modelContext)
        saveWithLogging(modelContext, operation: "delete label")
    }

    private func moveLabels(from source: IndexSet, to destination: Int) {
        var reordered = Array(labels)
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, label) in reordered.enumerated() {
            if label.sortOrder != index {
                label.sortOrder = index
            }
        }
        saveWithLogging(modelContext, operation: "reorder labels")
    }
}

// MARK: - Label Row

/// A single label row with always-editable name, swatch popover, usage count, and a
/// delete button that stays out of the way until the pointer is on the row.
private struct LabelRow: View {

    @Bindable var label: Label
    @Environment(\.modelContext) private var modelContext
    @State private var showingPalette = false
    @State private var isHovered = false

    var onRequestDelete: () -> Void

    /// How many clips carry this label, read straight off the inverse relationship.
    private var usageCount: Int { label.safeItems.count }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                showingPalette.toggle()
            } label: {
                swatch
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingPalette, arrowEdge: .leading) {
                // The shared selector, not a second hand-rolled palette. This row used
                // to carry its own copy of the colour grid, the emoji list, and the
                // curated emoji array, tuned to different spacing than the one the chip
                // bar and the edit palette use. Three pickers, one job, three looks.
                LabelStyleSelector(colorName: $label.colorName, emoji: $label.emoji)
                    .padding(12)
                    .frame(width: 220)
                    .onChange(of: label.colorName) { _, _ in
                        saveWithLogging(modelContext, operation: "update label color")
                    }
                    .onChange(of: label.emoji) { _, _ in
                        saveWithLogging(modelContext, operation: "update label emoji")
                    }
            }

            TextField("Label name", text: $label.name)
                .textFieldStyle(.plain)
                .onSubmit {
                    saveWithLogging(modelContext, operation: "update label name")
                }

            Spacer()

            // Answers "is this label doing anything?" without a trip to the History
            // tab, and gives the delete button beside it some weight.
            Text(usageCount == 1 ? "1 clip" : "\(usageCount) clips")
                .font(PanelStyle.Text.meta)
                .monospacedDigit()
                .foregroundStyle(.tertiary)

            // Revealed on hover. Every row used to show its own trash, so a list of
            // eight labels was also a column of eight delete buttons. The context menu
            // below keeps the action reachable without the pointer.
            Button(role: .destructive, action: onRequestDelete) {
                Image(systemName: "trash")
                    .font(PanelStyle.Icon.control)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete label")
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .contextMenu {
            Button("Edit Style") { showingPalette = true }
            Divider()
            Button("Delete Label", role: .destructive, action: onRequestDelete)
        }
    }

    private var swatch: some View {
        Group {
            if let emoji = label.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(PanelStyle.Icon.control)
            } else {
                Circle()
                    .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
                    .frame(width: 14, height: 14)
            }
        }
        .frame(width: 22, height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(PanelStyle.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(PanelStyle.stroke, lineWidth: 1)
        )
    }

}
