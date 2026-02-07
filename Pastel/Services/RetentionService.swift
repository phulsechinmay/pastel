import Foundation
import SwiftData
import OSLog

/// Automatically purges clipboard history items older than the user-configured retention period.
///
/// Reads the `historyRetention` UserDefaults key (in days). A value of 0 means "Forever" (no purge).
/// Runs an immediate purge on start, then schedules hourly purges via a repeating timer.
@MainActor
final class RetentionService {

    private let modelContext: ModelContext
    private var timer: Timer?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "RetentionService"
    )

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Start periodic purge: runs immediately, then every hour.
    func startPeriodicPurge() {
        purgeExpiredItems()

        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.purgeExpiredItems()
            }
        }
    }

    /// Purge items older than the configured retention period.
    ///
    /// Reads `historyRetention` from UserDefaults each time so changes
    /// take effect without restarting the app.
    func purgeExpiredItems() {
        let retentionDays = UserDefaults.standard.integer(forKey: "historyRetention")

        // 0 means "Forever" -- no purge
        guard retentionDays > 0 else {
            logger.debug("Retention set to Forever, skipping purge")
            return
        }

        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) else {
            logger.error("Failed to calculate cutoff date for retention: \(retentionDays) days")
            return
        }

        do {
            // Fetch items older than the cutoff
            let descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate<ClipboardItem> { item in
                    item.timestamp < cutoffDate
                }
            )
            let expiredItems = try modelContext.fetch(descriptor)

            guard !expiredItems.isEmpty else {
                logger.debug("No expired items to purge (cutoff: \(cutoffDate))")
                return
            }

            // Delete associated image files from disk
            for item in expiredItems {
                ImageStorageService.shared.deleteImage(
                    imagePath: item.imagePath,
                    thumbnailPath: item.thumbnailPath
                )
                // Clean up URL metadata cached images
                ImageStorageService.shared.deleteImage(
                    imagePath: item.urlFaviconPath,
                    thumbnailPath: item.urlPreviewImagePath
                )
            }

            // Delete expired items from SwiftData
            for item in expiredItems {
                modelContext.delete(item)
            }
            try modelContext.save()

            logger.info("Purged \(expiredItems.count) items older than \(retentionDays) days")
        } catch {
            modelContext.rollback()
            logger.error("Failed to purge expired items: \(error.localizedDescription)")
        }
    }

    /// Stop the periodic purge timer.
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
