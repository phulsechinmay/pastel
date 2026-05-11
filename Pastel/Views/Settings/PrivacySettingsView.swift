import SwiftUI
import UniformTypeIdentifiers

/// Privacy settings tab with an ignore list table, native search, and toolbar
/// add (menu) / remove buttons. Apps on the ignore list are excluded from
/// clipboard monitoring.
///
/// Persisted in UserDefaults under three keys:
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
        Group {
            if ignoredApps.isEmpty {
                ContentUnavailableView {
                    SwiftUI.Label("No Ignored Applications", systemImage: "hand.raised.slash")
                } description: {
                    Text("Apps on this list are excluded from clipboard monitoring.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredApps, selection: $selectedApp, sortOrder: $sortOrder) {
                    TableColumn("Name", sortUsing: KeyPathComparator(\IgnoredApp.name)) { app in
                        HStack(spacing: 8) {
                            if let icon = AppIconCache.shared.icon(forBundleID: app.bundleID) {
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
                .onChange(of: sortOrder) { _, newOrder in
                    ignoredApps.sort(using: newOrder)
                }
                .onDeleteCommand {
                    removeSelectedApp()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Choose from Installed Apps…") {
                        showingAppPicker = true
                    }
                    Button("Browse for Application…") {
                        selectAppManually()
                    }
                } label: {
                    SwiftUI.Label("Add Application", systemImage: "plus")
                }
                .help("Add an application to the ignore list")

                Button(action: removeSelectedApp) {
                    SwiftUI.Label("Remove Selected", systemImage: "minus")
                }
                .disabled(selectedApp == nil)
                .help("Remove the selected application")
            }
        }
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
