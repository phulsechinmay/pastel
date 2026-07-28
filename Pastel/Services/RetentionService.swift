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

            // Items are kept regardless of age when the user opted into permanence:
            // by labeling them, by pinning them, or by authoring them by hand.
            let purgeable = expiredItems.filter {
                $0.safeLabels.isEmpty && !$0.isPinned && !$0.isUserCreated
            }

            guard !purgeable.isEmpty else {
                logger.debug("No expired items to purge (cutoff: \(cutoffDate), kept: \(expiredItems.count))")
                return
            }

            // Delete expired items with full cleanup (images, labels, model)
            for item in purgeable {
                deleteClipboardItemWithCleanup(item, from: modelContext)
            }
            try modelContext.save()

            let keptCount = expiredItems.count - purgeable.count
            logger.info("Purged \(purgeable.count) items older than \(retentionDays) days (kept \(keptCount) labeled/pinned)")
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
