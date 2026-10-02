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
    private var purgeTask: Task<Void, Never>?

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
        purgeTask?.cancel()
        purgeTask = Task { await purgeExpiredItemsInBatches() }
    }

    private func purgeExpiredItemsInBatches() async {
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

        var offset = 0
        var purged = 0
        var kept = 0
        while !Task.isCancelled {
            do {
                var descriptor = FetchDescriptor<ClipboardItem>(
                    predicate: #Predicate<ClipboardItem> { $0.timestamp < cutoffDate },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                descriptor.fetchLimit = 25
                descriptor.fetchOffset = offset
                let batch = try modelContext.fetch(descriptor)
                if batch.isEmpty { break }
                var retainedInBatch = 0
                var deletedInBatch = 0
                for item in batch {
                    if item.safeLabels.isEmpty && !item.isPinned && !item.isUserCreated {
                        deleteClipboardItemWithCleanup(item, from: modelContext)
                        deletedInBatch += 1
                    } else {
                        retainedInBatch += 1
                    }
                }
                if deletedInBatch > 0 { try modelContext.save() }
                purged += deletedInBatch
                kept += retainedInBatch
                // Deleted rows leave the query; retained rows remain before the
                // cursor and must be skipped on the next bounded fetch.
                offset += retainedInBatch
                await Task.yield()
            } catch {
                modelContext.rollback()
                logger.error("Failed to purge expired items: \(error.localizedDescription)")
                return
            }
        }
        logger.info("Purged \(purged) items older than \(retentionDays) days (kept \(kept) labeled/pinned)")
    }

    /// Stop the periodic purge timer.
    func stop() {
        timer?.invalidate()
        timer = nil
        purgeTask?.cancel()
        purgeTask = nil
    }
}
