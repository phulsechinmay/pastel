import Foundation
import SwiftData

@main
struct PerformanceUpgradeSmoke {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let onDisk = ProcessInfo.processInfo.environment["PASTEL_FIXTURE_DISK"] == "1"
        let config = onDisk
            ? ModelConfiguration(url: directory.appendingPathComponent("fixture.sqlite"), cloudKitDatabase: .none)
            : ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ClipboardItem.self, Label.self, configurations: config)
        let context = container.mainContext
        let label = Label(name: "Sparse", colorName: "blue", sortOrder: 0)
        context.insert(label)

        let itemCount = Int(ProcessInfo.processInfo.environment["PASTEL_FIXTURE_ITEMS"] ?? "400") ?? 400
        for number in 0..<itemCount {
            let item = ClipboardItem(
                textContent: "ordinary item \(number)",
                timestamp: Date(timeIntervalSince1970: Double(number + 1)),
                sourceAppBundleID: number == 17 ? "fixture.app" : nil,
                characterCount: 20,
                byteCount: 20,
                contentHash: "fixture-\(number)"
            )
            if number % 17 == 0 {
                item.safeLabels = [label]
                item.labelKey = "|\(label.stableID)|"
            }
            if number == 17 {
                item.isPinned = true
                item.pinnedAt = Date(timeIntervalSince1970: 1000)
            }
            context.insert(item)
        }
        let hugeText = String(repeating: "🦄", count: 300_000) + " uniqueendtoken"
        let huge = ClipboardItem(
            textContent: hugeText,
            htmlContent: String(repeating: "<p>HTML</p>", count: 10_000),
            rtfData: Data(repeating: 65, count: 100_000),
            contentType: .richText,
            timestamp: Date(timeIntervalSince1970: 500),
            characterCount: hugeText.count,
            byteCount: hugeText.utf8.count,
            contentHash: "fixture-huge"
        )
        context.insert(huge)
        let accented = ClipboardItem(
            textContent: "café rendezvous", timestamp: Date(timeIntervalSince1970: 501),
            characterCount: 15, byteCount: 17, contentHash: "fixture-accented"
        )
        context.insert(accented)
        let legacyText = String(repeating: "L", count: 100_000) + " legacysuffix"
        let legacy = ClipboardItem(textContent: "legacy", timestamp: Date(timeIntervalSince1970: 502),
                                   contentHash: "fixture-legacy")
        legacy.textContent = legacyText
        legacy.characterCount = legacyText.count
        legacy.byteCount = legacyText.utf8.count
        context.insert(legacy)
        try context.save()

        check(huge.textContent?.utf8.count ?? 0 <= 4096, "bounded inline preview")
        check(huge.fullTextContent == hugeText, "full text survives externalization")
        check(huge.htmlContent == nil && huge.fullHTMLContent != nil, "HTML externalized")
        check(huge.rtfData == nil && huge.fullRTFData?.count == 100_000, "RTF externalized")
        let readContext = ModelContext(container)
        let reread = readContext.model(for: huge.persistentModelID) as? ClipboardItem
        check(reread?.fullTextContent == hugeText, "full text survives a fresh context")

        var cursor = HistoryPageCursor()
        var labeled: [ClipboardItem] = []
        let pageStart = ContinuousClock.now
        repeat {
            let page = try await HistoryPageLoader.nextPage(
                in: context, cursor: &cursor, searchText: "",
                selectedLabelIDs: [label.persistentModelID], allLabels: [label],
                pageSize: 7
            )
            labeled.append(contentsOf: page)
        } while !cursor.isExhausted && itemCount <= 10_000
        let expectedLabeled = itemCount > 10_000 ? 7 : (itemCount - 1) / 17 + 1
        check(labeled.count == expectedLabeled, "sparse labeled clips reachable")
        check(labeled.first?.isPinned == true, "old pinned match stays first")
        check(Set(labeled.map(\.persistentModelID)).count == labeled.count, "pages do not duplicate items")
        let pageDuration = pageStart.duration(to: .now)

        // Before FTS has finished, the fallback must search beyond the inline
        // preview and the chronological History stream must not repeat pages.
        var fallbackSearchCursor = HistoryPageCursor(pinnedExhausted: true)
        let fallbackSearchPage = try await HistoryPageLoader.nextPage(
            in: context, cursor: &fallbackSearchCursor, searchText: "uniqueendtoken",
            selectedLabelIDs: [], allLabels: [label], pinsFirst: false
        )
        check(fallbackSearchPage.map(\.persistentModelID) == [huge.persistentModelID],
              "deep text reachable before indexing")
        var chronologicalCursor = HistoryPageCursor()
        let chronologicalFirst = try await HistoryPageLoader.nextPage(
            in: context, cursor: &chronologicalCursor, searchText: "",
            selectedLabelIDs: [], allLabels: [label], pinsFirst: false, pageSize: 7
        )
        let chronologicalSecond = try await HistoryPageLoader.nextPage(
            in: context, cursor: &chronologicalCursor, searchText: "",
            selectedLabelIDs: [], allLabels: [label], pinsFirst: false, pageSize: 7
        )
        check(Set((chronologicalFirst + chronologicalSecond).map(\.persistentModelID)).count == 14,
              "chronological fallback does not repeat pages")

        let index = ClipboardSearchIndex(modelContainer: container)
        await index.useDatabase(at: directory.appendingPathComponent("search.sqlite"))
        let indexStart = ContinuousClock.now
        try await index.rebuild()
        let indexDuration = indexStart.duration(to: .now)
        let found = try await index.matchingIDs("uniqueendtoken", offset: 0, limit: 20, pinsFirst: true)
        check(found?.contains(huge.persistentModelID) == true, "deep large-text search")
        let accentMatches = try await index.matchingIDs("cafe", offset: 0, limit: 20, pinsFirst: true)
        check(accentMatches?.contains(accented.persistentModelID) == true, "diacritic-insensitive search")
        try await index.externalizeLegacyLargeClips()
        let migrated = ModelContext(container).model(for: legacy.persistentModelID) as? ClipboardItem
        check(migrated?.largeTextData != nil && migrated?.fullTextContent == legacyText,
              "older large clip migrated without loss")
        try await index.applyChanges(upserted: [legacy.persistentModelID], deleted: [])
        let legacyMatches = try await index.matchingIDs("legacysuffix", offset: 0, limit: 20, pinsFirst: true)
        check(legacyMatches?.contains(legacy.persistentModelID) == true, "migration keeps deep search")
        var indexedLabelCursor = HistoryPageCursor()
        let indexedLabelPage = try await HistoryPageLoader.nextPage(
            in: context, cursor: &indexedLabelCursor, searchText: "",
            selectedLabelIDs: [label.persistentModelID], allLabels: [label],
            searchIndex: index, pageSize: 7
        )
        check(indexedLabelPage.count == 7 && indexedLabelPage.first?.isPinned == true,
              "indexed label page preserves old pin and page size")
        var appCursor = HistoryPageCursor()
        var appFilters = SearchFilters()
        appFilters.appBundleIDs = ["fixture.app"]
        let appPage = try await HistoryPageLoader.nextPage(
            in: context, cursor: &appCursor, searchText: "",
            selectedLabelIDs: [], allLabels: [label], filters: appFilters,
            searchIndex: index
        )
        check(appPage.count == 1 && appPage.first?.sourceAppBundleID == "fixture.app", "indexed app filter")

        var searchCursor = HistoryPageCursor()
        let searchPage = try await HistoryPageLoader.nextPage(
            in: context, cursor: &searchCursor, searchText: "uniqueendtoken",
            selectedLabelIDs: [], allLabels: [label], searchIndex: index
        )
        check(searchPage.map(\.persistentModelID) == [huge.persistentModelID], "indexed page resolves full clip")

        huge.isPinned = true
        huge.pinnedAt = .now
        huge.safeLabels = [label]
        huge.labelKey = "|\(label.stableID)|"
        try context.save()
        try await index.applyChanges(upserted: [huge.persistentModelID], deleted: [])
        let deepAfterMetadata = try await index.matchingIDs("uniqueendtoken", offset: 0, limit: 20, pinsFirst: true)
        check(deepAfterMetadata?.first == huge.persistentModelID,
              "pin and label update preserves large-text search")
        var labeledAfterUpdateCursor = HistoryPageCursor()
        let labeledAfterUpdate = try await HistoryPageLoader.nextPage(
            in: context, cursor: &labeledAfterUpdateCursor, searchText: "",
            selectedLabelIDs: [label.persistentModelID], allLabels: [label],
            searchIndex: index, pageSize: 7
        )
        check(labeledAfterUpdate.first?.persistentModelID == huge.persistentModelID,
              "metadata-only update refreshes label membership and pin order")

        huge.title = "fresh searchable title"
        try context.save()
        try await index.applyChanges(upserted: [huge.persistentModelID], deleted: [])
        let editedMatches = try await index.matchingIDs("fresh searchable", offset: 0, limit: 20, pinsFirst: true)
        check(editedMatches?.contains(huge.persistentModelID) == true, "edit updates index")
        let hugeID = huge.persistentModelID
        context.delete(huge)
        try context.save()
        try await index.applyChanges(upserted: [], deleted: [hugeID])
        let deletedMatches = try await index.matchingIDs("uniqueendtoken", offset: 0, limit: 20, pinsFirst: true)
        check(deletedMatches?.isEmpty == true, "delete removes index entry")
        let reopened = ClipboardSearchIndex(modelContainer: container)
        await reopened.useDatabase(at: directory.appendingPathComponent("search.sqlite"))
        try await reopened.rebuild()
        let reopenedMatches = try await reopened.matchingIDs("cafe", offset: 0, limit: 20, pinsFirst: true)
        check(reopenedMatches?.contains(accented.persistentModelID) == true, "completed index reopens")
        print("Performance upgrade smoke checks passed (\(itemCount) ordinary clips, \(onDisk ? "disk" : "memory"); sparse pages \(pageDuration); index \(indexDuration))")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        precondition(condition(), name)
    }
}
