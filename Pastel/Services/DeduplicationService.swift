import SwiftData
import OSLog

@MainActor
final class DeduplicationService {
    private var observer: Any?
    private let modelContext: ModelContext
    private var debounceTask: Task<Void, Never>?

    private let logger = Logger(
        subsystem: "app.pastel.Pastel",
        category: "Dedup"
    )

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func startMonitoring() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // Debounce: cancel any pending dedup and schedule a new one
            // 3-second delay handles rapid CloudKit batch imports
            self?.debounceTask?.cancel()
            self?.debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.deduplicateItems()
            }
        }
    }

    private func deduplicateItems() {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        guard let allItems = try? modelContext.fetch(descriptor) else {
            logger.error("Dedup: failed to fetch items")
            return
        }

        // Group by contentHash, filtering out empty hashes
        var hashGroups: [String: [ClipboardItem]] = [:]
        for item in allItems where !item.contentHash.isEmpty {
            hashGroups[item.contentHash, default: []].append(item)
        }

        var mergedCount = 0

        for (hash, group) in hashGroups where group.count > 1 {
            // Determine the "keeper": prefer local device's item
            let keeper: ClipboardItem
            if let localItem = group.first(where: { $0.originDeviceID == DeviceIdentifier.current }) {
                keeper = localItem
            } else {
                // Both from other devices -- keep earliest timestamp
                keeper = group.first!
            }

            // Union merge labels from all duplicates onto the keeper
            var mergedLabelIDs = Set<Label>()
            for item in group {
                for label in item.safeLabels {
                    mergedLabelIDs.insert(label)
                }
            }
            keeper.safeLabels = Array(mergedLabelIDs)

            logger.info("Dedup: merging \(group.count - 1) duplicate(s) of hash \(hash.prefix(8))...")

            // Save the label merge first (separate from deletion per research pitfall 2)
            saveWithLogging(modelContext, operation: "dedup-label-merge")

            // Delete non-keeper items in a separate pass
            for item in group where item !== keeper {
                modelContext.delete(item)
            }
            saveWithLogging(modelContext, operation: "dedup-delete-duplicates")

            mergedCount += 1
        }

        if mergedCount > 0 {
            logger.info("Dedup pass complete: \(mergedCount) group(s) merged")
        }
    }

    func stopMonitoring() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        debounceTask?.cancel()
        debounceTask = nil
    }
}
