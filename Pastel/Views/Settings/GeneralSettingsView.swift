import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts
import UniformTypeIdentifiers

/// General settings tab with all 5 user-configurable settings.
///
/// Layout (top to bottom):
/// 1. Launch at login toggle (LaunchAtLogin package)
/// 2. Panel toggle hotkey recorder (KeyboardShortcuts package)
/// 3. Panel position selector (ScreenEdgePicker bound to @AppStorage "panelEdge")
/// 4. History retention dropdown (Picker bound to @AppStorage "historyRetention")
/// 5. Paste behavior dropdown (Picker bound to @AppStorage "pasteBehavior")
struct GeneralSettingsView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var showingClearConfirmation = false
    @State private var importExportService = ImportExportService()
    @State private var showingExportSuccess = false
    @State private var showingImportResult = false
    @State private var showingImportError = false
    @State private var exportedItemCount = 0
    @State private var lastImportResult: ImportResult?
    @State private var importErrorMessage = ""

    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue
    @AppStorage("historyRetention") private var retentionDays: Int = 90
    @AppStorage("pasteBehavior") private var pasteBehaviorRaw: String = PasteBehavior.paste.rawValue
    @AppStorage("fetchURLMetadata") private var fetchURLMetadata: Bool = true
    @AppStorage("quickPasteEnabled") private var quickPasteEnabled: Bool = true
    @AppStorage("dismissAfterDragPaste") private var dismissAfterDragPaste: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 1. Launch at login
                VStack(alignment: .leading, spacing: 6) {
                    Text("Startup")
                        .font(.headline)
                    LaunchAtLogin.Toggle("Launch at login")
                        .toggleStyle(.switch)
                }

                Divider()

                // 2. Panel toggle hotkey + Quick paste
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hotkey")
                        .font(.headline)
                    KeyboardShortcuts.Recorder("Panel Toggle Hotkey:", name: .togglePanel)

                    Toggle("Quick paste with \u{2318}1-9 while panel is open", isOn: $quickPasteEnabled)
                        .toggleStyle(.switch)
                    Text("Use \u{2318}N to paste the Nth item, \u{2318}\u{21E7}N to paste as plain text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // 3. Panel position
                HStack(spacing: 16) {
                    Text("Panel Position")
                        .font(.headline)
                    ScreenEdgePicker(selectedEdge: $panelEdgeRaw)
                }

                Divider()

                // 4. History retention
                VStack(alignment: .leading, spacing: 6) {
                    Text("History Retention")
                        .font(.headline)
                    Picker("Keep history for:", selection: $retentionDays) {
                        Text("1 Week").tag(7)
                        Text("1 Month").tag(30)
                        Text("3 Months").tag(90)
                        Text("1 Year").tag(365)
                        Text("Forever").tag(0)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }

                Divider()

                // 5. Paste behavior
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste Behavior")
                        .font(.headline)
                    Picker("When activating an item:", selection: $pasteBehaviorRaw) {
                        ForEach(PasteBehavior.allCases, id: \.rawValue) { behavior in
                            Text(behavior.displayName).tag(behavior.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320)

                    Text("\"Paste\" writes to clipboard and pastes into the active app.\n\"Copy to Clipboard\" only writes to clipboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Dismiss panel after drag-to-paste", isOn: $dismissAfterDragPaste)
                        .toggleStyle(.switch)
                    Text("Automatically closes the panel after dropping an item into another app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // 6. URL Previews
                VStack(alignment: .leading, spacing: 6) {
                    Text("URL Previews")
                        .font(.headline)
                    Toggle("Fetch page title, favicon, and preview image for copied URLs", isOn: $fetchURLMetadata)
                        .toggleStyle(.switch)
                    Text("When disabled, URL cards show only the raw link text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // 7. Data (Export / Import / Clear)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Data")
                            .font(.headline)
                        Spacer()
                        Button("Export...") {
                            performExport()
                        }
                        .disabled(importExportService.isProcessing)
                        Button("Import...") {
                            performImport()
                        }
                        .disabled(importExportService.isProcessing)
                        Button("Clear All History...") {
                            showingClearConfirmation = true
                        }
                        .foregroundStyle(.red)
                        .disabled(importExportService.isProcessing)
                        .alert("Clear All History", isPresented: $showingClearConfirmation) {
                            Button("Clear All", role: .destructive) {
                                appState.clearAllHistory(modelContext: modelContext)
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will permanently delete all clipboard items. This action cannot be undone.")
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

                    Text("Export saves text-based clipboard history to a .pastel file. Images are not included.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .alert("Export Complete", isPresented: $showingExportSuccess) {
                    Button("OK") {}
                } message: {
                    Text("Exported \(exportedItemCount) items to .pastel file.")
                }
                .alert("Import Complete", isPresented: $showingImportResult) {
                    Button("OK") {}
                } message: {
                    if let result = lastImportResult {
                        Text("Imported \(result.importedCount) items, skipped \(result.skippedCount) duplicates. \(result.labelsCreated) new labels created.")
                    }
                }
                .alert("Import Failed", isPresented: $showingImportError) {
                    Button("OK") {}
                } message: {
                    Text(importErrorMessage)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: panelEdgeRaw) {
            appState.panelController.handleEdgeChange()
        }
    }

    // MARK: - Export

    private func performExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pastelExport]
        panel.nameFieldStringValue = "Clipboard History.pastel"
        panel.title = "Export Clipboard History"
        panel.message = "Choose where to save your clipboard history."
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        Task {
            do {
                let data = try importExportService.exportHistory(modelContext: modelContext)
                try data.write(to: url, options: .atomic)
                exportedItemCount = importExportService.lastExportCount
                showingExportSuccess = true
            } catch {
                importErrorMessage = "Export failed: \(error.localizedDescription)"
                showingImportError = true
            }
        }
    }

    // MARK: - Import

    private func performImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pastelExport]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Import Clipboard History"
        panel.message = "Select a .pastel file to import."

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        Task {
            do {
                let data = try Data(contentsOf: url)
                let result = try importExportService.importHistory(from: data, modelContext: modelContext)
                lastImportResult = result
                showingImportResult = true
            } catch {
                importErrorMessage = "Import failed: \(error.localizedDescription)"
                showingImportError = true
            }
        }
    }
}
