import SwiftUI
import SwiftData

struct EditItemView: View {
    @Bindable var item: ClipboardItem
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Item")
                .font(.headline)

            // Title field
            TextField("Title (optional)", text: titleBinding)
                .textFieldStyle(.roundedBorder)

            // Label multi-select section
            if !allLabels.isEmpty {
                Text("Labels")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Reuse CenteredFlowLayout from ChipBarView
                CenteredFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(allLabels) { label in
                        labelToggleChip(for: label)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Title Binding

    /// Converts between optional String and TextField String.
    /// Caps title at 50 characters. Sets to nil when empty/whitespace-only.
    private var titleBinding: Binding<String> {
        Binding(
            get: { item.title ?? "" },
            set: { newValue in
                let capped = String(newValue.prefix(50))
                item.title = capped.trimmingCharacters(in: .whitespaces).isEmpty ? nil : capped
            }
        )
    }

    // MARK: - Label Toggle Chip

    @ViewBuilder
    private func labelToggleChip(for label: Label) -> some View {
        let isAssigned = item.labels.contains {
            $0.persistentModelID == label.persistentModelID
        }

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
            isAssigned
                ? Color.accentColor.opacity(0.3)
                : Color.white.opacity(0.1),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(
                isAssigned ? Color.accentColor.opacity(0.6) : Color.clear,
                lineWidth: 1
            )
        )
        .contentShape(Capsule())
        .onTapGesture {
            if isAssigned {
                item.labels.removeAll {
                    $0.persistentModelID == label.persistentModelID
                }
            } else {
                item.labels.append(label)
            }
        }
    }
}
