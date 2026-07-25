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

    /// Tracks selected language for the code language picker.
    /// Empty string means "Auto-detect", non-empty is a specific language ID.
    @State private var selectedLanguage: String = ""

    /// Tracks the edited color for the color picker.
    @State private var editColor: Color = .white

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
                        let isAssigned = item.safeLabels.contains {
                            $0.persistentModelID == label.persistentModelID
                        }
                        LabelChipView(label: label, isActive: isAssigned)
                            .contentShape(Capsule())
                            .onTapGesture {
                                if isAssigned {
                                    item.safeLabels.removeAll {
                                        $0.persistentModelID == label.persistentModelID
                                    }
                                } else {
                                    item.safeLabels.append(label)
                                }
                                item.refreshLabelKey()
                            }
                    }
                }
            }

            // Code edit section (language picker + remove code formatting)
            if item.type == .code {
                CodeEditSection(item: item, selectedLanguage: $selectedLanguage)
            }

            // Color edit section (color picker)
            if item.type == .color {
                ColorEditSection(item: item, editColor: $editColor)
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
        .onAppear {
            // Initialize language picker state
            selectedLanguage = item.detectedLanguage ?? ""

            // Initialize color picker state
            if let hex = item.detectedColorHex {
                editColor = Color(hex: hex)
            }
        }
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

// MARK: - Code Edit Section

/// Language picker and "Remove code formatting" button for code items.
private struct CodeEditSection: View {
    @Bindable var item: ClipboardItem
    @Binding var selectedLanguage: String

    /// Curated list of popular languages with display names and highlight.js IDs.
    private static let languages: [(display: String, id: String)] = [
        ("Auto-detect", ""),
        ("Bash", "bash"),
        ("C", "c"),
        ("C#", "csharp"),
        ("C++", "cpp"),
        ("CSS", "css"),
        ("Dart", "dart"),
        ("Dockerfile", "dockerfile"),
        ("Elixir", "elixir"),
        ("Go", "go"),
        ("GraphQL", "graphql"),
        ("Haskell", "haskell"),
        ("HTML", "html"),
        ("Java", "java"),
        ("JavaScript", "javascript"),
        ("JSON", "json"),
        ("Kotlin", "kotlin"),
        ("Lua", "lua"),
        ("Markdown", "markdown"),
        ("Objective-C", "objectivec"),
        ("Perl", "perl"),
        ("PHP", "php"),
        ("PowerShell", "powershell"),
        ("Python", "python"),
        ("R", "r"),
        ("Ruby", "ruby"),
        ("Rust", "rust"),
        ("Scala", "scala"),
        ("SQL", "sql"),
        ("Swift", "swift"),
        ("TypeScript", "typescript"),
        ("XML", "xml"),
        ("YAML", "yaml"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Code")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Language", selection: $selectedLanguage) {
                ForEach(Self.languages, id: \.id) { lang in
                    Text(lang.display).tag(lang.id)
                }
            }
            .onChange(of: selectedLanguage) { _, newValue in
                let language: String? = newValue.isEmpty ? nil : newValue
                item.detectedLanguage = language

                // Ensure item is marked as code when a language is selected
                if language != nil && item.type != .code {
                    item.contentType = ContentType.code.rawValue
                }

                // Evict stale highlight cache
                Task {
                    await HighlightCache.shared.evict(item.contentHash)
                }
            }

            Button("Remove code formatting", role: .destructive) {
                item.detectedLanguage = nil
                // Revert to richText if RTF data exists, otherwise plain text
                item.contentType = (item.rtfData != nil)
                    ? ContentType.richText.rawValue
                    : ContentType.text.rawValue

                Task {
                    await HighlightCache.shared.evict(item.contentHash)
                }
            }
            .foregroundStyle(.red)
            .buttonStyle(.plain)
            .font(.caption)
        }
    }
}

// MARK: - Color Edit Section

/// Color picker for color items, with hex display.
private struct ColorEditSection: View {
    @Bindable var item: ClipboardItem
    @Binding var editColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                ColorPicker("Color", selection: $editColor, supportsOpacity: false)
                    .labelsHidden()

                Text("#\(item.detectedColorHex ?? "FFFFFF")")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .onChange(of: editColor) { _, newColor in
                // Convert Color to NSColor to extract sRGB components
                guard let nsColor = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                let r = Int(round(nsColor.redComponent * 255))
                let g = Int(round(nsColor.greenComponent * 255))
                let b = Int(round(nsColor.blueComponent * 255))
                item.detectedColorHex = String(format: "%02X%02X%02X", r, g, b)
            }
        }
    }
}

// MARK: - Color Hex Extension

private extension Color {
    /// Creates a SwiftUI Color from a 6-character hex string (no # prefix).
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6,
              let value = UInt64(hex, radix: 16) else {
            self = .white
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
