import SwiftUI

/// Tab identifiers for the settings window.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case labels
    case privacy
    case history
    case iCloudSync

    var id: Self { self }

    var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .labels: return "tag.fill"
        case .privacy: return "hand.raised.fill"
        case .history: return "clock.arrow.circlepath"
        case .iCloudSync: return "icloud.fill"
        }
    }

    var displayName: String {
        switch self {
        case .general: return "General"
        case .labels: return "Labels"
        case .privacy: return "Privacy"
        case .history: return "History"
        case .iCloudSync: return "iCloud Sync"
        }
    }

    /// Tint color for the sidebar icon backplate (System Settings idiom).
    var tint: Color {
        switch self {
        case .general: return .gray
        case .labels: return .pink
        case .privacy: return .blue
        case .history: return .orange
        case .iCloudSync: return Color(red: 0.36, green: 0.69, blue: 0.95)
        }
    }
}

/// Root settings view using a native macOS `NavigationSplitView` sidebar.
///
/// Sidebar holds the section list (tinted icon backplate + name) with single
/// selection. The detail column hosts the actual settings panes unchanged.
/// Honors `SettingsWindowController.switchTab` notifications so callers can
/// jump to a specific tab while the window is already open.
struct SettingsView: View {

    @State private var selectedTab: SettingsTab
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(initialTab: SettingsTab = .general) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                SidebarRow(tab: tab).tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailContent
                .navigationTitle(selectedTab.displayName)
                .frame(minWidth: 460, idealWidth: 560, minHeight: 480, idealHeight: 600)
        }
        .navigationSplitViewStyle(.balanced)
        .fontDesign(.rounded)
        .onReceive(NotificationCenter.default.publisher(for: SettingsWindowController.switchTab)) { notification in
            if let rawValue = notification.userInfo?["tab"] as? String,
               let tab = SettingsTab(rawValue: rawValue) {
                selectedTab = tab
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsView()
        case .labels:
            LabelSettingsView()
        case .privacy:
            PrivacySettingsView()
        case .history:
            HistoryBrowserView()
        case .iCloudSync:
            SyncSettingsView()
        }
    }
}

/// Sidebar row: tinted rounded backplate behind a white SF Symbol, then label.
/// Mirrors the System Settings sidebar look.
private struct SidebarRow: View {
    let tab: SettingsTab

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tab.iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tab.tint.gradient)
                )
            Text(tab.displayName)
        }
    }
}
