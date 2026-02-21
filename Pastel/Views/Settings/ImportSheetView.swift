import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Import format selection for the import sheet.
private enum ImportFormat: String, CaseIterable {
    case pastel
    case pastePal

    var displayName: String {
        switch self {
        case .pastel: "Pastel (.pastel)"
        case .pastePal: "PastePal (.json)"
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .pastel: [.pastelExport]
        case .pastePal: [.json]
        }
    }
}

/// Import modal with format picker, file selection, and format validation.
struct ImportSheetView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var importExportService = ImportExportService()
    @State private var selectedFormat: ImportFormat = .pastel
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String = ""
    @State private var errorMessage: String?
    @State private var showingSuccess = false
    @State private var importResult: ImportResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Import Clipboard History")
                .font(.title2)
                .fontWeight(.semibold)

            // Format Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Format")
                    .font(.headline)
                Picker("Format", selection: $selectedFormat) {
                    ForEach(ImportFormat.allCases, id: \.rawValue) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            // File Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("File")
                    .font(.headline)
                HStack {
                    if selectedFileName.isEmpty {
                        Text("No file selected")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(selectedFileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Choose File...") {
                        chooseFile()
                    }
                }
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
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Import") {
                    performImport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedFileURL == nil || importExportService.isProcessing)
            }
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 300)
        .onChange(of: selectedFormat) {
            // Clear file selection when format changes
            selectedFileURL = nil
            selectedFileName = ""
            errorMessage = nil
        }
        .alert("Import Complete", isPresented: $showingSuccess) {
            Button("OK") { dismiss() }
        } message: {
            if let result = importResult {
                Text("Imported \(result.importedCount) items, skipped \(result.skippedCount) duplicates. \(result.labelsCreated) new labels created.")
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = selectedFormat.allowedContentTypes
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = selectedFormat == .pastel
            ? "Select Pastel Export File"
            : "Select PastePal Export File"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        selectedFileURL = url
        selectedFileName = url.lastPathComponent
        errorMessage = nil
    }

    private func performImport() {
        guard let url = selectedFileURL else { return }
        errorMessage = nil

        Task {
            do {
                let data = try Data(contentsOf: url)

                let result: ImportResult
                switch selectedFormat {
                case .pastel:
                    do {
                        result = try importExportService.importHistory(from: data, modelContext: modelContext)
                    } catch {
                        errorMessage = "The selected file does not appear to be a valid Pastel export. Please check the file and try again."
                        return
                    }
                case .pastePal:
                    do {
                        result = try importExportService.importPastePalHistory(from: data, modelContext: modelContext)
                    } catch {
                        errorMessage = "The selected file does not appear to be a valid PastePal export. Please check the file and try again."
                        return
                    }
                }

                importResult = result
                showingSuccess = true
            } catch {
                errorMessage = "Failed to read file: \(error.localizedDescription)"
            }
        }
    }
}
