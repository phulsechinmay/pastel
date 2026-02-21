import CryptoKit
import SwiftData
import OSLog

private let swiftDataLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
    category: "SwiftData"
)

@MainActor
func saveWithLogging(_ modelContext: ModelContext, operation: String) {
    do {
        try modelContext.save()
    } catch {
        swiftDataLogger.error("Save failed during \(operation): \(error.localizedDescription)")
    }
}

// MARK: - Content Hashing

/// Single source of truth for SHA256 content hashing used across clipboard monitoring,
/// import, and image deduplication.
enum ContentHash {

    /// Compute SHA256 hash of text content.
    ///
    /// - Parameter text: The text to hash.
    /// - Returns: Lowercase hex-encoded SHA256 hash string.
    static func hash(text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Compute SHA256 hash of image data (first 4KB for speed).
    ///
    /// Hashing only the first 4096 bytes is sufficient to distinguish
    /// different images without the cost of hashing multi-megabyte data.
    ///
    /// - Parameter imageData: Raw image data.
    /// - Returns: Lowercase hex-encoded SHA256 hash string.
    static func hash(imageData: Data) -> String {
        let prefix = imageData.prefix(4096)
        let digest = SHA256.hash(data: prefix)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Centralized Item Deletion

/// Delete a clipboard item with full cleanup: disk images, URL metadata images,
/// label relationships, and model deletion.
///
/// Ensures consistent behavior across all deletion paths:
/// - Removes clipboard image and thumbnail files from disk
/// - Removes URL metadata cached images (favicon + preview) from disk
/// - Clears many-to-many label relationships (required for CloudKit compatibility)
/// - Deletes the SwiftData model
///
/// Does NOT call save -- callers handle their own save strategy
/// (some batch multiple deletes before saving, some use saveWithLogging).
///
/// - Parameters:
///   - item: The clipboard item to delete.
///   - modelContext: The SwiftData model context to delete from.
@MainActor
func deleteClipboardItemWithCleanup(_ item: ClipboardItem, from modelContext: ModelContext) {
    // Clean up clipboard image and thumbnail from disk
    ImageStorageService.shared.deleteImage(
        imagePath: item.imagePath,
        thumbnailPath: item.thumbnailPath
    )
    // Clean up URL metadata cached images from disk
    ImageStorageService.shared.deleteImage(
        imagePath: item.urlFaviconPath,
        thumbnailPath: item.urlPreviewImagePath
    )
    // Clear many-to-many label relationships (CloudKit compatibility)
    item.safeLabels.removeAll()
    // Delete the model
    modelContext.delete(item)
}
