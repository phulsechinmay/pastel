import SwiftUI
import SwiftData

/// Label management view for the Settings Labels tab.
///
/// Displays all labels in a scrollable list with inline editing.
/// Supports create, rename, recolor, and delete operations.
struct LabelSettingsView: View {

    @Query(sort: \Label.sortOrder) private var labels: [Label]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                Text("Labels")
                    .font(.headline)
                Spacer()
                Button {
                    createLabel()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Add a new label")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Label list
            if labels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tag")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No labels yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(labels) { label in
                            LabelRow(label: label, onDelete: { deleteLabel(label) })
                            Divider()
                                .padding(.leading, 38)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
}

// MARK: - Label Row

/// A single label row with inline editing for name, color, and emoji.
private struct LabelRow: View {

    @Bindable var label: Label
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var showingPalette = false

    var onDelete: () -> Void

    /// Curated label-friendly emojis for quick selection.
    private static let curatedEmojis: [String] = [
        "📌", "📎", "📝", "📋", "📂", "💡",
        "⭐", "❤️", "🔥", "🎯", "🏷️", "🔖",
        "✅", "❌", "⚡", "🎨", "🔧", "🐛",
        "💬", "📧", "🔒", "🌟", "💎", "🚀"
    ]

    var body: some View {
        HStack(spacing: 12) {
            // Unified color + emoji palette button
            Button {
                showingPalette.toggle()
            } label: {
                if let emoji = label.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 14))
                        .frame(width: 20, height: 20)
                } else {
                    Circle()
                        .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
                        .frame(width: 14, height: 14)
                        .frame(width: 20, height: 20)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingPalette) {
                colorEmojiPalette
            }

            // Name field (click to edit)
            if isEditing {
                TextField("Label name", text: $label.name)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        isEditing = false
                        saveWithLogging(modelContext, operation: "update label name")
                    }
            } else {
                Text(label.name)
                    .onTapGesture {
                        isEditing = true
                    }
            }

            Spacer()

            // Delete button
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    // MARK: - Color + Emoji Palette Popover

    private var colorEmojiPalette: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 6x2 color grid (same layout as ChipBarView)
            let columns = Array(repeating: GridItem(.fixed(20), spacing: 6), count: 6)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(LabelColor.allCases, id: \.self) { labelColor in
                    Circle()
                        .fill(labelColor.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    label.colorName == labelColor.rawValue
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

            // Emoji header
            Text("Emoji")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Curated emoji grid (same 6-column layout as colors)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.curatedEmojis, id: \.self) { emoji in
                    Text(emoji)
                        .font(.system(size: 16))
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(label.emoji == emoji ? Color.white.opacity(0.2) : Color.clear)
                        )
                        .onTapGesture {
                            label.emoji = emoji
                            saveWithLogging(modelContext, operation: "update label emoji")
                            showingPalette = false
                        }
                }

            }
        }
        .padding(10)
        .frame(width: 170)
    }
}
