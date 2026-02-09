import SwiftUI

/// Tab identifiers for the settings window.
private enum SettingsTab: String, CaseIterable {
    case general
    case labels
    case history

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .labels: return "tag"
        case .history: return "clock.arrow.circlepath"
        }
    }

    var displayName: String {
        switch self {
        case .general: return "General"
        case .labels: return "Labels"
        case .history: return "History"
        }
    }
}

/// Root settings view with a custom horizontal tab bar.
///
/// Three tabs: General (all settings), Labels (CRUD label management),
/// and History (full history browser with search and grid).
/// The tab bar uses a compact icon-above-text layout with accent highlighting.
struct SettingsView: View {

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            HStack(spacing: 16) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 16))
                            Text(tab.displayName)
                                .font(.system(size: 12))
                        }
                        .frame(width: 80, height: 52)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.white.opacity(0.6))
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTab == tab ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)

            Divider()

            // Content area
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .labels:
                    LabelSettingsView()
                case .history:
                    HistoryBrowserView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(
                minWidth: 500,
                idealWidth: selectedTab == .history ? nil : 500,
                maxWidth: selectedTab == .history ? .infinity : 500,
                minHeight: 480,
                maxHeight: selectedTab == .history ? .infinity : 600
            )
        }
    }
}
