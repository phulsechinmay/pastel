import Foundation
import SwiftData

@Model
final class ClipboardItem {
    /// Plain text content, URL string, or file path
    var textContent: String?

    /// HTML representation when available
    var htmlContent: String?

    /// RTF data when available
    var rtfData: Data?

    /// Raw value of ContentType enum (stored as String for SwiftData predicate compatibility)
    var contentType: String

    /// When the clipboard item was captured
    var timestamp: Date

    /// Bundle identifier of the source application
    var sourceAppBundleID: String?

    /// Display name of the source application
    var sourceAppName: String?

    /// Character count of text content
    var characterCount: Int

    /// Byte count of the content
    var byteCount: Int

    /// NSPasteboard changeCount at time of capture
    var changeCount: Int

    /// Filename for stored image (UUID.png, NOT full path)
    var imagePath: String?

    /// Filename for stored thumbnail (UUID_thumb.png)
    var thumbnailPath: String?

    /// Whether the item contains concealed/sensitive content
    var isConcealed: Bool

    /// Optional expiration date for auto-cleanup
    var expiresAt: Date?

    /// SHA256 hash of content for deduplication
    @Attribute(.unique) var contentHash: String

    /// Optional label for organization/filtering
    var label: Label?

    /// Computed property to convert between String storage and ContentType enum
    var type: ContentType {
        get {
            ContentType(rawValue: contentType) ?? .text
        }
        set {
            contentType = newValue.rawValue
        }
    }

    init(
        textContent: String? = nil,
        htmlContent: String? = nil,
        rtfData: Data? = nil,
        contentType: ContentType = .text,
        timestamp: Date = .now,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        characterCount: Int = 0,
        byteCount: Int = 0,
        changeCount: Int = 0,
        imagePath: String? = nil,
        thumbnailPath: String? = nil,
        isConcealed: Bool = false,
        expiresAt: Date? = nil,
        contentHash: String
    ) {
        self.textContent = textContent
        self.htmlContent = htmlContent
        self.rtfData = rtfData
        self.contentType = contentType.rawValue
        self.timestamp = timestamp
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.characterCount = characterCount
        self.byteCount = byteCount
        self.changeCount = changeCount
        self.imagePath = imagePath
        self.thumbnailPath = thumbnailPath
        self.isConcealed = isConcealed
        self.expiresAt = expiresAt
        self.contentHash = contentHash
    }
}
