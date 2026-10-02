import Foundation
import SwiftData

@Model
final class ClipboardItem {
    /// Plain text (a bounded preview for large clips), URL string, or file path.
    var textContent: String?

    /// Full UTF-8 payload for large clips. Kept outside the SQLite row by
    /// SwiftData so a card-page fetch need not materialize megabytes per item.
    @Attribute(.externalStorage) var largeTextData: Data?

    static let inlineTextLimit = 64 * 1024

    var fullTextContent: String? {
        if let largeTextData { return String(data: largeTextData, encoding: .utf8) }
        return textContent
    }

    func setStoredText(_ value: String?) {
        if let value, Self.canExternalize(contentType) && value.utf8.count > Self.inlineTextLimit {
            largeTextData = Data(value.utf8)
            textContent = TextWorkBudget.cardPreview(value)
        } else {
            largeTextData = nil
            textContent = value
        }
    }

    /// HTML representation when available
    var htmlContent: String?
    @Attribute(.externalStorage) var largeHTMLData: Data?

    /// RTF data when available
    var rtfData: Data?
    @Attribute(.externalStorage) var largeRTFData: Data?

    var fullHTMLContent: String? {
        if let largeHTMLData { return String(data: largeHTMLData, encoding: .utf8) }
        return htmlContent
    }

    var fullRTFData: Data? { largeRTFData ?? rtfData }

    func setStoredHTML(_ value: String?) {
        if let value, value.utf8.count > Self.inlineTextLimit {
            largeHTMLData = Data(value.utf8)
            htmlContent = nil
        } else {
            largeHTMLData = nil
            htmlContent = value
        }
    }

    func setStoredRTF(_ value: Data?) {
        if let value, value.count > Self.inlineTextLimit {
            largeRTFData = value
            rtfData = nil
        } else {
            largeRTFData = nil
            rtfData = value
        }
    }

    /// Raw value of ContentType enum (stored as String for SwiftData predicate compatibility)
    var contentType: String = ContentType.text.rawValue

    /// When the clipboard item was captured
    var timestamp: Date = Date.now

    /// Bundle identifier of the source application
    var sourceAppBundleID: String?

    /// Display name of the source application
    var sourceAppName: String?

    /// Character count of text content
    var characterCount: Int = 0

    /// Byte count of the content
    var byteCount: Int = 0

    /// NSPasteboard changeCount at time of capture
    var changeCount: Int = 0

    /// Filename for stored image (UUID.png, NOT full path)
    var imagePath: String?

    /// Filename for stored thumbnail (UUID_thumb.png)
    var thumbnailPath: String?

    /// Whether the item contains concealed/sensitive content
    var isConcealed: Bool = false

    /// Optional expiration date for auto-cleanup
    var expiresAt: Date?

    /// SHA256 hash of content for deduplication
    var contentHash: String = ""

    /// Per-device origin tracking for cross-device sync (Phase 19).
    /// Stamped at capture time with DeviceIdentifier.current.
    /// Empty string for items created before v1.5 or synced from other devices before stamping.
    var originDeviceID: String = ""

    /// User-assigned title for easier discovery via search.
    /// Nil means no title was set. Displayed in card header when present.
    var title: String?

    /// Multiple labels for organization/filtering (many-to-many).
    /// New in Phase 11. Optional for CloudKit compatibility (Phase 19).
    @Relationship(deleteRule: .nullify, inverse: \Label.items)
    var labels: [Label]?

    /// Nil-safe access to labels array. Use this everywhere instead of `labels` directly.
    var safeLabels: [Label] {
        get { labels ?? [] }
        set { labels = newValue }
    }

    /// Denormalized membership string used for fast label filtering.
    /// Format: `"|<stableID1>|<stableID2>|"` when one or more labels are assigned,
    /// `"|"` when indexed with no labels, and `""` for rows that have not been
    /// indexed yet. Avoids faulting the `labels` to-many relationship during the
    /// filter pass once indexed. Maintained by `ClipboardItem.refreshLabelKey()`
    /// at every mutation site. Default `""` keeps the field CloudKit-compatible
    /// and lets lightweight migration add it transparently.
    var labelKey: String = ""

    /// Whether the item is pinned to the top of the panel.
    /// Pinned items sort above the time-ordered history and are exempt from
    /// retention purge, the same way labeled items are. Default `false` keeps
    /// the field CloudKit-compatible and lets lightweight migration add it.
    var isPinned: Bool = false

    /// When the item was pinned. Orders pinned items among themselves
    /// (most recently pinned first). Nil whenever `isPinned` is false.
    var pinnedAt: Date?

    /// Whether the user authored this item rather than copying it.
    /// Reserved for manual snippet creation; nothing sets it to `true` yet.
    /// Batched into this migration so the CloudKit schema changes only once.
    var isUserCreated: Bool = false

    /// When the item's content was last edited in place. Nil = never edited.
    /// `timestamp` deliberately keeps the original capture time so editing does
    /// not reshuffle the history.
    var modifiedAt: Date?

    /// Detected programming language (e.g., "swift", "python"). Nil = not code.
    /// Populated by CodeDetectionService in Phase 7.
    var detectedLanguage: String?

    /// Detected color as 6-digit hex (no #). Nil = not a color value.
    /// Populated by ColorDetectionService in Phase 7.
    var detectedColorHex: String?

    /// Page title fetched from URL metadata. Nil = not fetched or not a URL.
    /// Populated by URLMetadataService in Phase 8.
    var urlTitle: String?

    /// Filename of cached favicon image on disk. Nil = not fetched.
    /// Populated by URLMetadataService in Phase 8.
    var urlFaviconPath: String?

    /// Filename of cached og:image preview on disk. Nil = not fetched.
    /// Populated by URLMetadataService in Phase 8.
    var urlPreviewImagePath: String?

    /// URL metadata fetch state: nil = not attempted, false = failed, true = succeeded.
    /// Populated by URLMetadataService in Phase 8.
    var urlMetadataFetched: Bool?

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
        if let textContent, Self.canExternalize(contentType.rawValue),
           textContent.utf8.count > Self.inlineTextLimit {
            self.textContent = TextWorkBudget.cardPreview(textContent)
            self.largeTextData = Data(textContent.utf8)
        } else {
            self.textContent = textContent
            self.largeTextData = nil
        }
        if let htmlContent, htmlContent.utf8.count > Self.inlineTextLimit {
            self.htmlContent = nil
            self.largeHTMLData = Data(htmlContent.utf8)
        } else {
            self.htmlContent = htmlContent
            self.largeHTMLData = nil
        }
        if let rtfData, rtfData.count > Self.inlineTextLimit {
            self.rtfData = nil
            self.largeRTFData = rtfData
        } else {
            self.rtfData = rtfData
            self.largeRTFData = nil
        }
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
        self.title = nil
        self.labels = []
        // Born indexed: no labels at creation, so "|" is the correct "indexed, empty"
        // key. Avoids the relationship-fault fallback in label filtering for freshly
        // captured items (the newest/most-viewed rows) and keeps them out of the
        // backfill batch. See ClipboardItem.refreshLabelKey / backfillLabelIndex.
        self.labelKey = "|"
        self.originDeviceID = DeviceIdentifier.current
    }

    private static func canExternalize(_ rawType: String) -> Bool {
        rawType == ContentType.text.rawValue || rawType == ContentType.richText.rawValue ||
        rawType == ContentType.code.rawValue
    }
}
