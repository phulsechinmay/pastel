import SwiftUI
import SwiftData
import AppKit
import QuickLookUI
@preconcurrency import HighlightSwift

/// Full-image viewer shown in a resizable standalone window.
///
/// The image fits the window and scales with it (resize the window, the image grows
/// or shrinks to match). On top of that fit, the user can zoom via trackpad pinch or
/// the +/− buttons, and pan by dragging once zoomed in. Loaded at full resolution
/// (up to the 4K storage cap) via `ThumbnailLoader` so zoom reveals real detail.
struct ImageViewerView: View {

    let item: ClipboardItem

    /// Close callback for standalone window presentation.
    var onDone: (() -> Void)?

    @State private var image: NSImage?

    /// Committed zoom factor applied on top of the window-fit size.
    @State private var scale: CGFloat = 1.0
    /// Live pinch factor during a magnification gesture (multiplies `scale`).
    @GestureState private var gestureScale: CGFloat = 1.0

    /// Committed pan offset (only meaningful while zoomed in).
    @State private var offset: CGSize = .zero
    /// Live drag translation during a pan gesture (adds to `offset`).
    @GestureState private var gestureOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 8.0

    /// Clamped zoom currently in effect (committed × in-progress pinch).
    private var effectiveScale: CGFloat {
        min(max(scale * gestureScale, minScale), maxScale)
    }

    var body: some View {
        ZStack {
            Color(white: 0.08)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(effectiveScale)
                    .offset(
                        x: offset.width + gestureOffset.width,
                        y: offset.height + gestureOffset.height
                    )
                    .gesture(magnification)
                    .simultaneousGesture(pan)
                    .animation(.interactiveSpring(response: 0.3), value: effectiveScale)
            } else {
                ProgressView()
                    .controlSize(.large)
            }

            VStack {
                Spacer()
                controlBar
                    .padding(.bottom, 16)
            }
        }
        .frame(minWidth: 320, minHeight: 240)
        .onExitCommand { onDone?() }
        .task(id: item.imagePath ?? item.thumbnailPath) {
            guard let path = item.imagePath ?? item.thumbnailPath else { return }
            image = await ThumbnailLoader.shared.load(
                filename: path,
                maxPixelSize: ThumbnailLoader.fullImageMaxPixelSize
            )
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button { zoom(by: 1 / 1.25) } label: {
                Image(systemName: "minus")
            }
            .keyboardShortcut("-", modifiers: [])
            .disabled(effectiveScale <= minScale)

            Text("\(Int((effectiveScale * 100).rounded()))%")
                .font(.system(.callout, design: .rounded).monospacedDigit())
                .frame(width: 52)

            Button { zoom(by: 1.25) } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("=", modifiers: [])
            .disabled(effectiveScale >= maxScale)

            Divider().frame(height: 16)

            Button { resetZoom() } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .help("Reset zoom")
            .disabled(effectiveScale <= minScale && offset == .zero)
        }
        .buttonStyle(.plain)
        .font(PanelStyle.Text.title)
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(PanelStyle.stroke))
    }

    // MARK: - Gestures

    private var magnification: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in state = value }
            .onEnded { value in
                scale = min(max(scale * value, minScale), maxScale)
                if scale <= minScale { offset = .zero }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in
                guard effectiveScale > minScale else { return }
                state = value.translation
            }
            .onEnded { value in
                guard scale > minScale else { return }
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    // MARK: - Zoom actions

    private func zoom(by factor: CGFloat) {
        withAnimation(.easeOut(duration: 0.15)) {
            scale = min(max(scale * factor, minScale), maxScale)
            if scale <= minScale { offset = .zero }
        }
    }

    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1.0
            offset = .zero
        }
    }
}

// MARK: - Standalone Modal Window

/// Presents `ImageViewerView` in a resizable, floating standalone panel.
/// Mirrors `EditItemWindow` so it can become key and receive keyboard input,
/// unlike sheets on the non-activating sliding panel.
@MainActor
enum ImageViewerWindow {
    private static var currentPanel: NSPanel?

