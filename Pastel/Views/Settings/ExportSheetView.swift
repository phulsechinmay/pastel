import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Export configuration sheet with content type, label, and date range filters.
struct ExportSheetView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Label.sortOrder) private var labels: [Label]

    @State private var importExportService = ImportExportService()
    @State private var selectedTypes: Set<ContentType> = {
        var types = Set(ContentType.allCases)
        types.remove(.image)
        return types
    }()
    @State private var selectedLabelNames: Set<String> = []
    @State private var filterByDate: Bool = false
    @State private var exportSinceDays: Int = 30
    @State private var showingSuccess = false
    @State private var exportedItemCount = 0
    @State private var errorMessage: String?

    private var contentTypeName: (ContentType) -> String = { type in
        switch type {
        case .text: "Text"
        case .richText: "Rich Text"
        case .url: "URLs"
        case .image: "Images"
        case .code: "Code"
        case .color: "Colors"
        case .file: "Files"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Export Clipboard History")
                .font(.title2)
                .fontWeight(.semibold)

            // Content Types
            VStack(alignment: .leading, spacing: 8) {
                Text("Content Types")
                    .font(.headline)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], alignment: .leading, spacing: 6) {
                    ForEach(ContentType.allCases, id: \.rawValue) { type in
                        if type == .image {
                            Toggle(isOn: .constant(false)) {
                                Text(contentTypeName(type))
                                    .foregroundStyle(.secondary)
                            }
                            .toggleStyle(.checkbox)
                            .disabled(true)
                        } else {
                            Toggle(
                                contentTypeName(type),
                                isOn: Binding(
                                    get: { selectedTypes.contains(type) },
                                    set: { selected in
                                        if selected {
                                            selectedTypes.insert(type)
                                        } else {
                                            selectedTypes.remove(type)
                                        }
                                    }
                                )
                            )
                            .toggleStyle(.checkbox)
                        }
                    }
                }

                Text("Images are not supported in export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Labels
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Labels")
                        .font(.headline)
                    Spacer()
                    Button("Select All") {
                        selectedLabelNames = Set(labels.map(\.name))
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    Button("Deselect All") {
                        selectedLabelNames.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.blue)
                }

                if labels.isEmpty {
                    Text("No labels created yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(labels, id: \.name) { label in
                                Toggle(
                                    isOn: Binding(
                                        get: { selectedLabelNames.contains(label.name) },
                                        set: { selected in
                                            if selected {
                                                selectedLabelNames.insert(label.name)
                                            } else {
                                                selectedLabelNames.remove(label.name)
                                            }
                                        }
                                    )
                                ) {
                                    HStack(spacing: 6) {
                                        if let emoji = label.emoji {
                                            Text(emoji)
                                        } else {
                                            Circle()
                                                .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
                                                .frame(width: 10, height: 10)
                                        }
                                        Text(label.name)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }

            Divider()

            // Date Filter
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Export data since", isOn: $filterByDate)
                    .toggleStyle(.checkbox)

                if filterByDate {
                    Picker("Time range:", selection: $exportSinceDays) {
                        Text("1 Week").tag(7)
                        Text("1 Month").tag(30)
                        Text("3 Months").tag(90)
                        Text("1 Year").tag(365)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }

                Text("When unchecked, only items with selected labels are exported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if importExportService.isProcessing {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: importExportService.progress)
                    Text(importExportService.progressMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Export...") {
                    performExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedTypes.isEmpty || importExportService.isProcessing)
            }
        }
        .padding(24)
        .frame(minWidth: 440, minHeight: 500)
        .alert("Export Complete", isPresented: $showingSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Exported \(exportedItemCount) items to .pastel file.")
        }
    }

    private func performExport() {
        errorMessage = nil

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pastelExport]
        panel.nameFieldStringValue = "Clipboard History.pastel"
        panel.title = "Export Clipboard History"
        panel.message = "Choose where to save your clipboard history."
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        let sinceDate: Date? = filterByDate
            ? Calendar.current.date(byAdding: .day, value: -exportSinceDays, to: .now)
            : nil

        Task {
            do {
                let data = try importExportService.exportHistory(
                    modelContext: modelContext,
                    contentTypes: selectedTypes,
                    labelNames: selectedLabelNames,
                    sinceDate: sinceDate
                )
                try data.write(to: url, options: .atomic)
                exportedItemCount = importExportService.lastExportCount
                showingSuccess = true
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
