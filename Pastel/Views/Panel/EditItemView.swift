import SwiftUI
import SwiftData
import AppKit

/// Mutable box holding the editor's working text.
///
/// Owned by `EditItemWindow`, mirrored from `EditItemView`'s `@State` on every
/// keystroke. The window needs the current text in its `willClose` handler, which
/// runs when the view's own state is no longer reachable.
@MainActor
final class EditDraft {
    var text: String = ""
}

struct EditItemView: View {
    @Bindable var item: ClipboardItem
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Optional close callback for standalone window presentation.
    /// When nil, falls back to SwiftUI dismiss (sheet context).
    var onDone: (() -> Void)?

    /// Whether this is a freshly created snippet draft rather than an existing clip.
    /// Changes the heading; the discard-if-empty path lives in `EditItemWindow`,
    /// which is the only close path both the Done button and the window's close
    /// button pass through.
    var isNewSnippet: Bool = false

    /// Window-owned mirror of `editedText`, so the close handler can flush text typed
    /// inside the debounce window. Nil when presented without a hosting window.
    var draft: EditDraft?

    /// Tracks selected language for the code language picker.
    /// Empty string means "Auto-detect", non-empty is a specific language ID.
    @State private var selectedLanguage: String = ""

    /// Tracks the edited color for the color picker.
    @State private var editColor: Color = .white

    /// Working copy of the item's text. Committed to the model by
    /// `commitContentEdit()` — debounced while typing, and again on close.
    @State private var editedText: String = ""

    /// Guards `commitContentEdit()` until `onAppear` has seeded `editedText`,
    /// so the debounce task can never write an empty string over real content.
    @State private var hasLoadedContent = false

    /// Images and files have no text to edit; everything else does.
    private var isContentEditable: Bool {
        item.type != .image && item.type != .file
    }

    /// Whether the item still carries a rich representation that editing will drop.
    private var willDropFormatting: Bool {
        item.htmlContent != nil || item.rtfData != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNewSnippet ? "New Snippet" : "Edit Item")
                .font(.headline)

            if isContentEditable {
                contentEditor
            }

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
                    // Return has to stay available to the content editor for newlines,
                    // so Done takes Cmd+Return whenever that editor is present.
                    .keyboardShortcut(.return, modifiers: isContentEditable ? .command : [])
            }
        }
        .padding()
        .frame(width: 340)
        .onExitCommand { closeSelf() }
        .onAppear {
            // Seed the content editor's working copy
            editedText = item.textContent ?? ""
            draft?.text = editedText
            hasLoadedContent = true

            // Initialize language picker state
            selectedLanguage = item.detectedLanguage ?? ""

            // Initialize color picker state
            if let hex = item.detectedColorHex {
                editColor = Color(hex: hex)
            }
        }
        .onChange(of: editedText) { _, newValue in
            // Mirror synchronously so the window's close handler always sees the
            // latest keystroke, even when the debounce below hasn't fired yet.
            draft?.text = newValue
        }
        .task(id: editedText) {
            // Debounced commit: rehashing on every keystroke would be wasteful, but
            // committing only on Done would lose the edit if the window is closed
            // via its close button, which doesn't route through closeSelf().
            // Text typed inside this 400ms window is flushed by EditItemWindow.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            commitContentEdit()
        }
    }

    // MARK: - Content Editor

    @ViewBuilder
    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Content")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $editedText)
                .font(.system(size: 12, design: item.type == .code ? .monospaced : .default))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: 120)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            if willDropFormatting {
                // Answering Q6.1: the rich representation is dropped rather than left
                // stale, so say so before the user commits to it.
                SwiftUI.Label(
                    "Editing removes this clip's formatting.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Write the working copy back to the model, if it actually changed.
    /// Idempotent — `applyEditedText` no-ops when the text matches.
    private func commitContentEdit() {
        guard hasLoadedContent, isContentEditable else { return }
        commitEditedText(editedText, to: item, in: modelContext)
    }

    // MARK: - Dismiss

    private func closeSelf() {
        commitContentEdit()
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

    /// Token for the current panel's `willClose` observer. Held so it can be removed:
    /// the block captures the edited `ClipboardItem`, so leaving it registered would
    /// pin a model object (possibly a deleted one) alive for the life of the process
    /// and leave a stale registration against a deallocated window.
    private static var closeObserver: NSObjectProtocol?

    /// Insert a blank authored clip and open the editor on it, removing the
    /// placeholder row again if the user closes without typing anything.
    static func showNewSnippet(appState: AppState, modelContext: ModelContext) {
        let item = appState.createSnippet(in: modelContext)
        show(
            for: item,
            modelContainer: modelContext.container,
            isNewSnippet: true,
            onDiscardEmpty: { appState.discardSnippet(item, in: modelContext) }
        )
    }

    /// - Parameters:
    ///   - isNewSnippet: Presents the window as a snippet draft rather than an edit.
    ///   - onDiscardEmpty: Called on close when a draft still has no content, so the
    ///     caller can remove the placeholder row it inserted. Invoked from the
    ///     `willClose` observer because that is the one path both the Done button and
    ///     the window's close button go through.
    static func show(
        for item: ClipboardItem,
        modelContainer: ModelContainer,
        isNewSnippet: Bool = false,
        onDiscardEmpty: (() -> Void)? = nil
    ) {
        currentPanel?.close()

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )

        // Pre-seeded so a flush is a no-op if the window closes before the view appears.
        let draft = EditDraft()
        draft.text = item.textContent ?? ""

        let editView = EditItemView(
            item: item,
            onDone: { panel.close() },
            isNewSnippet: isNewSnippet,
            draft: draft
        )
        .environment(\.colorScheme, .dark)
        .modelContainer(modelContainer)

        let hostingView = NSHostingView(rootView: editView)
        panel.contentView = hostingView
        panel.title = isNewSnippet ? "New Snippet" : "Edit Item"
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
        if let previous = closeObserver {
            NotificationCenter.default.removeObserver(previous)
            closeObserver = nil
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            // Registered with `queue: .main`, so this always runs on the main thread;
            // asserting it lets the body touch the main-actor model and statics.
            MainActor.assumeIsolated {
                if let token = closeObserver {
                    NotificationCenter.default.removeObserver(token)
                    closeObserver = nil
                }
                currentPanel = nil

                // The close button bypasses the Done handler, and teardown cancels the
                // view's debounced commit — so anything typed in the last 400ms is still
                // only in the draft box. Flush it before deciding whether the item is
                // empty, otherwise a fast type-then-close would delete real content.
                commitEditedText(draft.text, to: item, in: modelContainer.mainContext)

                // A draft closed with nothing in it was never a snippet — drop the
                // placeholder row rather than leave a blank card in the history.
                // Decide *before* tearing anything down, while `item` is still valid.
                guard isNewSnippet, (item.textContent ?? "").isEmpty, item.title == nil else { return }

                // Drop the SwiftUI view before deleting the model it is bound to.
                // `willClose` fires while the hosting view is still installed, and
                // `EditItemView` holds the item via @Bindable — a body re-evaluation
                // scheduled by the delete would read properties off an invalidated
                // model and trap. Releasing the hosting view first cancels that.
                panel?.contentView = nil

                // Let the panel's card list drain its pending @Query update too: it keeps
                // model objects in @State, so the delete has to land on a clean run loop
                // turn rather than mid-update.
                DispatchQueue.main.async {
                    onDiscardEmpty?()
                }
            }
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
