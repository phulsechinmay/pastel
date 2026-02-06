import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts

/// General settings tab with all 4 user-configurable settings.
///
/// Layout (top to bottom):
/// 1. Launch at login toggle (LaunchAtLogin package)
/// 2. Panel toggle hotkey recorder (KeyboardShortcuts package)
/// 3. Panel position selector (ScreenEdgePicker bound to @AppStorage "panelEdge")
/// 4. History retention dropdown (Picker bound to @AppStorage "historyRetention")
struct GeneralSettingsView: View {

    @Environment(AppState.self) private var appState

    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue
    @AppStorage("historyRetention") private var retentionDays: Int = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 1. Launch at login
            VStack(alignment: .leading, spacing: 6) {
                Text("Startup")
                    .font(.headline)
                LaunchAtLogin.Toggle("Launch at login")
                    .toggleStyle(.switch)
            }

            Divider()

            // 2. Panel toggle hotkey
            VStack(alignment: .leading, spacing: 6) {
                Text("Hotkey")
                    .font(.headline)
                KeyboardShortcuts.Recorder("Panel Toggle Hotkey:", name: .togglePanel)
            }

            Divider()

            // 3. Panel position
            VStack(alignment: .leading, spacing: 8) {
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

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: panelEdgeRaw) {
            appState.panelController.handleEdgeChange()
        }
    }
}
