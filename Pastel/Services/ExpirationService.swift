import Foundation
import OSLog
import SwiftData

/// Auto-expiration service for concealed clipboard items (e.g., from password managers).
///
/// Concealed items are flagged with `isConcealed = true` and `expiresAt` set to 60 seconds
/// after capture. This service schedules their deletion using DispatchQueue timers.
///
/// All operations run on the main thread because SwiftData's ModelContext is main-thread-only
/// in Phase 1. The service also cleans up associated image files on disk.
@MainActor
final class ExpirationService {

    // MARK: - Properties

    private let modelContext: ModelContext
    private var pendingExpirations: [PersistentIdentifier: DispatchWorkItem] = [:]

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "ExpirationService"
    )

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    /// Schedule auto-expiration for a concealed clipboard item.
    ///
    /// Only schedules if the item is actually concealed. The item will be deleted
    /// from SwiftData and its images removed from disk after 60 seconds.
    ///
    /// - Parameter item: The clipboard item to schedule expiration for.
    func scheduleExpiration(for item: ClipboardItem) {
        guard item.isConcealed else { return }

        let itemID = item.persistentModelID
        let imagePath = item.imagePath
        let thumbnailPath = item.thumbnailPath

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.performExpiration(itemID: itemID, imagePath: imagePath, thumbnailPath: thumbnailPath)
            }
        }

        pendingExpirations[itemID] = workItem

        // Schedule deletion 60 seconds from now
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: workItem)
        Self.logger.info("Scheduled expiration for concealed item in 60s")
    }

    /// Expire all overdue concealed items. Call on app launch to clean up items
    /// that expired while the app was not running.
    func expireOverdueItems() {
        // v3: batched (100/batch, offset = retained count) instead of
        // fetching all concealed items at once on the main actor.
        // Concealed counts are normally small; this bounds the worst case
        // without changing semantics (labeled items are kept).
        let now = Date.now
        var expiredCount = 0
        var retainedOffset = 0
        do {
            while true {
                var descriptor = FetchDescriptor<ClipboardItem>(
                    predicate: #Predicate<ClipboardItem> { item in
                        item.isConcealed == true && item.expiresAt != nil
                    }
                )
                descriptor.fetchLimit = 100
                descriptor.fetchOffset = retainedOffset
                let batch = try modelContext.fetch(descriptor)
                if batch.isEmpty { break }
                var expiredInBatch = 0
                var retainedInBatch = 0
                for item in batch {
                    guard item.safeLabels.isEmpty else { retainedInBatch += 1; continue }
                    if let expiresAt = item.expiresAt, expiresAt < now {
                        deleteClipboardItemWithCleanup(item, from: modelContext)
                        expiredInBatch += 1
                    } else {
                        retainedInBatch += 1
                    }
                }
                if expiredInBatch > 0 { try modelContext.save() }
                expiredCount += expiredInBatch
                retainedOffset += retainedInBatch
                if batch.count < 100 { break }
            }
            if expiredCount > 0 {
                Self.logger.info("Expired \(expiredCount) overdue concealed items on launch")
            }
        } catch {
            // Error kind only; localized descriptions can embed item data.
            Self.logger.error("Failed to expire overdue items")
        }
    }

    /// Cancel a pending expiration (e.g., if the item is manually deleted).
    ///
    /// - Parameter itemID: The persistent model ID of the item.
    func cancelExpiration(for itemID: PersistentIdentifier) {
        if let workItem = pendingExpirations.removeValue(forKey: itemID) {
            workItem.cancel()
            Self.logger.debug("Cancelled pending expiration")
        }
    }

    // MARK: - Private Methods

    private func performExpiration(itemID: PersistentIdentifier, imagePath: String?, thumbnailPath: String?) {
        // Remove from pending tracking
        pendingExpirations.removeValue(forKey: itemID)

        // Fetch the item -- it may have been manually deleted already
        guard let item = modelContext.model(for: itemID) as? ClipboardItem else {
            Self.logger.debug("Concealed item already deleted, skipping expiration")
            return
        }

        // The user may have labeled the item during the 60s window — labeled items are kept.
        guard item.safeLabels.isEmpty else {
            Self.logger.info("Concealed item was labeled before expiration, keeping it")
            return
        }

        // Delete with full cleanup (images, URL metadata, labels, model)
        deleteClipboardItemWithCleanup(item, from: modelContext)

        do {
            try modelContext.save()
            Self.logger.info("Expired concealed clipboard item")
        } catch {
            Self.logger.error("Failed to save after expiring concealed item: \(error.localizedDescription)")
            modelContext.rollback()
        }
    }
}
