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

    /// Compute SHA256 hash of image data over its full length.
    ///
    /// This hashed only the first 4KB until it was found to collide constantly:
    /// pasteboard TIFF is uncompressed, so the leading bytes are the header plus
    /// part of the *first row of pixels*. Any two screenshots sharing a top edge —
    /// same menu bar, same title bar, same background — hashed identically and the
    /// second was silently discarded as a duplicate.
    ///
    /// Call this with the canonical PNG written to disk rather than raw pasteboard
    /// bytes: it is roughly an order of magnitude smaller than the equivalent TIFF,
    /// so full coverage costs a few milliseconds. See `ImageStorageService.saveImage`.
    ///
    /// - Parameter imageData: Encoded image data.
    /// - Returns: Lowercase hex-encoded SHA256 hash string.
    static func hash(imageData: Data) -> String {
        let digest = SHA256.hash(data: imageData)
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

// MARK: - Label Index (Phase B / quick-36)

extension Label {
    /// Ensure this label has a `stableID`. Generates a UUID if the field is empty
    /// (existing rows created before the `stableID` column was introduced).
    func ensureStableID() -> String {
        if stableID.isEmpty {
            stableID = UUID().uuidString
        }
        return stableID
    }
}

extension ClipboardItem {
    /// Rebuild `labelKey` from the current `safeLabels`. Call this right before
    /// `saveWithLogging` at every label-mutation site so the denormalized membership
    /// string stays in sync with the relationship.
    ///
    /// Format: `"|<stableID1>|<stableID2>|"` when labels are assigned, `"|"`
    /// when indexed with no labels, or `""` when not indexed yet.
    func refreshLabelKey() {
        let labels = safeLabels
        guard !labels.isEmpty else {
            if labelKey != "|" { labelKey = "|" }
            return
        }
        // Sort to keep the encoding stable (avoids spurious CloudKit writes).
        let slugs = labels.map { $0.ensureStableID() }.sorted()
        labelKey = "|" + slugs.joined(separator: "|") + "|"
    }
}

// MARK: - In-Place Content Editing

/// Write `newText` back to `item`, along with the side effects an in-place content
/// edit implies. Idempotent — `applyEditedText` no-ops when the text already matches.
///
/// A free function rather than a view method so every caller that rewrites content —
/// the edit window, its close handler, and text transforms — runs the identical path
/// instead of each remembering to evict caches and refresh URL metadata.
@MainActor
func commitEditedText(_ newText: String, to item: ClipboardItem, in modelContext: ModelContext) {
    // Images and files have no editable text; never let an empty draft blank them.
    guard item.type != .image, item.type != .file else { return }
    guard let supersededHash = item.applyEditedText(newText) else { return }

    saveWithLogging(modelContext, operation: "edit item content")

    // Highlighted output is cached by content hash; the old entry is unreachable now.
    Task { await HighlightCache.shared.evict(supersededHash) }

    // applyEditedText discarded the stale preview — fetch the new URL's metadata.
    // fetchMetadata honours the "fetchURLMetadata" setting itself.
    if item.type == .url, let urlString = item.textContent {
        let itemID = item.persistentModelID
        let ctx = modelContext
        Task { await URLMetadataService.fetchMetadata(for: urlString, itemID: itemID, modelContext: ctx) }
    }
}

extension ClipboardItem {
    /// Replace the item's text content, keeping every derived field consistent.
    ///
    /// Rewrites `contentHash` (dedup correctness) and the size counters, and stamps
    /// `modifiedAt`. Representations that no longer describe the new text are dropped
    /// rather than left stale:
    /// - `htmlContent` / `rtfData` are cleared, downgrading a `.richText` item to
    ///   `.text`. The edit sheet warns before this happens.
    /// - URL metadata (title, favicon, preview) is discarded so it can be re-fetched,
    ///   and the cached favicon/preview files are removed from disk.
    ///
    /// Color classification is re-run in both directions, because a `.color` card
    /// draws itself from `detectedColorHex` and would render the wrong swatch with a
    /// stale value. The code language is deliberately left alone — the edit sheet's
    /// picker is a manual override that shouldn't be second-guessed by re-detection.
    ///
    /// `timestamp` is untouched: editing a clip must not reshuffle the history.
    ///
    /// - Returns: The superseded content hash, so callers can evict caches keyed on
    ///   it, or `nil` when the text was unchanged and nothing was written.
    @discardableResult
    func applyEditedText(_ newText: String) -> String? {
        let original = fullTextContent ?? ""
        guard newText != original else { return nil }
        let supersededHash = contentHash

        setStoredText(newText)
        characterCount = newText.count
        byteCount = Data(newText.utf8).count
        contentHash = ContentHash.hash(text: newText)
        modifiedAt = .now

        // Rich representations describe the text as it was captured, not as it is now.
        if htmlContent != nil || largeHTMLData != nil || rtfData != nil || largeRTFData != nil {
            setStoredHTML(nil)
            setStoredRTF(nil)
            if type == .richText { type = .text }
        }

        if type == .url {
            ImageStorageService.shared.deleteImage(
                imagePath: urlFaviconPath,
                thumbnailPath: urlPreviewImagePath
            )
            urlTitle = nil
            urlFaviconPath = nil
            urlPreviewImagePath = nil
            urlMetadataFetched = nil
        }

        let detectedColor = ColorDetectionService.detectColor(newText)
        detectedColorHex = detectedColor
        if detectedColor != nil, type == .text {
            type = .color
        } else if detectedColor == nil, type == .color {
            type = .text
        }

        return supersededHash
    }
}

/// Split a `labelKey` into its stable-ID tokens (drops the `|` delimiters and the
/// empty leading/trailing segments). `"|a|b|"` -> `["a", "b"]`, `"|"` -> `[]`.
func labelKeyTokens(_ key: String) -> [Substring] {
    key.split(separator: "|")
}

/// Delete a label and rewrite `labelKey` on every clipboard item that referenced
/// it. This explicitly removes the relationship before deleting the label so the
/// denormalized key does not depend on SwiftData delete-rule timing.
///
/// Does NOT call save -- callers handle their own save strategy.
@MainActor
func deleteLabelWithCleanup(_ label: Label, from modelContext: ModelContext) {
    let deletedLabelID = label.persistentModelID
    let affectedItems = label.safeItems
    for item in affectedItems {
        item.safeLabels.removeAll { $0.persistentModelID == deletedLabelID }
        item.refreshLabelKey()
    }
    modelContext.delete(label)
}

/// Maximum stale items repaired during startup. Keep this bounded because reading
/// `safeLabels` may fault the relationship for legacy rows.
private let labelIndexRepairBatchSize = 200

/// Bounded repair that ensures labels have stable IDs and gradually indexes legacy
/// clipboard items. It deliberately does not use a one-shot UserDefaults flag:
/// CloudKit can deliver older rows after a previous launch, and the repair should
/// remain safe to run again.
///
/// Runs synchronously on the main actor, but only scans a small batch of stale
/// items per launch. Rows with no labels are marked as indexed via `labelKey == "|"`
/// so they are not repeatedly faulted on future launches.
@MainActor
func backfillLabelIndex(in modelContext: ModelContext) {
    do {
        var didChange = false

        // Ensure every Label has a stableID. Label counts are expected to stay small.
        let allLabels = try modelContext.fetch(FetchDescriptor<Label>())
        for label in allLabels where label.stableID.isEmpty {
            label.stableID = UUID().uuidString
            didChange = true
        }
        let knownStableIDs = Set(allLabels.map(\.stableID).filter { !$0.isEmpty })

        // 1. Index a bounded batch of not-yet-indexed (legacy) items.
        var emptyKeys = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.labelKey == "" }
        )
        emptyKeys.fetchLimit = labelIndexRepairBatchSize
        for item in try modelContext.fetch(emptyKeys) {
            item.refreshLabelKey()
            didChange = true
        }

        // 2. Self-heal stale keys: reconcile a bounded batch of the most recent
        //    already-indexed items whose labelKey references a stable ID that is no
        //    longer known — the cross-device `stableID` divergence case. Detection is
        //    a cheap attribute scan (no relationship fault); only the genuinely-stale
        //    items fault when refreshLabelKey re-reads safeLabels to rewrite the key.
        //    Recent items are prioritized because they dominate what users filter.
        //    Items with labelKey "|" (indexed, no labels) carry no tokens and are skipped.
        var indexed = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.labelKey != "" && $0.labelKey != "|" },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        indexed.fetchLimit = labelIndexRepairBatchSize
        for item in try modelContext.fetch(indexed) {
            let hasStaleToken = labelKeyTokens(item.labelKey)
                .contains { !knownStableIDs.contains(String($0)) }
            if hasStaleToken {
                item.refreshLabelKey()
                didChange = true
            }
        }

        if didChange {
            try modelContext.save()
        }
    } catch {
        swiftDataLogger.error("Label index repair failed: \(error.localizedDescription)")
    }
}
