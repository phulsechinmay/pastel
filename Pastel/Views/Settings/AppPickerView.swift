import SwiftUI

/// Sheet presenting a searchable list of installed applications.
///
/// Used by PrivacySettingsView to let users pick apps to add
/// to the clipboard ignore list. Already-ignored apps appear
/// dimmed and are non-selectable.
struct AppPickerView: View {

    let apps: [DiscoveredApp]
    let alreadyIgnored: Set<String>
    let onSelect: (DiscoveredApp) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredApps: [DiscoveredApp] {
        if searchText.isEmpty {
            return apps
        }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Application")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search applications...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // App list
            if filteredApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No matching applications")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredApps) { app in
                            let isIgnored = alreadyIgnored.contains(app.bundleID)
                            Button {
                                if !isIgnored {
                                    onSelect(app)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 20, height: 20)
                                    Text(app.name)
                                        .lineLimit(1)
                                    Spacer()
                                    if isIgnored {
                                        Text("Added")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .opacity(isIgnored ? 0.5 : 1.0)
                            .disabled(isIgnored)

                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
    }
}
