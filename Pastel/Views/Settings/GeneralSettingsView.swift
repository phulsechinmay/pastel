import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts

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

    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue
    @AppStorage("historyRetention") private var retentionDays: Int = 90
    @AppStorage("pasteBehavior") private var pasteBehaviorRaw: String = PasteBehavior.paste.rawValue
    @AppStorage("fetchURLMetadata") private var fetchURLMetadata: Bool = true
    @AppStorage("quickPasteEnabled") private var quickPasteEnabled: Bool = true

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
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: panelEdgeRaw) {
            appState.panelController.handleEdgeChange()
        }
    }
}
