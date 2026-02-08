import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts

/// First-launch onboarding view with three sections:
/// 1. Accessibility permission (with live status polling)
/// 2. Panel hotkey setup
/// 3. Quick settings (launch at login, retention, panel edge)
///
/// Shown once on first install via `OnboardingWindowController`.
/// After completion, subsequent launches fall back to `AccessibilityPromptView` if needed.
struct OnboardingView: View {
    var onDismiss: () -> Void = {}
    @Environment(AppState.self) private var appState

    // Accessibility polling
    @State private var accessibilityGranted = AccessibilityService.isGranted
    let pollTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    // Settings bindings (same @AppStorage keys as GeneralSettingsView)
    @AppStorage("panelEdge") private var panelEdgeRaw: String = PanelEdge.right.rawValue
    @AppStorage("historyRetention") private var retentionDays: Int = 90

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Header
                Image("PastelLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 64)

                Text("Welcome to Pastel")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Let's get you set up in under a minute.")
                    .foregroundStyle(.secondary)

                Divider()

                // MARK: - Section 1: Accessibility
                VStack(alignment: .leading, spacing: 12) {
                    Text("Accessibility Permission")
                        .font(.headline)

                    Text("Pastel needs Accessibility permission to paste items into other apps.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(accessibilityGranted ? .green : .red)
                            .frame(width: 10, height: 10)
                        Text(accessibilityGranted ? "Permission granted" : "Permission required")
                            .font(.body)
                    }

                    if accessibilityGranted {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("You're all set!")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Button {
                                AccessibilityService.requestPermission()
                            } label: {
                                Text("Grant Permission")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)

                            Button {
                                AccessibilityService.openAccessibilitySettings()
                            } label: {
                                Text("Open System Settings")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // MARK: - Section 2: Panel Hotkey
                VStack(alignment: .leading, spacing: 12) {
                    Text("Panel Hotkey")
                        .font(.headline)

                    KeyboardShortcuts.Recorder("Toggle panel:", name: .togglePanel)

                    Button("Try It!") {
                        appState.togglePanel()
                    }
                    .buttonStyle(.bordered)

                    Text("Press the hotkey anytime to open your clipboard panel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // MARK: - Section 3: Quick Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Settings")
                        .font(.headline)

                    LaunchAtLogin.Toggle("Launch at login")
                        .toggleStyle(.switch)

                    Picker("Keep history for:", selection: $retentionDays) {
                        Text("1 Week").tag(7)
                        Text("1 Month").tag(30)
                        Text("3 Months").tag(90)
                        Text("1 Year").tag(365)
                        Text("Forever").tag(0)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)

                    HStack {
                        Text("Panel position")
                        ScreenEdgePicker(selectedEdge: $panelEdgeRaw)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // MARK: - Footer
                Button {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    onDismiss()
                } label: {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
        }
        .onReceive(pollTimer) { _ in
            accessibilityGranted = AccessibilityService.isGranted
        }
        .onChange(of: panelEdgeRaw) {
            appState.panelController.handleEdgeChange()
        }
    }
}