    static func show(for item: ClipboardItem) {
        currentPanel?.close()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: true
        )

        let view = ImageViewerView(item: item, onDone: {
            panel.close()
        })

        panel.contentView = NSHostingView(rootView: view)
        panel.title = (item.title?.isEmpty == false) ? item.title! : "View Image"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 360, height: 280)
        panel.center()

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

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

// MARK: - Temporary clipboard preview

/// A read-only reading surface beside the history panel. It is a separate
/// nonactivating panel so opening it never changes the external paste target.
@MainActor
enum ClipPreviewWindow {
    private static var currentPanel: NSPanel?
    private static var currentItemID: PersistentIdentifier?
    private static weak var sourcePanel: NSPanel?
    private static var keyMonitor: Any?
    private static var activate: (() -> Void)?
    private static var navigate: ((Int) -> Void)?
    private static let closeDelegate = ClipPreviewCloseDelegate()

    static var isVisible: Bool { currentPanel?.isVisible == true }
    static func owns(_ window: NSWindow?) -> Bool { window != nil && window === currentPanel }

    static func toggle(for item: ClipboardItem, beside controller: PanelController,
                       actionTitle: String, selectionNote: String?,
                       onActivate: @escaping () -> Void,
                       onNavigate: @escaping (Int) -> Void) {
        if isVisible, currentItemID == item.persistentModelID {
            close()
            return
        }
        show(for: item, beside: controller, actionTitle: actionTitle, selectionNote: selectionNote,
             onActivate: onActivate, onNavigate: onNavigate)
    }

    static func show(for item: ClipboardItem, beside controller: PanelController,
                     actionTitle: String, selectionNote: String?,
                     onActivate: @escaping () -> Void,
                     onNavigate: @escaping (Int) -> Void) {
        guard let anchor = controller.panelForPreview, anchor.isVisible else { return }
        close(restoreFocus: false)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 440),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.title = "Preview"
        panel.level = NSWindow.Level(rawValue: anchor.level.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = closeDelegate
        panel.minSize = NSSize(width: 360, height: 280)
        panel.contentView = NSHostingView(rootView: ClipPreviewView(item: item, actionTitle: actionTitle,
            selectionNote: selectionNote,
            onClose: { close() }, onActivate: onActivate))
        position(panel, beside: anchor)
        sourcePanel = anchor
        currentPanel = panel
        currentItemID = item.persistentModelID
        activate = onActivate
        navigate = onNavigate
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === currentPanel else { return event }
            let textView = event.window?.firstResponder as? NSTextView
            if textView?.isEditable == true { return event }
            switch event.keyCode {
            case 0x31, 0x35: // Space or Escape
                close()
                return nil
            case 0x24, 0x4C: // Return
                activate?()
                return nil
            case 0x7B, 0x7E: // Left or Up
                if textView != nil { return event }
                navigate?(-1)
                return nil
            case 0x7C, 0x7D: // Right or Down
                if textView != nil { return event }
                navigate?(1)
                return nil
            default: return event
            }
        }
        panel.makeKeyAndOrderFront(nil)
    }

    static func update(for item: ClipboardItem, actionTitle: String,
                       selectionNote: String?,
                       onActivate: @escaping () -> Void) {
        guard isVisible, let panel = currentPanel, let anchor = sourcePanel else { return }
        currentItemID = item.persistentModelID
        activate = onActivate
        panel.contentView = NSHostingView(rootView: ClipPreviewView(item: item, actionTitle: actionTitle,
            selectionNote: selectionNote,
            onClose: { close() }, onActivate: onActivate))
        position(panel, beside: anchor)
    }

    static func close(restoreFocus: Bool = true) {
        guard let panel = currentPanel else { return }
        currentPanel = nil
        panel.orderOut(nil)
        panel.close()
        clearState(restoreFocus: restoreFocus)
    }

    fileprivate static func nativeWindowClosed() {
        guard currentPanel != nil else { return }
        currentPanel = nil
        clearState(restoreFocus: true)
    }

    private static func clearState(restoreFocus: Bool) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        activate = nil
        navigate = nil
        currentItemID = nil
        if restoreFocus, let sourcePanel, sourcePanel.isVisible {
            sourcePanel.makeKey()
        }
    }

    private static func position(_ panel: NSPanel, beside anchor: NSPanel) {
        let visible = (anchor.screen ?? NSScreen.main)?.visibleFrame ?? anchor.frame
        let gap: CGFloat = 12
        let size = panel.frame.size
        var origin = NSPoint(x: anchor.frame.midX - size.width / 2,
                             y: anchor.frame.midY - size.height / 2)
        if anchor.frame.width < anchor.frame.height {
            origin.x = anchor.frame.midX > visible.midX
                ? anchor.frame.minX - size.width - gap : anchor.frame.maxX + gap
        } else {
            origin.y = anchor.frame.midY > visible.midY
                ? anchor.frame.minY - size.height - gap : anchor.frame.maxY + gap
        }
        origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
        panel.setFrameOrigin(origin)
    }
}

