import SwiftUI
import SystemConfiguration

/// iCloud Sync settings tab rendered as a grouped `Form`.
///
/// Sections: Sync toggle, iCloud account, and (when enabled) Sync status.
/// Status rows use `LabeledContent` + system status SF Symbols rather than
/// custom colored dots so the look matches the rest of Settings.
struct SyncSettingsView: View {

    @Environment(SyncMonitor.self) private var syncMonitor: SyncMonitor?
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @State private var showingRestartAlert = false
    @State private var showingHelpPopover = false
    @State private var lastSyncedText: String?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        Form {
            syncSection
            accountSection

            if iCloudSyncEnabled {
                statusSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if let date = syncMonitor?.lastSyncDate {
                lastSyncedText = Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
            } else {
                lastSyncedText = nil
            }
        }
        .alert("Restart Required", isPresented: $showingRestartAlert) {
            Button("Restart Now") { AppRelaunchService.relaunch() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Pastel needs to restart to apply the sync change. Your clipboard history will be preserved.")
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        Section {
            Toggle("iCloud Sync", isOn: $iCloudSyncEnabled)
                .onChange(of: iCloudSyncEnabled) {
                    showingRestartAlert = true
                }
        } header: {
            Text("Sync")
        } footer: {
            Text("Sync clipboard history across your Macs via iCloud. Text, URLs, code snippets, color values, and labels are synced. Images, files, and passwords are not synced.")
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section("Account") {
            LabeledContent("iCloud Account") {
                accountStatusContent
            }
        }
    }

    @ViewBuilder
    private var accountStatusContent: some View {
        if let monitor = syncMonitor {
            if monitor.state == .accountUnavailable {
                StatusBadge(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .yellow,
                    text: "Not signed in"
                )
            } else if let name = monitor.iCloudAccountName {
                StatusBadge(
                    systemImage: "person.crop.circle.fill",
                    tint: .green,
                    text: name
                )
            } else {
                StatusBadge(
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    text: "Signed in"
                )
            }
        } else {
            StatusBadge(
                systemImage: "icloud",
                tint: .secondary,
                text: "Enable sync to check"
            )
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section {
            LabeledContent("Status") {
                syncStatusContent
            }
            if let lastSyncedText {
                LabeledContent("Last synced") {
                    Text(lastSyncedText)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("This device") {
                Text(deviceName)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Sync Status")
                Spacer()
                Button {
                    showingHelpPopover.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingHelpPopover, arrowEdge: .top) {
                    helpPopoverContent
                }
            }
        }
    }

    @ViewBuilder
    private var syncStatusContent: some View {
        if let monitor = syncMonitor {
            switch monitor.state {
            case .synced:
                StatusBadge(
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    text: syncedStatusText(monitor: monitor)
                )
            case .syncing(let phase):
                StatusBadge(
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .orange,
                    text: syncingText(for: phase),
                    rotating: true
                )
            case .error(let message):
                StatusBadge(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .red,
                    text: "Error: \(message)"
                )
            case .accountUnavailable:
                StatusBadge(
                    systemImage: "exclamationmark.icloud.fill",
                    tint: .red,
                    text: "iCloud account not available"
                )
            case .disabled:
                StatusBadge(
                    systemImage: "pause.circle",
                    tint: .secondary,
                    text: "Disabled"
                )
            }
        } else {
            StatusBadge(
                systemImage: "pause.circle",
                tint: .secondary,
                text: "Disabled"
            )
        }
    }

    // MARK: - Status Text Helpers

    private func syncedStatusText(monitor: SyncMonitor) -> String {
        let importCount = monitor.lastImportedCount
        let exportCount = monitor.lastExportedCount

        if importCount > 0 || exportCount > 0 {
            var parts: [String] = []
            if importCount > 0 { parts.append("\u{2193}\(importCount)") }
            if exportCount > 0 { parts.append("\u{2191}\(exportCount)") }
            return "Up to date (\(parts.joined(separator: " ")))"
        }
        return "Up to date"
    }

    private func syncingText(for phase: SyncMonitor.SyncPhase) -> String {
        switch phase {
        case .setup:
            return "Setting up\u{2026}"
        case .importing(isInitial: true):
            return "Initial sync\u{2026}"
        case .importing(isInitial: false):
            return "Importing\u{2026}"
        case .exporting:
            return "Exporting\u{2026}"
        }
    }

    // MARK: - Help Popover

    private var helpPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iCloud Sync")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("What syncs")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Text, URLs, code snippets, color values, and labels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("What doesn't sync")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Images, files, and passwords (concealed items)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Device Name

    private var deviceName: String {
        SCDynamicStoreCopyComputerName(nil, nil) as String?
            ?? ProcessInfo.processInfo.hostName
    }
}

// MARK: - StatusBadge

/// Compact label: SF Symbol + tinted color + text. Optionally rotates the icon.
private struct StatusBadge: View {
    let systemImage: String
    let tint: Color
    let text: String
    var rotating: Bool = false

    @State private var spin = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .rotationEffect(.degrees(rotating && spin ? 360 : 0))
                .animation(
                    rotating
                        ? .linear(duration: 1.6).repeatForever(autoreverses: false)
                        : .default,
                    value: spin
                )
                .onAppear { if rotating { spin = true } }
                .onDisappear { spin = false }
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}
