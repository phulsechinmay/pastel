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

/// Split a `labelKey` into its stable-ID tokens (drops the `|` delimiters and the
/// empty leading/trailing segments). `"|a|b|"` -> `["a", "b"]`, `"|"` -> `[]`.
func labelKeyTokens(_ key: String) -> [Substring] {
    key.split(separator: "|")
}

/// Fast label membership check backed by `ClipboardItem.labelKey`.
///
/// Correctness-first: the denormalized `labelKey` is treated as a positive cache,
/// never as an authoritative negative unless it is provably fresh. Concretely:
///
/// 1. Positive fast path — `labelKey` directly contains a selected label's stable
///    ID: match, no relationship fault.
/// 2. Trustworthy negative — no match AND `labelKey` is non-empty AND every token
///    it carries maps to a currently-known stable ID AND every selected label is
///    itself indexed: the item genuinely lacks the label, return false with NO
///    relationship fault. This is the common case, so the optimization holds.
/// 3. Otherwise — `labelKey` is empty (not indexed), carries an unknown/stale token
///    (e.g. cross-device `stableID` divergence), or a selected label has no stable
///    ID yet: fall back to the authoritative relationship scan. Only these few
///    items pay the fault, and `backfillLabelIndex` heals their stored key later.
///
/// `knownStableIDs` is the set of all current `Label.stableID` values, computed once
/// per filter pass by the caller (not per item). If selected label IDs cannot be
/// resolved through `allLabels`, this fails closed by returning `false`.
func itemMatchesSelectedLabels(
    _ item: ClipboardItem,
    selectedLabelIDs: Set<PersistentIdentifier>,
    allLabels: [Label],
    knownStableIDs: Set<String>
) -> Bool {
    guard !selectedLabelIDs.isEmpty else { return true }

    let selectedLabels = allLabels.filter {
        selectedLabelIDs.contains($0.persistentModelID)
    }
    guard !selectedLabels.isEmpty else { return false }

    let key = item.labelKey

    // 1. Positive fast path.
    let stableNeedles = selectedLabels
        .map(\.stableID)
        .filter { !$0.isEmpty }
        .map { "|\($0)|" }
    if !key.isEmpty,
       stableNeedles.contains(where: { key.contains($0) }) {
        return true
    }

    // 2. Trustworthy negative — no relationship fault.
    let selectedLabelsAllIndexed = !selectedLabels.contains { $0.stableID.isEmpty }
    let keyTokensAllKnown = !key.isEmpty
        && labelKeyTokens(key).allSatisfy { knownStableIDs.contains(String($0)) }
    if selectedLabelsAllIndexed && keyTokensAllKnown {
        return false
    }

    // 3. Authoritative fallback for empty/stale keys.
    return item.safeLabels.contains { label in
        selectedLabelIDs.contains(label.persistentModelID)
    }
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
