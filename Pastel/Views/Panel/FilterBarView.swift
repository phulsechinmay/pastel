import SwiftUI
import AppKit

/// Compact Type / App / Date filter row, revealed by the panel's filter toolbar button.
///
/// Three dropdown chips rather than one chip per value: `ContentType` alone has seven
/// cases and the app list is unbounded, so a flat `ChipBarView`-style row would wrap to
/// several lines in a panel that is already tight on vertical space. Each chip shows its
/// own active state, so the row reads at a glance without being expanded.
struct FilterBarView: View {

    @Binding var filters: SearchFilters

    /// Source apps present in history, most frequent first. Supplied by the parent so
    /// the menu doesn't re-derive it on every render.
    let availableApps: [SourceAppOption]

    var body: some View {
        HStack(spacing: 6) {
            typeMenu
            appMenu
            dateMenu

            if !filters.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        filters.removeAll()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear all filters")
                .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Type

    private var typeMenu: some View {
        filterMenu(
            title: typeTitle,
            isActive: !filters.types.isEmpty,
            systemImage: "square.grid.2x2"
        ) {
            ForEach(ContentType.allCases, id: \.self) { type in
                Button {
                    toggle(type)
                } label: {
                    SwiftUI.Label(
                        checkmarkTitle(type.displayName, isOn: filters.types.contains(type)),
                        systemImage: type.symbolName
                    )
                }
            }
            if !filters.types.isEmpty {
                Divider()
                Button("Clear Types") { filters.types.removeAll() }
            }
        }
    }

    private var typeTitle: String {
        switch filters.types.count {
        case 0: return "Type"
        case 1: return filters.types.first?.displayName ?? "Type"
        default: return "\(filters.types.count) Types"
        }
    }

    private func toggle(_ type: ContentType) {
        if filters.types.contains(type) {
            filters.types.remove(type)
        } else {
            filters.types.insert(type)
        }
    }

    // MARK: - App

    private var appMenu: some View {
        filterMenu(
            title: appTitle,
            isActive: !filters.appBundleIDs.isEmpty,
            systemImage: "app.dashed"
        ) {
            if availableApps.isEmpty {
                Text("No source apps yet")
            } else {
                ForEach(availableApps) { app in
                    Button {
                        toggle(app.bundleID)
                    } label: {
                        Text(checkmarkTitle(app.name, isOn: filters.appBundleIDs.contains(app.bundleID)))
                    }
                }
            }
            if !filters.appBundleIDs.isEmpty {
                Divider()
                Button("Clear Apps") { filters.appBundleIDs.removeAll() }
            }
        }
    }

    private var appTitle: String {
        switch filters.appBundleIDs.count {
        case 0: return "App"
        case 1:
            guard let id = filters.appBundleIDs.first else { return "App" }
            return availableApps.first { $0.bundleID == id }?.name ?? "App"
        default: return "\(filters.appBundleIDs.count) Apps"
        }
    }

    private func toggle(_ bundleID: String) {
        if filters.appBundleIDs.contains(bundleID) {
            filters.appBundleIDs.remove(bundleID)
        } else {
            filters.appBundleIDs.insert(bundleID)
        }
    }

    // MARK: - Date

    private var dateMenu: some View {
        filterMenu(
            title: filters.dateRange?.rawValue ?? "Date",
            isActive: filters.dateRange != nil,
            systemImage: "calendar"
        ) {
            ForEach(DateRangeFilter.allCases) { range in
                Button {
                    // Single-select: tapping the active range clears it.
                    filters.dateRange = (filters.dateRange == range) ? nil : range
                } label: {
                    Text(checkmarkTitle(range.rawValue, isOn: filters.dateRange == range))
                }
            }
            if filters.dateRange != nil {
                Divider()
                Button("Any Time") { filters.dateRange = nil }
            }
        }
    }

    // MARK: - Shared Chrome

    /// A menu styled as a chip, matching the label chips it sits beneath.
    ///
    /// Menu items can't show a real checkmark accessory cross-platform, so selection is
    /// carried by a leading "✓" in the title — the same approach the panel-edge menu in
    /// `PanelContentView` uses.
    private func filterMenu<Content: View>(
        title: String,
        isActive: Bool,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(0.6)
            }
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    isActive
                        ? Color.accentColor.opacity(0.18)
                        : Color.white.opacity(0.07)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isActive ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.10),
                    lineWidth: 1
                )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func checkmarkTitle(_ title: String, isOn: Bool) -> String {
        isOn ? "✓ \(title)" : "   \(title)"
    }
}

// MARK: - Source App Option

/// A source app present in clipboard history, for the app filter menu.
struct SourceAppOption: Identifiable, Equatable, Sendable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

extension SourceAppOption {
    /// Distinct source apps in `items`, most frequent first, capped at `limit`.
    ///
    /// Capped because an unbounded list becomes a 60-entry menu on a machine with a
    /// long history (plan question Q4.8), and the long tail is exactly the apps a user
    /// is least likely to filter by.
    static func derive(from items: [ClipboardItem], limit: Int = 12) -> [SourceAppOption] {
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]

        for item in items {
            guard let bundleID = item.sourceAppBundleID, !bundleID.isEmpty else { continue }
            counts[bundleID, default: 0] += 1
            if names[bundleID] == nil {
                names[bundleID] = item.sourceAppName ?? bundleID
            }
        }

        return counts
            .sorted { lhs, rhs in
                // Frequency first, then name, so the order is stable between renders
                // when two apps are tied.
                lhs.value == rhs.value
                    ? (names[lhs.key] ?? lhs.key) < (names[rhs.key] ?? rhs.key)
                    : lhs.value > rhs.value
            }
            .prefix(limit)
            .map { SourceAppOption(bundleID: $0.key, name: names[$0.key] ?? $0.key) }
    }
}
