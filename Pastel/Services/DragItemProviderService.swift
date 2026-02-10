import Foundation
import UniformTypeIdentifiers

/// Constructs NSItemProvider instances for drag-and-drop from clipboard cards.
///
/// Each content type maps to appropriate UTTypes so receiving applications
/// accept the drop correctly:
/// - `.text`, `.code`, `.color` -> `.plainText` via NSString
/// - `.richText` -> `.rtf` (primary) + `.plainText` (fallback)
/// - `.url` -> `.url` + `.plainText` via NSURL
/// - `.image` -> file URL with inferred UTType from extension
/// - `.file` -> file URL
///
/// This service is intentionally free of SwiftUI and SwiftData imports.
/// It is a pure Foundation/AppKit utility used by the `.onDrag()` modifier
/// in FilteredCardListView.
enum DragItemProviderService {

    /// Create an NSItemProvider appropriate for the given clipboard item's content type.
    ///
    /// - Parameter item: The clipboard item to create a drag provider for.
    /// - Returns: An NSItemProvider populated with the correct UTType representations.
    static func createItemProvider(for item: ClipboardItem) -> NSItemProvider {
        switch item.type {
        case .text, .code, .color:
            // NSString conforms to NSItemProviderWriting, auto-registers .plainText
            return NSItemProvider(object: (item.textContent ?? "") as NSString)

        case .richText:
            let provider = NSItemProvider()
            // Register RTF FIRST so richer representation takes priority
            if let rtfData = item.rtfData {
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.rtf.identifier,
                    visibility: .all
                ) { completion in
                    completion(rtfData, nil)
                    return nil // no progress
                }
            }
            // Always register plain text fallback
            provider.registerObject((item.textContent ?? "") as NSString, visibility: .all)
            return provider

        case .url:
            // NSURL conforms to NSItemProviderWriting, auto-registers .url and .plainText
            if let urlString = item.textContent, let url = URL(string: urlString) {
                return NSItemProvider(object: url as NSURL)
            }
            // Fallback: if URL parsing fails, provide as plain text
            return NSItemProvider(object: (item.textContent ?? "") as NSString)

        case .image:
            guard let imagePath = item.imagePath else {
                return NSItemProvider()
            }
            let fileURL = ImageStorageService.shared.resolveImageURL(imagePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                // Graceful degradation: file was deleted from disk
                return NSItemProvider()
            }
            // NSItemProvider(contentsOf:) reads UTType from file extension
            return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()

        case .file:
            guard let filePath = item.textContent else {
                return NSItemProvider()
            }
            let fileURL = URL(fileURLWithPath: filePath)
            return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
        }
    }
}
