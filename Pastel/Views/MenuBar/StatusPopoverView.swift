import SwiftUI
import SwiftData

struct StatusPopoverView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "clipboard.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Pastel")
                    .font(.headline)
                Spacer()
            }

            // Monitoring toggle (bound through ClipboardMonitor)
            Toggle("Monitoring", isOn: Binding(
                get: { appState.clipboardMonitor?.isMonitoring ?? false },
                set: { _ in appState.clipboardMonitor?.toggleMonitoring() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            // Show History panel button
            Button(action: {
                appState.togglePanel()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "clipboard.fill")
                    Text("Show History")
                    Spacer()
                    Text("\u{21E7}\u{2318}V")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Settings button
            Button(action: {
                if let container = appState.modelContainer {
                    SettingsWindowController.shared.showSettings(
                        modelContainer: container,
                        appState: appState
                    )
                }
            }) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings...")
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Clear All History button (destructive action with confirmation)
            Button(role: .destructive) {
                showingClearConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear All History")
                    Spacer()
                }
                .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "Clear All History",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    appState.clearAllHistory(modelContext: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all clipboard items. This action cannot be undone.")
            }

            Divider()

            // Quit button
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Text("Quit Pastel")
                    Spacer()
                    Text("\u{2318}Q")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
    }
}
