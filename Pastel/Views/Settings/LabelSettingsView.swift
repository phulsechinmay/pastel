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
            Text("\u{201C}\(label.name)\u{201D} will be removed from any clipboard items it's attached to.")
        }
    }

    // MARK: - Actions

    private func createLabel() {
        let maxOrder = labels.map(\.sortOrder).max() ?? -1
        let newLabel = Label(name: "New Label", colorName: "blue", sortOrder: maxOrder + 1)
        modelContext.insert(newLabel)
        saveWithLogging(modelContext, operation: "create label")
    }

    private func deleteLabel(_ label: Label) {
        modelContext.delete(label)
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

/// A single label row with always-editable name, swatch popover, and trash button.
private struct LabelRow: View {

    @Bindable var label: Label
    @Environment(\.modelContext) private var modelContext
    @State private var showingPalette = false

    var onRequestDelete: () -> Void

    /// Curated label-friendly emojis for quick selection.
    private static let curatedEmojis: [String] = [
        "📌", "📎", "📝", "📋", "📂", "💡",
        "⭐", "❤️", "🔥", "🎯", "🏷️", "🔖",
        "✅", "❌", "⚡", "🎨", "🔧", "🐛",
        "💬", "📧", "🔒", "🌟", "💎", "🚀"
    ]

    var body: some View {
        HStack(spacing: 10) {
            Button {
                showingPalette.toggle()
            } label: {
                swatch
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingPalette, arrowEdge: .leading) {
                colorEmojiPalette
            }

            TextField("Label name", text: $label.name)
                .textFieldStyle(.plain)
                .onSubmit {
                    saveWithLogging(modelContext, operation: "update label name")
                }

            Spacer()

            Button(role: .destructive, action: onRequestDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete label")
        }
        .padding(.vertical, 4)
    }

    private var swatch: some View {
        Group {
            if let emoji = label.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: 14))
            } else {
                Circle()
                    .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
                    .frame(width: 14, height: 14)
            }
        }
        .frame(width: 22, height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Color + Emoji Palette Popover

    private var colorEmojiPalette: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(.secondary)

            let columns = Array(repeating: GridItem(.fixed(22), spacing: 6), count: 6)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(LabelColor.allCases, id: \.self) { labelColor in
                    Circle()
                        .fill(labelColor.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    label.colorName == labelColor.rawValue && label.emoji == nil
                                        ? Color.white : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .onTapGesture {
                            label.colorName = labelColor.rawValue
                            label.emoji = nil
                            saveWithLogging(modelContext, operation: "update label color")
                            showingPalette = false
                        }
                }
            }

            Divider()

            Text("Emoji")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.curatedEmojis, id: \.self) { emoji in
                    Text(emoji)
                        .font(.system(size: 16))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(label.emoji == emoji ? Color.white.opacity(0.18) : Color.clear)
                        )
                        .onTapGesture {
                            label.emoji = emoji
                            saveWithLogging(modelContext, operation: "update label emoji")
                            showingPalette = false
                        }
                }
            }
        }
        .padding(12)
        .frame(width: 188)
    }
}