@MainActor
private final class ClipPreviewCloseDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        ClipPreviewWindow.nativeWindowClosed()
    }
}

private struct ClipPreviewView: View {
    let item: ClipboardItem
    let actionTitle: String
    let selectionNote: String?
    let onClose: () -> Void
    let onActivate: () -> Void
    @State private var image: NSImage?
    @State private var imageLoading = false
    @State private var sourceIcon: NSImage?
    @State private var showFormatted = true
    @State private var highlightedCode: AttributedString?
    @Environment(\.colorScheme) private var colorScheme

    private var title: String {
        if let title = item.title, !title.isEmpty { return title }
        if item.type == .file, let path = item.textContent, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        // The filter calls URLs "Link"; the preview names their content type.
        return item.type == .url ? "URL" : item.type.displayName
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let sourceIcon {
                    Image(nsImage: sourceIcon).resizable().scaledToFit().frame(width: 18, height: 18)
                } else {
                    Image(systemName: iconName).foregroundStyle(.secondary)
                }
                Text(title).font(PanelStyle.Text.title).lineLimit(1)
                if let selectionNote {
                    Text(selectionNote).font(PanelStyle.Text.meta).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close", action: onClose)
                    .help("Close preview (Space or Escape)")
            }
            .padding(14)
            Divider()
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text(item.sourceAppName ?? "Clipboard")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let image {
                    let pixels = image.representations.first
                    if let pixels, pixels.pixelsWide > 0, pixels.pixelsHigh > 0 {
                        Text("\(pixels.pixelsWide) × \(pixels.pixelsHigh)")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("\(actionTitle) ↵", action: onActivate)
            }
            .font(PanelStyle.Text.control)
            .padding(12)
        }
        .fontDesign(.rounded)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand(perform: onClose)
        .task(id: item.imagePath ?? item.urlPreviewImagePath) {
            let path = item.imagePath ?? item.urlPreviewImagePath
            guard let path else { return }
            imageLoading = true
            image = await ThumbnailLoader.shared.load(filename: path,
                maxPixelSize: ThumbnailLoader.fullImageMaxPixelSize)
            imageLoading = false
        }
        .task(id: item.sourceAppBundleID) {
            guard let bundleID = item.sourceAppBundleID else { return }
            sourceIcon = AppIconCache.shared.icon(forBundleID: bundleID)
        }
        .task(id: "\(item.contentHash)-\(colorScheme)") {
            await loadCodeHighlight()
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.type {
        case .image:
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(14)
                    .accessibilityLabel("Clipboard image preview")
            } else if imageLoading {
                ProgressView("Loading image…")
            } else {
                ContentUnavailableView("Image Unavailable", systemImage: "photo")
            }
        case .file:
            let path = item.textContent ?? ""
            if !path.isEmpty && FileManager.default.isReadableFile(atPath: path) {
                QuickLookFilePreview(url: URL(fileURLWithPath: path))
            } else {
                ContentUnavailableView("File Unavailable", systemImage: "doc",
                    description: Text(path.isEmpty ? "The clip has no file path." : path))
            }
        case .color:
            let hex = item.detectedColorHex ?? ""
            VStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color(for: hex))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PanelStyle.strokeStrong))
                    .frame(maxWidth: 300, maxHeight: 210)
                Text("#\(hex.uppercased())").font(PanelStyle.Text.display).textSelection(.enabled)
            }.padding(20)
        case .richText:
            VStack(spacing: 0) {
                if let rtf = item.fullRTFData, rtf.count <= 1_000_000 {
                    Picker("Representation", selection: $showFormatted) {
                        Text("Formatted").tag(true)
                        Text("Plain Text").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .padding(12)
                }
                ScrollView {
                    if showFormatted, let rtf = item.fullRTFData, rtf.count <= 1_000_000,
                       let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
                        Text(AttributedString(attributed)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(item.fullTextContent ?? "").textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(18)
            }
        case .url:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let image { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 180) }
                    if let title = item.urlTitle { Text(title).font(PanelStyle.Text.title) }
                    Text(item.fullTextContent ?? "").textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
        case .code:
            let content = item.fullTextContent ?? ""
            if content.utf8.count > 64 * 1024 {
                ReadOnlyTextPreview(text: content, monospaced: true)
            } else {
                ScrollView {
                    Group {
                        if let highlightedCode { Text(highlightedCode) }
                        else { Text(content) }
                    }
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                }
            }
        case .text:
            ReadOnlyTextPreview(text: item.fullTextContent ?? "", monospaced: false)
        }
    }

    private var iconName: String {
        switch item.type {
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        case .url: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .richText: "textformat"
        case .text: "text.alignleft"
        }
    }

    private func color(for hex: String) -> Color {
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return PanelStyle.surface }
        return Color(nsColor: NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1))
    }

    private func loadCodeHighlight() async {
        highlightedCode = nil
        guard item.type == .code, let fullText = item.fullTextContent,
              !fullText.isEmpty else { return }
        let sample = TextWorkBudget.codeSample(fullText)
        guard sample.utf8.count == fullText.utf8.count else { return }
        let colors: HighlightColors = colorScheme == .dark ? .dark(.atomOne) : .light(.atomOne)
        do {
            let highlighter = Highlight()
            let result: AttributedString
            if let language = item.detectedLanguage, !language.isEmpty {
                result = try await highlighter.attributedText(sample, language: language, colors: colors)
            } else {
                result = try await highlighter.request(sample, mode: .automatic, colors: colors).attributedText
            }
            guard !Task.isCancelled else { return }
            highlightedCode = result
        } catch {
            // Full plain code stays readable when syntax recognition is unavailable.
        }
    }
}

private struct QuickLookFilePreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> NSView {
        guard let view = QLPreviewView(frame: .zero, style: .normal) else {
            return NSTextField(labelWithString: "Quick Look is unavailable for this file.")
        }
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? QLPreviewView)?.previewItem = url as NSURL
    }
}

/// Native text layout keeps full, very large clips selectable without asking
/// SwiftUI to construct and diff a single enormous Text view.
private struct ReadOnlyTextPreview: NSViewRepresentable {
    let text: String
    let monospaced: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = NSTextView(frame: .zero)
        editor.isEditable = false
        editor.isSelectable = true
        editor.drawsBackground = false
        editor.usesFindBar = true
        editor.font = monospaced ? .monospacedSystemFont(ofSize: 13, weight: .regular)
                                 : .systemFont(ofSize: 13)
        editor.textColor = .labelColor
        editor.textContainerInset = NSSize(width: 18, height: 18)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.string = text
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
    }
}
