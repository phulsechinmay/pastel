import SwiftUI

/// Tab identifiers for the settings window.
private enum SettingsTab: String, CaseIterable {
    case general
    case labels

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .labels: return "tag"
        }
    }

    var displayName: String {
        switch self {
        case .general: return "General"
        case .labels: return "Labels"
        }
    }
}

/// Root settings view with a custom horizontal tab bar.
///
/// Two tabs: General (all 4 settings) and Labels (CRUD label management).
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 420)
    }
}
