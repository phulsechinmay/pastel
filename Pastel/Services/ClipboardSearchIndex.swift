import Foundation
import OSLog
import SQLite3
import SwiftData

/// A disposable, local read index. SwiftData remains the source of truth; the index
/// never syncs and can be rebuilt after an interrupted or incompatible migration.
@ModelActor
actor ClipboardSearchIndex {
    private var database: OpaquePointer?
    private var ready = false
    private var databaseURLOverride: URL?
    private let smallClipLimit = 64 * 1024
    private let logger = Logger(subsystem: "app.pastel.Pastel", category: "SearchIndex")

    private func open() throws {
        if database != nil { return }
        let url: URL
        if let databaseURLOverride {
            url = databaseURLOverride
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Pastel", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            url = directory.appendingPathComponent("clipboard-search.sqlite")
        }
        let path = url.path
        guard sqlite3_open(path, &database) == SQLITE_OK else { throw IndexError.database }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA busy_timeout=3000")
        if try schemaVersion() < 6 {
            try execute("DROP TABLE IF EXISTS clips")
            try execute("DROP TABLE IF EXISTS clip_keys")
            try execute("DROP TABLE IF EXISTS clip_labels")
            try execute("DROP TABLE IF EXISTS build_state")
            try execute("PRAGMA user_version=6")
        }
        try execute("CREATE VIRTUAL TABLE IF NOT EXISTS clips USING fts5(id UNINDEXED, body, title, app, timestamp UNINDEXED, pinRank UNINDEXED, tokenize='trigram')")
        try execute("CREATE TABLE IF NOT EXISTS clip_keys (id TEXT PRIMARY KEY, timestamp REAL NOT NULL, pinRank REAL NOT NULL, pinned INTEGER NOT NULL, contentType TEXT NOT NULL, sourceAppBundleID TEXT NOT NULL, originDeviceID TEXT NOT NULL, fingerprint TEXT NOT NULL)")
        try execute("CREATE INDEX IF NOT EXISTS clip_keys_by_time ON clip_keys(timestamp DESC, id DESC)")
        try execute("CREATE INDEX IF NOT EXISTS clip_keys_by_pin ON clip_keys(pinned DESC, pinRank DESC, timestamp DESC, id DESC)")
        try execute("CREATE TABLE IF NOT EXISTS clip_labels (clipRowID INTEGER NOT NULL, labelStableID TEXT NOT NULL, PRIMARY KEY(clipRowID, labelStableID))")
        try execute("CREATE INDEX IF NOT EXISTS clip_labels_by_label ON clip_labels(labelStableID, clipRowID)")
        try execute("CREATE TABLE IF NOT EXISTS build_state (phase TEXT NOT NULL, next_offset INTEGER NOT NULL)")
        try execute("INSERT INTO build_state(phase, next_offset) SELECT 'small', 0 WHERE NOT EXISTS (SELECT 1 FROM build_state)")
    }

    /// Allows the standalone synthetic fixture to keep its index in a temp folder.
    func useDatabase(at url: URL) {
        precondition(database == nil)
        databaseURLOverride = url
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw IndexError.database }
    }

    private func schemaVersion() throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw IndexError.database }
        return Int(sqlite3_column_int(statement, 0))
    }

    /// Rebuild in small transactions. Ordinary clips become searchable before large
    /// clips; callers keep the authoritative SwiftData fallback until completion.
    func rebuild() async throws {
        let started = ContinuousClock.now
        try open()
        var initial = try buildState()
        if initial.phase == "complete" {
            if try countsMatch() {
                ready = true
                return
            }
            try resetTables()
            initial = ("small", 0)
        }
        ready = false
        for largePass in [false, true] {
            if !largePass && initial.phase == "large" { continue }
            var offset = largePass && initial.phase == "small" ? 0 : initial.offset
            while !Task.isCancelled {
                let large = largePass
                let limit = smallClipLimit
                let predicate: Predicate<ClipboardItem>
                if large {
                    predicate = #Predicate<ClipboardItem> { $0.byteCount > limit && !$0.isConcealed }
                } else {
                    predicate = #Predicate<ClipboardItem> { $0.byteCount <= limit && !$0.isConcealed }
                }
                var descriptor = FetchDescriptor<ClipboardItem>(predicate: predicate)
                descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
                // Amortize SQLite/SwiftData round trips for small clips while
                // keeping giant payloads in a separate two-item batch.
                descriptor.fetchLimit = large ? 2 : 64
                descriptor.fetchOffset = offset
                let batchContext = ModelContext(modelContainer)
                let batch = try batchContext.fetch(descriptor)
                if batch.isEmpty {
                    try execute("UPDATE build_state SET phase='\(large ? "complete" : "large")', next_offset=0")
                    break
                }
                try execute("BEGIN IMMEDIATE")
                do {
                    for item in batch { try upsert(item) }
                    try execute("UPDATE build_state SET phase='\(large ? "large" : "small")', next_offset=\(offset + batch.count)")
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
                offset += batch.count
                await Task.yield()
            }
            if Task.isCancelled { return }
        }
        guard try countsMatch() else { throw IndexError.outOfSync }
        ready = true
        let elapsed = started.duration(to: .now)
        logger.info("Search index ready after \(String(describing: elapsed))")
    }

    func resetAndRebuild() async throws {
        try open()
        ready = false
        try resetTables()
        try await rebuild()
    }

    private func resetTables() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM clips")
            try execute("DELETE FROM clip_keys")
            try execute("DELETE FROM clip_labels")
            try execute("UPDATE build_state SET phase='small', next_offset=0")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func countsMatch() throws -> Bool {
        let context = ModelContext(modelContainer)
        let expected = try context.fetchCount(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { !$0.isConcealed }
        ))
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM clip_keys", -1, &statement, nil) == SQLITE_OK else {
            throw IndexError.database
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw IndexError.database }
        return expected == Int(sqlite3_column_int64(statement, 0))
    }

    /// One-time, resumable migration of older inline text. Changing the storage
    /// field leaves timestamp/order intact and is safe to repeat after a crash.
    func externalizeLegacyLargeClips() async throws {
        var offset = 0
        let limit = ClipboardItem.inlineTextLimit
        while !Task.isCancelled {
            let predicate = #Predicate<ClipboardItem> {
                $0.byteCount > limit || $0.characterCount > limit
            }
            var descriptor = FetchDescriptor<ClipboardItem>(predicate: predicate)
            descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
            descriptor.fetchLimit = 2
            descriptor.fetchOffset = offset
            let batchContext = ModelContext(modelContainer)
            let batch = try batchContext.fetch(descriptor)
            if batch.isEmpty { break }
            var changed = false
            for item in batch {
                if item.largeTextData == nil, let text = item.textContent,
                   [.text, .richText, .code].contains(item.type),
                   text.utf8.count > limit {
                    item.setStoredText(text)
                    changed = true
                }
                if let html = item.htmlContent, html.utf8.count > limit {
                    item.setStoredHTML(html)
                    changed = true
                }
                if let rtf = item.rtfData, rtf.count > limit {
                    item.setStoredRTF(rtf)
                    changed = true
                }
            }
            if changed { try batchContext.save() }
            offset += batch.count
            await Task.yield()
        }
    }

    private func buildState() throws -> (phase: String, offset: Int) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT phase, next_offset FROM build_state LIMIT 1", -1,
                                 &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let phase = sqlite3_column_text(statement, 0) else { throw IndexError.database }
        return (String(cString: phase), Int(sqlite3_column_int(statement, 1)))
    }

    /// Apply local SwiftData saves without another whole-history pass.
    func applyChanges(upserted: [PersistentIdentifier], deleted: [PersistentIdentifier]) throws {
        try open()
        try execute("BEGIN IMMEDIATE")
        do {
            let changeContext = ModelContext(modelContainer)
            for id in deleted { try remove(id) }
            for id in upserted {
                guard let item = changeContext.model(for: id) as? ClipboardItem else { continue }
                if item.isConcealed { try remove(id) } else { try upsert(item) }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            ready = false
            throw error
        }
    }

    func matchingIDs(_ search: String, offset: Int, limit: Int, pinsFirst: Bool) throws -> [PersistentIdentifier]? {
        let normalized = Self.normalize(search)
        guard ready, normalized.unicodeScalars.count >= 3 else { return nil }
        try open()
        var statement: OpaquePointer?
        let order = pinsFirst
            ? "clip_keys.pinned DESC, clip_keys.pinRank DESC, clip_keys.timestamp DESC, clip_keys.id DESC"
            : "clip_keys.timestamp DESC, clip_keys.id DESC"
        let sql = "SELECT clip_keys.id FROM clips JOIN clip_keys ON clips.rowid = clip_keys.rowid WHERE clips MATCH ? ORDER BY \(order) LIMIT ? OFFSET ?"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        let phrase = "\"" + normalized.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        bind(phrase, at: 1, in: statement)
        sqlite3_bind_int(statement, 2, Int32(limit))
        sqlite3_bind_int(statement, 3, Int32(offset))
        var ids: [PersistentIdentifier] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            if let pointer = sqlite3_column_text(statement, 0),
               let id = PersistentIdentifier.fromTransferString(String(cString: pointer)) {
                ids.append(id)
            }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw IndexError.database }
        return ids
    }

    /// Metadata-only browse path. Labels use a dedicated membership table, so
    /// switching a chip never scans or faults every ClipboardItem model.
    func browsingIDs(
        offset: Int, limit: Int, pinsFirst: Bool,
        selectedLabelStableIDs: [String]?, filters: SearchFilters,
        localDeviceID: String
    ) throws -> [PersistentIdentifier]? {
        guard ready else { return nil }
        try open()
        var clauses = [
            "(originDeviceID = ? OR originDeviceID = '' OR contentType NOT IN ('image','file'))"
        ]
        var arguments = [localDeviceID]
        if let selectedLabelStableIDs {
            guard !selectedLabelStableIDs.isEmpty else { return nil }
            clauses.append("EXISTS (SELECT 1 FROM clip_labels WHERE clipRowID = clip_keys.rowid AND labelStableID IN (\(placeholders(selectedLabelStableIDs.count))))")
            arguments += selectedLabelStableIDs
        }
        if !filters.types.isEmpty {
            let types = filters.types.map(\.rawValue).sorted()
            clauses.append("contentType IN (\(placeholders(types.count)))")
            arguments += types
        }
        if !filters.appBundleIDs.isEmpty {
            let apps = filters.appBundleIDs.sorted()
            clauses.append("sourceAppBundleID IN (\(placeholders(apps.count)))")
            arguments += apps
        }
        if let cutoff = filters.dateRange?.cutoff() {
            clauses.append("timestamp >= ?")
            arguments.append(String(cutoff.timeIntervalSince1970))
        }
        let order = pinsFirst
            ? "pinned DESC, pinRank DESC, timestamp DESC, id DESC"
            : "timestamp DESC, id DESC"
        let sql = "SELECT id FROM clip_keys WHERE \(clauses.joined(separator: " AND ")) ORDER BY \(order) LIMIT ? OFFSET ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        for (index, argument) in arguments.enumerated() { bind(argument, at: Int32(index + 1), in: statement) }
        sqlite3_bind_int(statement, Int32(arguments.count + 1), Int32(limit))
        sqlite3_bind_int(statement, Int32(arguments.count + 2), Int32(offset))
        var ids: [PersistentIdentifier] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            if let pointer = sqlite3_column_text(statement, 0),
               let id = PersistentIdentifier.fromTransferString(String(cString: pointer)) {
                ids.append(id)
            }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw IndexError.database }
        return ids
    }

    private func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }

    private func upsert(_ item: ClipboardItem) throws {
        guard let id = item.persistentModelID.asTransferString else { return }
        let labelIDs = Set(item.safeLabels.map(\.stableID)).filter { !$0.isEmpty }.sorted()
        let fingerprint = try indexFingerprint(item, labelIDs: labelIDs)
        let previousFingerprint = try existingFingerprint(for: id)
        if previousFingerprint == fingerprint { return }
        if let previousFingerprint,
           let previous = try? JSONDecoder().decode(IndexFingerprint.self, from: Data(previousFingerprint.utf8)),
           previous.contentHash == item.contentHash,
           previous.title == item.title,
           previous.app == item.sourceAppName {
            // Pin, label, time and source metadata do not change FTS tokens.
            // Avoid reading/re-tokenizing a large full-text payload for them.
            try updateMetadata(item, id: id, fingerprint: fingerprint, labelIDs: labelIDs)
            return
        }
        try remove(item.persistentModelID)
        var keyStatement: OpaquePointer?
        let keySQL = "INSERT INTO clip_keys(id, timestamp, pinRank, pinned, contentType, sourceAppBundleID, originDeviceID, fingerprint) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(database, keySQL, -1,
                                 &keyStatement, nil) == SQLITE_OK else { throw IndexError.database }
        bind(id, at: 1, in: keyStatement)
        sqlite3_bind_double(keyStatement, 2, item.timestamp.timeIntervalSince1970)
        sqlite3_bind_double(keyStatement, 3, item.isPinned ? (item.pinnedAt ?? item.timestamp).timeIntervalSince1970 : 0)
        sqlite3_bind_int(keyStatement, 4, item.isPinned ? 1 : 0)
        bind(item.contentType, at: 5, in: keyStatement)
        bind(item.sourceAppBundleID ?? "", at: 6, in: keyStatement)
        bind(item.originDeviceID, at: 7, in: keyStatement)
        bind(fingerprint, at: 8, in: keyStatement)
        let keyResult = sqlite3_step(keyStatement)
        sqlite3_finalize(keyStatement)
        guard keyResult == SQLITE_DONE else { throw IndexError.database }
        let rowID = sqlite3_last_insert_rowid(database)
        try insertLabels(labelIDs, rowID: rowID)
        var statement: OpaquePointer?
        let sql = "INSERT INTO clips(rowid, id, body, title, app, timestamp, pinRank) VALUES (?, ?, ?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, rowID)
        bind(id, at: 2, in: statement)
        bind(Self.normalize(item.fullTextContent ?? ""), at: 3, in: statement)
        bind(Self.normalize(item.title ?? ""), at: 4, in: statement)
        bind(Self.normalize(item.sourceAppName ?? ""), at: 5, in: statement)
        bind(String(item.timestamp.timeIntervalSince1970), at: 6, in: statement)
        bind(String(item.isPinned ? (item.pinnedAt ?? item.timestamp).timeIntervalSince1970 : 0), at: 7, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw IndexError.database }
    }

    private func updateMetadata(_ item: ClipboardItem, id: String, fingerprint: String,
                                labelIDs: [String]) throws {
        var statement: OpaquePointer?
        let sql = "UPDATE clip_keys SET timestamp=?, pinRank=?, pinned=?, contentType=?, sourceAppBundleID=?, originDeviceID=?, fingerprint=? WHERE id=?"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        sqlite3_bind_double(statement, 1, item.timestamp.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, item.isPinned ? (item.pinnedAt ?? item.timestamp).timeIntervalSince1970 : 0)
        sqlite3_bind_int(statement, 3, item.isPinned ? 1 : 0)
        bind(item.contentType, at: 4, in: statement)
        bind(item.sourceAppBundleID ?? "", at: 5, in: statement)
        bind(item.originDeviceID, at: 6, in: statement)
        bind(fingerprint, at: 7, in: statement)
        bind(id, at: 8, in: statement)
        let result = sqlite3_step(statement)
        sqlite3_finalize(statement)
        guard result == SQLITE_DONE else { throw IndexError.database }
        var rowStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT rowid FROM clip_keys WHERE id=?", -1, &rowStatement, nil) == SQLITE_OK else { throw IndexError.database }
        bind(id, at: 1, in: rowStatement)
        let rowResult = sqlite3_step(rowStatement)
        let rowID = sqlite3_column_int64(rowStatement, 0)
        sqlite3_finalize(rowStatement)
        guard rowResult == SQLITE_ROW else { throw IndexError.database }
        try execute("DELETE FROM clip_labels WHERE clipRowID=\(rowID)")
        try insertLabels(labelIDs, rowID: rowID)
    }

    private func insertLabels(_ labelIDs: [String], rowID: Int64) throws {
        for stableID in labelIDs {
            var labelStatement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "INSERT INTO clip_labels(clipRowID, labelStableID) VALUES (?, ?)", -1,
                                     &labelStatement, nil) == SQLITE_OK else { throw IndexError.database }
            sqlite3_bind_int64(labelStatement, 1, rowID)
            bind(stableID, at: 2, in: labelStatement)
            let labelResult = sqlite3_step(labelStatement)
            sqlite3_finalize(labelStatement)
            guard labelResult == SQLITE_DONE else { throw IndexError.database }
        }
    }

    private struct IndexFingerprint: Codable {
        let contentHash: String
        let title: String?
        let app: String?
        let timestamp: Double
        let pinRank: Double
        let pinned: Bool
        let contentType: String
        let bundleID: String?
        let originDeviceID: String
        let labelIDs: [String]
    }

    private func indexFingerprint(_ item: ClipboardItem, labelIDs: [String]) throws -> String {
        let value = IndexFingerprint(
            contentHash: item.contentHash, title: item.title, app: item.sourceAppName,
            timestamp: item.timestamp.timeIntervalSince1970,
            pinRank: item.isPinned ? (item.pinnedAt ?? item.timestamp).timeIntervalSince1970 : 0,
            pinned: item.isPinned, contentType: item.contentType,
            bundleID: item.sourceAppBundleID, originDeviceID: item.originDeviceID,
            labelIDs: labelIDs
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(data: try encoder.encode(value), encoding: .utf8) ?? ""
    }

    private func existingFingerprint(for id: String) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT fingerprint FROM clip_keys WHERE id = ?", -1,
                                 &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let pointer = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: pointer)
    }

    private func remove(_ id: PersistentIdentifier) throws {
        guard let key = id.asTransferString else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT rowid FROM clip_keys WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        bind(key, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return }
        let rowID = sqlite3_column_int64(statement, 0)
        try execute("DELETE FROM clips WHERE rowid = \(rowID)")
        try execute("DELETE FROM clip_labels WHERE clipRowID = \(rowID)")
        try execute("DELETE FROM clip_keys WHERE rowid = \(rowID)")
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer?) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    private enum IndexError: Error { case database, outOfSync }
}
