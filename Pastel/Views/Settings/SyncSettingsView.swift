import SwiftUI
import SystemConfiguration

/// iCloud Sync settings tab with toggle, status display, account info, and help popover.
///
/// Shows the sync toggle (bound to @AppStorage "iCloudSyncEnabled"), iCloud account status,
/// sync state with color dots, and a "?" help popover explaining what syncs and what doesn't.
/// Toggle changes trigger a modal restart alert with "Restart Now" / "Later" buttons.
struct SyncSettingsView: View {

    @Environment(SyncMonitor.self) private var syncMonitor: SyncMonitor?
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @State private var showingRestartAlert = false
    @State private var showingHelpPopover = false
    @State private var isPulsing = false
    @State private var lastSyncedText: String?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - Sync Toggle Section

                VStack(alignment: .leading, spacing: 6) {
                    Text("SYNC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Toggle("iCloud Sync", isOn: $iCloudSyncEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: iCloudSyncEnabled) {
                            showingRestartAlert = true
                        }

                    Text("Sync clipboard history across your Macs via iCloud. Text, URLs, code snippets, color values, and labels are synced. Images, files, and passwords are not synced.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // MARK: - iCloud Account Section

                VStack(alignment: .leading, spacing: 6) {
                    Text("ACCOUNT")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    accountStatusView
                }

                Divider()

                // MARK: - Sync Status Section

                if iCloudSyncEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("STATUS")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            Spacer()

                            Button {
                                showingHelpPopover = true
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                showingHelpPopover = hovering
                            }
                            .popover(isPresented: $showingHelpPopover) {
                                helpPopoverContent
                            }
                        }

                        syncStatusView
                    }

                    Divider()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if let date = syncMonitor?.lastSyncDate {
                lastSyncedText = Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
            } else {
                lastSyncedText = nil
            }
        }
        .alert("Restart Required", isPresented: $showingRestartAlert) {
            Button("Restart Now") {
                AppRelaunchService.relaunch()
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Pastel needs to restart to apply the sync change. Your clipboard history will be preserved.")
        }
    }

    // MARK: - Account Status

    @ViewBuilder
    private var accountStatusView: some View {
        if let monitor = syncMonitor {
            if monitor.state == .accountUnavailable {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("iCloud Account: Not Signed In")
                }
            } else if let name = monitor.iCloudAccountName {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(.green)
                    Text("iCloud Account: \(name)")
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("iCloud Account: Signed In & Ready to Sync")
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "icloud")
                    .foregroundStyle(.secondary)
                Text("iCloud Account: Enable sync to check")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sync Status

    @ViewBuilder
    private var syncStatusView: some View {
        if let monitor = syncMonitor {
            switch monitor.state {
            case .synced:
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text(syncedStatusText(monitor: monitor))
                            .foregroundStyle(.secondary)
                    }
                    if let lastSyncedText {
                        Text("Last synced: \(lastSyncedText)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 16)
                    }
                }

            case .syncing(let phase):
                HStack(spacing: 8) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                        .opacity(isPulsing ? 0.3 : 1.0)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true)
                            ) {
                                isPulsing = true
                            }
                        }
                        .onDisappear {
                            isPulsing = false
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(syncingText(for: phase))
                            .foregroundStyle(.secondary)
                        if monitor.lastImportedCount > 0 || monitor.lastExportedCount > 0 {
                            Text(activeSyncCountsText(monitor: monitor))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

            case .error(let message):
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Sync error: \(message)")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .accountUnavailable:
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("iCloud account not available")
                        .foregroundStyle(.red)
                }

            case .disabled:
                HStack(spacing: 8) {
                    Circle()
                        .fill(.gray)
                        .frame(width: 8, height: 8)
                    Text("Sync disabled")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(spacing: 8) {
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
                Text("Sync disabled")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Status Text Helpers

    private func syncedStatusText(monitor: SyncMonitor) -> String {
        let importCount = monitor.lastImportedCount
        let exportCount = monitor.lastExportedCount

        if importCount > 0 || exportCount > 0 {
            var parts: [String] = []
            if importCount > 0 { parts.append("↓\(importCount)") }
            if exportCount > 0 { parts.append("↑\(exportCount)") }
            return "Fully up to date (\(parts.joined(separator: " ")) last sync)"
        }
        return "Fully up to date"
    }

    private func syncingText(for phase: SyncMonitor.SyncPhase) -> String {
        switch phase {
        case .setup:
            return "Setting up..."
        case .importing(isInitial: true):
            return "Initial sync: Importing..."
        case .importing(isInitial: false):
            return "Importing..."
        case .exporting:
            return "Exporting..."
        }
    }

    private func activeSyncCountsText(monitor: SyncMonitor) -> String {
        var parts: [String] = []
        if monitor.lastImportedCount > 0 { parts.append("↓\(monitor.lastImportedCount)") }
        if monitor.lastExportedCount > 0 { parts.append("↑\(monitor.lastExportedCount)") }
        return parts.joined(separator: " ")
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

            VStack(alignment: .leading, spacing: 4) {
                Text("This device")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(deviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 260)
    }

    // MARK: - Device Name

    private var deviceName: String {
        SCDynamicStoreCopyComputerName(nil, nil) as String?
            ?? ProcessInfo.processInfo.hostName
    }
}
