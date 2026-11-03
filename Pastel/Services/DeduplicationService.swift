import SwiftData
import OSLog

@ModelActor
actor DuplicateScanWorker {
    /// Returns only duplicate IDs; ordinary rows are released after each batch.
    func duplicateGroups() throws -> [[PersistentIdentifier]] {
        var offset = 0
        var previousHash: String?
        var matchingIDs: [PersistentIdentifier] = []
        var groups: [[PersistentIdentifier]] = []
        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate<ClipboardItem> {
                    $0.contentHash != "" && $0.contentType != "image"
                },
                sortBy: [SortDescriptor(\.contentHash), SortDescriptor(\.timestamp)]
            )
            descriptor.fetchLimit = 100
            descriptor.fetchOffset = offset
            let context = ModelContext(modelContainer)
            let batch = try context.fetch(descriptor)
            if batch.isEmpty { break }
            for item in batch {
                if previousHash != item.contentHash {
                    if matchingIDs.count > 1 { groups.append(matchingIDs) }
                    previousHash = item.contentHash
                    matchingIDs = []
                }
                matchingIDs.append(item.persistentModelID)
            }
            offset += batch.count
        }
        if matchingIDs.count > 1 { groups.append(matchingIDs) }
        return groups
    }
}

@MainActor
final class DeduplicationService {
    private var observer: Any?
    private let modelContext: ModelContext
    private let worker: DuplicateScanWorker
    private var debounceTask: Task<Void, Never>?

    private let logger = Logger(
        subsystem: "app.pastel.Pastel",
        category: "Dedup"
    )

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.worker = DuplicateScanWorker(modelContainer: modelContext.container)
    }

    func startMonitoring() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // 3-second delay handles rapid CloudKit batch imports.
                self?.debounceTask?.cancel()
                self?.debounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    await self?.deduplicateItems()
                }
            }
        }
    }

    private func deduplicateItems() async {
        // v3 breadcrumb: group count only, never IDs or hashes.
        logger.info("Dedup: starting pass")
        guard let duplicateGroups = try? await worker.duplicateGroups() else {
            logger.error("Dedup: failed to scan item hashes")
            return
        }

        var mergedCount = 0

        for groupIDs in duplicateGroups {
            if Task.isCancelled { return }
            guard groupIDs.count > 1 else { continue }
            // Determine the "keeper", in preference order:
            // 1. A user-authored snippet. It carries a hand-written title the captured
            //    duplicate does not, and dropping it would destroy real user work.
            // 2. This device's copy.
            // 3. The earliest, when every copy came from elsewhere.
            // Resolve one model at a time. A large CloudKit duplicate group must
            // not fault its entire payload collection into the UI context.
            var keeper: ClipboardItem?
            var keeperPriority = -1
            var mergedLabelIDs = Set<Label>()
            var inheritedTitle: String?
            var inheritedPinDate: Date?
            var hasPin = false
            for id in groupIDs {
                guard let item = modelContext.model(for: id) as? ClipboardItem else { continue }
                let priority = item.isUserCreated ? 2 :
                    (item.originDeviceID == DeviceIdentifier.current ? 1 : 0)
                if priority > keeperPriority {
                    keeper = item
                    keeperPriority = priority
                }
                mergedLabelIDs.formUnion(item.safeLabels)
                if inheritedTitle == nil { inheritedTitle = item.title }
                if item.isPinned {
                    hasPin = true
                    if let pinnedAt = item.pinnedAt {
                        inheritedPinDate = min(inheritedPinDate ?? pinnedAt, pinnedAt)
                    }
                }
            }
            guard let keeper else { continue }

            // Union merge labels from all duplicates onto the keeper
            keeper.safeLabels = Array(mergedLabelIDs)
            keeper.refreshLabelKey()

            // Carry across metadata the keeper lacks, so a merge never silently drops
            // a title or a pin that only existed on the copy being deleted.
            if keeper.title == nil, let inheritedTitle {
                keeper.title = inheritedTitle
            }
            if !keeper.isPinned, hasPin {
                keeper.isPinned = true
                keeper.pinnedAt = inheritedPinDate ?? .now
            }

            logger.info("Dedup: merging \(groupIDs.count - 1) duplicate(s)")

            // Save the label merge first (separate from deletion per research pitfall 2)
            saveWithLogging(modelContext, operation: "dedup-label-merge")

            // Delete non-keeper items in a separate pass.
            //
            // Routed through the shared cleanup so cached URL favicon and preview files
            // are removed with the row; a bare `modelContext.delete` orphans them on disk
            // with nothing left to reference them.
            for batchStart in stride(from: 0, to: groupIDs.count, by: 25) {
                if Task.isCancelled { return }
                for id in groupIDs[batchStart..<min(batchStart + 25, groupIDs.count)] where id != keeper.persistentModelID {
                    if let item = modelContext.model(for: id) as? ClipboardItem {
                        deleteClipboardItemWithCleanup(item, from: modelContext)
                    }
                }
                saveWithLogging(modelContext, operation: "dedup-delete-duplicates")
                await Task.yield()
            }

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
