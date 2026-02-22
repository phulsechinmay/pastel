import SwiftData
import AppKit

/// Manages single-item deletion with a soft-delete buffer that enables single-level undo.
///
/// Items are hidden from display immediately on `softDelete()` but remain in SwiftData
/// until committed. The pending deletion is committed when the panel hides, or when
/// a new item is soft-deleted (replacing the previous pending deletion).
///
/// Plays the macOS "move to trash" system sound on each deletion. Image files are
/// cleaned up on a deferred 10-second timer that is cancelled if the user undoes.
///
/// Follows the project's `@MainActor @Observable` service pattern (like ClipboardMonitor, SyncMonitor).
@MainActor @Observable
final class DeletionManager {

    // MARK: - Types

    /// Captures the identity and file paths of a soft-deleted item.
    struct SoftDeleteEntry {
        let itemID: PersistentIdentifier
        let imagePath: String?
        let thumbnailPath: String?
        let urlFaviconPath: String?
        let urlPreviewImagePath: String?
    }

    // MARK: - Properties

    /// The single undo buffer. Only one deletion can be undone at a time.
    private(set) var pendingDeletion: SoftDeleteEntry?

    /// IDs to exclude from display (hidden but not yet permanently deleted).
    /// FilteredCardListView observes this to hide soft-deleted items.
    var softDeletedIDs: Set<PersistentIdentifier> {
        if let entry = pendingDeletion { return [entry.itemID] }
        return []
    }

    /// Cancellable deferred image cleanup work item.
    private var cleanupWorkItem: DispatchWorkItem?

    /// macOS system "move to trash" sound, loaded once and reused.
    private let trashSound: NSSound?

    // MARK: - Init

    init() {
        let soundURL = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/move to trash.aif")
        trashSound = NSSound(contentsOf: soundURL, byReference: true)
    }

    // MARK: - Public Methods

    /// Soft-delete an item: hide it from display, play trash sound, schedule image cleanup.
    ///
    /// If there is already a pending deletion, it is committed first (permanently deleted).
    /// This ensures only one item is in the undo buffer at a time.
    ///
    /// - Parameters:
    ///   - item: The clipboard item to soft-delete.
    ///   - modelContext: The SwiftData model context for committing any previous pending deletion.
    func softDelete(_ item: ClipboardItem, in modelContext: ModelContext) {
        // Commit any previous pending deletion first
        if pendingDeletion != nil {
            commitPendingDeletion(in: modelContext)
        }

        // Store new soft-delete entry
        pendingDeletion = SoftDeleteEntry(
            itemID: item.persistentModelID,
            imagePath: item.imagePath,
            thumbnailPath: item.thumbnailPath,
            urlFaviconPath: item.urlFaviconPath,
            urlPreviewImagePath: item.urlPreviewImagePath
        )

        // Play trash sound
        trashSound?.play()

        // Schedule deferred image cleanup
        scheduleImageCleanup()
    }

    /// Undo the most recent soft-delete: restore the item to visible and cancel image cleanup.
    ///
    /// The restored item's timestamp is set to `.now` so it sorts to position #1 (top of list).
    /// This follows the locked decision that restored items appear at top, not original position.
    ///
    /// - Parameter modelContext: The SwiftData model context for updating the restored item.
    func undo(in modelContext: ModelContext) {
        guard let entry = pendingDeletion else { return }

        // Cancel deferred image cleanup
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil

        // Restore item: update timestamp to sort to top
        if let item = modelContext.model(for: entry.itemID) as? ClipboardItem {
            item.timestamp = .now
            saveWithLogging(modelContext, operation: "undo soft-delete")
        }

        // Clear the undo buffer (makes softDeletedIDs empty, re-showing the item)
        pendingDeletion = nil
    }

    /// Permanently delete the pending soft-deleted item.
    ///
    /// Called when the panel hides or when a new item replaces the undo buffer.
    /// Cancels any pending image cleanup (images are deleted with the item via
    /// `deleteClipboardItemWithCleanup`).
    ///
    /// - Parameter modelContext: The SwiftData model context for deletion.
    func commitPendingDeletion(in modelContext: ModelContext) {
        guard let entry = pendingDeletion else { return }

        // Cancel deferred cleanup (images will be deleted with the item now)
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil

        // Fetch and permanently delete the item
        if let item = modelContext.model(for: entry.itemID) as? ClipboardItem {
            deleteClipboardItemWithCleanup(item, from: modelContext)
            saveWithLogging(modelContext, operation: "commit soft-delete")
        }

        pendingDeletion = nil
    }

    // MARK: - Private Methods

    /// Schedule deferred image cleanup after 10 seconds.
    ///
    /// This cleans up disk images early (before the item is permanently deleted)
    /// so they don't linger if the panel stays open. The work item is cancelled
    /// if the user undoes the deletion or if `commitPendingDeletion` runs first.
    private func scheduleImageCleanup() {
        cleanupWorkItem?.cancel()

        let entry = pendingDeletion
        let workItem = DispatchWorkItem { [weak self] in
            guard self?.pendingDeletion != nil else { return }
            guard let entry else { return }

            // Clean up clipboard image and thumbnail
            ImageStorageService.shared.deleteImage(
                imagePath: entry.imagePath,
                thumbnailPath: entry.thumbnailPath
            )
            // Clean up URL metadata cached images
            ImageStorageService.shared.deleteImage(
                imagePath: entry.urlFaviconPath,
                thumbnailPath: entry.urlPreviewImagePath
            )
        }
        cleanupWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
    }
}
