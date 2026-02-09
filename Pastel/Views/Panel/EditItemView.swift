import SwiftUI
import SwiftData
import AppKit

struct EditItemView: View {
    @Bindable var item: ClipboardItem
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]
    @Environment(\.dismiss) private var dismiss

    /// Optional close callback for standalone window presentation.
    /// When nil, falls back to SwiftUI dismiss (sheet context).
    var onDone: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Item")
                .font(.headline)

            // Title field
            TextField("Title (optional)", text: titleBinding)
                .textFieldStyle(.roundedBorder)

            // Label multi-select section
            if !allLabels.isEmpty {
                Text("Labels")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Reuse CenteredFlowLayout from ChipBarView
                CenteredFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(allLabels) { label in
                        let isAssigned = item.labels.contains {
                            $0.persistentModelID == label.persistentModelID
                        }
                        LabelChipView(label: label, isActive: isAssigned)
                            .contentShape(Capsule())
                            .onTapGesture {
                                if isAssigned {
                                    item.labels.removeAll {
                                        $0.persistentModelID == label.persistentModelID
                                    }
                                } else {
                                    item.labels.append(label)
                                }
                            }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { closeSelf() }
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding()
        .frame(width: 280)
        .onExitCommand { closeSelf() }
    }

    // MARK: - Dismiss

    private func closeSelf() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    // MARK: - Title Binding

    /// Converts between optional String and TextField String.
    /// Caps title at 50 characters. Sets to nil when empty/whitespace-only.
    private var titleBinding: Binding<String> {
        Binding(
            get: { item.title ?? "" },
            set: { newValue in
                let capped = String(newValue.prefix(50))
                item.title = capped.trimmingCharacters(in: .whitespaces).isEmpty ? nil : capped
            }
        )
    }

}

// MARK: - Standalone Modal Window

/// Presents EditItemView in a standalone NSPanel that can become key and
/// receive keyboard input, unlike sheets on the non-activating sliding panel.
@MainActor
enum EditItemWindow {
    private static var currentPanel: NSPanel?

    static func show(for item: ClipboardItem, modelContainer: ModelContainer) {
        currentPanel?.close()

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )

        let editView = EditItemView(item: item, onDone: {
            panel.close()
        })
        .environment(\.colorScheme, .dark)
        .modelContainer(modelContainer)

        let hostingView = NSHostingView(rootView: editView)
        panel.contentView = hostingView
        panel.title = "Edit Item"
        panel.level = .floating
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false

        // Use intrinsic size from the hosting view; fall back to a reasonable default
        // since fittingSize can return zero before the view's @Query resolves.
        var size = hostingView.fittingSize
        if size.width < 100 || size.height < 100 {
            size = NSSize(width: 300, height: 250)
        }
        panel.setContentSize(size)
        panel.center()

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Clean up reference when window closes (handles both Done and close button)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { _ in
            currentPanel = nil
        }

        currentPanel = panel
    }
}
