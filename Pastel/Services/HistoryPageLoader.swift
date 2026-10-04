import Foundation
import OSLog
import SwiftData

/// Cursor positions refer to rows examined, not rows shown. A sparse label can
/// therefore be found arbitrarily far back without retaining skipped records.
struct HistoryPageCursor: Sendable {
    var pinnedOffset = 0
    var ordinaryOffset = 0
    var pinnedExhausted = false
    var ordinaryExhausted = false
    var searchOffset = 0
    var searchExhausted = false
    var indexMode: Bool?
    var browseOffset = 0
    var browseExhausted = false
    var browseMode: Bool?

    var isExhausted: Bool {
        if indexMode == true { return searchExhausted }
        if browseMode == true { return browseExhausted }
        return pinnedExhausted && ordinaryExhausted
    }
}

struct HistoryIDPage: Sendable {
    let ids: [PersistentIdentifier]
    let cursor: HistoryPageCursor
}

/// All scans run in an actor-owned context. Only one page of IDs crosses back to
/// the UI, where the corresponding card models are resolved on demand.
@ModelActor
actor HistoryPageWorker {
    private let scanBatchSize = 100
    private let logger = Logger(subsystem: "app.pastel.Pastel", category: "HistoryPage")

    func recentSourceApps() throws -> [SourceAppOption] {
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 2_000
        descriptor.propertiesToFetch = [\.sourceAppBundleID, \.sourceAppName]
        let context = ModelContext(modelContainer)
        return SourceAppOption.derive(from: try context.fetch(descriptor))
    }

    func nextIDs(
        cursor initialCursor: HistoryPageCursor,
        searchText: String,
        labelPlan: LabelMatchPlan?,
        filters: SearchFilters,
        softDeletedIDs: Set<PersistentIdentifier>,
        searchIndex: ClipboardSearchIndex?,
        pinsFirst: Bool,
        pageSize: Int
    ) async throws -> HistoryIDPage {
        let started = ContinuousClock.now
        var cursor = initialCursor
        var ids: [PersistentIdentifier] = []
        defer {
            let elapsed = started.duration(to: .now)
            let milliseconds = elapsed.components.seconds * 1000 +
                elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.debug("Loaded \(ids.count) history IDs in \(milliseconds) ms; query length \(searchText.count)")
        }
        let localDeviceID = DeviceIdentifier.current
        let cutoff = filters.dateRange?.cutoff()
        // Until FTS is complete, the preview column cannot answer a deep-text
        // query. Scan the full payload off the UI actor for correctness.
        var needsFullTextScan = !searchText.isEmpty && searchText.unicodeScalars.count < 3

        func accepts(_ item: ClipboardItem) -> Bool {
            let id = item.persistentModelID
            if softDeletedIDs.contains(id) || item.isConcealed { return false }
            let isLocal = item.originDeviceID == localDeviceID || item.originDeviceID.isEmpty
            if !isLocal && (item.type == .image || item.type == .file) { return false }
            if !filters.matches(item, cutoff: cutoff) { return false }
            if let labelPlan, !labelPlan.matches(item) { return false }
            if needsFullTextScan {
                // Preview and metadata are cheap. Fault an external large-text
                // payload only when these cannot already satisfy the query.
                let found = item.textContent?.localizedStandardContains(searchText) == true ||
                    item.sourceAppName?.localizedStandardContains(searchText) == true ||
                    item.title?.localizedStandardContains(searchText) == true ||
                    ((item.byteCount > ClipboardItem.inlineTextLimit ||
                      item.characterCount > ClipboardItem.inlineTextLimit) &&
                     item.fullTextContent?.localizedStandardContains(searchText) == true)
                if !found { return false }
            }
            return true
        }

        if searchText.isEmpty, let searchIndex, cursor.browseMode != false,
           labelPlan == nil || labelPlan?.indexedStableIDs != nil {
            let first = try await searchIndex.browsingIDs(
                offset: cursor.browseOffset, limit: scanBatchSize, pinsFirst: pinsFirst,
                selectedLabelStableIDs: labelPlan?.indexedStableIDs,
                filters: filters, localDeviceID: localDeviceID
            )
            if cursor.browseMode == nil { cursor.browseMode = first != nil }
            if let first {
                var batchIDs = first
                let pageContext = ModelContext(modelContainer)
                while ids.count < pageSize && !cursor.browseExhausted {
                    try Task.checkCancellation()
                    var examined = 0
                    for id in batchIDs {
                        try Task.checkCancellation()
                        examined += 1
                        if softDeletedIDs.contains(id) { continue }
                        guard let item = pageContext.model(for: id) as? ClipboardItem,
                              accepts(item) else { continue }
                        ids.append(id)
                        if ids.count == pageSize { break }
                    }
                    cursor.browseOffset += examined
                    if examined == batchIDs.count && batchIDs.count < scanBatchSize {
                        cursor.browseExhausted = true
                    }
                    if ids.count == pageSize || cursor.browseExhausted { break }
                    guard let next = try await searchIndex.browsingIDs(
                        offset: cursor.browseOffset, limit: scanBatchSize, pinsFirst: pinsFirst,
                        selectedLabelStableIDs: labelPlan?.indexedStableIDs,
                        filters: filters, localDeviceID: localDeviceID
                    ) else { break }
                    batchIDs = next
                }
                return HistoryIDPage(ids: ids, cursor: cursor)
            }
        }

        if !searchText.isEmpty, let searchIndex, cursor.indexMode != false {
            let first = try await searchIndex.matchingIDs(
                searchText, offset: cursor.searchOffset, limit: scanBatchSize, pinsFirst: pinsFirst
            )
            if cursor.indexMode == nil { cursor.indexMode = first != nil }
            if let first {
                var batchIDs = first
                let pageContext = ModelContext(modelContainer)
                while ids.count < pageSize && !cursor.searchExhausted {
                    try Task.checkCancellation()
                    var examined = 0
                    for id in batchIDs {
                        try Task.checkCancellation()
                        examined += 1
                        if softDeletedIDs.contains(id) { continue }
                        guard let item = pageContext.model(for: id) as? ClipboardItem,
                              accepts(item) else { continue }
                        ids.append(id)
                        if ids.count == pageSize { break }
                    }
                    cursor.searchOffset += examined
                    if examined == batchIDs.count && batchIDs.count < scanBatchSize {
                        cursor.searchExhausted = true
                    }
                    if ids.count == pageSize || cursor.searchExhausted { break }
                    guard let next = try await searchIndex.matchingIDs(
                        searchText, offset: cursor.searchOffset, limit: scanBatchSize, pinsFirst: pinsFirst
                    ) else { break }
                    batchIDs = next
                }
                return HistoryIDPage(ids: ids, cursor: cursor)
            }
        }

        if !searchText.isEmpty { needsFullTextScan = true }
        // Settings history is chronological, including pinned rows. It has one
        // fallback stream, unlike the panel's pinned-then-ordinary ordering.
        if !pinsFirst { cursor.pinnedExhausted = true }

        while ids.count < pageSize && !cursor.isExhausted {
            try Task.checkCancellation()
            let pinned = !cursor.pinnedExhausted
            let offset = pinned ? cursor.pinnedOffset : cursor.ordinaryOffset
            let predicate: Predicate<ClipboardItem>
            if !pinsFirst {
                predicate = #Predicate<ClipboardItem> { !$0.isConcealed }
            } else {
                predicate = #Predicate<ClipboardItem> { $0.isPinned == pinned && !$0.isConcealed }
            }
            var descriptor = FetchDescriptor<ClipboardItem>(predicate: predicate)
            descriptor.sortBy = pinned
                ? [SortDescriptor(\.pinnedAt, order: .reverse), SortDescriptor(\.timestamp, order: .reverse)]
                : [SortDescriptor(\.timestamp, order: .reverse)]
            descriptor.fetchLimit = scanBatchSize
            descriptor.fetchOffset = offset
            let batchContext = ModelContext(modelContainer)
            let batch = try batchContext.fetch(descriptor)
            if pinned { cursor.pinnedOffset += batch.count } else { cursor.ordinaryOffset += batch.count }
            if batch.count < scanBatchSize {
                if pinned { cursor.pinnedExhausted = true } else { cursor.ordinaryExhausted = true }
            }
            var examined = 0
            for item in batch {
                try Task.checkCancellation()
                examined += 1
                if accepts(item) { ids.append(item.persistentModelID) }
                if ids.count == pageSize { break }
            }
            let unread = batch.count - examined
            if unread > 0 {
                if pinned {
                    cursor.pinnedOffset -= unread
                    cursor.pinnedExhausted = false
                } else {
                    cursor.ordinaryOffset -= unread
                    cursor.ordinaryExhausted = false
                }
            }
        }
        return HistoryIDPage(ids: ids, cursor: cursor)
    }
}

