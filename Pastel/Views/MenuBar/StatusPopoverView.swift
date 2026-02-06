import SwiftUI

struct StatusPopoverView: View {
    @Environment(AppState.self) private var appState

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

            // Item count
            Text("\(appState.itemCount) items captured")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Monitoring toggle (bound through ClipboardMonitor)
            Toggle("Monitoring", isOn: Binding(
                get: { appState.clipboardMonitor?.isMonitoring ?? false },
                set: { _ in appState.clipboardMonitor?.toggleMonitoring() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

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
