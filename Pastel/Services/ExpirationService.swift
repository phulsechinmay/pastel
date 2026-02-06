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
        let now = Date.now

        do {
            let descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate<ClipboardItem> { item in
                    item.isConcealed == true && item.expiresAt != nil
                }
            )
            let concealedItems = try modelContext.fetch(descriptor)

            var expiredCount = 0
            for item in concealedItems {
                if let expiresAt = item.expiresAt, expiresAt < now {
                    // Delete associated images from disk
                    ImageStorageService.shared.deleteImage(
                        imagePath: item.imagePath,
                        thumbnailPath: item.thumbnailPath
                    )
                    modelContext.delete(item)
                    expiredCount += 1
                }
            }

            if expiredCount > 0 {
                try modelContext.save()
                Self.logger.info("Expired \(expiredCount) overdue concealed items on launch")
            }
        } catch {
            Self.logger.error("Failed to expire overdue items: \(error.localizedDescription)")
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

        // Delete associated images from disk
        ImageStorageService.shared.deleteImage(imagePath: imagePath, thumbnailPath: thumbnailPath)

        // Delete from SwiftData
        modelContext.delete(item)

        do {
            try modelContext.save()
            Self.logger.info("Expired concealed clipboard item")
        } catch {
            Self.logger.error("Failed to save after expiring concealed item: \(error.localizedDescription)")
            modelContext.rollback()
        }
    }
}
