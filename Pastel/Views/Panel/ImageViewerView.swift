import SwiftUI
import SwiftData
import AppKit

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
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
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
        .environment(\.colorScheme, .dark)

        panel.contentView = NSHostingView(rootView: view)
        panel.title = (item.title?.isEmpty == false) ? item.title! : "View Image"
        panel.level = .floating
        panel.appearance = NSAppearance(named: .darkAqua)
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
