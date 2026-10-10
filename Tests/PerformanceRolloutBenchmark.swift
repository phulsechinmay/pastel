import Foundation
import SwiftData
import Darwin

/// Standalone release-mode component benchmark. It deliberately creates each
/// insert batch in a fresh context so fixture construction does not retain the
/// whole library and masquerade as page-loader memory use.
@main
struct PerformanceRolloutBenchmark {
    @MainActor
    static func main() async throws {
        let itemCount = Int(ProcessInfo.processInfo.environment["PASTEL_FIXTURE_ITEMS"] ?? "1000") ?? 1000
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pastel-perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = ModelConfiguration(url: directory.appendingPathComponent("fixture.sqlite"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: ClipboardItem.self, Label.self, configurations: config)
        let initialContext = ModelContext(container)
        let label = Label(name: "Sparse", colorName: "blue", sortOrder: 0)
        initialContext.insert(label)
        try initialContext.save()
        let labelID = label.persistentModelID

        let insertionStarted = ContinuousClock.now
        for batchStart in stride(from: 0, to: itemCount, by: 500) {
            let context = ModelContext(container)
            let batchLabel = context.model(for: labelID) as? Label
            for number in batchStart..<min(batchStart + 500, itemCount) {
                let item = ClipboardItem(
                    textContent: "ordinary item \(number) searchable",
                    timestamp: Date(timeIntervalSince1970: Double(number + 1)),
                    characterCount: 32,
                    byteCount: 32,
                    contentHash: "fixture-\(number)"
                )
                if number % 100 == 0, let batchLabel {
                    item.safeLabels = [batchLabel]
                    item.labelKey = "|\(batchLabel.stableID)|"
                }
                if number % 1000 == 17 {
                    item.isPinned = true
                    item.pinnedAt = item.timestamp
                }
                context.insert(item)
            }
            try context.save()
        }
        let largeContext = ModelContext(container)
        for size in [64 * 1024, 1024 * 1024, 10 * 1024 * 1024] {
            let text = String(repeating: "L", count: size) + " deepneedle"
            let item = ClipboardItem(
                textContent: text,
                timestamp: Date(timeIntervalSince1970: Double(itemCount + size)),
                characterCount: text.count,
                byteCount: text.utf8.count,
                contentHash: "large-\(size)"
            )
            largeContext.insert(item)
        }
        try largeContext.save()
        print("items=\(itemCount + 3) insert=\(insertionStarted.duration(to: .now)) residentMB=\(residentBytes() / 1_048_576)")
        fflush(stdout)

        let index = ClipboardSearchIndex(modelContainer: container)
        await index.useDatabase(at: directory.appendingPathComponent("search.sqlite"))
        let indexStarted = ContinuousClock.now
        try await index.rebuild()
        let indexDuration = indexStarted.duration(to: .now)
        let indexSize = (try? FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("search.sqlite").path
        )[.size] as? Int) ?? 0
        print("index=\(indexDuration) indexBytes=\(indexSize) residentMB=\(residentBytes() / 1_048_576)")
        fflush(stdout)

        let worker = HistoryPageWorker(modelContainer: container)
        let pageContext = ModelContext(container)
        let pageLabel = pageContext.model(for: labelID) as! Label
        let samples = 20
        let allPage = try await measure(samples) {
            var cursor = HistoryPageCursor()
            _ = try await HistoryPageLoader.nextPage(
                in: pageContext, cursor: &cursor, searchText: "",
                selectedLabelIDs: [], allLabels: [pageLabel],
                searchIndex: index, worker: worker, pageSize: 12
            )
        }
        let labelPage = try await measure(samples) {
            var cursor = HistoryPageCursor()
            _ = try await HistoryPageLoader.nextPage(
                in: pageContext, cursor: &cursor, searchText: "",
                selectedLabelIDs: [labelID], allLabels: [pageLabel],
                searchIndex: index, worker: worker, pageSize: 12
            )
        }
        let indexedSearch = try await measure(samples) {
            var cursor = HistoryPageCursor()
            _ = try await HistoryPageLoader.nextPage(
                in: pageContext, cursor: &cursor, searchText: "deepneedle",
                selectedLabelIDs: [], allLabels: [pageLabel],
                searchIndex: index, worker: worker, pageSize: 12
            )
        }
        let shortSearch = try await measure(samples) {
            var cursor = HistoryPageCursor()
            _ = try await HistoryPageLoader.nextPage(
                in: pageContext, cursor: &cursor, searchText: "de",
                selectedLabelIDs: [], allLabels: [pageLabel],
                searchIndex: index, worker: worker, pageSize: 12
            )
        }
        let singleSearch = try await measure(samples) {
            var cursor = HistoryPageCursor()
            _ = try await HistoryPageLoader.nextPage(
                in: pageContext, cursor: &cursor, searchText: "o",
                selectedLabelIDs: [], allLabels: [pageLabel],
                searchIndex: index, worker: worker, pageSize: 12
            )
        }
        let missingSearch = try await measure(samples) {
            var cursor = HistoryPageCursor()
            _ = try await HistoryPageLoader.nextPage(
                in: pageContext, cursor: &cursor, searchText: "absent-needle-12345",
                selectedLabelIDs: [], allLabels: [pageLabel],
                searchIndex: index, worker: worker, pageSize: 12
            )
        }
        print("firstPage \(allPage)")
        print("labelPage \(labelPage)")
        print("deepSearch \(indexedSearch)")
        print("shortSearch \(shortSearch)")
        print("singleSearch \(singleSearch)")
        print("missingSearch \(missingSearch)")
        let beforeSweep = residentBytes()
        try await sweepPages(in: container, index: index, worker: worker)
        let firstSweep = residentBytes()
        try await sweepPages(in: container, index: index, worker: worker)
        let secondSweep = residentBytes()
        print("pageSweep residentMB before=\(beforeSweep / 1_048_576) afterFirst=\(firstSweep / 1_048_576) afterSecond=\(secondSweep / 1_048_576)")
    }

    @MainActor
    private static func measure(_ count: Int, action: () async throws -> Void) async throws -> String {
        var values: [Double] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            let start = ContinuousClock.now
            try await action()
            let elapsed = start.duration(to: .now)
            values.append(Double(elapsed.components.seconds) * 1000 +
                          Double(elapsed.components.attoseconds) / 1_000_000_000_000_000)
        }
        values.sort()
        let median = values[count / 2]
        let p95 = values[min(count - 1, Int(Double(count) * 0.95))]
        return String(format: "p50=%.1fms p95=%.1fms", median, p95)
    }

    @MainActor
    private static func sweepPages(
        in container: ModelContainer, index: ClipboardSearchIndex, worker: HistoryPageWorker
    ) async throws {
        let context = ModelContext(container)
        var cursor = HistoryPageCursor()
        for _ in 0..<100 {
            let page = try await HistoryPageLoader.nextPage(
                in: context, cursor: &cursor, searchText: "",
                selectedLabelIDs: [], allLabels: [], searchIndex: index,
                worker: worker, pageSize: 50
            )
            if page.isEmpty || cursor.isExhausted { break }
        }
    }

    private static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
}