@MainActor
enum HistoryPageLoader {
    nonisolated static let pageSize = 50

    static func nextPage(
        in context: ModelContext,
        cursor: inout HistoryPageCursor,
        searchText: String,
        selectedLabelIDs: Set<PersistentIdentifier>,
        allLabels: [Label],
        filters: SearchFilters = SearchFilters(),
        softDeletedIDs: Set<PersistentIdentifier> = [],
        searchIndex: ClipboardSearchIndex? = nil,
        worker: HistoryPageWorker? = nil,
        pinsFirst: Bool = true,
        pageSize: Int = pageSize
    ) async throws -> [ClipboardItem] {
        let worker = worker ?? HistoryPageWorker(modelContainer: context.container)
        let labelPlan = selectedLabelIDs.isEmpty
            ? nil : LabelMatchPlan(selectedLabelIDs: selectedLabelIDs, allLabels: allLabels)
        let page = try await worker.nextIDs(
            cursor: cursor, searchText: searchText, labelPlan: labelPlan,
            filters: filters, softDeletedIDs: softDeletedIDs, searchIndex: searchIndex,
            pinsFirst: pinsFirst, pageSize: pageSize
        )
        cursor = page.cursor
        var items: [ClipboardItem] = []
        items.reserveCapacity(page.ids.count)
        for (index, id) in page.ids.enumerated() {
            try Task.checkCancellation()
            if let item = context.model(for: id) as? ClipboardItem { items.append(item) }
            // Model resolution can fault SQLite rows. Give AppKit a chance to
            // process key events between small groups of results.
            if index % 8 == 7 { await Task.yield() }
        }
        return items
    }
}
