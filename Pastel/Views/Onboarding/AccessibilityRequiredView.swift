import SwiftUI

/// Contextual permission prompt shown when the user attempts to paste without accessibility.
///
/// Shown as a standalone NSWindow. Polls `AccessibilityService.isGranted` every second
/// and auto-dismisses when granted. The item has already been copied to the clipboard
/// before this view appears, so the user's action is never lost.
struct AccessibilityRequiredView: View {
    var onDismiss: () -> Void = {}
    @State private var isChecking = false

    let pollTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "accessibility")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Accessibility Permission Needed")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Pastel needs Accessibility permission to paste items directly into apps.\n\nThe item has been copied to your clipboard \u{2014} you can paste it manually with \u{2318}V.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

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

                Button("OK") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 380)
        .fontDesign(.rounded)
        .onReceive(pollTimer) { _ in
            guard isChecking else { return }
            if AccessibilityService.isGranted {
                onDismiss()
            }
        }
        .preferredColorScheme(.dark)
    }
}
