import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts

/// General settings tab rendered as a native grouped `Form`.
///
/// Sections (top to bottom):
/// 1. General — Launch at login, History retention, (Sparkle) Updates
/// 2. Panel — Position, Toggle hotkey, Quick paste
/// 3. Pasting — Behavior, Dismiss after drag-paste, Accessibility warning (conditional)
/// 4. Content & Data — URL previews, Export / Import / Clear
struct GeneralSettingsView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    #if SPARKLE
    @EnvironmentObject private var updaterService: UpdaterService
    #endif

    @State private var showingClearConfirmation = false
    @State private var showingExportSheet = false
    @State private var showingImportSheet = false

    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue
    @AppStorage("historyRetention") private var retentionDays: Int = 90
    @AppStorage("pasteBehavior") private var pasteBehaviorRaw: String = PasteBehavior.copy.rawValue
    @AppStorage("fetchURLMetadata") private var fetchURLMetadata: Bool = true
    @AppStorage("quickPasteEnabled") private var quickPasteEnabled: Bool = true
    @AppStorage("dismissAfterDragPaste") private var dismissAfterDragPaste: Bool = true

    @State private var accessibilityGranted = AccessibilityService.isGranted
    let accessibilityPollTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            generalSection
            panelSection
            pastingSection
            contentAndDataSection
        }
        .formStyle(.grouped)
        .onReceive(accessibilityPollTimer) { _ in
            accessibilityGranted = AccessibilityService.isGranted
        }
        .onReceive(NotificationCenter.default.publisher(for: AccessibilityService.permissionChangedNotification)) { _ in
            accessibilityGranted = AccessibilityService.isGranted
        }
        .onChange(of: panelEdgeRaw) {
            appState.panelController.handleEdgeChange()
        }
        .sheet(isPresented: $showingExportSheet) { ExportSheetView() }
        .sheet(isPresented: $showingImportSheet) { ImportSheetView() }
        .alert("Clear All History", isPresented: $showingClearConfirmation) {
            Button("Clear All", role: .destructive) {
                appState.clearAllHistory(modelContext: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all clipboard items. This action cannot be undone.")
        }
    }

    // MARK: - General

    @ViewBuilder
    private var generalSection: some View {
        #if SPARKLE
        Section {
            generalRows
        } header: {
            Text("General")
        } footer: {
            Text("Labeled and pinned items are kept forever, regardless of retention. Pastel uses Sparkle to deliver updates outside the App Store.")
        }
        #else
        Section {
            generalRows
        } header: {
            Text("General")
        } footer: {
            Text("Labeled and pinned items are kept forever, regardless of retention.")
        }
        #endif
    }

    @ViewBuilder
    private var generalRows: some View {
        LaunchAtLogin.Toggle("Launch at login")

        Picker("Keep history for", selection: $retentionDays) {
            Text("1 Week").tag(7)
            Text("1 Month").tag(30)
            Text("3 Months").tag(90)
            Text("1 Year").tag(365)
            Text("Forever").tag(0)
        }

        #if SPARKLE
        Picker("Update behavior", selection: Binding(
            get: { updaterService.updateMode },
            set: { updaterService.applyUpdateMode($0) }
        )) {
            ForEach(UpdateCheckMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }

        HStack {
            Spacer()
            Button("Check for Updates Now") {
                updaterService.checkForUpdates()
            }
            .disabled(!updaterService.canCheckForUpdates)
        }
        #endif
    }

    // MARK: - Panel

    private var panelSection: some View {
        Section {
            LabeledContent("Panel position") {
                ScreenEdgePicker(selectedEdge: $panelEdgeRaw)
            }

            KeyboardShortcuts.Recorder("Toggle hotkey", name: .togglePanel)

            Toggle("Quick paste with \u{2318}1\u{2013}9", isOn: $quickPasteEnabled)
        } header: {
            Text("Panel")
        } footer: {
            Text("Use \u{2318}N to paste the Nth item, \u{2318}\u{21E7}N to paste as plain text.")
        }
    }

    // MARK: - Pasting

    private var pastingSection: some View {
        Section {
            Picker("When activating an item", selection: $pasteBehaviorRaw) {
                ForEach(PasteBehavior.allCases, id: \.rawValue) { behavior in
                    Text(behavior.displayName).tag(behavior.rawValue)
                }
            }

            Toggle("Dismiss panel after drag-to-paste", isOn: $dismissAfterDragPaste)

            if !accessibilityGranted && pasteBehaviorRaw != PasteBehavior.copy.rawValue {
                accessibilityWarningRow
            }
        } header: {
            Text("Pasting")
        } footer: {
            Text("\u{201C}Paste\u{201D} writes to the clipboard and pastes into the active app. \u{201C}Copy to Clipboard\u{201D} only writes to the clipboard.")
        }
    }

    private var accessibilityWarningRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Accessibility permission is required for direct pasting. Items will be copied to the clipboard until permission is granted.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Grant Permission") {
                    AccessibilityService.requestPermission()
                }
                Button("Open System Settings") {
                    AccessibilityService.openAccessibilitySettings()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Content & Data

    private var contentAndDataSection: some View {
        Section {
            Toggle("Fetch URL previews", isOn: $fetchURLMetadata)

            HStack {
                Text("Clipboard data")
                Spacer()
                Button("Export\u{2026}") { showingExportSheet = true }
                Button("Import\u{2026}") { showingImportSheet = true }
                Button("Clear All\u{2026}") { showingClearConfirmation = true }
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Content & Data")
        } footer: {
            Text("URL previews fetch page title, favicon, and image. Export and Import use Pastel and PastePal formats.")
        }
    }
}
