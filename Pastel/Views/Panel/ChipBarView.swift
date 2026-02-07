import SwiftUI
import SwiftData

/// Horizontal scrolling chip bar for label filtering and inline label creation.
///
/// Displays one chip per label plus a trailing "+" chip for creating new labels.
/// Tapping a chip toggles filtering; tapping the active chip deselects it.
/// The "+" chip presents a popover for entering a name and picking a color.
struct ChipBarView: View {

    let labels: [Label]
    @Binding var selectedLabel: Label?

    @Environment(\.modelContext) private var modelContext

    // MARK: - Label Creation State

    @State private var showingCreateLabel = false
    @State private var newLabelName = ""
    @State private var newLabelColor: LabelColor = .blue

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Existing label chips
                ForEach(labels) { label in
                    labelChip(for: label)
                }

                // "+" create chip
                createChip
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Label Chip

    @ViewBuilder
    private func labelChip(for label: Label) -> some View {
        let isActive = selectedLabel?.persistentModelID == label.persistentModelID

        Button {
            if isActive {
                selectedLabel = nil
            } else {
                selectedLabel = label
            }
        } label: {
            HStack(spacing: 4) {
                if let emoji = label.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 10))
                } else {
                    Circle()
                        .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
                        .frame(width: 8, height: 8)
                }

                Text(label.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isActive
                    ? Color.accentColor.opacity(0.3)
                    : Color.white.opacity(0.1),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.6) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create Chip

    private var createChip: some View {
        Button {
            newLabelName = ""
            newLabelColor = .blue
            showingCreateLabel = true
        } label: {
            Text("+")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingCreateLabel, arrowEdge: .bottom) {
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
                                    newLabelColor == labelColor ? Color.white : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .onTapGesture {
                            newLabelColor = labelColor
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
            sortOrder: maxOrder + 1
        )

        modelContext.insert(newLabel)
        try? modelContext.save()
        showingCreateLabel = false
    }
}
