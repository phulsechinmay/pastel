import SwiftUI

/// Card content for `.file` clipboard items.
///
/// Displays a document icon alongside the file name (last path component)
/// and the full path when it differs from the filename.
struct FileCardView: View {

    let item: ClipboardItem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if fullPath != filename {
                    Text(fullPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}
