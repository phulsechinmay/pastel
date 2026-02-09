import SwiftUI
import UniformTypeIdentifiers

/// Privacy settings tab with an ignore list table, app picker, and
/// one-time password manager detection prompt.
///
/// Apps on the ignore list are excluded from clipboard monitoring.
/// The list persists in UserDefaults under three keys:
/// - `ignoredAppBundleIDs`: `[String]` array of bundle IDs
/// - `ignoredAppDates`: `[String: Double]` dictionary of bundleID -> epoch
/// - `ignoredAppNames`: `[String: String]` dictionary of bundleID -> display name
struct PrivacySettingsView: View {

    // MARK: - Display Model

    private struct IgnoredApp: Identifiable, Equatable {
        let bundleID: String
        let name: String
        let dateAdded: Date
        var id: String { bundleID }
    }

    // MARK: - State

    @State private var ignoredApps: [IgnoredApp] = []
    @State private var sortOrder = [KeyPathComparator(\IgnoredApp.name)]
    @State private var selectedApp: IgnoredApp.ID?
    @State private var searchText = ""
    @State private var showingAppPicker = false
    @State private var installedApps: [DiscoveredApp] = []
    @State private var showingPasswordManagerPrompt = false

    // MARK: - Computed

    private var filteredApps: [IgnoredApp] {
        if searchText.isEmpty {
            return ignoredApps
        }
        return ignoredApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with title and action buttons
            HStack {
                Text("Ignored Applications")
                    .font(.headline)

                Spacer()

                Button {
                    showingAppPicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Add application from list")

                Button {
                    selectAppManually()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Browse for application")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter ignored apps...", text: $searchText)
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

            // Table or empty state
            if ignoredApps.isEmpty && searchText.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "hand.raised.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No ignored applications")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Apps on this list will be excluded from clipboard monitoring.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredApps, selection: $selectedApp, sortOrder: $sortOrder) {
                    TableColumn("Name", sortUsing: KeyPathComparator(\IgnoredApp.name)) { app in
                        HStack(spacing: 8) {
                            if let icon = NSWorkspace.shared.appIcon(forBundleIdentifier: app.bundleID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "app")
                                    .frame(width: 20, height: 20)
                                    .foregroundStyle(.secondary)
                            }
                            Text(app.name)
                                .lineLimit(1)
                        }
                    }

                    TableColumn("Date Added", sortUsing: KeyPathComparator(\IgnoredApp.dateAdded)) { app in
                        Text(app.dateAdded, style: .date)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 100, ideal: 120)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: sortOrder) { _, newOrder in
                    ignoredApps.sort(using: newOrder)
                }
                .onDeleteCommand {
                    removeSelectedApp()
                }
            }

            // Hint text
            if !ignoredApps.isEmpty {
                Text("Select an app and press Delete to remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(
                apps: installedApps,
                alreadyIgnored: Set(ignoredApps.map(\.bundleID)),
                onSelect: addApp
            )
        }
        .alert(
            "Add installed password managers to the ignore list?",
            isPresented: $showingPasswordManagerPrompt
        ) {
            Button("Yes") {
                let managers = AppDiscoveryService.detectInstalledPasswordManagers(from: installedApps)
                for manager in managers {
                    addApp(manager)
                }
                UserDefaults.standard.set(true, forKey: "hasShownPasswordManagerPrompt")
            }
            Button("No", role: .cancel) {
                UserDefaults.standard.set(true, forKey: "hasShownPasswordManagerPrompt")
            }
        }
        .onAppear {
            loadFromUserDefaults()
            installedApps = AppDiscoveryService.discoverInstalledApps()
            if !UserDefaults.standard.bool(forKey: "hasShownPasswordManagerPrompt") {
                showingPasswordManagerPrompt = true
            }
        }
    }

    // MARK: - Add / Remove

    private func addApp(_ app: DiscoveredApp) {
        guard !ignoredApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        let entry = IgnoredApp(bundleID: app.bundleID, name: app.name, dateAdded: Date())
        ignoredApps.append(entry)
        ignoredApps.sort(using: sortOrder)
        saveToUserDefaults()
    }

    private func removeSelectedApp() {
        guard let selected = selectedApp else { return }
        ignoredApps.removeAll { $0.bundleID == selected }
        selectedApp = nil
        saveToUserDefaults()
    }

    // MARK: - NSOpenPanel

    private func selectAppManually() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.message = "Select an application to ignore"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else { return }

            let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent

            let discovered = DiscoveredApp(bundleID: bundleID, name: name, url: url)
            addApp(discovered)
        }
    }

    // MARK: - Persistence

    private func saveToUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(ignoredApps.map(\.bundleID), forKey: "ignoredAppBundleIDs")

        let dates = Dictionary(uniqueKeysWithValues: ignoredApps.map {
            ($0.bundleID, $0.dateAdded.timeIntervalSince1970)
        })
        defaults.set(dates, forKey: "ignoredAppDates")

        let names = Dictionary(uniqueKeysWithValues: ignoredApps.map {
            ($0.bundleID, $0.name)
        })
        defaults.set(names, forKey: "ignoredAppNames")
    }

    private func loadFromUserDefaults() {
        let defaults = UserDefaults.standard
        let bundleIDs = defaults.stringArray(forKey: "ignoredAppBundleIDs") ?? []
        let dates = defaults.dictionary(forKey: "ignoredAppDates") as? [String: Double] ?? [:]
        let names = defaults.dictionary(forKey: "ignoredAppNames") as? [String: String] ?? [:]

        ignoredApps = bundleIDs.compactMap { bundleID in
            let name = names[bundleID] ?? bundleID
            let epoch = dates[bundleID] ?? Date().timeIntervalSince1970
            return IgnoredApp(bundleID: bundleID, name: name, dateAdded: Date(timeIntervalSince1970: epoch))
        }
        ignoredApps.sort(using: sortOrder)
    }
}
