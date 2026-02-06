import SwiftUI

/// Onboarding view that explains why Accessibility permission is needed
/// and provides buttons to grant it.
///
/// Shown as a standalone NSWindow at app launch when permission is not granted.
/// Polls `AXIsProcessTrusted()` every second and auto-dismisses when granted.
struct AccessibilityPromptView: View {
    var onDismiss: () -> Void = {}
    @State private var isChecking = false

    let pollTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "accessibility")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            // Title
            Text("Accessibility Permission Required")
                .font(.title2)
                .fontWeight(.semibold)

            // Explanation
            Text("Pastel needs Accessibility permission to paste clipboard items into other apps. Without it, you can browse your clipboard history but cannot paste directly.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Buttons
            VStack(spacing: 12) {
                Button {
                    AccessibilityService.requestPermission()
                    isChecking = true
                } label: {
                    Text("Grant Permission")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    AccessibilityService.openAccessibilitySettings()
                    isChecking = true
                } label: {
                    Text("Open System Settings")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Skip for Now") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
        .padding(32)
        .frame(width: 360)
        .onReceive(pollTimer) { _ in
            guard isChecking else { return }
            if AccessibilityService.isGranted {
                onDismiss()
            }
        }
        .preferredColorScheme(.dark)
    }
}
