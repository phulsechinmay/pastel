import SwiftUI
import AppKit

/// Card content for `.file` clipboard items.
///
/// The compact strip shows a system file icon, filename, and parent folder.
/// Other surfaces retain the path-based card treatment.
struct FileCardView: View {

    let item: ClipboardItem
    var isCompactStrip = false
    @State private var fileIcon: NSImage?

    var body: some View {
        Group {
            if isCompactStrip {
                HStack(spacing: 10) {
                    Group {
                        if let fileIcon {
                            Image(nsImage: fileIcon).resizable().scaledToFit()
                        } else {
                            Image(systemName: "doc").resizable().scaledToFit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 54, height: 68)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(filename)
                            .font(PanelStyle.Text.body.weight(.semibold))
                            .lineLimit(2)
                        Text(parentFolder)
                            .font(PanelStyle.Text.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(fullPath)
                .task(id: fullPath) {
                    fileIcon = fullPath.isEmpty ? nil : NSWorkspace.shared.icon(forFile: fullPath)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "doc")
                        .font(PanelStyle.Icon.content)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(filename)
                            .font(PanelStyle.Text.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if fullPath != filename {
                            Text(fullPath)
                                .font(PanelStyle.Text.meta)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Private Helpers

    private var fullPath: String {
        item.textContent ?? ""
    }

    private var filename: String {
        let path = fullPath
        guard !path.isEmpty else { return "" }
        return (path as NSString).lastPathComponent
    }

    private var parentFolder: String {
        let folder = (fullPath as NSString).deletingLastPathComponent
        return (folder as NSString).lastPathComponent
    }
}
