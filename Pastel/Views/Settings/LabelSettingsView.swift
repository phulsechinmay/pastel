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
        try? modelContext.save()
    }

    private func deleteLabel(_ label: Label) {
        modelContext.delete(label)
        try? modelContext.save()
    }
}

// MARK: - Label Row

/// A single label row with inline editing for name and color.
private struct LabelRow: View {

    @Bindable var label: Label
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false

    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Color dot with recolor menu
            Menu {
                ForEach(LabelColor.allCases, id: \.self) { color in
                    Button {
                        label.colorName = color.rawValue
                        try? modelContext.save()
                    } label: {
                        HStack {
                            Circle()
                                .fill(color.color)
                                .frame(width: 10, height: 10)
                            Text(color.rawValue.capitalized)
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
                    .frame(width: 14, height: 14)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Name field (click to edit)
            if isEditing {
                TextField("Label name", text: $label.name)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        isEditing = false
                        try? modelContext.save()
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
}
